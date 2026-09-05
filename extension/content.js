(() => {
  "use strict";

  /// False once this script has outlived the extension that injected it.
  ///
  /// Reloading or removing the extension orphans every content script already in a
  /// page. The page itself keeps running, so this bridge keeps being handed state to
  /// forward — and every `chrome.*` call from here then throws "Extension context
  /// invalidated" *synchronously*, which a `.catch()` never sees because it is a throw
  /// and not a rejected promise. Left alone it repeats on every heartbeat, filling the
  /// extension's error list until the tab is reloaded. Stop at the first one.
  let bridgeAlive = true;

  function teardown() {
    bridgeAlive = false;
    window.removeEventListener("message", onPageMessage);
  }

  function send(message) {
    if (!bridgeAlive) return;
    // `chrome.runtime.id` reads undefined the moment this script is orphaned, and
    // reading it is the only way to notice without provoking the throw — which is
    // logged to the extension's error page whether or not it is caught. The catch
    // below stays as the backstop for a context that dies mid-call.
    if (!chrome.runtime || !chrome.runtime.id) {
      teardown();
      return;
    }
    try {
      const sending = chrome.runtime.sendMessage(message);
      if (sending && typeof sending.catch === "function") {
        // A rejection is ordinary: the service worker sleeps, and the dropped message
        // is replaced by the next heartbeat.
        sending.catch(() => {});
      }
    } catch (error) {
      teardown();
    }
  }

  function onPageMessage(event) {
    if (event.source !== window) return;
    const data = event.data;
    if (!data || data.__pcTunes !== true || data.dir !== "out") return;

    if (data.kind === "notice") {
      send({ kind: "notice", text: data.text });
      return;
    }
    if (data.kind === "queue") {
      send({ kind: "queue", items: data.items });
      return;
    }
    send({ kind: "state", payload: data.payload });
  }

  window.addEventListener("message", onPageMessage);

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message) return;
    if (message.kind === "alive") {
      // Answering at all is the point — it proves this content script still exists.
      sendResponse({ alive: true });
      return;
    }
    if (message.kind === "cmd") {
      window.postMessage(
        { __pcTunes: true, dir: "in", action: message.action, value: message.value },
        "*"
      );
    }
  });

  // Announced separately from playback state: a page with an empty queue never emits
  // a state message, but can still be told to start playing.
  send({ kind: "ready" });
})();
