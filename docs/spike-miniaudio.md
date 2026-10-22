# The miniaudio FFI spike: findings

What CUR-502 asked, what this machine measured, and what CUR-503 should take
from it. The evidence lives in `spike/` (throwaway) and in the numbers below,
which were produced by `make spike-measure`. `docs/` holds this file only.

Host for every figure: macOS 27.0.1 on arm64 (Darwin 27.0.1), Apple clang
17.0.0, Salam 0.5.6. Times are wall-clock on an otherwise idle machine.

## Question

Can a Salam program drive miniaudio's playback device directly — with Salam code
as the data callback, filling interleaved f32 frames — using nothing but a thin
C shim, and what does that cost in compile time, binary size and callback
latency? If yes, mizrab's audio backend can be Salam over a vendored library
rather than a C engine behind an FFI wall. If no, CUR-503 needs a different
plan.

## Verdict

Viable. The deciding fact: the callback ran on miniaudio's audio thread and
filled the buffer. `make spike-run` on the default device prints

```
frames=95697 backend=Core Audio
```

after a 2 s sleep — 95,697 sample frames across two interleaved f32 channels,
written by exported Salam code called from Core Audio's thread. `make
spike-check` prints `frames=97440 backend=Null` on the null backend, so the two
paths are told apart by a log line.

The cost is one 365,464-byte object, a 1.70–2.31 s cold compile, a 331,480-byte
binary, and a median fill time of 0.009–0.013 ms against a ~10 ms callback
period. `make spike-run` was heard on macOS; the limit is that the Linux leg has
not run yet.

## What worked

`audio/miniaudio.c` is the single implementation unit:

```c
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
```

The nine defines cut decoders, encoders, generators, the resource manager, the
node graph and the engine. No backend define is set, so the null backend stays
compiled in and the platform backend is picked at run time.

```sh
MINIAUDIO_DEFS="-DMA_NO_DECODING -DMA_NO_ENCODING -DMA_NO_WAV -DMA_NO_FLAC \
  -DMA_NO_MP3 -DMA_NO_GENERATION -DMA_NO_RESOURCE_MANAGER -DMA_NO_NODE_GRAPH \
  -DMA_NO_ENGINE"

mkdir -p build
cc -c -O2 -Iaudio $MINIAUDIO_DEFS -o build/miniaudio.o audio/miniaudio.c
cc -c -O2 -Iaudio $MINIAUDIO_DEFS -o build/ma_shim.o spike/ma_shim.c
cd spike && salam build tone.salam --output=../build/spike --log-level=warn --backend=llvm
```

`make spike-build` runs those commands in that order; the nine defines
live in `MINIAUDIO_DEFS` in the `Makefile`, not in the Salam source. The linker
prints `ld: warning: ignoring duplicate libraries: '-lm'` because the source
links `m` explicitly and Salam adds it anyway; it is harmless.

**Linking is resolved twice, from two directories.** `tone.salam` says

```salam
link static "../build/miniaudio.o"
link static "../build/ma_shim.o"
```

The compiler checks the path relative to the source file (`spike/`), then hands
the string to the linker from its own working directory. Relative `../build/...`
satisfies both only when the build runs from `spike/`, which is why
`spike-build` does `cd spike`.

On Unix the source also links `m`, `dl` and `pthread`.

**The callback is a top-level `export:` function.** Salam lambdas are not C
function pointers, so the callback cannot be a closure. It is a named function
in an `export:` block, and its state is module globals:

```salam
export:
    func mizrab_tone_fill(_dev: void *, out: void *, _inp: void *, frames: u32)
end
```

That shape matches miniaudio's callback type:

```c
typedef void (* ma_device_data_proc)(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount);
```

Pointers cross the boundary as `void *` (`out as f32 *` recovers the buffer),
and `frameCount` as `u32`.

**The shim is six device functions plus a clock.** `spike/ma_shim.h` declares:

- `mizrab_ma_create(fill, sample_rate, channels, null_backend)` — initialises
  context and device, returns `void *` or null.
- `mizrab_ma_start(device)` / `mizrab_ma_stop(device)` — wrap
  `ma_device_start` / `ma_device_stop`, return 0 or the `ma_result`.
- `mizrab_ma_destroy(device)` — `ma_device_uninit` then `ma_context_uninit`;
  joins the audio thread, so main only.
- `mizrab_ma_last_error()` — the last failure as a string, set from
  `ma_result_description(result)`.
- `mizrab_ma_backend_name(device)` — `ma_get_backend_name` of the context that
  actually opened, so a log distinguishes Core Audio from Null from ALSA.
- `mizrab_now_ns()` — monotonic nanoseconds for the measurements, because Salam
  cannot fill a `timespec`.

The shim holds one `ma_context` and one `ma_device` as statics; the spike plays
one stream at a time.

## What needed workarounds

**Salam has no `sizeof`.** It cannot allocate an opaque `ma_context`,
`ma_device` or a `timespec` for `clock_gettime`, and the compiler cannot hand it
the size of a C type. The shim owns the storage and Salam only ever holds
`void *`.

**`ma_device_config` cannot be built in Salam.** `ma_device_config_init` returns
the config by value, and the mirrored struct cannot be turned into the pointer
that `ma_device_init` wants. Measured with Salam 0.5.6, taking the address of
the mirrored value fails at compile time:

```
error[E023]: cannot cast 'MaDeviceConfig' to 'MaDeviceConfig*'
   --> spike/probe_struct.salam:138:45
```

Variants, same compiler and host:

- `p := &c` → `error[E072]: '&c' requires a function, 'c' is not one`
- `c as void *` → `error[E023]: cannot cast 'Cfg' to 'void*'`
- a struct declared before an `extern:` block →
  `error[E083]: 'import' must appear before any other top-level statement, right after the package declaration; 'Cfg' (line 1) already starts the rest of the file`

So `ma_device_config_init` and `ma_device_init` are both called inside the shim,
one after the other, and Salam never sees the struct. `spike/probe_struct.salam`
is the repro; it is not built by `spike-build`.

**The callback needs globals.** With no `pUserData` plumbed through Salam, the
phase, frame count, rate and channel count are module-level `mut` values. The
callback writes them and main reads them while the device runs. That race is
deliberate and harmless for a counter; CUR-503 needs a real hand-off.

## Measured

`make spike-measure` runs `spike/measure.sh`, which does M1–M3 with the shell and
M4–M8 in `build/spike-measure`. Four full runs were recorded; the ranges below
are across all of them. The raw transcripts were scratch files outside the
repository, so this section is the record.

| Item | What | Command | Figure |
| ---- | ---- | ------- | ------ |
| M1 | cold compile of `audio/miniaudio.c` | `/usr/bin/time -p make build/miniaudio.o` after `make clean`, 3× | 1.70–2.31 s real |
| M2 | object sizes | `ls -l`, `size -m` | miniaudio 365,464 B, shim 3,008 B |
| M3 | linked binary | `make clean && make spike-build` | 331,480 B; `strip -x` 309,056 B |
| M4 | cadence | `./build/spike-measure --measure` | median 9.990–9.996 ms, n≈215 |
| M5 | fill time | `./build/spike-measure --measure` | median 0.009–0.013 ms, n≈215 |
| M6 | `mem.Allocate(1024)` per callback | `./build/spike-measure --alloc-in-callback` | non-null on every callback; median unchanged |
| M7 | `println` in the callback | 10 s timeout on `./build/spike-measure --print-in-callback` | 3 lines / 216 callbacks, no deadlock |
| M8 | ordinary Salam function from the callback | `./build/spike-measure --measure` | counter == callbacks, every run |
| M9 | lifecycle call in the callback | not run | not tested; citation only |

### Compile time

Four runs of three cold compiles each: 1.80/1.75/1.76 s, 1.81/1.79/1.70 s,
1.81/1.73/1.87 s and 2.31/1.74/1.72 s. The `2.31` is the outlier; the rest sit
between 1.70 and 1.87 s. This is a one-off cost per clean tree: the object is
then cached by `make` and the shim's compile is small.

### Binary size

`build/miniaudio.o` is 365,464 B on disk; `size -m` reports a total of 238,132,
of which `__text` is 189,284. `build/ma_shim.o` is 3,008 B, `size -m` total
5,456. The linked `build/spike` is 331,480 B, and 309,056 B after `strip -x` —
a 22,424-byte saving, not worth a build rule.

### Callback entry latency

Core Audio at 48 kHz/2 ch, 215–218 callbacks over 2 s. Entry delta: median
9.990–9.996 ms, mean 9.16 ms, min 0.016–0.026 ms, max 10.09–10.27 ms, n≈215.
Time from `mizrab_ma_start` to the first callback entry: 43.1, 68.9, 85.4 and
95.8 ms across the four runs. No delta exceeded 10.27 ms, so no callback arrived
more than about 0.28 ms after the nominal period; the small minimum is the
initial chunk `ma_device_start` fetches before it returns.

### Callback execution time

The tone fill — one `math.Sin`, two channel writes and a phase update per frame —
takes a median of 0.009–0.013 ms, mean 0.011–0.013 ms, max 0.020–0.038 ms over
~215 callbacks. That is about 0.1% of the 10 ms period.

### Allocation

`mem.Allocate(1024)` followed by `mem.Free` inside every callback returned
non-null on every callback: 215/215, 217/217, 215/215 and 215/215 across the four
runs, and freed cleanly. Median execution was unchanged at 0.009–0.011 ms
(1.00x the baseline pass on three runs, 0.85x on the fourth, i.e. noise), and
max execution was 0.020–0.036 ms against the ~10 ms period. On that budget there
was no dropout. The allocation mode itself was not listened to; the plain tone
was, separately, and was audible.

All four runs agreed on the outcome: allocation always succeeded and the median
did not move. The ratio between the baseline and allocation medians ranged from
0.85x to 1.00x, and the callback count per pass varied from 215 to 217, because
each pass is a fixed wall-clock span rather than a fixed frame count.

## Callback rules

The rules CUR-503 inherits, each with where it comes from:

| Allowed in the callback | Evidence |
| ----------------------- | -------- |
| Fill the output buffer, read and write module globals | M4/M5: 215+ callbacks per run, buffer filled every time |
| Call ordinary (non-exported) Salam functions | M8: counter == callbacks in every run |
| Compute, branch, loop, do float math | M5: full sine fill inside the period |

| Not allowed in the callback | Evidence |
| --------------------------- | -------- |
| `ma_device_init`, `ma_device_uninit`, `ma_device_start`, `ma_device_stop` | manual: "You cannot stop and start the device from inside the callback or else you'll get a deadlock" (`audio/miniaudio.h`); M9 not run |
| Holding a lock main may take | design rule; M6 shows allocation did not break the budget once, not that the allocator is lock-free |
| Assuming a fixed `frameCount` | manual: the period size is a hint, "You must not assume this will always be the same value" |
| `println` per callback | M7: 3 lines from 216 callbacks did not deadlock (max 0.023–0.050 ms), but stdout is shared and blocking; a log line per callback is not real-time safe |

Two facts that shape the lifecycle:

- `ma_device_start` retrieves an initial chunk of audio before it returns, so a
  callback can run on the audio thread before the caller regains control. State
  the callback reads must be ready before `start`, not after it.
- The device must be stopped from the main thread. `mizrab_ma_stop` and
  `mizrab_ma_destroy` exist for that, and M7's heartbeat lines show main stays
  responsive while the audio thread prints.

## Null backend for CI

Selecting only the null backend goes through the context, not the device:

```c
static const ma_backend null_only[] = { ma_backend_null };
result = ma_context_init(null_only, 1, NULL, &g_context);
```

Passing `NULL, 0` instead means "try every compiled backend in miniaudio's
default order". On Linux that order tries PulseAudio before ALSA, so without a
PulseAudio server it falls through to ALSA — which is why the CI step must
provide an ALSA default PCM rather than rely on miniaudio's null backend.

The CI steps, as written:

- **Linux:** write `~/.asoundrc` mapping `pcm.!default` and `ctl.!default` to the
  ALSA `null` plugin, then run `make spike-check-device`. The caller opens a real
  ALSA PCM, so the callback runs under the ALSA backend, not miniaudio's timer.
  No `--null` fallback: a missing `libasound` must fail the step.
- **macOS:** `make spike-check`, which passes `--null` and runs on miniaudio's
  null backend.

The log line is the check: `backend=Null` versus `backend=Core Audio` (or
`backend=ALSA` on Linux). The Linux step has not run yet; it is written, not
observed. Until it does, no Linux claim in this document is backed by a run.

**Pacing caveat.** The null backend advances on a timer, not on a device clock,
so M4 (entry delta), M5 (execution time), M6 (allocation under a real period) and
M7 (printing from a real audio thread) are meaningless on it. The build figures
(M2, M3) and the "did the callback run" checks (M8, frame counts) still hold.
Never quote M4–M7 from a `--null` run.

## Recommendation for CUR-503

Take `spike/ma_shim.h` and `spike/ma_shim.c` essentially as they are, and take
`spike/tone.salam` as the shape of the callback and the start/stop/destroy
sequence. Throw away `spike/measure.salam`, `spike/measure.sh` and
`spike/probe_struct.salam`: they are measurement scaffolding, not an engine.

- Keep the shim C-side surface small: create, start, stop, destroy, last error,
  backend name. Every new field added to it is a place Salam cannot see.
- Put the ring buffer and the playback state machine in Salam. The spike proves
  an ordinary Salam function runs on the audio thread (M8), so decoders and state
  belong there, not in C.
- The callback must not allocate. M6 shows one 1 KB allocation fit the budget;
  it does not show that a shared allocator will not block when the main thread is
  also allocating.
- Prefer `mem.Allocate` for buffers in `main` before `start`, and pass them to
  the callback as globals.
- Keep `spike/` until CUR-503 supersedes it, then delete it. It costs nothing to
  keep and it is the only runnable proof of the FFI path.

## What was not verified

- **Linux audible output.** Not verified. The Linux CI step opens the ALSA null
  plugin, which produces no sound by construction, and it has not run yet. No
  Linux host was available for this spike.
- **Linux at all.** Only macOS was run. The Linux leg of CI is written, not
  observed.
- **Windows.** Neither WASAPI nor any Windows build was attempted; the shim's
  `#include <time.h>` and `clock_gettime` are POSIX-only.
- **Non-Core Audio backends.** ALSA, PulseAudio, JACK and sndio are compiled in
  via `MINIAUDIO_DEFS` but not exercised. The shim calls only backend-agnostic
  miniaudio entry points, so the risk is in the untested backends, not the shim.
- **Device hotplug.** Nothing listens for `ma_device_notification_proc`; a
  device change while playing is unhandled and untested.
- **M7's effect on a real audio thread under load.** Three prints in 2 s says
  `println` does not deadlock here; it does not say stdout is real-time safe.
- **M9.** Lifecycle calls inside the callback were not attempted. The deadlock is
  miniaudio's documented behaviour, quoted from `audio/miniaudio.h`, not measured
  by this spike.

## Upstream findings

Four defects are recorded here, each in the four fields `CONTRIBUTING.md` asks
for. Each is for CUR-510 to copy into `FINDINGS.md` and file; nothing has been
filed yet.

**1. Salam version.** `salam 0.5.6`.

**2. OS and terminal.** macOS 27.0.1, arm64 (Darwin 27.0.1), Apple clang 17.0.0.
The terminal was not recorded.

**3. Minimal reproductions.** All three are built with `--backend=llvm` and a
plain `salam build <file>`, outside the repository.

- The real case: `spike/probe_struct.salam`, which mirrors `ma_device_config`
  and passes it by pointer. The reduction below shows the same failure without
  the mirror. Declaration order matters: the `extern:` block comes first, or
  `E083` fires as well.

  ```salam
  extern:
      func f(c: Cfg *): int
  end

  struct Cfg:
      pub a: int
  end

  func main:
      c := Cfg{a = 7}
      ret f(c as Cfg *)
  end
  ```

- A struct declared before an `extern:` block:

  ```salam
  struct Cfg:
      pub a: int
  end

  extern:
      func f(c: Cfg *): int
  end
  ```

- A small struct passed by value to an `extern`, and the C helper it calls:

  ```c
  typedef struct { int a; int b; } Two;

  void take_two(Two t) { printf("a=%d b=%d\n", t.a, t.b); }
  ```

  ```salam
  link static "two.o"

  extern:
      func take_two(t: Two)
  end

  struct Two:
      pub a: int
      pub b: int
  end

  func main:
      take_two(Two{a = 7, b = 9})
      ret 0
  end
  ```

**4. Expected vs actual.** Expected: the address of a mirrored struct can be
passed as its pointer, a struct can be declared before an `extern:` block, and a
small struct survives a by-value call. Actual, with exit codes:

- `c as Cfg *` → `error[E023]: cannot cast 'Cfg' to 'Cfg*'`, exit 1. With the
  real struct, as quoted above:
  `error[E023]: cannot cast 'MaDeviceConfig' to 'MaDeviceConfig*'`.
- `c as void *` → `error[E023]: cannot cast 'Cfg' to 'void*'`, exit 1.
- `p := &c` → `error[E072]: '&c' requires a function, 'c' is not one`, exit 1;
  the compiler also reports `E059` for `c` being unused, because the `&c` does
  not count as a use.
- struct before `extern:` →
  `error[E083]: 'import' must appear before any other top-level statement, right after the package declaration; 'Cfg' (line 1) already starts the rest of the file`,
  exit 1, with the help line `'salam format' moves top-level declarations into
  the required order for you`.
- by-value small struct: the helper printed `a=7 b=0` and the program exited 0,
  so the second field was silently lost. The `b` value of 9 never reached C.
- by-value `MaDeviceConfig`: the process segfaulted, exit 139.

Workaround used here: the shim constructs and passes `ma_device_config` in C, so
Salam only exchanges opaque pointers and scalars. That is why
`ma_device_config_init` never appears in Salam source.
