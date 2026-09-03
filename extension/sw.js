"use strict";

const PORTS = [8787, 8788, 8789, 8790, 8791];
const BACKOFF_MS = [1000, 2000, 4000, 8000, 30000];
const KEEPALIVE_MS = 20000;

let socket = null;
let portIndex = 0;
let attempt = 0;
let reconnectTimer = null;
let keepaliveTimer = null;

/** tabId -> "app" | "tab". Lets us emit a `gone` message when a tab closes. */
const knownTabs = new Map();

async function windowKindFor(tabId) {
  try {
    const tab = await chrome.tabs.get(tabId);
    const win = await chrome.windows.get(tab.windowId);
    return win.type === "app" ? "app" : "tab";
  } catch (error) {
    return "tab";
  }
}

function sendToApp(object) {
  if (!socket || socket.readyState !== WebSocket.OPEN) return;
  socket.send(JSON.stringify(object));
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
    attempt = 0;
    console.log(`[PC Tunes] connected on port ${port}`);
    clearInterval(keepaliveTimer);
    // WebSocket traffic resets the service worker idle timer on Chrome 116+.
    keepaliveTimer = setInterval(() => sendToApp({ type: "ping" }), KEEPALIVE_MS);
  };

  ws.onmessage = async (event) => {
    let message;
    try {
      message = JSON.parse(event.data);
    } catch (error) {
      return;
    }
    if (!message || message.type !== "cmd" || typeof message.tabId !== "number") return;

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
    socket = null;
    scheduleReconnect();
  };

  ws.onerror = () => {
    // onclose always follows, which is where the reconnect is scheduled.
  };
}

chrome.runtime.onMessage.addListener((message, sender) => {
  if (!message || message.kind !== "state") return;
  const tabId = sender.tab && sender.tab.id;
  if (typeof tabId !== "number") return;

  // Once a tab's window kind is known, label and forward synchronously: two updates
  // from one tab must not overtake each other on the way to the app.
  const known = knownTabs.get(tabId);
  if (known) {
    sendToApp({ type: "state", tabId, source: known, ...message.payload });
    return;
  }

  windowKindFor(tabId).then((source) => {
    knownTabs.set(tabId, source);
    sendToApp({ type: "state", tabId, source, ...message.payload });
  });
});

chrome.tabs.onRemoved.addListener((tabId) => {
  if (!knownTabs.has(tabId)) return;
  knownTabs.delete(tabId);
  sendToApp({ type: "gone", tabId });
});

chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
connect();
