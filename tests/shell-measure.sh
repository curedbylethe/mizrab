#!/bin/sh
# mizrab shell measure: startup to first frame and shutdown, headless.
#
# Twelve runs of tests/probe/probe_shell.salam, every raw value printed, then a
# min / median / max table. The figure covers config.FromEnv, ui.NewShell(100,
# 30), draw() and present() on the null audio backend with start() never called,
# so it is comparable across runs and does not include opening a device.
# Shutdown covers Shell.Close(), that is Screen.close().
#
# Not a test, not part of `make test`, not run by CI, and tests/run.sh never
# discovers it (tests/*_test.salam only). Run by path, as tests/gap.sh is.
#
# Usage: sh tests/shell-measure.sh        Env: SALAM=path/to/salam
#
# No run is retried: an outlier is printed as it happened.

set -eu

SALAM="${SALAM:-salam}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/build/tests/probe"
RUNS=12

# Salam links with the host toolchain on macOS; pin the deployment target to
# the running OS so the linker does not warn about mismatched versions.
if [ "$(uname -s)" = "Darwin" ] && [ -z "${MACOSX_DEPLOYMENT_TARGET:-}" ]; then
    MACOSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion)
    export MACOSX_DEPLOYMENT_TARGET
fi

mkdir -p "$BIN"
STARTS="$BIN/shell-measure-startup.txt"
STOPS="$BIN/shell-measure-shutdown.txt"
: >"$STARTS"
: >"$STOPS"

# Build and run from tests/: the link paths resolve from there, as they do for
# tests/run.sh and tests/gap.sh.
cd "$ROOT/tests"
rm -f "$BIN/probe_shell"
"$SALAM" build probe/probe_shell.salam --output="$BIN/probe_shell" --backend=llvm --log-level=warn

printf 'mizrab shell measure\n'
printf 'host:  %s\n' "$(sw_vers -productVersion 2>/dev/null | sed 's/^/macOS /' || uname -sr)"
printf 'arch:  %s\n' "$(uname -m)"
printf 'salam: %s\n' "$("$SALAM" version | head -n 1)"
printf 'date:  %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
printf 'runs:  %s\n' "$RUNS"
printf 'scope: config.FromEnv, NewShell(100, 30), draw, present; then Close\n'
printf '       null audio backend, no tty, present() never flushes\n\n'

printf 'run   startup_us   shutdown_us\n'
i=1
while [ "$i" -le "$RUNS" ]; do
    line=$("$BIN/probe_shell")
    startup=$(printf '%s\n' "$line" | cut -d' ' -f1 | cut -d= -f2)
    shutdown=$(printf '%s\n' "$line" | cut -d' ' -f2 | cut -d= -f2)
    case "$startup$shutdown" in
        '' | *[!0-9]*)
            echo "shell-measure: unreadable probe output: $line" >&2
            exit 1
            ;;
    esac
    printf '%s\n' "$startup" >>"$STARTS"
    printf '%s\n' "$shutdown" >>"$STOPS"
    printf '%3d %12s %13s\n' "$i" "$startup" "$shutdown"
    i=$((i + 1))
done

# min/median/max of one value per line. The median of an even count is the mean
# of the two middle values, rounded down to whole microseconds.
stats() {
    sort -n "$1" | awk '
        { v[NR] = $1 }
        END {
            n = NR
            if (n % 2) {
                med = v[(n + 1) / 2]
            } else {
                med = int((v[n / 2] + v[n / 2 + 1]) / 2)
            }
            printf "%s %s %s\n", v[1], med, v[n]
        }'
}

set -- $(stats "$STARTS")
startup_min=$1
startup_med=$2
startup_max=$3
set -- $(stats "$STOPS")
shutdown_min=$1
shutdown_med=$2
shutdown_max=$3

printf '\nmeasurement   min_us   median_us   max_us\n'
printf 'startup    %9s %12s %9s\n' "$startup_min" "$startup_med" "$startup_max"
printf 'shutdown   %9s %12s %9s\n' "$shutdown_min" "$shutdown_med" "$shutdown_max"
printf '\nn=%s runs. One value is not the figure; quote the median and the range.\n' "$RUNS"

exit 0
