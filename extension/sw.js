"use strict";

const PORTS = [8787, 8788, 8789, 8790, 8791];
const BACKOFF_MS = [1000, 2000, 4000, 8000, 30000];
// Short enough to stay inside the app's 15s stale timeout. Chrome throttles a
// backgrounded page's timers to once a minute, so the page's own heartbeat cannot
// be relied on — the worker's can.
const KEEPALIVE_MS = 5000;
const HELLO_TIMEOUT_MS = 2000;
const PENDING_START_MS = 30000;

let socket = null;
let portIndex = 0;
let attempt = 0;
let reconnectTimer = null;
let keepaliveTimer = null;
let helloTimer = null;

/** tabId -> "app" | "tab". Lets us emit a `gone` message when a tab closes. */
const knownTabs = new Map();

/** tabId -> the last state message sent, re-sent on the keepalive tick. */
const lastState = new Map();

/** Tabs whose bridge has announced itself. Insertion order, most recent last. */
const readyTabs = new Set();
let pendingStartAt = 0;

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

function sendKeepalive() {
  if (lastState.size === 0) {
    sendToApp({ type: "ping" });
    return;
  }
  for (const state of lastState.values()) {
    sendToApp(state);
  }
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  const delay = BACKOFF_MS[Math.min(attempt, BACKOFF_MS.length - 1)];
  attempt += 1;
  portIndex = (portIndex + 1) % PORTS.length;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, delay);
}

function startPlaybackIn(tabId) {
  chrome.tabs.sendMessage(tabId, { kind: "cmd", action: "startPlayback" }).catch(() => {});
}

function mostRecentReadyTab() {
  let latest = null;
  for (const tabId of readyTabs) latest = tabId;
  return latest;
}

function connect() {
  if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
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

  ws.onopen = () => {
    // A socket that opens proves only that something is listening. Wait for the
    // app's greeting before treating this port as ours.
    clearTimeout(helloTimer);
    helloTimer = setTimeout(() => {
      console.warn(`[PC Tunes] no greeting on port ${port} — not our server`);
      ws.close();
    }, HELLO_TIMEOUT_MS);
  };

  ws.onmessage = async (event) => {
    let message;
    try {
      message = JSON.parse(event.data);
    } catch (error) {
      return;
    }
    if (message && message.type === "hello") {
      clearTimeout(helloTimer);
      attempt = 0;
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

    chrome.tabs
      .sendMessage(message.tabId, { kind: "cmd", action: message.action })
      .catch(() => {});
  };

  ws.onclose = () => {
    clearInterval(keepaliveTimer);
    clearTimeout(helloTimer);
    socket = null;
    scheduleReconnect();
  };

  ws.onerror = () => {
    // onclose always follows, which is where the reconnect is scheduled.
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

  if (message.kind !== "state") return;

  // Once a tab's window kind is known, label and forward synchronously: two updates
  // from one tab must not overtake each other on the way to the app.
  const known = knownTabs.get(tabId);
  if (known) {
    const state = { type: "state", tabId, source: known, ...message.payload };
    lastState.set(tabId, state);
    sendToApp(state);
    return;
  }

  windowKindFor(tabId).then((source) => {
    knownTabs.set(tabId, source);
    const state = { type: "state", tabId, source, ...message.payload };
    lastState.set(tabId, state);
    sendToApp(state);
  });
});

chrome.tabs.onRemoved.addListener((tabId) => {
  readyTabs.delete(tabId);
  if (!knownTabs.has(tabId)) return;
  knownTabs.delete(tabId);
  lastState.delete(tabId);
  sendToApp({ type: "gone", tabId });
});

chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
connect();
