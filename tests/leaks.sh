#!/bin/sh
# mizrab leaks: file descriptors and threads across twenty play/stop cycles.
#
# tests/probe/probe_audio.salam plays and stops fixtures/tone.wav twenty times
# on the null backend, opening a file, spawning the decoder thread and creating
# the device each cycle, then prints its pid and holds still. This script
# samples `lsof -p <pid>` (one row per open file handle) and `ps -M <pid>` (one
# row per thread) at 3 s and at 8 s after that pid line, and prints both counts
# with their deltas.
#
# Two samples are not a proof of absence: a leak that starts later than 8 s, or
# one that reuses a descriptor number, is not visible here. A non-zero delta is
# a finding to report, not to round away.
#
# Not a test, not part of `make test`, not run by CI, and tests/run.sh never
# discovers it (tests/*_test.salam only). Run by path, as tests/gap.sh is.
#
# Usage: sh tests/leaks.sh        Env: SALAM=path/to/salam
# Run `make build` first: the probe links build/miniaudio.o and ma_shim.o.

set -eu

SALAM="${SALAM:-salam}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR="$ROOT/build/tests/leaks"
BIN="$DIR/probe_audio"

die() {
    echo "leaks: FAIL $*" >&2
    exit 1
}

for obj in miniaudio ma_shim; do
    [ -f "$ROOT/build/$obj.o" ] || die "$ROOT/build/$obj.o is missing; run 'make build' first"
done

# Both samplers are the measurement; a missing one is a hard failure, not a
# zero count.
command -v lsof >/dev/null 2>&1 || die "lsof is not available; cannot count file descriptors"
ps -M $$ >/dev/null 2>&1 || die "'ps -M' is not available; cannot count threads"

# Salam links with the host toolchain on macOS; pin the deployment target to
# the running OS so the linker does not warn about mismatched versions.
if [ "$(uname -s)" = "Darwin" ] && [ -z "${MACOSX_DEPLOYMENT_TARGET:-}" ]; then
    MACOSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion)
    export MACOSX_DEPLOYMENT_TARGET
fi

mkdir -p "$DIR"

# The compiler checks a `link` path against the declaring file's directory but
# hands it to the linker unchanged from the cwd, so the probe one directory
# deeper is built from its own directory and then run from tests/, where the
# fixture path resolves as it does for tests/run.sh.
cd "$ROOT/tests/probe"
rm -f "$BIN"
"$SALAM" build probe_audio.salam --output="$BIN" --backend=llvm --log-level=warn
cd "$ROOT/tests"

OUT="$DIR/probe.out"
: >"$OUT"
"$BIN" >"$OUT" 2>"$DIR/probe.err" &
harness_pid=$!

# The probe prints its own pid after the twenty cycles, so the samples start
# from a settled process rather than from process start. `$!` is the same pid
# here, since nothing wraps the probe.
pid=""
i=0
while [ "$i" -lt 1200 ]; do
    pid=$(sed -n 's/^pid=\([0-9]*\)$/\1/p' "$OUT" | tail -n 1)
    [ -n "$pid" ] && break
    kill -0 "$harness_pid" 2>/dev/null || break
    sleep 0.05
    i=$((i + 1))
done
[ -n "$pid" ] || {
    cat "$DIR/probe.err" >&2
    die "the probe printed no pid line; it failed before the idle window"
}

fds() {
    lsof -p "$1" 2>/dev/null | awk 'NR > 1 { n++ } END { print n + 0 }'
}

threads() {
    ps -M "$1" 2>/dev/null | awk 'NR > 1 { n++ } END { print n + 0 }'
}

sleep 3
fd_early=$(fds "$pid")
th_early=$(threads "$pid")
sleep 5
fd_late=$(fds "$pid")
th_late=$(threads "$pid")

# A count of zero means the sampler saw nothing, which is a broken measurement
# and not a clean process.
[ "$fd_early" -gt 0 ] && [ "$fd_late" -gt 0 ] || die "lsof returned no rows for pid $pid"
[ "$th_early" -gt 0 ] && [ "$th_late" -gt 0 ] || die "ps -M returned no rows for pid $pid"

printf 'mizrab leaks: %s\n' "twenty play/stop cycles on the null backend, fixture fixtures/tone.wav"
printf 'host:  %s\n' "$(sw_vers -productVersion 2>/dev/null | sed 's/^/macOS /' || uname -sr)"
printf 'salam: %s\n' "$("$SALAM" version | head -n 1)"
printf 'pid:   %s\n\n' "$pid"

printf '%-22s %18s %10s\n' "sample" "file descriptors" "threads"
printf '%-22s %18s %10s\n' "3 s after the pid line" "$fd_early" "$th_early"
printf '%-22s %18s %10s\n' "8 s after the pid line" "$fd_late" "$th_late"
printf '%-22s %18s %10s\n' "delta" "$((fd_late - fd_early))" "$((th_late - th_early))"

kill -TERM "$pid" 2>/dev/null || true
wait "$harness_pid" 2>/dev/null || true

printf '\nTwo samples at 3 s and 8 s, not proof of absence. A non-zero delta is a\n'
printf 'finding to report, not to round away.\n'

exit 0
