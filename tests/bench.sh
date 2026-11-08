#!/bin/sh
# Record one host's benchmark measurements in bench/results.jsonl.

set -eu

SALAM="${SALAM:-salam}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/bench"
LIBRARY="$OUT/library"
INDEX="$OUT/index.json"
BENCH="$OUT/bench"
PROBE="$OUT/probe_shell"
RESULT="$OUT/probe_shell.result"
STARTS="$OUT/startup.txt"

if ! command -v script >/dev/null 2>&1; then
    echo "bench: 'script' is required for startup measurement" >&2
    exit 1
fi

mkdir -p "$OUT"
rm -rf "$LIBRARY"
mkdir -p "$LIBRARY"
rm -f "$INDEX"
: >"$STARTS"

i=1
while [ "$i" -le 1000 ]; do
    name=$(printf 'track-%04d' "$i")
    case $(((i - 1) % 4)) in
        0) fixture=tone.wav ;;
        1) fixture=tone.flac ;;
        2) fixture=tone.mp3 ;;
        3) fixture=tone.ogg ;;
    esac
    cp "$ROOT/tests/fixtures/$fixture" "$LIBRARY/$name.${fixture##*.}"
    i=$((i + 1))
done

cd "$ROOT/tests"
"$SALAM" build bench.salam --output="$BENCH" --backend=llvm --log-level=warn
"$SALAM" build probe/probe_shell.salam --output="$PROBE" --backend=llvm --log-level=warn

TERM=xterm-256color
export TERM
unset NO_COLOR COLORTERM CLICOLOR_FORCE
XDG_STATE_HOME="$OUT/state"
export XDG_STATE_HOME
mkdir -p "$XDG_STATE_HOME"

i=1
while [ "$i" -le 12 ]; do
    rm -f "$RESULT"
    if ! script -q /dev/null "$PROBE" "$RESULT" >/dev/null; then
        echo "bench: startup probe failed on run $i; this uses macOS script syntax, while Linux script uses -c" >&2
        exit 1
    fi
    if [ ! -s "$RESULT" ]; then
        echo "bench: startup probe wrote no result on run $i" >&2
        exit 1
    fi
    startup=$(sed -n 's/^startup_us=\([0-9][0-9]*\) shutdown_us=.*/\1/p' "$RESULT")
    case "$startup" in
        '' | *[!0-9]*)
            echo "bench: unreadable startup probe output: $(cat "$RESULT")" >&2
            exit 1
            ;;
    esac
    printf '%s\n' "$startup" >>"$STARTS"
    i=$((i + 1))
done

startup_us=$(sort -n "$STARTS" | awk '
    { value[NR] = $1 }
    END { printf "%d", (value[6] + value[7]) / 2 }
')
metrics=$("$BENCH" "$LIBRARY" "$INDEX")
frame_us=$(printf '%s\n' "$metrics" | sed -n 's/^frame_us_200x60=//p')
frames=$(printf '%s\n' "$metrics" | sed -n 's/^frames=//p')
scan_rate=$(printf '%s\n' "$metrics" | sed -n 's/^scan_tracks_per_s=//p')
scan_tracks=$(printf '%s\n' "$metrics" | sed -n 's/^scan_tracks=//p')
case "$startup_us$frame_us$frames$scan_rate$scan_tracks" in
    '' | *[!0-9]*)
        echo "bench: unreadable benchmark output: $metrics" >&2
        exit 1
        ;;
esac

basalam=$(sed -n '/path = "github.com\/curedbylethe\/basalam"/{n;s/version = "\(.*\)"/\1/p;}' "$ROOT/salam.lock")
if [ -z "$basalam" ]; then
    echo "bench: cannot read basalam version from salam.lock" >&2
    exit 1
fi
date=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
host=$(hostname)
os=$(uname -s)
arch=$(uname -m)
salam=$(cat "$ROOT/.salam-version")

line=$(printf '{"schema":1,"date":"%s","host":"%s","os":"%s","arch":"%s","salam":"%s","basalam":"%s","startup_us":%s,"frame_us_200x60":%s,"scan_tracks_per_s":%s,"scan_tracks":%s,"frames":%s,"startup_samples":12}' \
    "$date" "$host" "$os" "$arch" "$salam" "$basalam" "$startup_us" "$frame_us" "$scan_rate" "$scan_tracks" "$frames")
printf '%s\n' "$line" >>"$ROOT/bench/results.jsonl"
printf '%s\n' "$line"
