#!/bin/sh
# mizrab frame measure: one forced full frame at 200 x 60 with 1,000 tracks.
#
# Twelve measured frames of tests/probe/probe_frame.salam, every raw value
# printed, then a min / median / max table, appended to
# build/tests/frame-measure.txt. The probe is a child of `script`, so stdin is
# a pty: present() only writes to the terminal when the screen is attached, and
# without a pty it would draw and diff and write nothing.
#
# One frame is `dirty = true` + present(): the dirty flag forces the full
# repaint of the 200 x 60 back buffer, present diffs it against the front grid
# and writes the changed cells. That is the frame the issue budgets. Excluded,
# as in tests/shell-measure.sh: fixture construction, the index load, startup,
# terminal setup and the terminal emulator's own paint.
#
# State stays under build/tests/probe: XDG_STATE_HOME points there, so no lock
# or crash flag ever touches the developer's real state directory.
#
# Not a test, not part of `make test`, not run by CI, and tests/run.sh never
# discovers it (tests/*_test.salam only). Run by path, as tests/shell-measure.sh
# is.
#
# Usage: sh tests/frame-measure.sh        Env: SALAM=path/to/salam
#
# No run is retried: an outlier is printed as it happened.

set -eu

SALAM="${SALAM:-salam}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/build/tests/probe"
RUNS=12
RESULT="$BIN/probe_frame.result"
ROWS="$BIN/frame-measure-rows.txt"
REPORT="$ROOT/build/tests/frame-measure.txt"

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

: >"$ROWS"

# Build and run from tests/: the link paths resolve from there, as they do for
# tests/run.sh and tests/shell-measure.sh.
cd "$ROOT/tests"
rm -f "$BIN/probe_frame"
"$SALAM" build probe/probe_frame.salam --output="$BIN/probe_frame" --backend=llvm --log-level=warn

rm -f "$RESULT"
if ! script -q /dev/null "$BIN/probe_frame" "$RESULT" >/dev/null; then
    echo "frame-measure: probe failed; it needs a pty (macOS script)" >&2
    exit 1
fi
if [ ! -s "$RESULT" ]; then
    echo "frame-measure: probe wrote no result (pty or state setup)" >&2
    exit 1
fi

i=1
while IFS= read -r row; do
    us=${row#us=}
    case "$us" in
        '' | *[!0-9]*)
            echo "frame-measure: unreadable probe output: $row" >&2
            exit 1
            ;;
    esac
    printf '%s\n' "$us" >>"$ROWS"
    i=$((i + 1))
done <"$RESULT"

if [ "$i" -ne $((RUNS + 1)) ]; then
    echo "frame-measure: probe wrote $((i - 1)) rows, want $RUNS" >&2
    exit 1
fi

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

set -- $(stats "$ROWS")
frame_min=$1
frame_med=$2
frame_max=$3

{
    printf 'mizrab frame measure\n'
    printf 'host:  %s\n' "$(sw_vers -productVersion 2>/dev/null | sed 's/^/macOS /' || uname -sr)"
    printf 'arch:  %s\n' "$(uname -m)"
    printf 'salam: %s\n' "$("$SALAM" version | head -n 1)"
    printf 'date:  %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'runs:  %s\n' "$RUNS"
    printf 'scope: dirty = true + present() at 200 x 60 with 1,000 tracks\n'
    printf '       under a pty: full repaint, diff and write; no startup or paint\n\n'
    printf 'run   frame_us\n'
    awk '{ printf "%3d %10s\n", NR, $1 }' "$ROWS"
    printf '\nmeasurement   min_us   median_us   max_us\n'
    printf 'frame      %9s %12s %9s\n' "$frame_min" "$frame_med" "$frame_max"
    printf '\nn=%s frames. One value is not the figure; quote the median and the range.\n' "$RUNS"
} | tee -a "$REPORT"

exit 0
