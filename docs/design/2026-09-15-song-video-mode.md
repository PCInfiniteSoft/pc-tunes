# Song / Video mode

YouTube Music serves many tracks in two forms: the song, and the official music
video. They are different files of different lengths — Despacito is 4:42 as a video
and 3:49 as a song — and which one plays is a preference the page holds, not a
property of the track. The widget said nothing about this, and the page's default is
the video.

Two things follow from that. The widget should say which form is playing, and it
should ask for the song.

## What the page exposes

The player page carries one `ytmusic-av-toggle`. Measured against a signed-in
account on 2026-09-15:

| Attribute | Meaning |
| --- | --- |
| `playback-mode` | `OMV_PREFERRED` (video) or `ATV_PREFERRED` (song) |
| `is-audio-playback-mode-selected` | `"true"` / `"false"`, mirrors `playback-mode` |
| `selected-queue-item-has-counterpart` | present when this item exists in both forms |
| `selected-item-has-video` | present when a video form of this item exists |

It holds two buttons, `button.song-button` and `button.video-button`. Their classes
are the only language-independent handle on them: their text ("Song", "Video") and
the element's own `song-audio-label` attribute are localized, and the same mistake
has already been made once in this extension with `aria-label` on the rating
buttons.

Three measured behaviours shape the design:

- **The preference is not the truth.** On an item that exists only as a video, the
  toggle happily reports `ATV_PREFERRED` and `is-audio-playback-mode-selected="true"`
  while the video plays on. Verified on `ysoJ4fm0nwc`, an hour-long compilation:
  clicking Song left the video id and the 3673-second duration untouched.
- **The preference carries across tracks but not across page loads.** After clicking
  Song, `next` kept `ATV_PREFERRED`; a reload put it back to `OMV_PREFERRED`.
- **Switching form restarts the track.** Clicking Song on Despacito swapped the
  loaded video from `kJQP7kiw5Fk` (282s) to `FXovf5dsRTw` (229s) and the position
  went back to zero. They are separate files; there is nothing to seek to.

## Design

### Reading the mode

`readAvToggle()` reports the form that is *playing*, not the one that is preferred:

- no toggle on the page (anything but a watch page) — no answer, and the field is
  left off the state message
- no `selected-queue-item-has-counterpart` — this item has one form only, and
  `selected-item-has-video` says which
- otherwise the preference decides, because both forms exist and the page honours it

### Asking for the song

On every track change, if the form playing is the video *and* a song counterpart
exists, click `button.song-button`. An item with no counterpart is left alone and
keeps playing.

This lives entirely in the page script. Nothing about it needs the app's
involvement, so it adds no command to the protocol.

The consequence is deliberate: a video caught part-way through goes back to 0:00,
because switching form loads a different file. In practice it bites only the first
track after a page load, since the preference then carries itself forward.

### Showing it

`TrackState` gains `mode`, a `song`/`video` value that is absent when the page had
no answer. The dropdown draws it under the title, beside the artist, as a caption —
and draws nothing when the field is absent, which is the honest rendering of "the
page did not say".

### Opening the web app

The title and the artwork become buttons for `openYouTubeMusic()`, which already
focuses an existing window or launches the web app. The dropdown had no obvious way
to get to the page it is controlling; these are the two things a person would try.

## Deliberately not done

- **No setting to turn the preference off.** The request was for the song, always.
- **A compilation still shows the wrong track name.** One video, one title, songs
  changing inside it, and no per-song metadata to read. YouTube Music names it the
  same way. The badge can say it is a video; it cannot name what is audible.
