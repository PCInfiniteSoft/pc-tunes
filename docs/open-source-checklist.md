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
- [x] Builds clean and tests pass (`cd app && swift run PCTunesTests` → 97 checks)
- [x] Menu bar icon shows on macOS 26.6 (LSUIElement app, bundle id `com.pcinfinity.pc-tunes`)
- [x] Song/Video mode + cold-start resume merged to `master`

## Pending

- [ ] **Create the GitHub repo and push.** No remote exists yet. Decide owner
      (`PCInfiniteSoft`?) and public vs private. Repo name `pc-tunes` (matches the
      clone URL already in `INSTALL.md`).
- [ ] **Set the clone URL owner.** `INSTALL.md` still has
      `git clone https://github.com/<owner>/pc-tunes.git` — replace `<owner>` once the
      repo exists.
- [ ] **Refresh the README for this session's work.** Not yet documented:
      - Song/Video mode: the badge under the title, and forcing Song when a counterpart exists.
      - The title and artwork opening the web app from the dropdown.
      - The menu bar title is now off by default, with a "Show track title" toggle in Settings
        (the Features/settings lines still describe only "menu bar title length").

## Optional / nice to have

- [ ] Add `.env*` to `.gitignore` for hygiene (the app has no `.env` today, so low priority).
- [ ] `CONTRIBUTING.md` / `CODE_OF_CONDUCT.md` / `.github` issue & PR templates — the
      README already has a Contributing section, so these are optional for a hobby project.
- [ ] CI (build + `PCTunesTests`) once the repo is on GitHub.
