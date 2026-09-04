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
  // The like-button renderer sits in the player bar and carries a `like-status`
  // attribute of "LIKE", "DISLIKE" or "INDIFFERENT".
  const LIKE_RENDERER_SELECTORS = [
    "ytmusic-like-button-renderer",
    "#like-button-renderer",
  ];
  const LIKE_BUTTON_SELECTORS = [
    "#button-shape-like button",
    "yt-button-shape#like button",
    "button[aria-label='Like']",
  ];
  const DISLIKE_BUTTON_SELECTORS = [
    "#button-shape-dislike button",
    "yt-button-shape#dislike button",
    "button[aria-label='Dislike']",
  ];
  const QUEUE_MAX = 20;
  const QUEUE_ITEM_SELECTORS = [
    "ytmusic-player-queue-item",
  ];
  const QUEUE_TITLE_SELECTORS = [
    ".song-title",
    ".title",
    "yt-formatted-string.song-title",
  ];
  const QUEUE_ARTIST_SELECTORS = [
    ".byline",
    ".subtitle",
    "yt-formatted-string.byline",
  ];
  // Reuses the Quick Pick shapes where the search results page renders the same
  // list-item renderer, plus a couple of search-specific guesses.
  const SEARCH_RESULT_SELECTORS = [
    "ytmusic-shelf-renderer ytmusic-responsive-list-item-renderer ytmusic-play-button-renderer",
    "ytmusic-shelf-renderer ytmusic-responsive-list-item-renderer #play-button",
    "ytmusic-section-list-renderer ytmusic-responsive-list-item-renderer #play-button",
    "ytmusic-responsive-list-item-renderer a#thumbnail",
  ];
  const SEARCH_PENDING_KEY = "pcTunesPendingSearch";

  const playerBar = () => document.querySelector("ytmusic-player-bar");
  const videoEl = () => document.querySelector("video");

  function notice(text) {
    window.postMessage({ __pcTunes: true, dir: "out", kind: "notice", text }, "*");
  }

  function likeRenderer() {
    const bar = playerBar();
    if (!bar) return null;
    for (const selector of LIKE_RENDERER_SELECTORS) {
      const found = bar.querySelector(selector);
      if (found) return found;
    }
    return null;
  }

  /// Maps the renderer's `like-status` attribute to the wire vocabulary. Returns
  /// `undefined` for "INDIFFERENT" and for a renderer that cannot be found — both mean
  /// "omit the field", which is distinct from actively knowing the track is unrated.
  function readLiked() {
    const renderer = likeRenderer();
    if (!renderer) return undefined;
    const status = renderer.getAttribute("like-status");
    if (status === "LIKE") return "like";
    if (status === "DISLIKE") return "dislike";
    return undefined;
  }

  function clickRatingButton(selectors, label) {
    const renderer = likeRenderer();
    const button = renderer
      ? selectors.map((selector) => renderer.querySelector(selector)).find(Boolean)
      : null;
    if (button) {
      button.click();
      setTimeout(() => push(true), 300);
      return;
    }
    console.warn(`[PC Tunes] ${label} control not found`);
    notice("Like and dislike are unavailable — YouTube Music's page has changed.");
  }

  function firstText(scope, selectors) {
    for (const selector of selectors) {
      const el = scope.querySelector(selector);
      const text = el && el.textContent && el.textContent.trim();
      if (text) return text;
    }
    return "";
  }

  /// Reads the up-next list, capped at QUEUE_MAX. An empty or missing list is ordinary
  /// (queue closed, or nothing queued) and is reported as an empty array, not a notice.
  function readQueue() {
    let nodes = [];
    for (const selector of QUEUE_ITEM_SELECTORS) {
      const found = document.querySelectorAll(selector);
      if (found.length) {
        nodes = Array.from(found);
        break;
      }
    }
    const items = [];
    for (const node of nodes) {
      if (items.length >= QUEUE_MAX) break;
      const title = firstText(node, QUEUE_TITLE_SELECTORS);
      if (!title) continue;
      items.push({ title, artist: firstText(node, QUEUE_ARTIST_SELECTORS) });
    }
    return items;
  }

  function readState() {
    const video = videoEl();
    const metadata = navigator.mediaSession && navigator.mediaSession.metadata;
    if (!video || !metadata) return null;

    const artworkList = metadata.artwork || [];
    const artwork = artworkList.length ? artworkList[artworkList.length - 1].src : null;

    const state = {
      playing: !video.paused,
      title: metadata.title || "",
      artist: metadata.artist || "",
      album: metadata.album || "",
      artwork,
      position: video.currentTime || 0,
      duration: Number.isFinite(video.duration) ? video.duration : 0,
      volume: Number.isFinite(video.volume) ? video.volume : 1,
    };
    const liked = readLiked();
    if (liked) state.liked = liked;
    return state;
  }

  let lastKey = "";
  let coalesceTimer = null;

  function push(force) {
    const state = readState();
    if (!state) return;
    const key = JSON.stringify([
      state.playing, state.title, state.artist, state.album, state.artwork,
      state.liked, state.volume,
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
    notice("Couldn't start playback — no queued track or Quick Pick was found. YouTube Music's page may have changed.");
  }

  /// Polls for the first playable search result and clicks it, mirroring
  /// `startPlayback`'s deadline-and-poll shape. Used both right after a `search`
  /// command and, via `resumePendingSearch`, after the navigation it causes reloads
  /// this script.
  function pollSearchResult(deadline) {
    const candidate = SEARCH_RESULT_SELECTORS
      .map((selector) => document.querySelector(selector))
      .find(Boolean);
    if (candidate) {
      candidate.click();
      setTimeout(() => push(true), 1000);
      return;
    }
    if (Date.now() < deadline) {
      setTimeout(() => pollSearchResult(deadline), START_POLL_MS);
      return;
    }
    console.warn("[PC Tunes] no playable search result found before the deadline");
    notice("Search didn't find a playable result — YouTube Music's page may have changed or the results didn't load in time.");
  }

  /// Navigating by assigning `location.href` always reloads the document, even though
  /// the destination is the same single-page app — the browser gives page script no way
  /// to intercept that. The pending deadline is stashed in sessionStorage (which survives
  /// the reload within the same tab) so the reinjected script can resume polling for a
  /// result once the new page comes up.
  function runSearch(text) {
    const query = typeof text === "string" ? text.trim() : "";
    if (!query) return;
    try {
      sessionStorage.setItem(
        SEARCH_PENDING_KEY,
        JSON.stringify({ deadline: Date.now() + START_TIMEOUT_MS })
      );
    } catch (error) {
      // Storage can be unavailable (private mode, quota). The search still happens;
      // it just won't resume polling once the navigation completes.
    }
    window.location.href = `https://music.youtube.com/search?q=${encodeURIComponent(query)}`;
  }

  function resumePendingSearch() {
    let pending = null;
    try {
      const raw = sessionStorage.getItem(SEARCH_PENDING_KEY);
      sessionStorage.removeItem(SEARCH_PENDING_KEY);
      if (raw) pending = JSON.parse(raw);
    } catch (error) {
      pending = null;
    }
    if (!pending || typeof pending.deadline !== "number") return;
    if (Date.now() < pending.deadline) {
      pollSearchResult(pending.deadline);
    }
  }

  function runCommand(action, data) {
    // focusTab is handled entirely by the service worker.
    if (action === "focusTab") return;

    if (action === "startPlayback") {
      startPlayback();
      return;
    }

    if (action === "like") {
      clickRatingButton(LIKE_BUTTON_SELECTORS, "like");
      return;
    }

    if (action === "dislike") {
      clickRatingButton(DISLIKE_BUTTON_SELECTORS, "dislike");
      return;
    }

    if (action === "volume") {
      const video = videoEl();
      if (!video) {
        console.warn("[PC Tunes] volume control not found: no video element");
        notice("Volume control is unavailable — YouTube Music's page has changed.");
        return;
      }
      if (typeof data.value !== "number") return;
      video.volume = Math.min(1, Math.max(0, data.value));
      setTimeout(() => push(true), 100);
      return;
    }

    if (action === "seek") {
      const video = videoEl();
      if (!video) {
        console.warn("[PC Tunes] seek control not found: no video element");
        notice("Seek is unavailable — YouTube Music's page has changed.");
        return;
      }
      if (typeof data.value !== "number") return;
      const duration = Number.isFinite(video.duration) ? video.duration : 0;
      video.currentTime = Math.min(Math.max(0, data.value), duration);
      // Push immediately, not after the usual settle delay, so the app's local
      // interpolation resyncs to the new position right away.
      push(true);
      return;
    }

    if (action === "search") {
      runSearch(data.text);
      return;
    }

    if (action === "requestQueue") {
      window.postMessage({ __pcTunes: true, dir: "out", kind: "queue", items: readQueue() }, "*");
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
    if (action === "next" || action === "prev") {
      notice("Next and previous are unavailable — YouTube Music's page has changed.");
    } else if (action === "playPause") {
      notice("Play/pause is unavailable — YouTube Music's page has changed.");
    } else {
      notice(`"${action}" is unavailable — YouTube Music's page has changed.`);
    }
  }

  window.addEventListener("message", (event) => {
    if (event.source !== window) return;
    const data = event.data;
    if (!data || data.__pcTunes !== true || data.dir !== "in") return;
    runCommand(data.action, data);
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
        boundVideo.removeEventListener("volumechange", onPlaybackEvent);
      }
      video.addEventListener("play", onPlaybackEvent);
      video.addEventListener("pause", onPlaybackEvent);
      video.addEventListener("loadedmetadata", onPlaybackEvent);
      video.addEventListener("volumechange", onPlaybackEvent);
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
        attributes: true,
        attributeFilter: ["like-status"],
      });
      boundBar = bar;
    }
  }

  setInterval(bindIfChanged, 1000);
  setInterval(() => push(true), HEARTBEAT_MS);
  bindIfChanged();
  push(true);
  resumePendingSearch();
})();
