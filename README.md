# mizrab

mizrab is a music player built on basalam: a terminal application written in
the [Salam](https://github.com/SalamLang/Salam) programming language.

> **Status: scaffold.** The binary answers `--version` and `--help` and prints
> its usage when invoked bare. There is no playback, no library scanning and no
> user interface yet; those land in later issues. A spike under `spike/` proved
> that a Salam function can serve as miniaudio's data callback and fill f32
> frames on Core Audio; the engine itself is not written
> ([docs/spike-miniaudio.md](docs/spike-miniaudio.md)).

<!-- Screenshot placeholder: replaced by a real capture once the first playable
     build exists (CUR-511). -->

Screenshot: coming with the first playable build.

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

Every task is a `make` target; run `make help` for the same list.

| Command         | What it does                                                          |
| --------------- | --------------------------------------------------------------------- |
| `make help`     | List the targets and the Salam version the Makefile reads             |
| `make build`    | Compile `main.salam` to `build/mizrab` with `--backend=llvm`          |
| `make run`      | Build, then run `build/mizrab`                                        |
| `make test`     | Build and run `tests/run.sh`                                          |
| `make fmt`      | Format every Salam source in place with `salam format`                |
| `make fmt-check` | Fail if any Salam source would be rewritten                          |
| `make clean`    | Remove `build/` and the compiler's `.salam-build/` scratch directory  |
| `make spike-build` | Compile miniaudio and the shim, then link `spike/tone.salam` to `build/spike` |
| `make spike-run` | Build the spike and play its 2 s tone on the default device          |
| `make spike-check` | Build the spike and run it on miniaudio's null backend             |
| `make spike-check-device` | Build the spike and run it on the default device; the name CI uses            |
| `make spike-measure` | Print the spike's measurement table (M1–M8, real device)         |

The `spike-*` targets belong to the FFI spike, not to the player. `make
spike-build` compiles miniaudio with `-O2` and links two objects by relative
path, so it is slower than `make build` on a clean tree; see
[docs/spike-miniaudio.md](docs/spike-miniaudio.md) for the recipe and the
measurements.

`make test` runs `tests/run.sh`, which builds each `tests/*_test.salam`
program with the LLVM backend and compares its stdout byte-for-byte with the
matching `.out` golden. `tests/cli_test.salam` makes 2 assertions; the harness
then smoke-tests the real binary three ways (`--version`, `--help`, an unknown
flag). One test on its own:

```sh
sh tests/run.sh cli_test
```

That narrows the golden checks to `cli_test`; the three binary smoke checks
always run.

## Built on

- **[basalam](https://github.com/curedbylethe/basalam)** — a retained-mode
  terminal UI library for Salam. It is vendored at `vendor/basalam` and pinned
  to a commit, not a branch or tag (basalam has no tags yet).
- **[Salam](https://github.com/SalamLang/Salam)** — the language, compiler and
  standard library mizrab is written in.

The player currently imports only the Salam standard library (`flag`, `os`) plus
its own `commands` package; the basalam include arrives with the application
layer. The spike also imports `conv`, `math`, `mem` and `sync`.

## Repository layout

| Path          | Contents                                                                  |
| ------------- | ------------------------------------------------------------------------- |
| `main.salam`  | Entry point: flag parsing, `--version`, `--help`, usage output            |
| `commands/`   | Command layer: the version constant and the usage string (more to come)    |
| `audio/`      | Vendored miniaudio 0.11.25: `miniaudio.c` (the implementation unit) and `miniaudio.h`; the playback backend lands here with CUR-503 |
| `spike/`      | The miniaudio FFI spike: `tone.salam`, `ma_shim.{h,c}`, the measurement harness and a struct probe; throwaway once CUR-503 exists |
| `player/`     | Reserved for playback state and control                                    |
| `library/`    | Reserved for library scanning and metadata                                 |
| `config/`     | Reserved for configuration loading                                         |
| `ui/`         | Reserved for the basalam-based terminal interface                          |
| `tests/`      | Test programs, their `.out` goldens and the `run.sh` harness               |
| `vendor/`     | Vendored dependencies; `vendor/basalam` is a submodule pinned to a commit  |
| `docs/`       | Written findings; `docs/spike-miniaudio.md` is the only file today          |

`player/`, `library/`, `config/` and `ui/` hold only a `.gitkeep` today.

## Licence

mizrab is licensed under the GNU General Public License, version 3 or later
(`GPL-3.0-or-later`). The full text is in [LICENSE](LICENSE); each source file
carries the same notice in its header.
