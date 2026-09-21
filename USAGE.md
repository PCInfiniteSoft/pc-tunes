# Using PC Tunes

This guide covers everything PC Tunes does once it's installed. If you haven't built
and loaded it yet, start with [INSTALL.md](INSTALL.md).

*(เวอร์ชันภาษาไทย: [USAGE.th.md](USAGE.th.md))*

PC Tunes controls whatever YouTube Music is playing in your Chromium browser — the
installed web app or an ordinary tab. It never plays audio itself; it reads and drives
the page. So there is nothing to "open" beyond having YouTube Music playing somewhere,
or letting PC Tunes start it for you (see [Cold start](#cold-start)).

## The menu bar icon

PC Tunes lives in the menu bar, with no Dock icon and no main window. Click the icon to
open the dropdown; click anywhere else to close it.

By default the icon shows on its own. If you turn on **Show track title beside the icon**
in Settings, the current title appears next to it, trimmed to the length you set.

## The dropdown

Everything is in the dropdown that opens from the menu bar icon.

- **Artwork, title, artist, album.** The **artwork** and the **title** are buttons —
  click either to open the YouTube Music web app in your browser, focused on what's
  playing.
- **Song / Video badge.** A small badge next to the artist shows whether the current
  track is playing as a *Song* or a *Video*. It's absent when the page didn't say (for
  anything that isn't a watch page). See [Song vs Video](#song-vs-video).
- **Like / dislike.** The thumbs up / down on the right mirror YouTube Music's own
  rating for the track, and set it when you click.
- **Progress bar.** Shows elapsed and total time. Drag the knob to seek.
- **Playback controls**, left to right:
  - **Shuffle** — toggles shuffle. The button lights up when shuffle is on.
  - **Previous** — previous track.
  - **Play / Pause** — the middle button; its icon reflects the current state.
  - **Next** — next track.
  - **Repeat** — cycles the queue's repeat mode: off → repeat all → repeat one. The
    button lights up when repeat is on, and shows a distinct "repeat one" icon for the
    single-track setting.
- **Volume.** The slider sets YouTube Music's volume.
- **Go to YouTube Music** — opens the web app, same as clicking the artwork or title.
- **Settings…** — opens the settings window (see [Settings](#settings)).
- **Quit PC Tunes** — quits the app. This does not close your browser or stop playback.

The shuffle, repeat, next, previous, like and dislike controls are dimmed and inactive
whenever no controllable YouTube Music page is connected.

## Song vs Video

YouTube Music serves many tracks as both a song and an official music video — different
files, of different lengths. The badge under the title tells you which form is playing.

When a track exists as both, PC Tunes asks the page for the **song**. Because the two
are separate files, switching restarts the track from the beginning — there is nothing
to seek to, so this is accepted rather than worked around. The page keeps the preference
across later tracks and only forgets it on a reload, so the track it interrupts is
usually just the first one after the web app opened, a few seconds in. A track that has
no song form (a compilation, a live set) is left playing as the video.

## Cold start

You don't have to open YouTube Music first. Press **Play** with nothing playing and
PC Tunes launches YouTube Music behind whatever you're looking at, starts playback, and
minimises the browser window to the Dock once the music is actually running — so you get
music without losing your place in the app you were using.

## Global hotkeys

Global hotkeys let you control playback without opening the dropdown, from any app.

**They are off by default.** Turn them on in **Settings → Hotkeys → Global hotkeys**.
The defaults are:

| Action | Shortcut |
| --- | --- |
| Play / Pause | `⌃⌥Space` |
| Next | `⌃⌥→` |
| Previous | `⌃⌥←` |

Each one is rebindable in Settings — click the shortcut field and press the combination
you want. If a combination is already claimed by another app, the system refuses it and
Settings flags that one as unavailable; rebind it and the other two keep working.

Hotkeys are registered with Carbon's `RegisterEventHotKey`, which — unlike the
`NSEvent` route most apps use — needs **no Accessibility permission**. PC Tunes never
asks for that.

## Settings

Open Settings from the dropdown. Everything is saved immediately.

- **Launch at login** — start PC Tunes automatically when you log in.
- **Show track title beside the icon** — off by default. When on, the current title
  shows next to the menu bar icon, trimmed to **Title length** (10–80 characters; the
  preview underneath shows how a long title will look).
- **Show notifications when the track changes** — off by default. When on, a macOS
  notification appears each time the track changes.
- **Global hotkeys** — off by default; see [Global hotkeys](#global-hotkeys).

## When a control stops working

Everything PC Tunes drives depends on selectors into YouTube Music's markup, which
Google can change without notice. When one breaks, the single control it drove stops
working and PC Tunes shows a short **notice** at the top of the dropdown rather than
failing silently.

If that happens, reloading the browser extension usually gets you going again while the
selector is fixed. See the [Troubleshooting](INSTALL.md#if-it-didnt-work) section of the
install guide, and the README's
[Known limitations](README.md#status-and-known-limitations) for the wider picture.
