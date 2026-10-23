#!/bin/sh
# mizrab soak: one hour of audio frames through the engine, on a virtual clock.
#
# Not a device test and not a wall-clock result. tests/soak.salam arms the
# engine on the null backend without starting its callback and pulls the ring
# empty with FillFrames (the body of the real callback) as fast as the decoder
# thread can fill it. The hour is 3600 * 48000 output frames; the source is an
# 8 kHz mono 8-bit WAV of 28 800 000 samples that the decoder upsamples 6x.
# Checked: frames_played equals the budget exactly, no decode errors, the ring
# ends empty, and the process RSS stays under a bound (sampled once a second).
#
# Opt-in: `make soak`. Not part of `make test`, not a CI step.
# Usage: tests/soak.sh          Env: SALAM=path/to/salam
# Exit non-zero if the file is wrong, the program fails or RSS exceeds the bound.

set -eu

SALAM="${SALAM:-salam}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR="$ROOT/build/soak"
WAV="$DIR/soak-60min-8k-mono-u8.wav"
BIN="$DIR/soak-bin"
OUT="$DIR/soak.out"

DURATION_S=3600
SRC_RATE=8000
PAYLOAD=$((DURATION_S * SRC_RATE))
WAV_SIZE=$((PAYLOAD + 44))
BUDGET=$((DURATION_S * 48000))

# RSS bound: 2 x the steady-state RSS of the first measured run (steady = median
# of the second half of the 1 Hz series). Measured on macOS 27.0.1 arm64,
# Salam 0.5.6: steady 1568 KB, so 3136 KB. (The first run's series started at
# 2208 KB and settled to 1568 KB; max 2208 KB is also inside the bound.)
BOUND_KB=3136

die() {
    echo "soak: FAIL $*" >&2
    exit 1
}

for obj in miniaudio ma_shim; do
    [ -f "$ROOT/build/$obj.o" ] || die "$ROOT/build/$obj.o is missing; run 'make build' first"
done
command -v perl >/dev/null 2>&1 || die "perl is required to generate the payload"

# Salam links with the host toolchain on macOS; pin the deployment target to
# the running OS so the linker does not warn about mismatched versions.
if [ "$(uname -s)" = "Darwin" ] && [ -z "${MACOSX_DEPLOYMENT_TARGET:-}" ]; then
    MACOSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion)
    export MACOSX_DEPLOYMENT_TARGET
fi

mkdir -p "$DIR"
rm -f "$WAV" "$BIN" "$OUT"

# le32 N: N as four little-endian bytes, as printf escapes.
le32() {
    printf '\\%03o\\%03o\\%03o\\%03o' $(($1 & 255)) $((($1 >> 8) & 255)) $((($1 >> 16) & 255)) $((($1 >> 24) & 255))
}

# 44-byte header: RIFF, WAVE, fmt (PCM, 1 ch, 8000 Hz, 8000 B/s, align 1, 8 bit), data.
{
    printf 'RIFF'
    # shellcheck disable=SC2059
    printf "$(le32 $((PAYLOAD + 36)))"
    printf 'WAVEfmt '
    # shellcheck disable=SC2059
    printf "$(le32 16)\\001\\000\\001\\000$(le32 $SRC_RATE)$(le32 $SRC_RATE)\\001\\000\\010\\000"
    printf 'data'
    # shellcheck disable=SC2059
    printf "$(le32 $PAYLOAD)"
    # 64-byte sine period around 0x80 (amplitude 8), repeated to the payload size.
    perl -e 'print pack("C*", map { 128 + int(8 * sin($_ * 2 * 3.14159265358979 / 64)) } 0 .. 63) x ('"$PAYLOAD"' / 64)'
} > "$WAV"

size=$(wc -c < "$WAV" | tr -d ' ')
[ "$size" -eq "$WAV_SIZE" ] || die "generated WAV is $size bytes, want $WAV_SIZE (truncated)"
if command -v shasum >/dev/null 2>&1; then
    sum=$(shasum -a 256 "$WAV" | cut -d ' ' -f 1)
else
    sum=$(sha256sum "$WAV" | cut -d ' ' -f 1)
fi
echo "wav: $WAV"
echo "wav_size_bytes=$size sha256=$sum"
# audio-engine.mdx quotes this hash as the source identity of the recorded runs.
[ "$sum" = 61d97cd8754359385b24dafa4a07452567af4bd04028a2e57c07e61542c3f17c ] || die "generated WAV sha256 $sum differs from the recorded source hash"
echo "budget_frames=$BUDGET (${DURATION_S} s x 48000 Hz; source ${SRC_RATE} Hz mono 8-bit, ${PAYLOAD} samples)"

# Build from tests/ so the `link` paths in soak.salam resolve for both the
# compiler check and the linker (see tests/run.sh).
(cd "$ROOT/tests" && "$SALAM" build soak.salam --output="$BIN" --backend=llvm --log-level=warn) || die "build"

start=$(date +%s)
"$BIN" "$WAV" "$BUDGET" > "$OUT" 2>&1 &
pid=$!
samples=""
while kill -0 "$pid" 2>/dev/null; do
    rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ') || rss=""
    [ -n "$rss" ] && samples="$samples $rss"
    sleep 1
done
code=0
wait "$pid" || code=$?
end=$(date +%s)

echo "-- program output"
cat "$OUT"
echo "-- rss series"
[ -n "$samples" ] || die "no RSS sample was taken"
sorted=$(for s in $samples; do echo "$s"; done | sort -n)
n=$(echo "$sorted" | wc -l | tr -d ' ')
# baseline = the second sample: the first is taken before the fork has exec'd
# the program and shows the shell's image, not the engine.
baseline=$(for s in $samples; do echo "$s"; done | sed -n '2p')
max=$(echo "$sorted" | tail -n 1)
[ -n "$baseline" ] || baseline=$max
# steady = median of the second half of the series in time order.
half=$((n / 2))
steady=$(for s in $samples; do echo "$s"; done | tail -n $((n - half)) | sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }')
echo "rss_series_kb=${samples# }"
echo "rss_samples=$n"
echo "rss_kb baseline=$baseline steady=$steady max=$max bound=$BOUND_KB"
echo "wall_time_s=$((end - start))"

[ "$code" -eq 0 ] || die "soak program exited $code"
grep -q '^soak: PASS$' "$OUT" || die "soak program did not print PASS"
[ "$max" -le "$BOUND_KB" ] || die "RSS max $max KB exceeds bound $BOUND_KB KB"
echo "soak: PASS (frames exact, rss within bound)"
