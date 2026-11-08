# projectmem - mizrab

_Last updated: 2026-11-08_

## Project purpose
mizrab is a music player built on basalam: a terminal application written in the [Salam](https://github.com/SalamLang/Salam) programming language.

## Recent issues
- [DONE] #legacy_e021 Legacy issue: fix(ui): take resize events from the screen again (fixed)
- [DONE] #legacy_69a2 Legacy issue: fix(ui): refit the shell when the terminal is resized (fixed)
- [DONE] #legacy_1451 Legacy issue: test(shell): measure a real start and close under a pty (fixed)

## Decisions
- No decisions logged yet.

## Notes
- docs(ui): record the screen's two threads and the resize event
- feat(ui): add the library view model
- feat(ui): split the body and lower the floor to 40x12
- feat(ui): render the playlist and play the selected row
- feat(ui): show the playing track and the player state
- feat(ui): add modes, the footer prompt and live search
- feat(ui): parse and run command-mode verbs
- feat(ui): add the help overlay and the quit confirmation
- test(ui): add the frame budget instruments
- docs(ui): describe the interface and log the basalam limits

## Key files
- `tests/leaks.sh`
- `tests/probe/probe_audio.salam`
- `app-shell.mdx`
- `docs.json`
- `CONTRIBUTING.md`
- `README.md`
- `audio-engine.mdx`
- `configuration.mdx`
- `index.mdx`
- `install.mdx`
- `playback-controller.mdx`
- `repository-layout.mdx`
- `tests.mdx`
- `tests/loop_test.out`
- `tests/loop_test.salam`
- `ui/loop.salam`
- `tests/probe/probe_shell.salam`
- `tests/shell-measure.sh`
- `contributing.mdx`
- `salam.lock`

## Open questions
- None logged yet.
