# Contributing to mizrab

mizrab is a terminal music player written in
[Salam](https://github.com/SalamLang/Salam), built on basalam. This guide
covers setup, the pins, the conventions and how to report an upstream defect.

## Set up

1. Install the Salam compiler, version **0.5.6** (`salam version` to check).
   See the [Salam repository](https://github.com/SalamLang/Salam) for how to
   build or install it.
2. Clone with the submodule, then build and test:

   ```sh
   git clone --recurse-submodules https://github.com/curedbylethe/mizrab
   cd mizrab
   make build && make test
   ```

Set `SALAM=/path/to/salam` to use a compiler that is not on your `PATH`.

**macOS note.** The Makefile pins `MACOSX_DEPLOYMENT_TARGET` to the running OS
version so the linker does not warn about a mismatched SDK. Leave it alone; if
you need to override it, export your own value before running `make`.

## Common tasks

| Command              | What it does                                                        |
| -------------------- | ------------------------------------------------------------------- |
| `make help`          | List the targets and the Salam version in use                       |
| `make build`         | Compile `main.salam` to `build/mizrab` with `--backend=llvm`        |
| `make run`           | Build, then run `build/mizrab`                                      |
| `make test`          | Build, then run `sh tests/run.sh`                                   |
| `make fmt`           | Format all Salam sources in place                                   |
| `make fmt-check`     | Fail if any Salam source would be rewritten                         |
| `make clean`         | Remove `build/` and `.salam-build/`                                 |
| `make spike-build`   | Compile miniaudio and the shim, then link `spike/tone.salam`        |
| `make spike-run`     | Build the spike and play its tone on the default device             |
| `make spike-check`   | Build and run the spike on miniaudio's null backend                 |
| `make spike-check-device` | Build and run the spike on the default device                  |
| `make spike-measure` | Print the spike's M1–M8 measurement table                           |
| `sh tests/run.sh <name>` | Run the named test only, for example `sh tests/run.sh cli_test`   |

## Repository layout

- `main.salam` — the entry point (CUR-501).
- `commands/` — the command layer; the version and usage text today, the
  command parser later (CUR-505, CUR-506, CUR-508 extend it).
- `audio/` — miniaudio 0.11.25, vendored as `miniaudio.h` plus a two-line
  `miniaudio.c` implementation unit; the playback backend lands here with
  CUR-503.
- `spike/` — the miniaudio FFI spike: a tone program, the `ma_shim.{h,c}` glue,
  a measurement harness and a struct probe. It is throwaway once CUR-503
  supersedes it; the findings are in
  [the spike findings](https://mizrab.mintlify.app/spike-miniaudio).
- `player/`, `library/`, `config/`, `ui/` — reserved for the application
  layer; the directories are empty until CUR-503 to CUR-508 fill them.
- `tests/` — test programs, `.out` goldens and the shell harness; CUR-509
  extends the harness rather than replacing it.
- `vendor/basalam` — the pinned basalam submodule.

## Tests

Tests follow the convention of Salam's own test corpus and of basalam:

- `tests/<name>.salam`, with `<name>` ending in `_test` (for example
  `tests/cli_test.salam`), is an ordinary program that asserts with
  `std/testing` and ends with `ret testing.Summary()`.
- `tests/<name>.out` is its exact expected stdout: `--` and the
  `tests: N passed, M failed` summary line.
- `tests/run.sh` builds each program with the LLVM backend, runs it with empty
  stdin under a 30-second watchdog, and fails when the exit code is non-zero
  or stdout differs from the golden (byte-exact `diff -u`). It also smoke-tests
  the real binary: `--version`, `--help` and an unknown flag.

To add a test, write `tests/<name>.salam` (name it `<something>_test`), run
`sh tests/run.sh <name>`, check the output is what you expect, then save it as
`tests/<name>.out`. There is no update flag: the golden is edited by hand.
`make test` reads the goldens and never rewrites `tests/`.

## Code style

- `salam format` is the authority. Run `make fmt` before committing;
  `make fmt-check` is the gate that rejects unformatted files.
- Indent with 4 spaces (`.editorconfig` matches the formatter).
- Every file starts with the project licence header comment.
- Declaration order is imports, then `include`s, then declarations; the
  formatter enforces this order (`--fix-order` is on by default) and the
  compiler rejects the wrong order outright.
- Every `pub` declaration carries an `@en "Name"` annotation followed by a
  `///` doc comment — basalam's convention; the doc comment comes after the
  annotation so `salam doc` picks it up.
- Write the language, not a binding: use `std/term` for escape sequences.

## Commits

Use Conventional Commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`,
`chore:`, with a scope when it helps.

```
feat(commands): add the version command
chore(deps): bump Salam to 0.5.7
```

- Imperative mood in the subject.
- One coherent change per commit; no "wip" or "fixes" commits.
- The tree is green after every commit: `make build && make test && make fmt-check`.

## Version pins and the bump procedure

mizrab has exactly three pins:

| Pin                | Where it lives      | Current value                                |
| ------------------ | ------------------- | -------------------------------------------- |
| Salam compiler     | `.salam-version`    | `0.5.6`                                      |
| basalam            | `vendor/basalam`    | `v0.2.0` (annotated), commit `926aefde852a00472b8f5e50e4b0804e79b27602` |
| miniaudio          | `audio/miniaudio.h` + `audio/miniaudio.c` | `0.11.25` from https://github.com/mackron/miniaudio/releases/tag/0.11.25; sha256 `ac7af4de748b7e26b777f37e01cee313a308a7296a3eb080e2906b320cc55c89` (`.h`) and `ab1984bb9804ffd7b0303813595d0b345a8a86c34da1daffc353a14b34102a65` (`.c`); public domain or MIT-0 |

To bump any one:

1. **Compiler.** Edit `.salam-version`. That file is the only place the
   version appears; the Makefile reads it, and CI asserts that `salam version`
   matches it.
2. **basalam.** Move the submodule to the release tag and stage the gitlink:

   ```sh
   git -C vendor/basalam fetch --tags
   git -C vendor/basalam checkout vX.Y.Z
   git add vendor/basalam
   ```

   A submodule cannot track a tag: the gitlink records the commit the tag
   points at, so a bump still stores a SHA. Check out `vX.Y.Z` rather than the
   SHA, then record both the tag name and its SHA in this file.
3. Verify the whole tree on the new pin:
   `make clean && make build && make test && make fmt-check`.
4. Commit as `chore(deps): bump Salam to X` or
   `chore(deps): bump basalam to vX.Y.Z`, with the new tag and SHA recorded in
   this file in the same commit.
5. If a bump breaks the build, that is a finding to report upstream (below),
   not a reason to loosen the pin or fall back to `latest`.

## Contest compliance checklist

Verified against [SalamLang/Salam#1713](https://github.com/SalamLang/Salam/issues/1713)
on 2026-10-22. This is a checklist, not a claim that submission is done.

- [x] **Public GitHub repository.** The repo is public.
- [ ] **Description mentions "Salam Programming Language".** It currently does
      not. Change it manually at submission time:

      ```sh
      gh repo edit curedbylethe/mizrab --description "mizrab — a terminal music player written in Salam Programming Language, built on basalam"
      ```

- [ ] **A real multi-file application**, not a one-file program split
      artificially. `main.salam`, `commands/` and `tests/` are the start of it.
- [ ] **More than 12 meaningful commits.** The contest issue says more than 12;
      one-commit histories are rejected. (CUR-501's issue text says "more than
      five"; the live issue page wins.)
- [x] **README links the official Salam repository** and explains what the
      project does and how to run it.
- [ ] **Salam VS Code extension installed and enabled** in the editor used for
      the work.
- [ ] **Participant is not a member of the Salam organisation.**
- [ ] Docker is optional and not required for any of the above.

## Upstream findings

Any limitation in the Salam compiler or standard library, or in basalam, is
reported upstream as it is found — do not work around it silently. A report
needs four fields:

1. **`salam version`** — the full output, not just the number.
2. **OS and terminal** — for example "macOS 15.6, arm64, Ghostty".
3. **Minimal reproduction** — the smallest program, or the exact command, that
   shows the problem.
4. **Expected vs actual** — what should happen, what happens instead (include
   the exit code and the relevant stdout/stderr), plus the workaround used.

File it at [Salam issues](https://github.com/SalamLang/Salam/issues) or
[basalam issues](https://github.com/curedbylethe/basalam/issues), then link it
back from `FINDINGS.md`. That file (CUR-510) is the log of local findings and
their upstream links; this section is only the convention.
