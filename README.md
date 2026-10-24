# mizrab

mizrab is a music player built on basalam: a terminal application written in
the [Salam](https://github.com/SalamLang/Salam) programming language.

> **Status: audio engine, playback controller and library scanner, no player
> yet.** The audio engine exists: it decodes MP3, FLAC, WAV and OGG, streams
> them through a lock-free ring buffer to miniaudio's playback callback, and
> runs headless on miniaudio's null backend, where its tests exercise it
> ([the engine](https://mizrab.mintlify.app/audio-engine)). The playback
> controller above it exists too: states, commands, position, a queue and error
> text, tested the same way
> ([the controller](https://mizrab.mintlify.app/playback-controller)). The
> binary uses neither yet. It does run the library scanner: `mizrab --scan
> ROOT...` walks the roots, reads tags and writes a JSON index
> ([the library](https://mizrab.mintlify.app/library)). Otherwise it answers
> `--version` and `--help` and prints its usage when invoked bare. There is no
> playback command and no user interface; the first playable build arrives when
> the command line gains a play command.

<!-- Screenshot placeholder: replaced by a real capture once the first playable
     build exists. -->

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

- **Salam 0.5.9.** The pinned compiler version lives in `.salam-version`;
  `salam version` must report exactly that. Build or install it from the
  [Salam repository](https://github.com/SalamLang/Salam) — there is no separate
  mizrab installer.
- **A C toolchain with LLVM.** Salam's LLVM backend uses `clang` and the
  system linker, so on Debian/Ubuntu install `build-essential` and `clang`, and
  on macOS install the Xcode command-line tools (`xcode-select --install`).
- macOS or Linux.

```sh
git clone https://github.com/curedbylethe/mizrab
cd mizrab
make build
make run
```

At this commit `make run` prints the usage block, which lists `--version`,
`--scan`, `--index` and `--help`; a bare `./build/mizrab` prints the same block
and exits 0. `./build/mizrab --scan ~/Music` scans a library and prints a
one-line summary. `make build` first runs `salam deps`, which downloads the
packages `salam.lock` pins and checks their sha256 sums, so the first build
needs network access; it then compiles the vendored miniaudio and the C glue
and links them into the binary.

## Build and run

`make build` compiles `main.salam` to `build/mizrab` with the LLVM backend;
`make run` builds and runs it. `make test` checks each `tests/*_test.salam`
program against its `.out` golden, then smoke-tests the binary;
[tests](https://mizrab.mintlify.app/tests) covers the convention, the checks and
running a single test.

[Make targets](https://mizrab.mintlify.app/make-targets) documents every target,
including `make help` and the opt-in `make soak`.

## Built on

- **[basalam](https://github.com/curedbylethe/basalam)** — a retained-mode
  terminal UI library for Salam. It comes from Salam's package registry at
  `v0.3.2`, pinned by commit and sha256 in `salam.lock`.
- **[Salam](https://github.com/SalamLang/Salam)** — the language, compiler and
  standard library mizrab is written in.

The player binary currently imports the Salam standard library (`conv`, `flag`,
`os`) plus its own `commands` and `library` packages, and links the third C
object, `build/library_shim.o`; the basalam import arrives with the application
layer. The `library` package additionally uses the `audio.tag` and `audio.flac`
readers pinned in `salam.toml`, plus the standard library's JSON, crypto and
filesystem packages. The audio engine uses
`atomic`, `mem`, `sync` and `thread`, and is exercised by the tests, not by the
binary. The `player` package is tested headlessly and is not yet included by
the binary.

## Repository layout

`main.salam` is the entry point, `commands/` the command layer, `audio/` the
vendored miniaudio and stb_vorbis plus the decode/ring/device engine, `player/`
the playback controller, `library/` the scanner, tag readers and index, and
`tests/` the harness and its audio fixtures.
[Repository layout](https://mizrab.mintlify.app/repository-layout) describes
every directory, including the reserved `config/` and `ui/` packages.

## Licence

mizrab is licensed under the GNU General Public License, version 3 or later
(`GPL-3.0-or-later`). The full text is in [LICENSE](LICENSE); each source file
carries the same notice in its header.
