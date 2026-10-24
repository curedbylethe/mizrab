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

- `make fmt` formats the Salam sources; `make fmt-check` fails if any would be
  rewritten.
- `make check` is the tree-green check: it runs `make fmt-check`, then
  `make build` and `make test`.
- `make docs-check` and `make docs-format-check` are the documentation gates.

[Make targets](https://mizrab.mintlify.app/make-targets) documents every target
and [tests](https://mizrab.mintlify.app/tests) covers the harness.

## Documentation site

The site is <https://mizrab.mintlify.app> (subdomain `mizrab`); its pages are
the `.mdx` files at the repository root.

- **Local preview.** `npm i -g "mint@$(cat .mint-version)"`, then `make docs`.
- **Gates.** `make docs-check` validates `docs.json` and checks internal links
  and anchors; `make docs-format-check` fails if `mint format` would rewrite a
  page. The format gate compares against the index, so stage or commit page
  edits first.
- **Deployment.** Mintlify project `mizrab`, plan `hobby`, no custom domain.
  Source `curedbylethe/mizrab`, deploy branch `main`, content directory the
  repository root; the Mintlify GitHub App is installed on the repository. A
  push to `main` publishes. The dashboard is external and holds no repository
  state.
- **Owner.** Parsa Jahanbani (@curedbylethe), the account's sole member.
- **Status.** Until the first documentation commit reaches `main`, the live site
  shows the Mintlify starter kit; verification happens after merge, not in CI.

## Repository layout

[Repository layout](https://mizrab.mintlify.app/repository-layout) describes
every directory, including the reserved application-layer packages.

## Tests

`tests/<name>_test.salam` asserts with `std/testing`, ends with
`ret testing.Summary()` and has a byte-exact `tests/<name>.out` golden;
[tests](https://mizrab.mintlify.app/tests) covers the harness, the CLI smoke
checks and adding a test. Run one with `sh tests/run.sh <name>`.

## Code style

- `salam format` is the authority. Run `make fmt` before committing;
  `make fmt-check` is the gate that rejects unformatted files.
- Indent with 4 spaces (`.editorconfig` matches the formatter).
- Every file starts with the project licence header comment; `make header-check`
  fails, naming the file, when one does not.
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
- The tree is green after every commit: `make check`.

## Version pins and the bump procedure

mizrab has six pins: the Salam compiler (`.salam-version`), the setup action
that installs it (`.github/workflows/ci.yml`), basalam (`vendor/basalam`),
miniaudio (`audio/miniaudio.h` and `audio/miniaudio.c`), stb_vorbis
(`audio/stb_vorbis.c`) and the Mintlify CLI. Current values and the bump procedure are on the site:
[version pins](https://mizrab.mintlify.app/contributing#version-pins).

The Mintlify pin lives only in `.mint-version`. The Makefile and CI read that
file, and the README names the file rather than repeating the value.

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
needs four fields, listed with the convention in
[upstream findings](https://mizrab.mintlify.app/contributing#upstream-findings).

File it at [Salam issues](https://github.com/SalamLang/Salam/issues) or
[basalam issues](https://github.com/curedbylethe/basalam/issues), then link it
back from `FINDINGS.md`. That file (CUR-510) is the log of local findings and
their upstream links; this section is only the convention.
