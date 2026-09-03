# PC Tunes

A macOS menu bar widget for YouTube Music. Shows the current track and provides
play/pause, next and previous without leaving whatever app you are in. Pressing play
with nothing open launches YouTube Music and starts playing.

## How it works

A Chrome MV3 extension reads playback state from the YouTube Music page and pushes it
over a loopback WebSocket to a native Swift menu bar app. The app sends transport
commands back over the same socket.

macOS 15.4 and later block the private MediaRemote framework for third-party apps, so
reading "now playing" from the system is not possible — the state has to come from the
page itself.

When YouTube Music is open both as the installed Chrome PWA and as a regular tab, the
PWA always wins.

## Requirements

- macOS 14 or later
- Google Chrome
- Swift toolchain (Command Line Tools is enough — full Xcode is not required)

## Build and install

```bash
cd app && ./build.sh
open "PC Tunes.app"
```

Then load the extension:

1. Open `chrome://extensions`
2. Enable **Developer mode**
3. Click **Load unpacked** and select the `extension/` directory

Enable "Launch at login" from the widget's dropdown to have it start automatically.

## Development

```bash
cd app && swift run PCTunesTests   # run the test suite
cd app && swift build              # build without bundling
```

The project has no third-party dependencies. Tests use a small hand-rolled harness in
`Sources/PCTunesTests/TestKit.swift` because neither XCTest nor swift-testing ships with
the Command Line Tools.

## Troubleshooting

**The menu bar shows `♪` with no text while music is playing.** Open the service worker
console from `chrome://extensions` and look for `[PC Tunes] connected on port 8787`. If
it is absent, the app is not running or every port in 8787-8791 is occupied. A
`[PC Tunes] no greeting on port X — not our server` line means something else is
listening on that port; the extension will keep scanning the rest of the range.

**Next and previous stop working after a YouTube Music update.** The button selectors in
`extension/inject.js` (`CONTROL_SELECTORS`) need updating against the current DOM.

## Verification status

The following have been verified automatically on this machine and are confirmed
working:

- `swift run PCTunesTests` passes: `✅ 52 checks passed`, exit code 0.
- `./build.sh` produces a clean release build and an ad-hoc-signed `PC Tunes.app`
  bundle using `swift build` alone (no Xcode required — this machine only has the
  Command Line Tools, and `xcodebuild` is not available).
- `extension/manifest.json` parses as valid JSON, and `content.js`, `inject.js`, and
  `sw.js` all pass `node --check` (no syntax errors).
- The built app launches, binds a loopback listener (confirmed with `lsof`, e.g.
  `TCP localhost:8787 (LISTEN)`), and quits cleanly, releasing the port.
- With the extension loaded, Chrome's service worker connects to the app — confirmed
  with `lsof` showing an ESTABLISHED pair between Google Chrome and PCTunes on
  `127.0.0.1:8787`.

The rest requires a human at the keyboard — playing tracks, opening and closing
Chrome windows, and rebooting are not things an automated agent can do. The first
three items below are confirmed working against the real YouTube Music PWA, which
also confirms the transport selectors in `extension/inject.js` match the current
DOM. The remainder are still open:

- [x] Open the YouTube Music PWA and play a track. Title and artist appear in the menu
      bar within 5s.
- [x] Click ⏯ in the dropdown. Playback toggles; the icon in the dropdown flips within
      1s.
- [x] Click ⏭, then ⏮. The track changes and the menu bar text follows.
- [ ] Also open `https://music.youtube.com` in a regular Chrome tab and play something
      there. The menu bar still shows the PWA's track, and the transport buttons still
      control the PWA.
- [ ] Close the PWA window. Within 15s the widget switches to the regular tab's track.
- [ ] Close the regular tab too. The menu bar shows the bare `♪` icon and "Not
      playing"; transport buttons are disabled.
- [ ] Click "Open YouTube Music" with nothing open. The PWA launches.
- [ ] With music playing, quit and relaunch `PC Tunes.app`. A relaunch onto the same
      port reconnects within a few seconds without touching Chrome; a relaunch onto a
      different port can take up to a full pass of the port range.
- [ ] Enable "Launch at login", reboot. The icon returns after login. Then disable it
      again if unwanted.
- [ ] Pause playback, leave YouTube Music in the background for six minutes, then check the menu bar still shows the track and the play button still works.
- [ ] Squat on port 8787 with a WebSocket server that completes the handshake and then
      says nothing, restart the app so it takes 8788, and confirm the widget still
      connects. The service worker console should log
      `[PC Tunes] no greeting on port 8787 — not our server` and then connect on 8788.
- [ ] With YouTube Music closed entirely, click ⏯ in the dropdown. The PWA opens and
      playback begins — the queued track if there is one, otherwise the first Quick Pick.
