## What this changes

<!-- A short description of the change and why. Link any related issue. -->

## Checklist

- [ ] `swift build` passes (from `app/`)
- [ ] `swift run PCTunesTests` passes — new logic has a test; a bug fix has a regression test
- [ ] If the extension changed: `node --check *.js` and `node check.mjs inject.js content.js sw.js` pass (from `extension/`)
- [ ] Commits follow Conventional Commits (`type(scope): summary`)
- [ ] No secrets, debug logging, or dead experimental code left in

<!-- CI runs all of the above on the PR as well. -->
