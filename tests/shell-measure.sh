#!/bin/sh
# mizrab shell measure: startup to first frame and shutdown, on a real pty.
#
# Twelve runs of tests/probe/probe_shell.salam, every raw value printed, then a
# min / median / max table. Each run is a child of `script`, so stdin is a pty:
# ui.Open then really takes the terminal (raw mode, alternate screen, hidden
# cursor, input thread) and Shell.Close really joins that thread. Run without a
# pty, Open would no-op and both figures would describe nothing.
#
# Startup covers ui.Begin (guard install and flag file), NewTerminalShell,
# Open (raw mode, alternate screen, input thread spawn) and the first
# present(). Shutdown covers Shell.Close (terminal restore, input thread join,
# frees) and ui.End. config.FromEnv and the instance lock are outside the
# startup timer, as the probe's comment explains.
#
# State stays under build/tests/probe: XDG_STATE_HOME points there, so the lock
# and the crash flag never touch the developer's real state directory.
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
RESULT="$BIN/probe_shell.result"

# Salam links with the host toolchain on macOS; pin the deployment target to
# the running OS so the linker does not warn about mismatched versions.
if [ "$(uname -s)" = "Darwin" ] && [ -z "${MACOSX_DEPLOYMENT_TARGET:-}" ]; then
    MACOSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion)
    export MACOSX_DEPLOYMENT_TARGET
fi

mkdir -p "$BIN/state"
# Absolute, so config.FromEnv uses it verbatim, and it lands under build/tests.
XDG_STATE_HOME="$BIN/state"
export XDG_STATE_HOME

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
printf 'scope: Begin, NewTerminalShell, Open, first present; then Close, End\n'
printf '       under a pty: raw mode, alternate screen, input thread and its join\n\n'

printf 'run   startup_us   shutdown_us\n'
i=1
while [ "$i" -le "$RUNS" ]; do
    rm -f "$RESULT"
    if ! script -q /dev/null "$BIN/probe_shell" "$RESULT" >/dev/null; then
        echo "shell-measure: probe failed on run $i; it needs a pty (macOS script)" >&2
        exit 1
    fi
    if [ ! -s "$RESULT" ]; then
        echo "shell-measure: probe wrote no result on run $i (pty or state setup)" >&2
        exit 1
    fi
    line=$(cat "$RESULT")
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
