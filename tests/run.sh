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

# No names on the command line: every tests/*_test.salam.
if [ "$#" -eq 0 ]; then
    for src in "$ROOT"/tests/*_test.salam; do
        [ -e "$src" ] || continue
        base=${src##*/}
        set -- "$@" "${base%.salam}"
    done
fi

pass=0
fail=0
for name in "$@"; do
    src="$ROOT/tests/$name.salam"
    want="$ROOT/tests/$name.out"
    bin="$OUT/$name"
    got="$OUT/$name.stdout"

    if ! "$SALAM" build "$src" --output="$bin" --backend=llvm --log-level=warn; then
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

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
