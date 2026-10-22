#!/bin/sh
# STAGE-03 measurement table for the miniaudio spike. Not a CI gate.
#
# M1-M3 are build quantities measured here with coreutils; M4-M8 are in-process
# and come from build/spike-measure. Raw output only: no rounding, no averaging
# away a spike. Run `make spike-measure` and keep the transcript.

set -u

cd "$(dirname "$0")/.." || exit 1

TMP=$(mktemp "${TMPDIR:-/tmp}/spike-measure.XXXXXX") || exit 1
trap 'rm -f "$TMP"' EXIT HUP INT TERM

say() { printf '%s\n' "$*"; }

say "spike-measure host: $(uname -s) $(sw_vers -productVersion 2>/dev/null || uname -r) $(uname -m)"
say "salam: $(salam version 2>/dev/null | head -1)"
say "cc: $(cc --version 2>/dev/null | head -1)"
say "miniaudio compile: $(make -Bn build/miniaudio.o | grep -m1 -- ' -c ')"
say ""

say "== M1 cold compile time of the miniaudio translation unit (3 runs) =="
i=1
while [ "$i" -le 3 ]; do
    make clean >/dev/null 2>&1
    if ! /usr/bin/time -p make build/miniaudio.o >"$TMP" 2>&1; then
        cat "$TMP"
        exit 1
    fi
    awk -v run="$i" '/^real / { print "M1 run " run " " $0 }' "$TMP"
    i=$((i + 1))
done
say ""

say "== M3 linked binary size from a clean tree =="
make clean >/dev/null 2>&1
if ! make spike-build >"$TMP" 2>&1; then
    cat "$TMP"
    exit 1
fi
say "-- M3: make clean && make spike-build"
ls -l build/spike
say "-- M3: cp build/spike build/spike-stripped && strip -x build/spike-stripped"
cp build/spike build/spike-stripped
strip -x build/spike-stripped
ls -l build/spike build/spike-stripped
say ""

say "== M2 object size =="
ls -l build/miniaudio.o build/ma_shim.o
if size -m build/miniaudio.o build/ma_shim.o >"$TMP" 2>/dev/null; then
    cat "$TMP"
else
    say "M2 size -m not available on this host"
fi
say ""

if ! make build/spike-measure >"$TMP" 2>&1; then
    cat "$TMP"
    exit 1
fi

say "== M4, M5, M8, M9: ./build/spike-measure --measure =="
if ! ./build/spike-measure --measure; then
    say "M4/M5/M8 pass failed"
    exit 1
fi
say ""

say "== M6: ./build/spike-measure --alloc-in-callback =="
if ! ./build/spike-measure --alloc-in-callback; then
    say "M6 pass failed"
    exit 1
fi
say ""

say "== M7: 10 s timeout ./build/spike-measure --print-in-callback =="
run_with_timeout() {
    limit=$1
    shift
    "$@" &
    pid=$!
    ( sleep "$limit"; kill -9 "$pid" 2>/dev/null ) &
    watcher=$!
    wait "$pid"
    status=$?
    kill "$watcher" 2>/dev/null
    wait "$watcher" 2>/dev/null
    return "$status"
}

run_with_timeout 10 ./build/spike-measure --print-in-callback >"$TMP" 2>&1
status=$?
cat "$TMP"
if [ "$status" -eq 0 ]; then
    say "M7 stopped within 10 s: yes (no deadlock)"
else
    say "M7 stopped within 10 s: no (exit $status, killed at the 10 s limit means a deadlock or a stall)"
fi
cb=$(grep -c '^\[cb\] print-in-callback at [0-9][0-9]*$' "$TMP")
hb=$(grep -c '^\[main\] heartbeat [0-9][0-9]*s$' "$TMP")
bad=$(grep -vEc '^\[cb\] print-in-callback at [0-9]+$|^\[main\] heartbeat [0-9]+s$|^M7 ' "$TMP")
say "M7 transcript: $cb well-formed callback lines, $hb main heartbeat lines, $bad spliced or malformed lines"
say ""

say "Raw run commands: make clean; /usr/bin/time -p make build/miniaudio.o (M1); ls -l (M2, M3); strip -x (M3); ./build/spike-measure --measure|--alloc-in-callback|--print-in-callback (M4-M8)."
