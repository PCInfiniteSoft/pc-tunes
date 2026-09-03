(() => {
  "use strict";

  const HEARTBEAT_MS = 5000;
  const COALESCE_MS = 500;
  const CONTROL_SELECTORS = {
    playPause: "#play-pause-button",
    next: ".next-button",
    prev: ".previous-button",
  };
  const START_TIMEOUT_MS = 15000;
  const START_POLL_MS = 500;
  // The home page's markup is not ours and has changed before, so try several shapes.
  const QUICK_PICK_SELECTORS = [
    "ytmusic-responsive-list-item-renderer ytmusic-play-button-renderer",
    "ytmusic-responsive-list-item-renderer #play-button",
    "ytmusic-two-row-item-renderer ytmusic-play-button-renderer",
    "ytmusic-carousel-shelf-renderer ytmusic-play-button-renderer",
    "ytmusic-responsive-list-item-renderer a#thumbnail",
  ];

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

  /// Resumes the queued track if there is one, otherwise starts the first Quick Pick.
  /// The page is often still loading when this arrives, so it keeps looking until
  /// something is playable or the deadline passes.
  function startPlayback(deadline) {
    const stopAt = deadline || Date.now() + START_TIMEOUT_MS;

    const video = videoEl();
    if (video && Number.isFinite(video.duration) && video.duration > 0) {
      if (video.paused) {
        video.play();
      }
      setTimeout(() => push(true), 300);
      return;
    }

    for (const selector of QUICK_PICK_SELECTORS) {
      const candidate = document.querySelector(selector);
      if (candidate) {
        candidate.click();
        setTimeout(() => push(true), 1000);
        return;
      }
    }

    if (Date.now() < stopAt) {
      setTimeout(() => startPlayback(stopAt), START_POLL_MS);
      return;
    }
    console.warn("[PC Tunes] nothing to start: no queued track and no Quick Pick found");
  }

  function runCommand(action) {
    // focusTab is handled entirely by the service worker.
    if (action === "focusTab") return;

    if (action === "startPlayback") {
      startPlayback();
      return;
    }

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

  let boundVideo = null;
  let boundBar = null;
  let barObserver = null;

  function onPlaybackEvent() {
    push(true);
  }

  /// YouTube Music replaces the video element and can remount the player bar during
  /// SPA navigation, so listeners have to follow whatever is currently on the page
  /// rather than whatever was there at load.
  function bindIfChanged() {
    const video = videoEl();
    if (video && video !== boundVideo) {
      if (boundVideo) {
        boundVideo.removeEventListener("play", onPlaybackEvent);
        boundVideo.removeEventListener("pause", onPlaybackEvent);
        boundVideo.removeEventListener("loadedmetadata", onPlaybackEvent);
      }
      video.addEventListener("play", onPlaybackEvent);
      video.addEventListener("pause", onPlaybackEvent);
      video.addEventListener("loadedmetadata", onPlaybackEvent);
      boundVideo = video;
      push(true);
    }

    const bar = playerBar();
    if (bar && bar !== boundBar) {
      if (barObserver) barObserver.disconnect();
      barObserver = new MutationObserver(schedulePush);
      barObserver.observe(bar, {
        subtree: true,
        childList: true,
        characterData: true,
      });
      boundBar = bar;
    }
  }

  setInterval(bindIfChanged, 1000);
  setInterval(() => push(true), HEARTBEAT_MS);
  bindIfChanged();
  push(true);
})();
