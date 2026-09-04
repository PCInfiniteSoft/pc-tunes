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
  // The like-button renderer sits in the visible player bar (see `playerBar`) and
  // carries a `like-status` attribute of "LIKE", "DISLIKE" or "INDIFFERENT". Verified
  // present, by this id, with a track loaded. `ytmusic-like-button-renderer` elements
  // also exist outside the player bar, belonging to menu renderers for other tracks —
  // scoping the lookup to the (correctly-chosen) player bar is what keeps this on the
  // currently-playing track rather than one of those.
  const LIKE_RENDERER_SELECTORS = [
    "#like-button-renderer",
    "ytmusic-like-button-renderer",
  ];
  // The renderer holds exactly two <button> elements with no id or class of their own,
  // each wrapped in a yt-button-shape, in DOM order: like first, dislike second.
  // Their aria-label ("Like"/"Dislike") is a localized, English-only string, so it
  // cannot be matched on for anyone whose YouTube is not in English — position within
  // the renderer is the only language-independent signal available.
  const RATING_BUTTON_INDEX = { like: 0, dislike: 1 };
  const QUEUE_MAX = 20;
  const QUEUE_ITEM_SELECTORS = [
    "ytmusic-player-queue-item",
  ];
  // Verified against a loaded queue (51 items) with Thai-text tracks: both resolve
  // inside `ytmusic-player-queue-item`.
  const QUEUE_TITLE_SELECTOR = ".song-title";
  const QUEUE_ARTIST_SELECTOR = ".byline";
  const SEARCH_PENDING_KEY = "pcTunesPendingSearch";

  /// Two player bars exist in the page; only one is ever visible, and the hidden one
  /// carries a full set of identical-looking controls that do nothing. Verified by
  /// clicking `.next-button` inside the visible bar and observing
  /// `navigator.mediaSession.metadata` change, and `#play-pause-button` toggling
  /// `video.paused` both ways.
  const playerBar = () =>
    [...document.querySelectorAll("ytmusic-player-bar")].find((bar) => bar.offsetParent !== null) ??
    document.querySelector("ytmusic-player-bar");
  const videoEl = () => document.querySelector("video");

  /// YouTube's own player object, which YouTube Music embeds and drives.
  ///
  /// It is the only source of per-track timing on this page. YouTube Music streams a
  /// whole queue through a single MediaSource, so the `<video>` element's `currentTime`
  /// and `duration` are the totals for the listening session, not for the song: after
  /// two tracks a 3:42 song reads as "10:28 / 11:55". The player object reports the
  /// current track — verified against `watch?v=6uxTE0h6w94`, where `getDuration()`
  /// returned 293 for a track that is 4:53 long.
  const moviePlayer = () => document.getElementById("movie_player");

  /// Position and duration of the track playing now, both in seconds.
  ///
  /// Falls back to the video element when the player object is not up yet — during a
  /// page load it briefly is not. The fallback is wrong in exactly the way described
  /// above once a second track has played, but it is only ever reached before the first
  /// one has finished, when the two agree.
  function readTiming(video) {
    const player = moviePlayer();
    if (player && typeof player.getDuration === "function"
        && typeof player.getCurrentTime === "function") {
      const duration = player.getDuration();
      const position = player.getCurrentTime();
      if (Number.isFinite(duration) && duration > 0 && Number.isFinite(position)) {
        return { position, duration };
      }
    }
    return {
      position: video.currentTime || 0,
      duration: Number.isFinite(video.duration) ? video.duration : 0,
    };
  }

  /// The first playable item on the page.
  ///
  /// A song links to `watch?v=`; an artist links to `channel/` and an album to
  /// `browse/`, so this is what tells a playable result apart from a navigable one.
  /// It holds on the home page (verified: 14 such links) and on search results alike
  /// (search results carry no play-button component at all, and the first result is
  /// often the artist rather than a song), and unlike a component name it does not
  /// depend on which shelf the page happens to be rendering.
  const firstPlayableLink = () => document.querySelector('a[href*="watch?v="]');

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

  function clickRatingButton(kind) {
    const renderer = likeRenderer();
    const button = renderer
      ? renderer.querySelectorAll("button")[RATING_BUTTON_INDEX[kind]]
      : null;
    if (button) {
      button.click();
      setTimeout(() => push(true), 300);
      return;
    }
    console.warn(`[PC Tunes] ${kind} control not found`);
    notice("Like and dislike are unavailable — YouTube Music's page has changed.");
  }

  function firstText(scope, selector) {
    const el = scope.querySelector(selector);
    const text = el && el.textContent && el.textContent.trim();
    return text || "";
  }

  /// Reads the up-next list, capped at QUEUE_MAX. An empty or missing list is ordinary
  /// (queue closed, or nothing queued) and is reported as an empty array, not a notice.
  ///
  /// The queue holds the whole session, not just what is still to come, so everything
  /// up to and including the current track is dropped. YouTube Music marks that track
  /// with a bare `selected` attribute — verified against a 74-item queue, where exactly
  /// one item carried it. If nothing is marked, the list is used whole rather than
  /// discarded: a slightly wrong list beats an empty one.
  function readQueue() {
    let nodes = [];
    for (const selector of QUEUE_ITEM_SELECTORS) {
      const found = document.querySelectorAll(selector);
      if (found.length) {
        nodes = Array.from(found);
        break;
      }
    }
    const current = nodes.findIndex((node) => node.hasAttribute("selected"));
    if (current >= 0) {
      nodes = nodes.slice(current + 1);
    }
    const items = [];
    for (const node of nodes) {
      if (items.length >= QUEUE_MAX) break;
      const title = firstText(node, QUEUE_TITLE_SELECTOR);
      if (!title) continue;
      items.push({ title, artist: firstText(node, QUEUE_ARTIST_SELECTOR) });
    }
    return items;
  }

  function readState() {
    const video = videoEl();
    const metadata = navigator.mediaSession && navigator.mediaSession.metadata;
    if (!video || !metadata) return null;

    const artworkList = metadata.artwork || [];
    const artwork = artworkList.length ? artworkList[artworkList.length - 1].src : null;

    const timing = readTiming(video);
    const state = {
      playing: !video.paused,
      title: metadata.title || "",
      artist: metadata.artist || "",
      album: metadata.album || "",
      artwork,
      position: timing.position,
      duration: timing.duration,
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

  /// Resumes the queued track if there is one, otherwise clicks the first playable
  /// link on the page (see `firstPlayableLink`). The page is often still loading when
  /// this arrives, so it keeps looking until something is playable or the deadline
  /// passes.
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

    const link = firstPlayableLink();
    if (link) {
      link.click();
      setTimeout(() => push(true), 1000);
      return;
    }

    if (Date.now() < stopAt) {
      setTimeout(() => startPlayback(stopAt), START_POLL_MS);
      return;
    }
    console.warn("[PC Tunes] nothing to start: no queued track and no playable link found");
    notice("Couldn't start playback — no queued track or playable item was found. YouTube Music's page may have changed.");
  }

  /// Polls for the first playable search result — the first `watch?v=` link, via
  /// `firstPlayableLink` — and clicks it, mirroring `startPlayback`'s
  /// deadline-and-poll shape. Used both right after a `search` command and, via
  /// `resumePendingSearch`, after the navigation it causes reloads this script.
  function pollSearchResult(deadline) {
    const candidate = firstPlayableLink();
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
      clickRatingButton("like");
      return;
    }

    if (action === "dislike") {
      clickRatingButton("dislike");
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
      // Seek through the player, on the same clock the position was reported on.
      // Writing `video.currentTime` would land at that offset into the whole session:
      // once a second track has played, dragging to 1:00 jumps back into the first.
      const timing = readTiming(video);
      const target = Math.min(Math.max(0, data.value), timing.duration || 0);
      const player = moviePlayer();
      if (player && typeof player.seekTo === "function") {
        player.seekTo(target, true);
      } else {
        video.currentTime = target;
      }
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
