# mizrab

mizrab is a music player built on basalam: a terminal application written in
the [Salam](https://github.com/SalamLang/Salam) programming language.

> **Status: audio engine, playback controller, library scanner and app
> shell.** The audio engine exists: it decodes MP3, FLAC, WAV and OGG, streams
> them through a lock-free ring buffer to miniaudio's playback callback, and
> runs headless on miniaudio's null backend, where its tests exercise it
> ([the engine](https://mizrab.mintlify.app/audio-engine)). The playback
> controller above it owns the states, the commands, the position, the queue
> and the error text
> ([the controller](https://mizrab.mintlify.app/playback-controller)). The
> binary runs both: a bare `mizrab` with stdin a terminal opens the app shell
> ([the shell](https://mizrab.mintlify.app/app-shell)), where `space`, `n` and
> `p` are bound to play/pause, next and previous. With stdin not a terminal it
> prints its usage block and exits 0, as it always has. It also runs the library
> scanner:
> `mizrab --scan ROOT...` walks the roots, reads tags and writes a JSON index
> ([the library](https://mizrab.mintlify.app/library)). It reads a config file
> at startup ([configuration](https://mizrab.mintlify.app/configuration)) and
> answers `--version` and `--help`. The shell is not finished: `:` and `/`
> record the request and open nothing yet.

<!-- Screenshot placeholder: replaced by a real capture once the first playable
     build exists. -->

Screenshot: pending. The shell runs, but no terminal capture is recorded yet.

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

At this commit `make run` opens the app shell when its stdin is a terminal.
With stdin not a terminal the binary prints the usage block, which lists
`--version`, `--scan`, `--index`, `--config` and `--help`, and exits 0; a pipe
or a script sees the block. `./build/mizrab --scan ~/Music` scans a library and
prints a one-line summary. The roots and the index path can also come from
`$XDG_CONFIG_HOME/mizrab/config.ini`; the flag beats the file and the file beats
the defaults ([configuration](https://mizrab.mintlify.app/configuration)).

`make build` first runs `salam deps`, which downloads the
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
  `v0.3.3`, pinned by commit and sha256 in `salam.lock`.
- **[Salam](https://github.com/SalamLang/Salam)** — the language, compiler and
  standard library mizrab is written in.

The player binary imports the Salam standard library (`conv`, `flag`, `os`)
plus its own `commands`, `config`, `library`, `ui` and `player` packages, and
links the third C object, `build/library_shim.o`; basalam arrives through
`ui/`. The `library` package additionally uses the `audio.tag` and `audio.flac`
readers pinned in `salam.toml`, plus the standard library's JSON, crypto and
filesystem packages. The audio engine uses `atomic`, `mem`, `sync` and
`thread`, and the binary reaches it through `player/`, which it includes.

## Repository layout

`main.salam` is the entry point, `commands/` the command layer, `audio/` the
vendored miniaudio and stb_vorbis plus the decode/ring/device engine, `player/`
the playback controller, `library/` the scanner, tag readers and index,
`config/` the XDG directory resolver and the config file reader with its
commented sample, `ui/` the shell, the keymap, the event loop, the terminal
guard and the instance lock, and `tests/` the harness and its audio fixtures.
[Repository layout](https://mizrab.mintlify.app/repository-layout) describes
every directory, and [configuration](https://mizrab.mintlify.app/configuration)
covers the file `config/` reads.

## Licence

mizrab is licensed under the GNU General Public License, version 3 or later
(`GPL-3.0-or-later`). The full text is in [LICENSE](LICENSE); each source file
carries the same notice in its header.
