#!/bin/sh
# mizrab test runner.
#
# Follows basalam's convention (itself Salam's test corpus convention): every
# tests/<name>_test.salam is a program that asserts with std/testing and ends
# with `ret testing.Summary()`, and tests/<name>_test.out is its golden stdout.
# A test passes when it builds, exits 0, and its stdout matches the golden file
# byte for byte. Failed assertions are reported on stderr by std/testing.
#
# Every test is built with --backend=llvm; one backend is the policy, so there
# is no SALAM_BACKEND knob and no second target.
#
# Usage: tests/run.sh [name ...]      (default: every tests/*_test.salam)
# Env:   SALAM=path/to/salam          (default: salam on PATH)
#        TEST_TIMEOUT=seconds          (default: 30; bound on each test run)
#
# Goldens are byte-exact and there is no update flag. To add an assertion, edit
# the test, run it, and update the .out by hand. `make test` only reads tests/.

set -u

SALAM="${SALAM:-salam}"
TEST_TIMEOUT="${TEST_TIMEOUT:-30}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/tests"
BIN="$ROOT/build/mizrab"
mkdir -p "$OUT"

# The binary now reads a config file, so a smoke check must not depend on the
# developer's ~/.config: point HOME and the four XDG variables under $OUT, and
# every invocation of this script reads and writes only under build/tests/.
# The compiler keeps its packages under ~/.salam, so it gets the real HOME back.
TOOL_HOME="${HOME:-}"
mkdir -p "$OUT/home" "$OUT/xdg-config" "$OUT/xdg-data" "$OUT/xdg-cache" "$OUT/xdg-state"
HOME="$OUT/home"
XDG_CONFIG_HOME="$OUT/xdg-config"
XDG_DATA_HOME="$OUT/xdg-data"
XDG_CACHE_HOME="$OUT/xdg-cache"
XDG_STATE_HOME="$OUT/xdg-state"
export HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME

if [ ! -x "$BIN" ]; then
    echo "tests: $BIN is missing; run 'make build' first" >&2
    exit 1
fi

# Salam links with the host toolchain on macOS; pin the deployment target to
# the running OS so the linker does not warn about mismatched versions.
if [ "$(uname -s)" = "Darwin" ] && [ -z "${MACOSX_DEPLOYMENT_TARGET:-}" ]; then
    MACOSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion)
    export MACOSX_DEPLOYMENT_TARGET
fi

# Builds one test with the compiler's own HOME, so its package lookup still
# works while $BIN runs with the isolated one.
build_test() {
    if [ -n "$TOOL_HOME" ]; then
        HOME="$TOOL_HOME" "$SALAM" build "$1" --output="$2" --backend=llvm --log-level=warn
        return
    fi
    "$SALAM" build "$1" --output="$2" --backend=llvm --log-level=warn
}

# No names on the command line: every tests/*_test.salam.
if [ "$#" -eq 0 ]; then
    for src in "$ROOT"/tests/*_test.salam; do
        [ -e "$src" ] || continue
        base=${src##*/}
        set -- "$@" "${base%.salam}"
    done
fi

# Build from tests/: the compiler checks a `link` path against the declaring
# file's directory but hands it to the linker unchanged from its cwd, so the
# two agree only when the cwd is the test directory.
cd "$ROOT/tests"

pass=0
fail=0
for name in "$@"; do
    src="$ROOT/tests/$name.salam"
    want="$ROOT/tests/$name.out"
    bin="$OUT/$name"
    got="$OUT/$name.stdout"

    if ! build_test "$src" "$bin"; then
        echo "FAIL $name (build)"
        fail=$((fail + 1))
        continue
    fi
    # Tests never read the terminal; give them an empty stdin so a test that
    # accidentally does cannot hang the run. A watchdog bounds the run as
    # well: a hung test must fail fast, not stall the whole suite (a blocked
    # SIGWINCH wait once hung CI for twenty minutes).
    "$bin" < /dev/null > "$got" &
    pid=$!
    ( sleep "$TEST_TIMEOUT"; kill -9 "$pid" 2>/dev/null ) &
    watchdog=$!
    wait "$pid"
    code=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    if [ "$code" -eq 137 ]; then
        echo "FAIL $name (timeout after ${TEST_TIMEOUT}s)"
        fail=$((fail + 1))
    elif [ "$code" -ne 0 ]; then
        echo "FAIL $name (exit $code)"
        fail=$((fail + 1))
    elif ! diff -u "$want" "$got"; then
        echo "FAIL $name (output differs from $name.out)"
        fail=$((fail + 1))
    else
        echo "ok   $name"
        pass=$((pass + 1))
    fi
done

# The real binary is part of the contract, so the smoke checks run it rather
# than a test program: --version prints the pinned version, --help prints the
# usage line, and an unknown flag is a usage error (exit 2). They count as
# failures only; the summary's numbers count test programs.
"$BIN" --version > "$OUT/cli-version.stdout" 2>&1
code=$?
if [ "$code" -ne 0 ]; then
    echo "FAIL cli: --version (exit $code)"
    fail=$((fail + 1))
elif ! grep -qx "mizrab 0.0.1" "$OUT/cli-version.stdout"; then
    echo "FAIL cli: --version (does not print 'mizrab 0.0.1')"
    fail=$((fail + 1))
else
    echo "ok   cli: --version"
fi

"$BIN" --help > "$OUT/cli-help.stdout" 2>&1
code=$?
if [ "$code" -ne 0 ]; then
    echo "FAIL cli: --help (exit $code)"
    fail=$((fail + 1))
elif ! grep -q "Usage: mizrab" "$OUT/cli-help.stdout"; then
    echo "FAIL cli: --help (does not mention 'Usage: mizrab')"
    fail=$((fail + 1))
else
    echo "ok   cli: --help"
fi

"$BIN" --nope > "$OUT/cli-unknown.stdout" 2>&1
code=$?
if [ "$code" -ne 2 ]; then
    echo "FAIL cli: --nope (exit $code, want 2)"
    fail=$((fail + 1))
else
    echo "ok   cli: --nope"
fi

# --scan runs the whole path headless. Roots are tests/fixtures (the harness has
# cd'd into tests/); every index goes under $OUT so nothing touches $HOME or the
# repository.
rm -f "$OUT/scan-a.json" "$OUT/scan-b.json"
"$BIN" --scan fixtures --index "$OUT/scan-a.json" > "$OUT/cli-scan-a.stdout" 2>&1
code=$?
if [ "$code" -ne 0 ]; then
    echo "FAIL cli: --scan (exit $code)"
    fail=$((fail + 1))
elif ! grep -q "^mizrab: scanned " "$OUT/cli-scan-a.stdout"; then
    echo "FAIL cli: --scan (no summary line)"
    fail=$((fail + 1))
else
    echo "ok   cli: --scan"
fi

# Rerun on the same index: nothing to read, nothing changes. A scan into a fresh
# file must still produce the same bytes.
/bin/cp -f "$OUT/scan-a.json" "$OUT/scan-a.first"
"$BIN" --scan fixtures --index "$OUT/scan-a.json" > "$OUT/cli-scan-b.stdout" 2>&1
code=$?
if [ "$code" -ne 0 ]; then
    echo "FAIL cli: --scan rerun (exit $code)"
    fail=$((fail + 1))
elif ! grep -q "0 added, 0 updated, 0 removed" "$OUT/cli-scan-b.stdout"; then
    echo "FAIL cli: --scan rerun (not '0 added, 0 updated, 0 removed')"
    fail=$((fail + 1))
elif ! cmp -s "$OUT/scan-a.first" "$OUT/scan-a.json"; then
    echo "FAIL cli: --scan rerun (index changed on rerun)"
    fail=$((fail + 1))
elif ! "$BIN" --scan fixtures --index "$OUT/scan-b.json" > "$OUT/cli-scan-c.stdout" 2>&1 \
    || ! cmp -s "$OUT/scan-a.json" "$OUT/scan-b.json"; then
    echo "FAIL cli: --scan rerun (fresh index differs from first)"
    fail=$((fail + 1))
else
    echo "ok   cli: --scan rerun"
fi

if ! grep -q '"schema": 1' "$OUT/scan-a.json"; then
    echo "FAIL cli: --scan index (no '\"schema\": 1')"
    fail=$((fail + 1))
else
    echo "ok   cli: --scan index"
fi

"$BIN" --scan /nonexistent-path-for-mizrab --index "$OUT/scan-missing.json" > "$OUT/cli-scan-missing.stdout" 2>&1
code=$?
if [ "$code" -ne 1 ]; then
    echo "FAIL cli: --scan missing root (exit $code, want 1)"
    fail=$((fail + 1))
else
    echo "ok   cli: --scan missing root"
fi

"$BIN" --scan --index "$OUT/scan-none.json" > "$OUT/cli-scan-none.stdout" 2>&1
code=$?
if [ "$code" -ne 2 ]; then
    echo "FAIL cli: --scan no root (exit $code, want 2)"
    fail=$((fail + 1))
else
    echo "ok   cli: --scan no root"
fi

# A config file that cannot be trusted stops the run before any work, and the
# message names the file and the offending line.
printf '[library]\nroots = fixtures\nnonsense\n' > "$OUT/bad.ini"
"$BIN" --config "$OUT/bad.ini" --scan fixtures > "$OUT/cli-config-bad.stdout" 2>&1
code=$?
if [ "$code" -ne 2 ]; then
    echo "FAIL cli: config broken (exit $code, want 2)"
    fail=$((fail + 1))
elif ! grep -q ":3:" "$OUT/cli-config-bad.stdout"; then
    echo "FAIL cli: config broken (no ':3:' in the message)"
    fail=$((fail + 1))
else
    echo "ok   cli: config broken"
fi

# A config file in XDG_CONFIG_HOME supplies the roots when no positional root is
# given. The explicit --index keeps the index under $OUT.
rm -f "$OUT/scan-cfg.json"
mkdir -p "$XDG_CONFIG_HOME/mizrab"
printf '[library]\nroots = fixtures\n' > "$XDG_CONFIG_HOME/mizrab/config.ini"
"$BIN" --scan --index "$OUT/scan-cfg.json" > "$OUT/cli-scan-config.stdout" 2>&1
code=$?
rm -f "$XDG_CONFIG_HOME/mizrab/config.ini"
if [ "$code" -ne 0 ]; then
    echo "FAIL cli: config roots (exit $code)"
    fail=$((fail + 1))
elif ! grep -q "^mizrab: scanned " "$OUT/cli-scan-config.stdout"; then
    echo "FAIL cli: config roots (no summary line)"
    fail=$((fail + 1))
else
    echo "ok   cli: config roots"
fi

# The flags beat the file: the positional root and --index both override what
# the config sets, so the config's index is never written even though its root
# does not exist. This is the wiring `Resolve` alone cannot prove.
rm -f "$OUT/prec-file.json" "$OUT/prec-flag.json"
printf '[library]\nroots = %s/does-not-exist\nindex = %s/prec-file.json\n' "$OUT" "$OUT" > "$OUT/prec-config.ini"
"$BIN" --config "$OUT/prec-config.ini" --scan fixtures --index "$OUT/prec-flag.json" > "$OUT/cli-config-precedence.stdout" 2>&1
code=$?
rm -f "$OUT/prec-config.ini"
if [ "$code" -ne 0 ]; then
    echo "FAIL cli: config precedence (exit $code)"
    fail=$((fail + 1))
elif ! grep -q "^mizrab: scanned " "$OUT/cli-config-precedence.stdout"; then
    echo "FAIL cli: config precedence (no summary line)"
    fail=$((fail + 1))
elif [ ! -f "$OUT/prec-flag.json" ]; then
    echo "FAIL cli: config precedence (flag index not written)"
    fail=$((fail + 1))
elif [ -f "$OUT/prec-file.json" ]; then
    echo "FAIL cli: config precedence (config index written)"
    fail=$((fail + 1))
else
    echo "ok   cli: config precedence"
fi

# An explicitly named config that is not there is an error, not a silent fall
# back to the defaults.
"$BIN" --config "$OUT/there-is-no.ini" --scan fixtures > "$OUT/cli-config-missing.stdout" 2>&1
code=$?
if [ "$code" -ne 2 ]; then
    echo "FAIL cli: config missing (exit $code, want 2)"
    fail=$((fail + 1))
elif ! grep -q "cannot read" "$OUT/cli-config-missing.stdout"; then
    echo "FAIL cli: config missing (no 'cannot read')"
    fail=$((fail + 1))
else
    echo "ok   cli: config missing"
fi

# --version is answered before the file is read, so a broken file in the same
# command line changes nothing.
"$BIN" --version --config "$OUT/bad.ini" > "$OUT/cli-config-version.stdout" 2>&1
code=$?
if [ "$code" -ne 0 ]; then
    echo "FAIL cli: config after --version (exit $code, want 0)"
    fail=$((fail + 1))
elif ! grep -qx "mizrab 0.0.1" "$OUT/cli-config-version.stdout"; then
    echo "FAIL cli: config after --version (does not print 'mizrab 0.0.1')"
    fail=$((fail + 1))
else
    echo "ok   cli: config after --version"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
