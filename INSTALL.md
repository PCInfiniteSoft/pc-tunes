# Installing PC Tunes

This guide assumes no prior experience building Swift projects. If you get stuck, the
[Troubleshooting](#if-it-didnt-work) section at the end is keyed to what you'll
actually see on screen.

*(เวอร์ชันภาษาไทย: [INSTALL.th.md](INSTALL.th.md))*

## Requirements

- **macOS 14 or later.**
- **Google Chrome, or another Chromium-based browser** (Brave, Edge). Chrome is the
  one this has actually been tested with — see the README's
  [Known limitations](README.md#status-and-known-limitations) for the others.
- **The Xcode Command Line Tools.** You do *not* need to install full Xcode. If you're
  not sure whether you already have them, open Terminal and run:

  ```bash
  xcode-select --install
  ```

  If they're already installed, this tells you so and exits. If not, it opens a small
  installer — let it finish before continuing.

## 1. Clone the repository

```bash
git clone https://github.com/PCInfiniteSoft/pc-tunes.git
cd pc-tunes
```

(Replace the URL with wherever this repository actually lives.)

## 2. Build the app

```bash
cd app
./build.sh
```

This runs `swift build -c release`, assembles `PC Tunes.app` by hand (there is no
Xcode project file), and ad-hoc signs it — a signature step the app needs at runtime
to register itself as a login item. The first build compiles everything from scratch
and can take under a minute; you'll see:

```
Building for production...
...
Build of product 'PCTunes' complete!
PC Tunes.app: replacing existing signature
Built /path/to/pc-tunes/app/PC Tunes.app
```

If you see errors instead, they're almost always a missing Command Line Tools
installation — go back to the Requirements step above.

## 3. Open the app

You can run it directly from where it was built:

```bash
open "PC Tunes.app"
```

Or drag `PC Tunes.app` into `/Applications` first and open it from there — either
works. There's no installer and nothing else to place on disk.

The app has no Dock icon or menu bar text yet at this point — it's a
menu-bar-only app (look for a small ringed play-triangle icon near the clock). That's
expected until you finish step 4; without the extension it has nothing to show.

## 4. Load the browser extension

1. Open `chrome://extensions` in Chrome.
2. Turn on **Developer mode** (top-right toggle).
3. Click **Load unpacked**.
4. Select the `extension/` folder inside the cloned repository (not a file inside
   it — the folder itself).

You should see "PC Tunes Bridge" appear in the extension list.

## 5. Verify it worked

1. Open YouTube Music (`music.youtube.com`) in Chrome and start playing something.
2. Click the PC Tunes icon in the menu bar. Within a few seconds you should see the
   track's title, artist and artwork, and the transport buttons should be enabled.
3. Try play/pause from the dropdown and confirm playback actually toggles on the page.

### First-run checklist

- [ ] `./build.sh` completed without errors and printed "Built .../PC Tunes.app"
- [ ] `PC Tunes.app` is running (its icon is visible in the menu bar)
- [ ] "PC Tunes Bridge" is listed and enabled at `chrome://extensions`
- [ ] With YouTube Music open and playing, the dropdown shows the current track
- [ ] Play/pause, next and previous all work from the dropdown
- [ ] (Optional) "Launch at login" is turned on from the dropdown if you want PC Tunes
      to start automatically
- [ ] (Optional) Settings… → Hotkeys → "Global hotkeys" on, then click a shortcut and
      press the keys you want. A shortcut already taken by another app is marked
      "Already in use by another app" — the other two keep working.

## If it didn't work

**The dropdown says "Not playing" right after you reloaded the extension.**
Reloading an extension tears its content scripts out of pages that were already open,
so a YouTube Music window that was running before the reload stops reporting anything
even though the extension itself reconnects. Reload that window (or close it and press
play in the dropdown) and it comes back.

**The dropdown says "Extension not connected."**
The app is running but no browser has attached to it yet. Reload the YouTube Music
tab (the extension only starts a connection once its content script runs on a
matching page), and check the extension's own logs: at `chrome://extensions`, click
"service worker" under PC Tunes Bridge to open its console. Look for
`[PC Tunes] connected on port 8787` — if instead you see
`[PC Tunes] no greeting on port 8787 — not our server`, something else is listening
on that port and the extension is scanning further into the 8787–8791 range; give it
a few seconds. If nothing at all shows up there, confirm the extension is enabled
and that you're actually on `music.youtube.com`.

**Nothing appears in the menu bar at all.**
The app either isn't running or exited immediately. Check Console.app (search or
filter for "PC Tunes") for a crash or a line like
`could not bind a port in 8787-8791` — that means every port in the range is already
in use by something else; quit whatever that is (or a stale copy of PC Tunes itself)
and relaunch. If Console.app shows nothing at all, re-run `./build.sh` from a
terminal and read its output directly rather than double-clicking the app.

**The buttons are visible but do nothing.**
The extension is probably connected but a page selector no longer matches — YouTube
Music's markup changes without notice, and every button here works by finding and
clicking an element on the actual web page. Open DevTools on the YouTube Music tab
itself and check its Console for a `[PC Tunes] ... not found` warning; the same
problem also shows as an orange notice banner in the PC Tunes dropdown. See the
README's [Known limitations](README.md#status-and-known-limitations) section — the
selectors live in `extension/inject.js` in named constants, and fixing one is the
most useful contribution this project can currently take.
