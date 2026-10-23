#!/bin/sh
# mizrab gap: the inter-track gap on the real audio backend.
#
# Plays tests/fixtures/tone.wav into tests/fixtures/tone.flac on the default
# output device through the player's queue and prints `backend=<name>` and
# `gap_ms=<n>` (see tests/gap.salam for what the number is). Needs the machine's
# audio output; it is not a test, not part of `make test` and not run by CI,
# and tests/run.sh never discovers it. The unit test asserts the measurement
# with a fake clock instead.
#
# Usage: tests/gap.sh          Env: SALAM=path/to/salam
#                                   GAP_TIMEOUT=seconds (default: 30)
# Run `make build` first: the program links build/miniaudio.o and ma_shim.o.

set -eu

SALAM="${SALAM:-salam}"
GAP_TIMEOUT="${GAP_TIMEOUT:-30}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/build/tests/gap"

for obj in miniaudio ma_shim; do
    if [ ! -f "$ROOT/build/$obj.o" ]; then
        echo "gap: $ROOT/build/$obj.o is missing; run 'make build' first" >&2
        exit 1
    fi
done

# Salam links with the host toolchain on macOS; pin the deployment target to
# the running OS so the linker does not warn about mismatched versions.
if [ "$(uname -s)" = "Darwin" ] && [ -z "${MACOSX_DEPLOYMENT_TARGET:-}" ]; then
    MACOSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion)
    export MACOSX_DEPLOYMENT_TARGET
fi

mkdir -p "$ROOT/build/tests"

# Build and run from tests/: the `link` paths and the fixture paths both
# resolve from there (see tests/run.sh).
cd "$ROOT/tests"
"$SALAM" build gap.salam --output="$BIN" --backend=llvm --log-level=warn

"$BIN" < /dev/null &
pid=$!
( sleep "$GAP_TIMEOUT"; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 &
watchdog=$!
code=0
wait "$pid" || code=$?
kill "$watchdog" 2>/dev/null || true
wait "$watchdog" 2>/dev/null || true
if [ "$code" -eq 137 ]; then
    echo "gap: FAIL timeout after ${GAP_TIMEOUT}s" >&2
fi
exit "$code"
