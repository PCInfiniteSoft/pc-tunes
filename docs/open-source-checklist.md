# Open-source release checklist

Reconstructed 2026-09-19 from git history and the current tree (the original list
lived in an earlier chat session that was cleared and never written down). Keep this
file as the source of truth from here on.

## Done

- [x] MIT `LICENSE` at the repo root
- [x] Public `README.md` — why it exists, how it works, install, features, status &
      known limitations, security, troubleshooting, contributing, licence, trademark
      disclaimer
- [x] `INSTALL.md` build/install guide with a first-run checklist
- [x] Internal scaffolding dropped (`docs/superpowers/**` removed; see commit `1c1e423`)
- [x] No secrets committed; no `.env` in the tree
- [x] Builds clean and tests pass (`cd app && swift run PCTunesTests` → 117 checks)
- [x] Menu bar icon shows on macOS 26.6 (LSUIElement app, bundle id `com.pcinfinity.pc-tunes`)
- [x] Song/Video mode + cold-start resume merged to `master`
- [x] README refreshed for Song/Video mode, shuffle/repeat, title/artwork actions and
      the "Show track title" toggle (commit `27c8e0d`)
- [x] Protocol tests cover `mode`/`shuffleOn`/`repeatMode` + `shuffle`/`cycleRepeat`
      (review item #1; commit `c27c352`)
- [x] Carbon hotkey handler now uninstalled when unused (review item #7; commit `ae705d1`)
- [x] `.env*` ignored in `.gitignore` (review item #4; commit `60ae1a2`)
- [x] **GitHub repo created and pushed** — public at
      https://github.com/PCInfiniteSoft/pc-tunes (owner `PCInfiniteSoft`, default
      branch `master`), with description + topics for discoverability
- [x] Clone URL owner set to `PCInfiniteSoft` in `INSTALL.md` / `INSTALL.th.md`
      (commit `b732fef`)

## Pending

_All release-blocking items done. The push to GitHub is complete._

## Optional / nice to have

- [x] Add `.env*` to `.gitignore` for hygiene (done; commit `60ae1a2`).
- [ ] `CONTRIBUTING.md` / `CODE_OF_CONDUCT.md` / `.github` issue & PR templates — the
      README already has a Contributing section, so these are optional for a hobby project.
- [ ] CI (build + `PCTunesTests`) once the repo is on GitHub.
