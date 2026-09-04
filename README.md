# PC Tunes

A macOS menu bar widget for YouTube Music. Shows the current track with artwork and
gives you play/pause, next/previous, like/dislike, seeking, volume and an
up-next list without switching away from whatever app you're in.

It needs a Chromium-based browser — Google Chrome is the one this has actually been
tested against. See [Known limitations](#status-and-known-limitations) for what that
means for Brave, Edge and Safari.

## Why it exists

Starting with macOS 15.4, Apple blocks third-party apps from reading "now playing"
information through the private `MediaRemote` framework. That framework is how every
prior generation of menu-bar music widgets worked, and on 15.4+ they simply stop
getting data — there is no public replacement API.

PC Tunes sidesteps the restriction by not using `MediaRemote` at all. Instead, a
browser extension reads the playback state directly out of the YouTube Music page
itself — the same information `MediaRemote` used to relay, read from the source it
originally came from. This is also why the project needs a browser component in the
first place, and why that component only knows about YouTube Music: it isn't reading
system-level media state, it's reading one specific web page.

## How it works

Two processes, one loopback WebSocket:

- **The extension** (`extension/`) runs inside Chrome. `inject.js` executes in the
  YouTube Music page's own JavaScript world so it can read `video.currentTime`,
  `navigator.mediaSession.metadata` and the player bar's DOM directly, and click the
  page's own buttons to control playback. `content.js` relays those messages to and
  from `sw.js`, the background service worker, which owns the single WebSocket
  connection out to the app.
- **The app** (`app/`) is a native SwiftUI menu bar app. `WSServer`
  (`app/Sources/PCTunesCore/WSServer.swift`) listens on `127.0.0.1`, decodes state
  messages, and sends transport commands back over the same socket.

YouTube Music is normally installed as a Chromium "progressive web app" — its own
window, its own Dock icon — but under the hood that's still a Chrome browser tab
running the same extension content scripts. That means it's possible to have YouTube
Music open twice at once: as the installed PWA and as an ordinary tab. When that
happens, `SourceArbiter` (`app/Sources/PCTunesCore/SourceArbiter.swift`) always prefers
the PWA; within a given kind, the most recently updated source wins, and a source that
stops sending heartbeats is dropped after 15 seconds.

## Install

See [INSTALL.md](INSTALL.md) for step-by-step setup (English), or
[INSTALL.th.md](INSTALL.th.md) for the Thai translation.

## Features

- Now-playing display with title, artist, album and artwork
- Play/pause, next, previous
- Like / dislike, reflecting the page's own rating state
- A progress bar that can be dragged to seek
- Volume control
- An up-next list, fetched on demand when you expand it
- Cold-start playback: press play with nothing open and PC Tunes launches YouTube
  Music hidden — it stays in the Dock, never taking the screen — and starts playing
- Launch at login
- A settings window (menu bar title length, notifications, hotkeys)
- Optional notifications when the track changes
- Optional global hotkeys, rebindable in Settings (⌃⌥Space play/pause, ⌃⌥→ next,
  ⌃⌥← previous out of the box) — registered with Carbon's `RegisterEventHotKey`, which
  needs no Accessibility permission
- An in-dropdown notice when the extension can't do something, most often because a
  page selector no longer matches

See `docs/design/2026-09-04-feature-expansion.md` for the design notes behind the
progress bar, settings, hotkeys and browser-fallback work. (In-menu search is
described there too, but was dropped before release — see below.)

## Status and known limitations

This is a working hobby project, built and used daily by its author, not a polished
release. A few things are worth knowing before you install it:

- **There is no search.** It was built and then taken out again before release. It
  worked, but only by navigating the page to a results URL and playing the first
  result, which stops whatever is playing and offers no way to choose anything else —
  a worse deal than switching to the window and typing there.

- **The extension is unpacked, not from the Chrome Web Store.** Chrome will show a
  "disable developer mode extensions" warning on browser restart, the extension's ID
  changes every time you reload it unpacked, and there are no automatic updates. A
  Web Store listing would fix all three; none has been done.
- **The app is ad-hoc signed, not notarized.** You build it from source. A prebuilt
  binary handed to someone else would be blocked by Gatekeeper.
- **Everything the extension does depends on selectors into Google's markup**, which
  can change without notice. When a selector breaks, the one control it drove stops
  working, the page console gets a `console.warn`, and the app surfaces a notice in
  the dropdown. The selectors themselves live in `extension/inject.js` as clearly
  named constants and helpers (`CONTROL_SELECTORS`, `LIKE_RENDERER_SELECTORS`,
  `firstPlayableLink`, and so on) so fixing a break is a matter of updating one
  constant, not reverse-engineering the file.
- **Chrome only, in practice.** Web app discovery itself is browser-agnostic — it
  matches a Chromium web app bundle's `CrAppModeShortcutURL`, not anything
  Chrome-specific — and the extension is plain Manifest V3 with nothing Chrome-only in
  it, so it should load in Brave and Edge unchanged. Neither has actually been tried.
  Safari is not supported: Safari extensions need full Xcode and a paid Apple
  Developer account to distribute, which is a lot of cost for a small audience.

## Security

The WebSocket between the extension and the app carries no authentication. Concretely:

- The server binds `127.0.0.1` only — it is never reachable from another machine.
- On accepting a connection it sends a fixed greeting,
  `{"type":"hello","app":"PC Tunes"}`, so the extension can distinguish "this is PC
  Tunes" from some other process that happens to be listening on the same port. That
  greeting is not a secret — it's a literal string in `WSServer.swift`, published in
  this very repository — so it proves the app's identity to a casual squatter, not to
  someone who has actually read the source.
- Anything else running as your user that binds one of ports 8787-8791 first, and
  replies with that same greeting, can impersonate PC Tunes to the extension: it would
  receive the extension's playback feed and could send it fabricated transport
  commands.
- Symmetrically, the app accepts a connection from any local process and decodes
  whatever "state" messages it sends with no verification that they actually came from
  the extension — a local process could put arbitrary text in your menu bar or claim
  you're listening to something you aren't.

In short: on a single-user Mac where you trust everything already running as you, this
is a reasonable design — it needs no setup and no secret to manage. On a shared or
multi-user machine, or if you routinely run untrusted local code, treat the socket as
unauthenticated, because it is. A per-run shared secret was considered and rejected:
the extension is loaded unpacked with no build step to inject one, so the secret would
either have to be hardcoded (defeating the point) or entered by hand on every restart,
which isn't a workable model for an unpacked-extension project. Shipping the current
design without saying so plainly would not have been.

## Troubleshooting

There are three separate places PC Tunes logs to, and depending on the symptom you'll
need one specific one:

1. **The page console**, because `inject.js` runs inside the YouTube Music page
   itself (`"world": "MAIN"` in `extension/manifest.json`). Open DevTools on the
   YouTube Music tab or app window and look at its Console. This is where a broken
   page selector shows up — `console.warn` lines about a control or the queue not
   being found, right before the matching notice appears in the app's dropdown.
2. **The service worker console**, at `chrome://extensions` → PC Tunes Bridge →
   "service worker" (click it to open its own DevTools). This is where `sw.js` logs
   connection state: `[PC Tunes] connected on port 8787`, or
   `[PC Tunes] no greeting on port 8787 — not our server` if something else is
   squatting on that port. If the dropdown says "Extension not connected", this is
   where to look first.
3. **Console.app**, because the Swift app logs through `NSLog`. Filter for `PC Tunes`
   or `PCTunes`. This is where you'll see port-binding failures (`could not bind a
   port in 8787-8791`), login-item registration errors, and hotkey registration
   failures.

If nothing shows up in the menu bar at all, the app likely never launched or exited
immediately — check Console.app for a crash, and confirm `./build.sh` actually
completed (see [INSTALL.md](INSTALL.md)).

If the buttons visibly exist but don't do anything, the extension is probably
connected but a selector is stale — check the page console and the dropdown's notice
banner, then see "Known limitations" above.

## Contributing

This is a small, single-maintainer hobby project — issues and pull requests are
welcome, especially:

- Confirming the extension actually works, unmodified, in Brave or Edge
- Fixing a selector in `extension/inject.js` after a YouTube Music markup change

The test suite is a small hand-rolled harness (`app/Sources/PCTunesTests/TestKit.swift`)
because this project has no Xcode project file and is built with the Swift toolchain
that ships with the Command Line Tools alone, which includes neither XCTest nor
swift-testing. Run it with:

```bash
cd app && swift run PCTunesTests
```

## Licence

MIT — see [LICENSE](LICENSE).

## Trademark disclaimer

PC Tunes is an unofficial, third-party project. It is not affiliated with, endorsed
by, or sponsored by Google or YouTube. YouTube and YouTube Music are trademarks of
Google LLC. This project ships none of Google's artwork; the menu bar icon is drawn
programmatically in `app/Sources/PCTunes/MenuBarIcon.swift`.
