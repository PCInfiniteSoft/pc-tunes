# Contributing to PC Tunes

PC Tunes is a small hobby project, but patches and bug reports are welcome. This file
covers how to get set up, what the code expects, and how to send a change.

## Getting set up

Follow [INSTALL.md](INSTALL.md) to build the app and load the extension. You need the
Xcode Command Line Tools (not full Xcode) and a Chromium-based browser. `node` is
optional — it's only used for the extension checks below.

## Project layout

| Path | What it is |
| --- | --- |
| `app/Sources/PCTunes` | The macOS app (SwiftUI, menu bar, settings, hotkeys). |
| `app/Sources/PCTunesCore` | Pure, testable core — message protocol, WebSocket server, arbiter. No UI. |
| `app/Sources/PCTunesTests` | The test suite (a plain executable, not XCTest). |
| `extension` | The Manifest V3 browser extension that reads and drives the page. |
| `docs` | Design notes, the release checklist, and review records. |

Logic that can be tested without a UI belongs in `PCTunesCore`, where the tests can
reach it.

## Building and testing

From `app/`:

```bash
swift build                 # compile everything (this is also the type check)
swift run PCTunesTests       # run the suite — currently 117 checks, all must pass
```

To build the runnable `PC Tunes.app` bundle (signing + Launch Services registration),
use `./build.sh` instead — see INSTALL.md.

If you touched the extension, check it too, from `extension/`:

```bash
for f in *.js; do node --check "$f"; done   # parse
node check.mjs inject.js content.js sw.js    # catch calls to deleted functions
```

CI runs all of the above on every push and pull request
(`.github/workflows/ci.yml`).

## Code expectations

- **Match the surrounding code** — its naming, its comment density, its idioms. The
  code leans on comments to explain *why* a non-obvious choice was made; keep that up.
- **New logic needs a test**, written to fail first, then made to pass. A bug fix
  needs a regression test that reproduces the bug.
- **Don't make a test pass by weakening it** — no dropped assertions, no skips, no
  quietly changed expectations.
- **No secrets, debug logging, or dead experimental code** left in a change.
- The extension copies message fields one-by-one on purpose (page-world spoofing
  defence) and the WebSocket binds loopback-only — don't loosen either without saying
  why.

## Commits and pull requests

- **[Conventional Commits](https://www.conventionalcommits.org/)**: `type(scope): summary`
  in imperative English, e.g. `fix(hotkeys): uninstall the Carbon event handler`.
  One topic per commit.
- Work on a branch named `feat/…`, `fix/…`, `chore/…`, `docs/…`, `refactor/…` or
  `test/…`, and open a pull request against `master`.
- Make sure `swift build`, `swift run PCTunesTests` and the extension checks pass
  before you open the PR — CI will run them anyway.

## Reporting bugs

Open an issue with what you did, what you expected, and what happened — plus your macOS
and browser versions. If a control silently stopped working, note whether a **notice**
appeared at the top of the dropdown: that usually means a YouTube Music selector
changed, which is a known and expected failure mode (see the README's
[Known limitations](README.md#status-and-known-limitations)).
