(() => {
  "use strict";

  window.addEventListener("message", (event) => {
    if (event.source !== window) return;
    const data = event.data;
    if (!data || data.__pcTunes !== true || data.dir !== "out") return;
    chrome.runtime.sendMessage({ kind: "state", payload: data.payload }).catch(() => {
      // The service worker restarts on its own; a dropped message is replaced by
      // the next heartbeat.
    });
  });

  chrome.runtime.onMessage.addListener((message) => {
    if (!message || message.kind !== "cmd") return;
    window.postMessage({ __pcTunes: true, dir: "in", action: message.action }, "*");
  });

  // Announced separately from playback state: a page with an empty queue never emits
  // a state message, but can still be told to start playing.
  chrome.runtime.sendMessage({ kind: "ready" }).catch(() => {});
})();
