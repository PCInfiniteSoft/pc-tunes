(() => {
  "use strict";

  const HEARTBEAT_MS = 5000;
  const COALESCE_MS = 500;
  const CONTROL_SELECTORS = {
    playPause: "#play-pause-button",
    next: ".next-button",
    prev: ".previous-button",
  };

  const playerBar = () => document.querySelector("ytmusic-player-bar");
  const videoEl = () => document.querySelector("video");

  function readState() {
    const video = videoEl();
    const metadata = navigator.mediaSession && navigator.mediaSession.metadata;
    if (!video || !metadata) return null;

    const artworkList = metadata.artwork || [];
    const artwork = artworkList.length ? artworkList[artworkList.length - 1].src : null;

    return {
      playing: !video.paused,
      title: metadata.title || "",
      artist: metadata.artist || "",
      album: metadata.album || "",
      artwork,
      position: video.currentTime || 0,
      duration: Number.isFinite(video.duration) ? video.duration : 0,
    };
  }

  let lastKey = "";
  let coalesceTimer = null;

  function push(force) {
    const state = readState();
    if (!state) return;
    const key = JSON.stringify([
      state.playing, state.title, state.artist, state.album, state.artwork,
    ]);
    if (!force && key === lastKey) return;
    lastKey = key;
    window.postMessage({ __pcTunes: true, dir: "out", payload: state }, "*");
  }

  function schedulePush() {
    if (coalesceTimer) return;
    coalesceTimer = setTimeout(() => {
      coalesceTimer = null;
      push(false);
    }, COALESCE_MS);
  }

  function runCommand(action) {
    // focusTab is handled entirely by the service worker.
    if (action === "focusTab") return;

    const selector = CONTROL_SELECTORS[action];
    const bar = playerBar();
    const button = selector && bar ? bar.querySelector(selector) : null;
    if (button) {
      button.click();
      setTimeout(() => push(true), 300);
      return;
    }

    // Fallback for play/pause only. Next and previous have no equivalent.
    if (action === "playPause") {
      const video = videoEl();
      if (video) {
        if (video.paused) { video.play(); } else { video.pause(); }
        setTimeout(() => push(true), 300);
        return;
      }
    }
    console.warn("[PC Tunes] control not found for action:", action);
  }

  window.addEventListener("message", (event) => {
    if (event.source !== window) return;
    const data = event.data;
    if (!data || data.__pcTunes !== true || data.dir !== "in") return;
    runCommand(data.action);
  });

  function attach() {
    const video = videoEl();
    if (!video) {
      setTimeout(attach, 500);
      return;
    }
    video.addEventListener("play", () => push(true));
    video.addEventListener("pause", () => push(true));
    video.addEventListener("loadedmetadata", () => push(true));

    const bar = playerBar();
    if (bar) {
      new MutationObserver(schedulePush).observe(bar, {
        subtree: true,
        childList: true,
        characterData: true,
      });
    }

    setInterval(() => push(true), HEARTBEAT_MS);
    push(true);
  }

  attach();
})();
