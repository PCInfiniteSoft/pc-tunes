(() => {
  "use strict";

  window.addEventListener("message", (event) => {
    if (event.source !== window) return;
    const data = event.data;
    if (!data || data.__pcTunes !== true || data.dir !== "out") return;

    if (data.kind === "notice") {
      chrome.runtime.sendMessage({ kind: "notice", text: data.text }).catch(() => {});
      return;
    }
    if (data.kind === "queue") {
      chrome.runtime.sendMessage({ kind: "queue", items: data.items }).catch(() => {});
      return;
    }

    chrome.runtime.sendMessage({ kind: "state", payload: data.payload }).catch(() => {
      // The service worker restarts on its own; a dropped message is replaced by
      // the next heartbeat.
    });
  });

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message) return;
    if (message.kind === "alive") {
      // Answering at all is the point — it proves this content script still exists.
      sendResponse({ alive: true });
      return;
    }
    if (message.kind === "cmd") {
      window.postMessage(
        { __pcTunes: true, dir: "in", action: message.action, value: message.value, text: message.text },
        "*"
      );
    }
  });

  // Announced separately from playback state: a page with an empty queue never emits
  // a state message, but can still be told to start playing.
  chrome.runtime.sendMessage({ kind: "ready" }).catch(() => {});
})();
