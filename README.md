# mizrab

mizrab is a music player built on basalam: a terminal application written in
the [Salam](https://github.com/SalamLang/Salam) programming language.

> **Status: scaffold.** The binary answers `--version` and `--help` and prints
> its usage when invoked bare. There is no playback, no library scanning and no
> user interface yet; those land in later issues. A spike under `spike/` proved
> that a Salam function can serve as miniaudio's data callback and fill f32
> frames on Core Audio; the engine itself is not written
> ([the spike's findings](https://mizrab.mintlify.app/spike-miniaudio)).

<!-- Screenshot placeholder: replaced by a real capture once the first playable
     build exists (CUR-511). -->

Screenshot: coming with the first playable build.

## Documentation

The documentation site is <https://mizrab.mintlify.app>. Preview it locally with
the Mintlify CLI pinned in `.mint-version` (the Makefile and CI read that file,
so the version is not repeated here):

```sh
npm i -g "mint@$(cat .mint-version)"
make docs
```

`make docs-check` validates `docs.json` and checks internal links and anchors;
`make docs-format-check` fails if `mint format` would rewrite a page. The format
gate compares against the index, so stage or commit page edits first.

## Install

Prerequisites:

- **Salam 0.5.6.** The pinned compiler version lives in `.salam-version`;
  `salam version` must report exactly that. Build or install it from the
  [Salam repository](https://github.com/SalamLang/Salam) — there is no separate
  mizrab installer.
- **A C toolchain with LLVM.** Salam's LLVM backend uses `clang` and the
  system linker, so on Debian/Ubuntu install `build-essential` and `clang`, and
  on macOS install the Xcode command-line tools (`xcode-select --install`).
- macOS or Linux.

```sh
git clone --recurse-submodules https://github.com/curedbylethe/mizrab
cd mizrab
make build
make run
```

`--recurse-submodules` matters: `vendor/basalam` is a git submodule and stays
empty without it.

At this commit `make run` prints the usage block; a bare `./build/mizrab`
prints the same block and exits 0.

## Build and run

`make build` compiles `main.salam` to `build/mizrab` with the LLVM backend;
`make run` builds and runs it. `make test` checks each `tests/*_test.salam`
program against its `.out` golden, then smoke-tests the binary;
[tests](https://mizrab.mintlify.app/tests) covers the convention, the checks and
running a single test.

[Make targets](https://mizrab.mintlify.app/make-targets) documents every target,
including `make help` and the `spike-*` group.

## Built on

- **[basalam](https://github.com/curedbylethe/basalam)** — a retained-mode
  terminal UI library for Salam. It is vendored at `vendor/basalam` and pinned
  to the `v0.2.0` release tag, by the commit that tag points at.
- **[Salam](https://github.com/SalamLang/Salam)** — the language, compiler and
  standard library mizrab is written in.

The player currently imports only the Salam standard library (`flag`, `os`) plus
its own `commands` package; the basalam include arrives with the application
layer. The spike also imports `conv`, `math`, `mem` and `sync`.

## Repository layout

`main.salam` is the entry point, `commands/` the command layer, `audio/` the
vendored miniaudio, `spike/` the throwaway FFI spike and `tests/` the harness.
[Repository layout](https://mizrab.mintlify.app/repository-layout) describes
every directory, including the reserved application-layer packages.

## Licence

mizrab is licensed under the GNU General Public License, version 3 or later
(`GPL-3.0-or-later`). The full text is in [LICENSE](LICENSE); each source file
carries the same notice in its header.
