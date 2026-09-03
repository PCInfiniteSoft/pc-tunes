# PC Tunes — YouTube Music Menu Bar Widget

**Date:** 2026-09-03
**Status:** Approved design, ready for implementation planning

## Problem

Controlling YouTube Music on macOS requires switching to its window. The user wants a
macOS menu bar widget that shows the currently playing track and provides basic
transport controls without leaving the current app.

## Constraints

- **Host:** macOS 26.6.2 (Darwin 25.6), Apple Silicon Mac. Swift toolchain and Xcode
  present. Python 3.11 and Node available but not required.
- **macOS 15.4+ blocks the private MediaRemote framework for third-party apps**, so
  system-level "now playing" data is unavailable. Track state must come from the page
  itself.
- YouTube Music is installed as a **Chrome PWA** at
  `~/Applications/Chrome Apps.localized/YouTube Music.app`. It is still a Chrome tab
  living in an app-type window, so extension content scripts apply normally.
- Chrome is the only browser in scope. Safari is not supported.

## Scope

**In scope:**

- Play / Pause / Next / Previous
- Now-playing display: title, artist, album art
- Menu item to open or focus YouTube Music
- Launch at login

**Out of scope (YAGNI):**

- Like / dislike
- Volume control and seek bar
- Global hotkeys
- Playlist or queue browsing
- Safari support

## Architecture

Two processes: Chrome (hosting the extension) and a native Swift menu bar app. They
talk over a loopback WebSocket.

```
music.youtube.com (PWA window or tab)      Menu bar app (Swift)
┌──────────────────────────────┐          ┌──────────────────────────┐
│ inject.js  (MAIN world)      │          │ WSServer                 │
│  - reads navigator.          │          │  NWListener on           │
│    mediaSession.metadata     │          │  127.0.0.1:8787..8791    │
│  - reads <video> paused/     │          │                          │
│    currentTime/duration      │          │ PlayerState              │
│  - clicks player-bar buttons │          │  (ObservableObject)      │
└───────────┬──────────────────┘          │                          │
            │ window.postMessage          │ MenuBarExtra UI          │
┌───────────▼──────────────────┐          └────────────┬─────────────┘
│ content.js (isolated world)  │                       │
│  - postMessage <-> runtime   │                       │
└───────────┬──────────────────┘                       │
            │ chrome.runtime.sendMessage               │
┌───────────▼──────────────────┐   WebSocket           │
│ sw.js (service worker)       │◄──────────────────────┘
│  - owns the WebSocket        │   ws://127.0.0.1:<port>
│  - source arbitration        │
│  - reconnect + keepalive     │
└──────────────────────────────┘
```

### Why the WebSocket lives in the service worker

`music.youtube.com` is an HTTPS page. A `ws://127.0.0.1` connection opened from page
context is subject to Chrome's Local Network Access restrictions and may be blocked or
prompt the user. The extension service worker runs on the `chrome-extension://` origin
and is exempt.

Chrome 116+ resets the service worker's idle timer on WebSocket activity, so an
application-level ping every 20 seconds keeps the worker alive for as long as the
connection is up.

### Why a MAIN-world script is required

`navigator.mediaSession.metadata` set by the YouTube Music page is not readable from an
isolated content script world. `inject.js` runs in the page's own JavaScript context
(`"world": "MAIN"` in the manifest) and relays data out via `window.postMessage`.

### Source arbitration

The PWA window and a regular Chrome tab can both have YouTube Music open, producing two
state sources.

**Rule: the PWA always wins.** The service worker resolves each sender's window type
with `chrome.windows.get(windowId)`. If any connected source lives in a window of type
`app`, it is the sole active source and all `normal`-window sources are ignored. If no
app-type window exists, the most recently updated normal tab is used.

## Protocol

Newline-free JSON objects over a single WebSocket text frame each.

### Extension to app

```json
{
  "type": "state",
  "tabId": 42,
  "source": "app",
  "playing": true,
  "title": "Song title",
  "artist": "Artist name",
  "album": "Album name",
  "artwork": "https://lh3.googleusercontent.com/...",
  "position": 42.1,
  "duration": 215.0
}
```

`source` is `"app"` for a PWA window and `"tab"` for a regular tab. Sent on metadata
change, on play/pause, and as a heartbeat every 5 seconds.

```json
{ "type": "gone", "tabId": 42 }
```

Sent when the YouTube Music tab or window closes.

### App to extension

```json
{ "type": "cmd", "action": "playPause" }
{ "type": "cmd", "action": "next" }
{ "type": "cmd", "action": "prev" }
{ "type": "cmd", "action": "focusTab" }
```

Commands are routed to the currently active source per the arbitration rule.

## Components

### Chrome extension (MV3)

| File | Responsibility |
| --- | --- |
| `manifest.json` | MV3 manifest. Two content scripts on `https://music.youtube.com/*` — one isolated, one `"world": "MAIN"`. Permissions: `tabs`, `windows` is implicit via `tabs`. No host permissions beyond the content script match. |
| `inject.js` | MAIN world. Reads `navigator.mediaSession.metadata` and the `<video>` element. Executes commands by clicking real player-bar controls. Emits change events. |
| `content.js` | Isolated world. Bridges `window.postMessage` and `chrome.runtime` messaging in both directions. |
| `sw.js` | Service worker. Owns the WebSocket client, port discovery, reconnect backoff, keepalive ping, source arbitration, and command routing. |

**Control selectors** (`inject.js`):

- Play/Pause — `#play-pause-button` in `ytmusic-player-bar`
- Next — `.next-button` in `ytmusic-player-bar`
- Previous — `.previous-button` in `ytmusic-player-bar`

**State change detection:** a `MutationObserver` on the player bar plus `play`, `pause`,
and `timeupdate` listeners on the `<video>` element, coalesced so at most one `state`
message is sent per 500 ms.

### Menu bar app (Swift)

Built with Swift Package Manager. No Xcode project file; `build.sh` assembles the
bundle. No third-party dependencies — `Network.framework` provides the WebSocket server
via `NWProtocolWebSocket`.

| File | Responsibility |
| --- | --- |
| `Sources/PCTunes/WSServer.swift` | `NWListener` bound to 127.0.0.1. Tries ports 8787 through 8791 in order and binds the first free one. Decodes incoming JSON, encodes outgoing commands. |
| `Sources/PCTunes/PlayerState.swift` | `ObservableObject` holding the current track, playing flag, and connection state. Owns the disconnect timeout. |
| `Sources/PCTunes/LoginItem.swift` | Registers and unregisters the app with `SMAppService.mainApp`. |
| `Sources/PCTunes/YouTubeMusicLauncher.swift` | Launches the PWA, falling back to a Chrome tab. |
| `Sources/PCTunes/App.swift` | `MenuBarExtra` scene and dropdown view. |
| `build.sh` | Builds release binary and assembles `PC Tunes.app` with an `Info.plist` setting `LSUIElement` to `true`. |

**Menu bar icon** is always visible, in two states:

- **Disconnected / no source** — dimmed `music.note` symbol only. Dropdown shows
  "Not playing", an "Open YouTube Music" button, a "Launch at login" toggle, and "Quit".
- **Connected** — `music.note` plus `Title — Artist`, truncated to 35 characters with an
  ellipsis. Dropdown shows album art, full title and artist, the ⏮ ⏯ ⏭ row, a
  "Go to YouTube Music" button, a "Launch at login" toggle, and "Quit".

**Open YouTube Music** behaviour:

1. If a source is connected, send `{"type":"cmd","action":"focusTab"}`. The service
   worker calls `chrome.tabs.update({active: true})` and
   `chrome.windows.update({focused: true})`.
2. Otherwise, if `~/Applications/Chrome Apps.localized/YouTube Music.app` exists, launch
   it with `NSWorkspace.openApplication`.
3. Otherwise, open `https://music.youtube.com` in Google Chrome.

## Error handling

| Situation | Behaviour |
| --- | --- |
| YouTube Music not open | Dimmed icon, transport buttons disabled, "Open YouTube Music" enabled. |
| Menu bar app not running | Service worker retries with backoff: 1s, 2s, 4s, 8s, then every 30s. Silent — no console spam beyond one line per attempt. |
| Extension disconnects without a `gone` message | App marks state disconnected after 15 seconds without a heartbeat. |
| Port 8787 occupied | App tries 8787 through 8791 and binds the first free port. The service worker probes the same range in order on each connection attempt. |
| Both PWA and regular tab open | PWA wins. Regular tabs are ignored entirely while an app-type window is connected. |
| YouTube Music changes its DOM and a control selector misses | `inject.js` falls back to `video.play()` / `video.pause()` for play/pause. Next and previous have no fallback; the app logs a warning and the button becomes a no-op rather than throwing. |
| Artwork URL fails to load | Show the `music.note` symbol placeholder in the dropdown. |

## Testing

**Swift unit tests** (`swift test`):

- JSON decoding of `state` and `gone` messages, including missing optional fields.
- Source arbitration: app-type source preempts tab-type; tab-type used when alone;
  falling back to the most recent tab when the app window closes.
- Disconnect timeout: state flips to disconnected 15 seconds after the last heartbeat.
- Port selection: binds the next port when the preferred one is occupied.

**Manual verification checklist:**

1. Open the YouTube Music PWA, play a track — title and artist appear in the menu bar.
2. Click ⏯ from the menu bar — playback toggles, icon state updates within 1 second.
3. Click ⏭ and ⏮ — track changes and the display follows.
4. Open YouTube Music in a regular Chrome tab as well — the PWA still drives the widget.
5. Close the PWA — the widget switches to the regular tab.
6. Close all YouTube Music windows — the icon dims.
7. Click "Open YouTube Music" with nothing open — the PWA launches.
8. Quit and relaunch the app while music plays — state resyncs within 5 seconds.
9. Reboot with "Launch at login" enabled — the icon returns.

## Security notes

- The WebSocket server binds to `127.0.0.1` only, never `0.0.0.0`.
- The app accepts only two inbound message types, `state` and `gone`. Anything else is
  dropped. No shell command or file path is ever derived from wire data — the launcher
  paths are compile-time constants.
- The extension's `matches` is limited to `https://music.youtube.com/*`.

## Repository layout

```
PC Tunes/
├── extension/
│   ├── manifest.json
│   ├── sw.js
│   ├── content.js
│   └── inject.js
├── app/
│   ├── Package.swift
│   ├── Sources/PCTunes/
│   │   ├── App.swift
│   │   ├── WSServer.swift
│   │   ├── PlayerState.swift
│   │   ├── LoginItem.swift
│   │   └── YouTubeMusicLauncher.swift
│   ├── Tests/PCTunesTests/
│   └── build.sh
├── docs/
└── README.md
```
