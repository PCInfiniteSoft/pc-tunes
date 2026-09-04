# Feature expansion design

**Date:** 2026-09-04
**Status:** shipped, except for search — see below

Nine features requested together. They share one protocol revision, one settings store
and one dropdown, so they are designed as a set rather than nine separate additions.

## Protocol revision

The wire format gains four things. Everything stays backward compatible in the sense
that a field's absence means "unknown", never an error.

### Commands, app to extension

`OutboundCommand` gains two optional payload fields:

```json
{ "type": "cmd", "action": "seek",   "tabId": 42, "value": 91.5 }
{ "type": "cmd", "action": "volume", "tabId": 42, "value": 0.4 }
{ "type": "cmd", "action": "search", "tabId": 42, "text": "bodyslam ครึ่งหนึ่ง" }
```

New actions: `like`, `dislike`, `seek`, `volume`, `search`, `requestQueue`.
Existing actions keep their shape; `value` and `text` are omitted when unused.

### State, extension to app

`TrackState` gains two fields, both optional:

- `liked` — `"like"`, `"dislike"` or absent. Absent means unknown, which is distinct
  from neutral; the UI shows an unlit button either way, but never claims to know.
- `volume` — `0.0` to `1.0`, absent when unread.

### Two new inbound message types

```json
{ "type": "notice", "tabId": 42, "text": "Next and previous are unavailable — YouTube Music's page has changed." }
{ "type": "queue",  "tabId": 42, "items": [ { "title": "...", "artist": "..." } ] }
```

`notice` is how the extension reports that it could not do something. Today the only
signal for a broken selector is a `console.warn` in a console the user will never open,
which for a project whose whole job is driving someone else's web page is the wrong
place for its most likely failure. A notice is shown in the dropdown and cleared when a
command next succeeds.

`queue` is sent only in reply to `requestQueue`, so the up-next list costs nothing while
the dropdown is closed.

The app continues to reject any message type it does not know.

## Progress bar

`position` and `duration` already travel on the wire and are rendered nowhere.

The bar interpolates locally rather than asking for a faster feed: `PlayerModel` records
the position and the instant it arrived, and while `playing` is true the displayed
position is `position + (now - receivedAt)`, clamped to `duration`. A fresh state
message resets both. This keeps the bar smooth at one frame per second of UI timer
while leaving wire traffic exactly as it is.

This also settles a known wart: the service worker's keepalive currently strips
`position` before re-sending a cached state, because a stale position interleaved with
fresh ones made the value jump backwards. With interpolation the strip stays, and the
absent position simply means the bar holds its interpolated value.

Dragging the bar issues `seek`.

## Settings

Four features need persisted preferences, which is more than a dropdown should carry:

| Setting | Default |
| --- | --- |
| Menu bar title length | 35 characters |
| Show track-change notifications | off |
| Global hotkeys enabled | off |
| Hotkey bindings | ⌃⌥Space, ⌃⌥→, ⌃⌥← (rebindable) |

Stored in `UserDefaults`, read through a single `Settings` observable object so the
views bind to it directly. The dropdown gets a "Settings…" item opening a small window;
the dropdown itself keeps only the controls used while listening.

Notifications default to off deliberately. A widget that starts nagging on first launch
is a widget people uninstall.

## Global hotkeys

Carbon's `RegisterEventHotKey` rather than `NSEvent.addGlobalMonitorForEvents`. The
`NSEvent` route needs Accessibility permission, which is a real barrier at install time
for a tool whose whole appeal is that it is small. `RegisterEventHotKey` needs no
permission at all and is what most menu bar apps use.

Registered only while the setting is on, and unregistered when it is turned off.

Bindings are the user's to change, so each is recorded by a click-then-press control in
the settings window and stored as a virtual key code plus a Carbon modifier mask. Two
constraints fall out of that being a *global* shortcut: it must carry at least one of
⌃, ⌥ or ⌘ — shift alone would swallow an ordinary typing key system-wide — and the key's
label is resolved against the live keyboard layout with `UCKeyTranslate`, so a Thai or
Dvorak user sees the legend on the key they actually pressed rather than the US one.

A combination another app already owns is reported per binding rather than turning the
whole feature off: the other two still work, and the settings window says which one is
dead instead of leaving it to be discovered by pressing keys and getting nothing.

## Search — dropped before release

*Built, then removed. What follows is the design as it was implemented. It navigated
the page away from whatever was playing and then played the first result with no way
to pick another, which is a worse deal than switching to the window and typing there.
The `search` command and its `text` payload are gone from the protocol with it.*


`search` navigates the page to `https://music.youtube.com/search?q=<query>` and then
plays the first song result, reusing the polling approach the cold-start path already
uses for Quick Picks — the page is a single-page app and the results arrive well after
the command does.

The selectors for a search result are, like every other selector here, guesses against
markup nobody controls. The notice pipeline exists partly so this fails loudly.

## Browser fallback

`YouTubeMusicLauncher` finds an installed web app by its `CrAppModeShortcutURL`, which
is browser-agnostic, but its fallback path hardcodes Chrome's bundle identifier. A Brave
or Edge user with no installed web app currently gets a log line and silence. The
fallback opens the URL with the system's default handler instead.

## What is deliberately not included

- Safari support. Safari extensions need full Xcode and a paid Apple Developer account
  to distribute — a large cost for a small audience.
- Spotify and Apple Music. Different architectures entirely; Apple Music is scriptable
  natively and Spotify has a web API, so neither belongs behind this browser bridge.
