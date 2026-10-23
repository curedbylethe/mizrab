# Test fixtures

Four 440 Hz sine tones (amplitude 0.5 full scale), one per decoder format, each at a different rate or channel count so the decoder's conversion to f32 / 2 ch / 48000 is exercised. All are generated, not third-party: no external licence applies; the repository's own licence covers them.

| File | Format | Rate | Channels | Bit depth | Duration | Size (bytes) | sha256 |
|------|--------|------|----------|-----------|----------|--------------|--------|
| `tone.wav` | PCM WAV | 8000 Hz | 1 | 16 | 1.500 s (12000 frames) | 24044 | `d43ed9b3106fc53e387fcd94971336d48d178e3e7d85411b4187cec980725fb3` |
| `tone.flac` | FLAC | 44100 Hz | 2 | 16 | 1.500 s (66150 frames) | 25237 | `77bd11f10cb898e581af4525549df553d1f00e49061e61c17d868d8e716427cf` |
| `tone.mp3` | MPEG-1 Layer III, 64 kbps CBR, joint stereo | 44100 Hz | 2 | n/a (lossy) | ~1.38 s decoded (61056 frames) | 11075 | `217af7b3e19c4a65d192f838803fec7ff1367e6a6bac69e21b368251ab99870c` |
| `tone.ogg` | Ogg Vorbis, ~48 kbps | 22050 Hz | 1 | n/a (lossy) | ~1.42 s decoded (31232 frames) | 5422 | `651a5d25e0d18c8a65788c9545e745e9c2b80b52d41bdd895a58d1d37083fedc` |

The lossy files decode a little shorter than 1.5 s (encoder trimming); tests must not assert exact frame counts for MP3 or OGG. Vorbis has no known length in miniaudio, so `LengthKnown` is false for `tone.ogg`. After conversion to 48 kHz every file yields well over 4800 frames, and the WAV yields 72000, so seeking to frame 24000 is valid.

## Provenance

Generated once on macOS (Darwin, 2026-10-23) with only stock tools: Python 3 stdlib and `afconvert` (FLAC). No local `ffmpeg`, `lame`, `flac`, `oggenc` or `sox` exists, and `afconvert` cannot encode MP3 or Vorbis, so VLC 3.0.20's bundled libmp3lame / libvorbis encoders produced those two. The sha256 values above are authoritative: encoder output is not guaranteed byte-identical across runs or VLC versions, so do not regenerate casually.

Source PCM, from `gen.py` (Python stdlib only):

```python
import wave, struct, math, sys
out, rate, ch, secs = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4])
n = int(rate*secs)
w = wave.open(out, 'wb'); w.setnchannels(ch); w.setsampwidth(2); w.setframerate(rate)
w.writeframes(b''.join(struct.pack('<h', int(0.5*32767*math.sin(2*math.pi*440*i/rate)))*ch for i in range(n)))
w.close()
```

Commands:

```sh
python3 -I gen.py tone.wav   8000  1 1.5          # tone.wav is the generator output as-is
python3 -I gen.py src44s.wav 44100 2 1.5
python3 -I gen.py src22m.wav 22050 1 1.5
afconvert -f flac -d flac src44s.wav tone.flac
V=/Applications/VLC.app/Contents/MacOS/VLC
$V -I dummy --no-video src44s.wav --sout '#transcode{acodec=mp3,ab=64,channels=2,samplerate=44100}:std{access=file,mux=raw,dst=tone.mp3}' vlc://quit
$V -I dummy --no-video src22m.wav --sout '#transcode{acodec=vorb,ab=48,channels=1,samplerate=22050}:std{access=file,mux=ogg,dst=tone.ogg}' vlc://quit
```

## Verification

`file` on each output reports the properties in the table. Each of FLAC, MP3 and OGG was also decoded independently with `afconvert -f AIFF -d BEI16` and checked in Python: the decoded rate and channel count match, and a correlation at 440 Hz gives ~16384 (0.5 full scale) against 0 at 1000 Hz, so each file carries a clean 440 Hz tone.
