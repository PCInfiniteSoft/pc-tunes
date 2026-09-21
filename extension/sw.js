"use strict";

const PORTS = [8787, 8788, 8789, 8790, 8791];
const BACKOFF_MS = [1000, 2000, 4000, 8000, 30000];
// Short enough to stay inside the app's 15s stale timeout. Chrome throttles a
// backgrounded page's timers to once a minute, so the page's own heartbeat cannot
// be relied on — the worker's can.
const KEEPALIVE_MS = 5000;
const HELLO_TIMEOUT_MS = 3000;
const PENDING_START_MS = 30000;

/// Chrome terminates an idle MV3 service worker and its pending timers with it, so a
/// reconnect armed with setTimeout is lost the moment the worker sleeps — which is
/// exactly what happens when the app quits and the socket closes. An alarm survives
/// termination and restarts the worker, so it is the only reliable way back.
const RECONNECT_ALARM = "pc-tunes-reconnect";

let socket = null;
let portIndex = 0;
let attempt = 0;
let reconnectTimer = null;
let keepaliveTimer = null;
let helloTimer = null;
/** The port a greeting arrived on. Worth retrying before scanning the range again. */
let verifiedPort = null;

/** tabId -> "app" | "tab". Lets us emit a `gone` message when a tab closes. */
const knownTabs = new Map();

/** tabId -> the last state message sent, re-sent on the keepalive tick. */
const lastState = new Map();

/** Tabs whose bridge has announced itself. Insertion order, most recent last. */
const readyTabs = new Set();
let pendingStartAt = 0;

/// How long a start the widget asked for has to actually begin playing before the
/// follow-up minimise is given up on.
const MINIMIZE_DEADLINE_MS = 30000;

/// How far into the track playback has to have actually got before the window can be
/// put away. `playing` on its own does not mean the media pipeline is up: a window
/// minimised the moment it appeared reported `playing: true` with the duration read
/// correctly and the position pinned at 0.0 for forty-five seconds straight.
const MINIMIZE_MIN_POSITION = 3;

/// The tab whose window is to be put away once its playback starts, and the instant
/// that intent expires. Set only for a start the widget itself asked for.
let minimizeTab = null;
let minimizeBy = 0;

/// How long after a track change we keep watching for a starved media pipeline.
const STALL_WINDOW_MS = 25000;
/// A new track that has got this far is past the point where it starves.
const STALL_SETTLED_POSITION = 15;
/// The track change we are watching, as `{ tabId, until }`, or null.
let stallWatch = null;

/// Where the id of the last track the extension saw is kept, so a cold start can go
/// back to it instead of guessing from the home page. Written to `chrome.storage.local`
/// so it survives the worker being unloaded and the browser being restarted.
const LAST_VIDEO_KEY = "lastVideoId";
let lastVideoId = "";
chrome.storage.local
  .get(LAST_VIDEO_KEY)
  .then((stored) => {
    const value = stored && stored[LAST_VIDEO_KEY];
    if (typeof value === "string" && value && !lastVideoId) lastVideoId = value;
  })
  .catch(() => {});

function rememberVideo(payload) {
  const id = payload && payload.videoId;
  if (typeof id !== "string" || !id || id === lastVideoId) return;
  lastVideoId = id;
  chrome.storage.local.set({ [LAST_VIDEO_KEY]: id }).catch(() => {});
}

async function windowKindFor(tabId) {
  try {
    const tab = await chrome.tabs.get(tabId);
    const win = await chrome.windows.get(tab.windowId);
    return win.type === "app" ? "app" : "tab";
  } catch (error) {
    console.warn(`[PC Tunes] could not resolve the window for tab ${tabId}, ` +
      `treating it as an ordinary tab:`, error);
    return "tab";
  }
}

function sendToApp(object) {
  if (!socket || socket.readyState !== WebSocket.OPEN) return;
  socket.send(JSON.stringify(object));
}

/// Drops every trace of a tab and tells the app, so its arbitration can move on.
function forgetTab(tabId) {
  const known = lastState.has(tabId) || knownTabs.has(tabId) || readyTabs.has(tabId);
  lastState.delete(tabId);
  knownTabs.delete(tabId);
  readyTabs.delete(tabId);
  if (known) {
    sendToApp({ type: "gone", tabId });
  }
}

function sendKeepalive() {
  if (lastState.size === 0) {
    sendToApp({ type: "ping" });
    return;
  }
  // A cached state is only worth re-sending while the page it came from still exists.
  // A tab can die without ever firing onRemoved — navigation away, a Memory Saver
  // discard, a renderer crash — so ask it before speaking for it.
  for (const tabId of [...lastState.keys()]) {
    chrome.tabs
      .sendMessage(tabId, { kind: "alive" })
      .then(() => {
        const current = lastState.get(tabId);
        if (!current) return;
        // Re-send without `position`: the cached one is up to five seconds old, and a
        // stale position interleaved with fresh ones would make it jump backwards.
        const { position, ...rest } = current;
        sendToApp(rest);
      })
      .catch(() => forgetTab(tabId));
  }
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  const delay = BACKOFF_MS[Math.min(attempt, BACKOFF_MS.length - 1)];
  attempt += 1;
  if (verifiedPort === null) {
    portIndex = (portIndex + 1) % PORTS.length;
  } else if (attempt >= 3) {
    // Three failures on a port that used to answer: the app has probably moved.
    verifiedPort = null;
  }
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, delay);
}

function startPlaybackIn(tabId) {
  // The widget asked for this, so the window it opens is not one the user went looking
  // for: put it away again as soon as it is actually playing.
  minimizeTab = tabId;
  minimizeBy = Date.now() + MINIMIZE_DEADLINE_MS;
  chrome.tabs
    .sendMessage(tabId, { kind: "cmd", action: "startPlayback", value: lastVideoId })
    .catch(() => {});
}

/// Puts a web app window away once the track it was opened for is really playing.
///
/// Minimised, not hidden. Hiding the app makes Chrome treat the window as fully
/// occluded and starves the page's media pipeline — the `<video>` element never gets
/// past `readyState` 0 and playback restarts from zero every few seconds. A minimised
/// window keeps playing: measured across a minute of a minimised web app, the position
/// advanced by exactly five seconds on every five-second heartbeat.
///
/// Waits for the position to have actually moved, not merely for `playing`. A window
/// put away before its media pipeline is up is starved exactly as a hidden one is, and
/// `playing` goes true well before that: minimising 600ms after the window appeared
/// gave forty-five seconds of `playing: true` with the position stuck at 0.0, which
/// recovered — the position climbing again — the moment the window was restored.
///
/// Only ever an app window. Minimising an ordinary browser window would take whatever
/// else the user had open in it down with the music.
function minimizeIfPending(tabId, windowId, payload) {
  if (minimizeTab !== tabId) return;
  if (Date.now() > minimizeBy) {
    minimizeTab = null;
    return;
  }
  if (!payload || payload.playing !== true) return;
  if (typeof payload.position !== "number" || payload.position < MINIMIZE_MIN_POSITION) return;
  minimizeTab = null;
  if (knownTabs.get(tabId) !== "app" || typeof windowId !== "number") return;
  chrome.windows.update(windowId, { state: "minimized" }).catch(() => {});
}

/// Restarts a track that stopped by itself moments after we changed it.
///
/// Loading a track is the fragile moment: a page whose window is minimised — and a
/// freshly opened one above all — can start a new track, play a few seconds of what it
/// had buffered, and then stop dead. Measured on a cold start: the window was minimised
/// three seconds in, `next` arrived five seconds after that, and the new track played to
/// 6.47s and stayed frozen there for two and a half minutes. Playing it again is enough
/// to recover it; the user had been doing that by hand.
///
/// Only a pause this soon after a change *we* asked for is treated this way, and only
/// once. Its cost when the guess is wrong — the user hit Next and then paused on the
/// page within the same few seconds — is one unwanted resume, which the next press of
/// pause undoes. A pause the user asks for through the widget clears the watch outright,
/// and so does the track settling in (`STALL_SETTLED_POSITION`), which is the ordinary
/// way this ends.
function recoverStalledTrack(tabId, payload) {
  if (!stallWatch || stallWatch.tabId !== tabId || !payload) return;
  if (Date.now() > stallWatch.until) {
    stallWatch = null;
    return;
  }
  if (payload.playing === true) {
    if (typeof payload.position === "number" && payload.position >= STALL_SETTLED_POSITION) {
      stallWatch = null;
    }
    return;
  }
  stallWatch = null;
  chrome.tabs.sendMessage(tabId, { kind: "cmd", action: "playPause" }).catch(() => {});
}

function mostRecentReadyTab() {
  let latest = null;
  for (const tabId of readyTabs) latest = tabId;
  return latest;
}

function connect() {
  if (
    socket &&
    (socket.readyState === WebSocket.OPEN ||
      socket.readyState === WebSocket.CONNECTING ||
      socket.readyState === WebSocket.CLOSING)
  ) {
    return;
  }
  const port = PORTS[portIndex];
  let ws;
  try {
    ws = new WebSocket(`ws://127.0.0.1:${port}/`);
  } catch (error) {
    scheduleReconnect();
    return;
  }
  socket = ws;

  // Armed here rather than in `onopen` so it also covers a peer that accepts the TCP
  // connection but never completes the WebSocket upgrade — that never fires `onopen`,
  // and without a deadline the reconnect loop stalls forever on CONNECTING.
  clearTimeout(helloTimer);
  helloTimer = setTimeout(() => {
    console.warn(`[PC Tunes] no greeting on port ${port} — not our server`);
    verifiedPort = null;
    ws.close();
  }, HELLO_TIMEOUT_MS);

  ws.onmessage = async (event) => {
    if (ws !== socket) return;
    let message;
    try {
      message = JSON.parse(event.data);
    } catch (error) {
      return;
    }
    if (message && message.type === "hello" && message.app === "PC Tunes") {
      clearTimeout(helloTimer);
      attempt = 0;
      verifiedPort = port;
      console.log(`[PC Tunes] connected on port ${port}`);
      clearInterval(keepaliveTimer);
      keepaliveTimer = setInterval(sendKeepalive, KEEPALIVE_MS);
      return;
    }
    if (!message || message.type !== "cmd" || typeof message.tabId !== "number") return;

    if (message.action === "startPlayback") {
      const target = mostRecentReadyTab();
      if (target !== null) {
        startPlaybackIn(target);
      } else {
        pendingStartAt = Date.now();
      }
      return;
    }

    if (message.action === "focusTab") {
      try {
        const tab = await chrome.tabs.get(message.tabId);
        await chrome.tabs.update(message.tabId, { active: true });
        await chrome.windows.update(tab.windowId, { focused: true });
      } catch (error) {
        // The tab went away; the app will notice via the heartbeat timeout.
      }
      return;
    }

    if (message.action === "next" || message.action === "prev") {
      stallWatch = { tabId: message.tabId, until: Date.now() + STALL_WINDOW_MS };
    } else if (message.action === "playPause") {
      // The user is working the transport themselves; whatever they leave it on is
      // what they meant.
      stallWatch = null;
    }

    chrome.tabs
      .sendMessage(message.tabId, {
        kind: "cmd",
        action: message.action,
        value: message.value,
      })
      .catch(() => {});
  };

  ws.onclose = () => {
    if (ws !== socket) return;
    clearInterval(keepaliveTimer);
    clearTimeout(helloTimer);
    socket = null;
    scheduleReconnect();
  };

  ws.onerror = () => {
    // onclose always follows, which is where the reconnect is scheduled.
  };
}

/// A floor under `scheduleReconnect`'s setTimeout backoff, not a replacement for it:
/// Chrome may terminate the worker (and the pending timeout) while disconnected, so
/// this periodic alarm is what wakes the worker back up. `connect()`'s own re-entry
/// guard makes firing it during a healthy session a cheap no-op.
function armReconnectAlarm() {
  chrome.alarms.create(RECONNECT_ALARM, { periodInMinutes: 0.5 });
}

/// Builds a state message from a page-supplied payload.
///
/// The fields are copied one by one rather than spread: `inject.js` runs in the page's
/// own world, so anything on the page can shape that payload, and a spread would let it
/// overwrite `type`, `tabId` or `source` and lie about which window it came from.
function stateMessage(tabId, source, payload) {
  const state = payload || {};
  const message = {
    type: "state",
    tabId,
    source,
    playing: state.playing === true,
    title: typeof state.title === "string" ? state.title : "",
    artist: typeof state.artist === "string" ? state.artist : "",
    album: typeof state.album === "string" ? state.album : "",
    artwork: typeof state.artwork === "string" ? state.artwork : null,
    position: typeof state.position === "number" ? state.position : 0,
    duration: typeof state.duration === "number" ? state.duration : 0,
  };
  // Omitted rather than defaulted: the app's decoder treats absence as "unknown" and
  // rejects any `liked` value it does not recognize, so a bad or missing rating from
  // the page must disappear rather than turn into a guess.
  if (state.liked === "like" || state.liked === "dislike") {
    message.liked = state.liked;
  }
  if (typeof state.volume === "number") {
    message.volume = state.volume;
  }
  // Same reasoning as `liked`: a page that could not tell says nothing, and the app
  // draws nothing, rather than both of them guessing at "song".
  if (state.mode === "song" || state.mode === "video") {
    message.mode = state.mode;
  }
  // Same reasoning again: a page that could not read shuffle/repeat says nothing.
  if (typeof state.shuffleOn === "boolean") {
    message.shuffleOn = state.shuffleOn;
  }
  if (state.repeatMode === "off" || state.repeatMode === "all" || state.repeatMode === "one") {
    message.repeatMode = state.repeatMode;
  }
  return message;
}

const QUEUE_MAX = 20;

/// Builds a notice message field by field, for the same reason as `stateMessage`:
/// `inject.js` runs in the page's own world, so anything on the page can shape what it
/// sends, and a spread would let it overwrite `type` or `tabId`.
function noticeMessage(tabId, text) {
  return {
    type: "notice",
    tabId,
    text: typeof text === "string" ? text : "",
  };
}

/// Builds a queue message field by field, same reasoning as `stateMessage` and
/// `noticeMessage`. Caps at QUEUE_MAX and coerces each entry to a {title, artist}
/// string pair, dropping anything the page didn't actually provide as a string.
function queueMessage(tabId, items) {
  const list = Array.isArray(items) ? items : [];
  return {
    type: "queue",
    tabId,
    items: list.slice(0, QUEUE_MAX).map((item) => {
      const entry = item || {};
      return {
        title: typeof entry.title === "string" ? entry.title : "",
        artist: typeof entry.artist === "string" ? entry.artist : "",
      };
    }),
  };
}

chrome.runtime.onMessage.addListener((message, sender) => {
  if (!message) return;
  const tabId = sender.tab && sender.tab.id;
  if (typeof tabId !== "number") return;

  if (message.kind === "ready") {
    readyTabs.delete(tabId);
    readyTabs.add(tabId);
    if (pendingStartAt && Date.now() - pendingStartAt < PENDING_START_MS) {
      pendingStartAt = 0;
      startPlaybackIn(tabId);
    }
    return;
  }

  if (message.kind === "notice") {
    sendToApp(noticeMessage(tabId, message.text));
    return;
  }

  if (message.kind === "queue") {
    sendToApp(queueMessage(tabId, message.items));
    return;
  }

  if (message.kind !== "state") return;

  // Once a tab's window kind is known, label and forward synchronously: two updates
  // from one tab must not overtake each other on the way to the app.
  const windowId = sender.tab && sender.tab.windowId;

  const known = knownTabs.get(tabId);
  if (known) {
    const state = stateMessage(tabId, known, message.payload);
    lastState.set(tabId, state);
    sendToApp(state);
    minimizeIfPending(tabId, windowId, message.payload);
    recoverStalledTrack(tabId, message.payload);
    rememberVideo(message.payload);
    return;
  }

  windowKindFor(tabId).then((source) => {
    knownTabs.set(tabId, source);
    const state = stateMessage(tabId, source, message.payload);
    lastState.set(tabId, state);
    sendToApp(state);
    minimizeIfPending(tabId, windowId, message.payload);
    recoverStalledTrack(tabId, message.payload);
    rememberVideo(message.payload);
  });
});

chrome.tabs.onRemoved.addListener((tabId) => {
  forgetTab(tabId);
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name !== RECONNECT_ALARM) return;
  connect();
});

/// Chrome does not re-inject content scripts into already-open tabs when the extension
/// is reloaded or updated: the old scripts are orphaned, their `chrome.*` calls go dead,
/// and an open YouTube Music tab silently stops reporting until it is reloaded by hand.
/// Re-injecting both scripts fixes it without a manual reload. The page-world `inject.js`
/// survives the reload and guards against a double copy (`window.__pcTunesInjected`), so
/// injecting it again is a no-op there; the isolated-world `content.js` bridge is the
/// part that actually died and gets replaced.
async function reinjectOpenTabs() {
  if (!chrome.scripting) return;
  let tabs;
  try {
    tabs = await chrome.tabs.query({ url: "https://music.youtube.com/*" });
  } catch (error) {
    return;
  }
  for (const tab of tabs) {
    if (tab.id == null) continue;
    chrome.scripting
      .executeScript({ target: { tabId: tab.id }, world: "MAIN", files: ["inject.js"] })
      .then(() =>
        chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["content.js"] })
      )
      .catch(() => {});
  }
}

chrome.runtime.onStartup.addListener(() => {
  armReconnectAlarm();
  connect();
});
chrome.runtime.onInstalled.addListener(() => {
  armReconnectAlarm();
  connect();
  reinjectOpenTabs();
});
armReconnectAlarm();
connect();
