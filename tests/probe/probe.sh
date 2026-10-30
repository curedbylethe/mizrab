#!/bin/sh
# mizrab probe: what Salam actually does on the exit, signal, spawn and
# exclusive-create paths. Run by hand; not a test, not part of `make test`, not
# run by CI, and tests/run.sh never discovers it (tests/*_test.salam only).
#
# It builds the four probe programs under tests/probe/ into build/tests/probe/,
# runs each exit path and signals the ones that wait, and prints one fixed-width
# table with the ten observations STAGE-00 asks for. A build or link failure is
# a result too: the rows for that program say "build failed" and the compiler
# log is left next to the binary.
#
# Usage: sh tests/probe/probe.sh        Env: SALAM=path/to/salam
#
# The startup wait before a signal is a fixed 0.5 s; it is process-start
# settling, not a tolerance on an observation. No case is retried: a case that
# goes wrong is printed as it happened.

set -eu

SALAM="${SALAM:-salam}"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BIN="$ROOT/build/tests/probe"

# Salam links with the host toolchain on macOS; pin the deployment target to
# the running OS so the linker does not warn about mismatched versions.
if [ "$(uname -s)" = "Darwin" ] && [ -z "${MACOSX_DEPLOYMENT_TARGET:-}" ]; then
    MACOSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion)
    export MACOSX_DEPLOYMENT_TARGET
fi

mkdir -p "$BIN"

# Build and run from tests/: the link paths and fixture paths resolve from
# there, as tests/gap.sh and tests/run.sh do.
cd "$ROOT/tests"

for name in probe_exit probe_spawn probe_lock probe_signal; do
    rm -f "$BIN/$name"
    if ! "$SALAM" build "probe/$name.salam" --output="$BIN/$name" --backend=llvm --log-level=warn 2>"$BIN/$name.build.log"; then
        echo "probe: build failed: $name" >&2
        tail -n 1 "$BIN/$name.build.log" | sed 's/^/probe:   /' >&2
    fi
done

# run_capture OUT ERR CMD... -> exit status on stdout
run_capture() {
    out=$1
    err=$2
    shift 2
    status=0
    "$@" >"$out" 2>"$err" || status=$?
    printf '%s\n' "$status"
}

# ran FILE MARKER -> yes when MARKER is a whole line of FILE
ran() {
    if [ -f "$1" ] && grep -qx "$2" "$1"; then
        printf 'yes'
    else
        printf 'no'
    fi
}

# line_of FILE MARKER -> first line number of MARKER, empty when absent
line_of() {
    grep -nx "$2" "$1" 2>/dev/null | head -n 1 | cut -d: -f1
}

# Rows 1-3: a normal return from main. Markers from the function-level defer,
# the defer in a nested block and the atexit handler all land in one capture.
normal_status="build failed"
defer_ret="n/a"
defer_block="n/a"
atexit_normal="n/a"
if [ -x "$BIN/probe_exit" ]; then
    normal_status=$(run_capture "$BIN/normal.out" "$BIN/normal.err" "$BIN/probe_exit" normal)
    defer_ret=$(ran "$BIN/normal.out" defer_outer)
    atexit_normal=$(ran "$BIN/normal.out" atexit_ran)
    defer_block=no
    inner=$(line_of "$BIN/normal.out" defer_inner)
    after=$(line_of "$BIN/normal.out" after_inner)
    if [ -n "$inner" ] && [ -n "$after" ] && [ "$inner" -lt "$after" ]; then
        defer_block="yes (inner<after)"
    fi
fi

# Row 4: core.Panic with no SIGABRT handler installed.
panic_status="build failed"
panic_defer="n/a"
panic_atexit="n/a"
if [ -x "$BIN/probe_exit" ]; then
    panic_status=$(run_capture "$BIN/panic.out" "$BIN/panic.err" "$BIN/probe_exit" panic)
    panic_defer=$(ran "$BIN/panic.out" defer_outer)
    panic_atexit=$(ran "$BIN/panic.out" atexit_ran)
fi

# Row 5: the same panic with a Salam SIGABRT handler installed first. The
# handler writes its marker and returns; abort() re-raises, so the status says
# whether the handler was reached and the status says what that cost.
abort_status="build failed"
abort_defer="n/a"
abort_atexit="n/a"
abort_handler="n/a"
if [ -x "$BIN/probe_exit" ]; then
    abort_status=$(run_capture "$BIN/abort.out" "$BIN/abort.err" "$BIN/probe_exit" panic sigabrt)
    abort_defer=$(ran "$BIN/abort.out" defer_outer)
    abort_atexit=$(ran "$BIN/abort.out" atexit_ran)
    abort_handler=$(ran "$BIN/abort.out" abort_handler_ran)
fi

# signal_term TAG BIN: start it, wait 0.5 s, send SIGTERM, record the status and
# the markers. Echoes "STATUS DEFER ATEXIT" as one line.
signal_term() {
    tag=$1
    bin=$2
    out="$BIN/$tag.out"
    err="$BIN/$tag.err"
    : >"$out"
    : >"$err"
    "$bin" sigterm >"$out" 2>"$err" &
    p=$!
    ( sleep 10; kill -9 "$p" 2>/dev/null ) >/dev/null 2>&1 &
    w=$!
    sleep 0.5
    kill -TERM "$p" 2>/dev/null || true
    status=0
    wait "$p" || status=$?
    kill "$w" 2>/dev/null || true
    wait "$w" 2>/dev/null || true
    printf '%s %s %s\n' "$status" "$(ran "$out" defer_outer)" "$(ran "$out" atexit_ran)"
}

# Row 6: one thread, so the backend installed its SIGTERM handler.
sigterm_status="build failed"
sigterm_defer="n/a"
sigterm_atexit="n/a"
sigterm_handler="n/a"
if [ -x "$BIN/probe_exit" ]; then
    set -- $(signal_term sigterm "$BIN/probe_exit")
    sigterm_status=$1
    sigterm_defer=$2
    sigterm_atexit=$3
    if [ "$sigterm_atexit" = "yes" ]; then
        sigterm_handler="yes (atexit ran)"
    else
        sigterm_handler="no"
    fi
fi

# Row 7: the same binary family, but main spawned a thread, so the backend
# installed nothing. Both paths report 143 to the shell; the atexit marker is
# what separates exit(143) from killed-by-SIGTERM.
spawn_status="build failed"
spawn_defer="n/a"
spawn_atexit="n/a"
spawn_handler="n/a"
if [ -x "$BIN/probe_spawn" ]; then
    set -- $(signal_term spawn "$BIN/probe_spawn")
    spawn_status=$1
    spawn_defer=$2
    spawn_atexit=$3
    if [ "$spawn_atexit" = "yes" ]; then
        spawn_handler="yes (atexit ran)"
    else
        spawn_handler="no"
    fi
fi

# Row 8: a Salam SIGUSR1 handler that writes one literal and _exit(0)s.
usr1_status="build failed"
usr1_handler="n/a"
if [ -x "$BIN/probe_signal" ]; then
    : >"$BIN/usr1.out"
    : >"$BIN/usr1.err"
    "$BIN/probe_signal" >"$BIN/usr1.out" 2>"$BIN/usr1.err" &
    p=$!
    ( sleep 10; kill -9 "$p" 2>/dev/null ) >/dev/null 2>&1 &
    w=$!
    sleep 0.5
    kill -USR1 "$p" 2>/dev/null || true
    usr1_status=0
    wait "$p" || usr1_status=$?
    kill "$w" 2>/dev/null || true
    wait "$w" 2>/dev/null || true
    usr1_handler=$(ran "$BIN/usr1.out" usr1_handler_ran)
fi

# Row 9: two exclusive creates on the same path.
lock_status="build failed"
lock_first="n/a"
lock_second="n/a"
if [ -x "$BIN/probe_lock" ]; then
    lock_status=$(run_capture "$BIN/lock.out" "$BIN/lock.err" "$BIN/probe_lock" "$BIN/probe.lock")
    if grep -qx "first=ok" "$BIN/lock.out" 2>/dev/null; then
        lock_first="first=ok"
    elif grep -qx "first=null" "$BIN/lock.out" 2>/dev/null; then
        lock_first="first=null"
    else
        lock_first="not reached"
    fi
    if grep -qx "second=null" "$BIN/lock.out" 2>/dev/null; then
        lock_second="second=null"
    elif grep -qx "second=ok" "$BIN/lock.out" 2>/dev/null; then
        lock_second="second=ok"
    else
        lock_second="second=not reached"
    fi
fi

# Row 10: the same SIGUSR1 handler, installed before NewScreen(...).start().
# start() needs a tty, and the capture needs a file, so the probe runs on the
# throwaway pty `script` creates; the probe's own pid comes from its ready line
# because `$!` is script's pid. Nothing is left started: the pty dies with the
# process, and a handler miss closes the screen before exiting.
screen_status="build failed"
screen_handler="n/a"
screen_method="not run"
if [ -x "$BIN/probe_signal" ] && command -v script >/dev/null 2>&1; then
    : >"$BIN/screen.out"
    : >"$BIN/screen.err"
    script -q /dev/null "$BIN/probe_signal" screen >"$BIN/screen.out" 2>"$BIN/screen.err" &
    sp=$!
    ( sleep 10; kill -9 "$sp" 2>/dev/null ) >/dev/null 2>&1 &
    w=$!
    pid=""
    i=0
    while [ "$i" -lt 250 ]; do
        pid=$(grep -ao 'ready pid=[0-9]*' "$BIN/screen.out" 2>/dev/null | tail -n 1 | cut -d= -f2)
        if [ -n "$pid" ]; then
            break
        fi
        sleep 0.02
        i=$((i + 1))
    done
    if [ -n "$pid" ]; then
        kill -USR1 "$pid" 2>/dev/null || true
    fi
    screen_status=0
    wait "$sp" || screen_status=$?
    kill "$w" 2>/dev/null || true
    wait "$w" 2>/dev/null || true
    if [ -n "$pid" ]; then
        kill -9 "$pid" 2>/dev/null || true
    fi
    screen_handler=$(ran "$BIN/screen.out" usr1_handler_ran)
    screen_method="script -q /dev/null (throwaway pty)"
fi

printf '%-18s | %-34s | %-11s | %-19s | %-10s | %-15s\n' \
    "case" "mechanism" "exit status" "defer ran" "atexit ran" "handler ran"
printf '%s\n' \
    "-------------------+------------------------------------+-------------+---------------------+------------+-----------------"
printf '%-18s | %-34s | %-11s | %-19s | %-10s | %-15s\n' \
    "exit:normal" "defer at ret" "$normal_status" "$defer_ret" "$atexit_normal" "-"
printf '%-18s | %-34s | %-11s | %-19s | %-10s | %-15s\n' \
    "exit:nested" "defer in block" "$normal_status" "$defer_block" "$atexit_normal" "-"
printf '%-18s | %-34s | %-11s | %-19s | %-10s | %-15s\n' \
    "exit:atexit" "atexit on exit(0)" "$normal_status" "$defer_ret" "$atexit_normal" "-"
printf '%-18s | %-34s | %-11s | %-19s | %-10s | %-15s\n' \
    "exit:panic" "core.Panic" "$panic_status" "$panic_defer" "$panic_atexit" "no"
printf '%-18s | %-34s | %-11s | %-19s | %-10s | %-15s\n' \
    "exit:panic-abort" "SIGABRT handler" "$abort_status" "$abort_defer" "$abort_atexit" "$abort_handler"
printf '%-18s | %-34s | %-11s | %-19s | %-10s | %-15s\n' \
    "exit:sigterm" "SIGTERM, 1 thread" "$sigterm_status" "$sigterm_defer" "$sigterm_atexit" "$sigterm_handler"
printf '%-18s | %-34s | %-11s | %-19s | %-10s | %-15s\n' \
    "spawn:sigterm" "SIGTERM, spawned" "$spawn_status" "$spawn_defer" "$spawn_atexit" "$spawn_handler"
printf '%-18s | %-34s | %-11s | %-19s | %-10s | %-15s\n' \
    "signal:usr1" "SIGUSR1 handler" "$usr1_status" "-" "-" "$usr1_handler"
printf '%-18s | %-34s | %-11s | %-19s | %-10s | %-15s\n' \
    "lock:wx" "os.Open \"wx\" $lock_first $lock_second" "$lock_status" "-" "-" "-"
printf '%-18s | %-34s | %-11s | %-19s | %-10s | %-15s\n' \
    "signal:screen" "SIGUSR1 after start()" "$screen_status" "-" "-" "$screen_handler"

printf '\nrow10 method: %s\n' "$screen_method"
printf 'host: macOS %s, term %s\n' "$(sw_vers -productVersion 2>/dev/null || uname -sr)" "${TERM:-unset}"
"$SALAM" version | sed 's/^/  /'

exit 0
