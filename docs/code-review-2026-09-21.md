# Code review — full project (2026-09-21)

Reviewed all Swift + extension sources after merging shuffle/repeat + settings work
to `master`. Overall quality is high: layered architecture, `PCTunesCore` is
pure/testable, extension copies message fields one-by-one to block page-world
spoofing, WebSocket binds loopback-only with a hello handshake. 97 tests pass.

Below are the items worth fixing, ranked. Nothing is a release blocker on its own,
but #1 and #6 should land before the open-source push.

## To fix

### Medium
1. **Test coverage gap for the new protocol fields.** `MessageDecoder` tests cover
   `liked`/`volume` but not `mode`, `shuffleOn`, or `repeatMode`; `OutboundCommand`
   tests do not cover the `shuffle` / `cycleRepeat` actions. A regression in the
   `RepeatMode` raw mapping (NONE/ALL/ONE -> off/all/one) would not be caught.
   Add decode tests for the new `TrackState` fields and encode tests for the new
   actions (mirrors the existing rigor for `liked`/`volume`). CLAUDE.md section 6
   wants tests for new logic.
   - Files: `app/Tests/PCTunesTests/main.swift`, against
     `app/Sources/PCTunesCore/Messages.swift`.

### Low
2. **WebSocket has no token/origin auth.** Any local process can connect to the
   loopback port, receive outbound commands, and push fake state. The hello
   handshake authenticates app -> extension, not the reverse. Acceptable for a
   localhost hobby tool; document the threat model in the README security section
   rather than adding auth.
   - File: `app/Sources/PCTunesCore/WSServer.swift`.
3. **`WSServer.start()` can block the main actor up to ~2.5s** at launch in the
   worst case (5 ports x 0.5s semaphore wait) if every port is contended. Rare
   (loopback bind is sub-ms) and commented; move the bind off-main only if it ever
   bites.
   - File: `app/Sources/PCTunesCore/WSServer.swift`.
4. **`.gitignore` lacks `.env*`.** The app has no `.env` today, so hygiene-only.
   - File: `.gitignore`.
5. **`upNext` view + `isUpNextExpanded` state are now unused** (feature hidden).
   Intentional and documented; compiles clean. Re-enable or delete when the queue
   feature is finished.
   - File: `app/Sources/PCTunes/MenuContent.swift`.

### Docs
6. **README drift** (also in the OSS checklist). Not yet documented: Song/Video
   mode + badge, title/artwork opening the web app, menu-bar title now off by
   default with the Settings toggle, and the new shuffle/repeat controls.
   - File: `README.md`.

### Nit
7. `Hotkeys` never uninstalls its Carbon event handler (singleton lifetime).
   Harmless.
   - File: `app/Sources/PCTunes/Hotkeys.swift`.

## Not found
No TODO/FIXME left, no committed secrets, no silent failures, no dead experimental
code, no concurrency bugs.
