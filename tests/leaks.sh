#!/bin/sh
# mizrab leaks: absolute file-descriptor and thread counts for three runs.
#
#   1. probe_audio 0           no cycles, no screen  - the baseline
#   2. probe_audio 20          twenty play/stop cycles, no screen
#   3. probe_audio 0 screen    no cycles, the real shell open on a pty
#
# Each run plays and stops fixtures/tone.wav on the null backend for its cycle
# count, opens the shell only when asked, prints its pid and then holds still.
# Every cycle opens a file, spawns the decoder thread, creates the device and
# tears both down again. This script samples `lsof -p <pid>` (one row per open
# file handle) and `ps -M <pid>` (one row per thread) at 3 s and at 8 s after
# that pid line, prints both counts and the run's own delta, then prints run 2
# and run 3 against run 1 at both sample points.
#
# Why a baseline: without one, a leak of one descriptor per cycle reads the
# same after twenty cycles and after zero, so the difference between run 2 and
# run 1 is the per-cycle cost, and the difference between run 3 and run 1 is
# what a running shell itself holds. The baseline is not an empty process: it
# still calls player.Init(true), so miniaudio's null backend and its constant
# handles are part of it.
#
# The shell needs a terminal, because ui.Open is a no-op without one, so run 3
# is wrapped in `script -q /dev/null`, which gives it a throwaway pty; `$!` is
# then script's pid, which is why the probe's own pid line is the one sampled.
# That run's fd count includes the pty slave. Its thread count is measured, not
# assumed: this script prints what ps -M sees, not what the screen is expected
# to start.
#
# Sampling twice is not a proof of absence: a leak that starts later than 8 s,
# or one that reuses a descriptor number, is not visible here, and a clean
# 3 s -> 8 s delta says nothing about a leak that began after 8 s. A non-zero
# delta is a finding to report, not to round away.
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

# The three runs the script measures.
CYCLES=20

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
# Run 3 is the only one that needs a pty, and it is measured, so a host without
# script cannot report the shell's own cost. Fail rather than silently dropping
# the run.
command -v script >/dev/null 2>&1 || die "script is not available; cannot run the screen case on a pty"

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

fds() {
    lsof -p "$1" 2>/dev/null | awk 'NR > 1 { n++ } END { print n + 0 }'
}

threads() {
    ps -M "$1" 2>/dev/null | awk 'NR > 1 { n++ } END { print n + 0 }'
}

# run_probe TAG CYCLES MODE -> RUN_PID RUN_FD_EARLY RUN_TH_EARLY RUN_FD_LATE RUN_TH_LATE
#
# MODE is "plain" or "screen". Each sample pair is taken 3 s and 8 s after the
# pid line, so the probe must still be inside its idle window; the probe holds
# for twenty seconds. The probe is sampled by its own pid, not by `$!`: under
# script `$!` is the wrapper.
run_probe() {
    tag=$1
    cycles=$2
    mode=$3
    out="$DIR/$tag.out"
    err="$DIR/$tag.err"
    : >"$out"
    : >"$err"
    if [ "$mode" = "screen" ]; then
        script -q /dev/null "$BIN" "$cycles" screen >"$out" 2>"$err" &
    else
        "$BIN" "$cycles" >"$out" 2>"$err" &
    fi
    harness_pid=$!

    # The probe prints its pid after the cycles (and after opening the shell),
    # so the samples start from a settled process rather than from start-up.
    # The pty's escape bytes can share the line, so the pid is matched anywhere
    # in the capture.
    pid=""
    i=0
    while [ "$i" -lt 600 ]; do
        pid=$(grep -ao 'pid=[0-9]*' "$out" 2>/dev/null | tail -n 1 | cut -d= -f2)
        [ -n "$pid" ] && break
        kill -0 "$harness_pid" 2>/dev/null || break
        sleep 0.05
        i=$((i + 1))
    done
    [ -n "$pid" ] || {
        cat "$err" >&2
        die "$tag: the probe printed no pid line; it failed before the idle window"
    }

    sleep 3
    fd_early=$(fds "$pid")
    th_early=$(threads "$pid")
    sleep 5
    fd_late=$(fds "$pid")
    th_late=$(threads "$pid")

    # A count of zero means the sampler saw nothing, which is a broken
    # measurement and not a clean process.
    [ "$fd_early" -gt 0 ] && [ "$fd_late" -gt 0 ] || die "$tag: lsof returned no rows for pid $pid"
    [ "$th_early" -gt 0 ] && [ "$th_late" -gt 0 ] || die "$tag: ps -M returned no rows for pid $pid"

    kill -TERM "$pid" 2>/dev/null || true
    wait "$harness_pid" 2>/dev/null || true

    RUN_PID=$pid
    RUN_FD_EARLY=$fd_early
    RUN_TH_EARLY=$th_early
    RUN_FD_LATE=$fd_late
    RUN_TH_LATE=$th_late
}

# print_run TITLE -> the run's pid, both samples and its own 3 s -> 8 s delta.
print_run() {
    printf '%s\n' "$1"
    printf '  pid    %s\n' "$RUN_PID"
    printf '  %-8s %18s %10s\n' "sample" "file descriptors" "threads"
    printf '  %-8s %18s %10s\n' "3 s" "$RUN_FD_EARLY" "$RUN_TH_EARLY"
    printf '  %-8s %18s %10s\n' "8 s" "$RUN_FD_LATE" "$RUN_TH_LATE"
    printf '  %-8s %18s %10s\n\n' "delta" "$((RUN_FD_LATE - RUN_FD_EARLY))" "$((RUN_TH_LATE - RUN_TH_EARLY))"
}

run_probe base 0 plain
base_fd_early=$RUN_FD_EARLY
base_th_early=$RUN_TH_EARLY
base_fd_late=$RUN_FD_LATE
base_th_late=$RUN_TH_LATE
base_pid=$RUN_PID

run_probe churn "$CYCLES" plain
churn_fd_early=$RUN_FD_EARLY
churn_th_early=$RUN_TH_EARLY
churn_fd_late=$RUN_FD_LATE
churn_th_late=$RUN_TH_LATE
churn_pid=$RUN_PID

run_probe screen 0 screen
screen_fd_early=$RUN_FD_EARLY
screen_th_early=$RUN_TH_EARLY
screen_fd_late=$RUN_FD_LATE
screen_th_late=$RUN_TH_LATE
screen_pid=$RUN_PID

printf 'mizrab leaks: three runs on the null backend, fixture fixtures/tone.wav\n'
printf 'host:  %s\n' "$(sw_vers -productVersion 2>/dev/null | sed 's/^/macOS /' || uname -sr)"
printf 'salam: %s\n' "$("$SALAM" version | head -n 1)"
printf 'probe: build/tests/leaks/probe_audio\n'
printf 'samples: 3 s and 8 s after each run'"'"'s pid line\n\n'

RUN_PID=$base_pid
RUN_FD_EARLY=$base_fd_early
RUN_TH_EARLY=$base_th_early
RUN_FD_LATE=$base_fd_late
RUN_TH_LATE=$base_th_late
print_run "run 1: 0 cycles, no screen - the baseline"

RUN_PID=$churn_pid
RUN_FD_EARLY=$churn_fd_early
RUN_TH_EARLY=$churn_th_early
RUN_FD_LATE=$churn_fd_late
RUN_TH_LATE=$churn_th_late
print_run "run 2: $CYCLES cycles, no screen - the churn"

RUN_PID=$screen_pid
RUN_FD_EARLY=$screen_fd_early
RUN_TH_EARLY=$screen_th_early
RUN_FD_LATE=$screen_fd_late
RUN_TH_LATE=$screen_th_late
print_run "run 3: 0 cycles, screen open (pty via script) - the shell itself"

printf 'differences vs the baseline (run 1)\n'
printf '  %-12s %25s %25s\n' "run" "3 s after the pid line" "8 s after the pid line"
printf '  %-12s %13s %11s %13s %11s\n' "" "files" "threads" "files" "threads"
printf '  %-12s %+13s %+11s %+13s %+11s\n' "2: churn" \
    "$((churn_fd_early - base_fd_early))" "$((churn_th_early - base_th_early))" \
    "$((churn_fd_late - base_fd_late))" "$((churn_th_late - base_th_late))"
printf '  %-12s %+13s %+11s %+13s %+11s\n' "3: screen" \
    "$((screen_fd_early - base_fd_early))" "$((screen_th_early - base_th_early))" \
    "$((screen_fd_late - base_fd_late))" "$((screen_th_late - base_th_late))"

printf '\nTwo samples at 3 s and 8 s are not proof of absence. A non-zero delta is a\n'
printf 'finding to report, not to round away, and a run whose 3 s and 8 s counts\n'
printf 'match has only been shown not to grow inside those five seconds.\n'

exit 0
