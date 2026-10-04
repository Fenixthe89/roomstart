#!/usr/bin/env bash
# Contract tests use mocks; Linux additionally exercises real util-linux
# locking, PTY logging and signal cleanup. No GUI or network is required.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
ORIGINAL_PATH=$PATH
TEMP_BASE=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
TEST_TMP=$(mktemp -d "$TEMP_BASE/roomstart-runtime-test.XXXXXXXX")
cleanup() {
    local resolved
    resolved=$(realpath -- "$TEST_TMP") || return
    [[ $resolved == "$TEMP_BASE"/roomstart-runtime-test.* ]] && rm -rf -- "$resolved"
}
trap cleanup EXIT
mkdir -p "$TEST_TMP/bin"
ROOM="$TEST_TMP/A room; literal"
SESSION="$ROOM/.roomstart/sessions/test-session"
mkdir -p "$SESSION"
printf 'Original notes\n' > "$ROOM/notes.md"
export MOCK_ARGS="$TEST_TMP/args" MOCK_FLOCK_RESULT=0 MOCK_EXIT=0
export ROOMSTART_ROOM='A room; literal' ROOMSTART_TARGET=10.10.10.20
export ROOMSTART_LISTENER_PORT=4444
cat > "$TEST_TMP/bin/flock" <<'MOCK'
#!/usr/bin/env bash
exit "${MOCK_FLOCK_RESULT:-0}"
MOCK
cat > "$TEST_TMP/bin/setsid" <<'MOCK'
#!/usr/bin/env bash
[[ $1 == --wait ]] && shift
exec "$@"
MOCK
cat > "$TEST_TMP/bin/script" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MOCK_ARGS"
[[ $SHELL == /bin/bash ]] || exit 91
log='' command=''
while [[ $# -gt 0 ]]; do
    case "$1" in
        --log-out) log=$2; shift 2 ;;
        --command) command=$2; shift 2 ;;
        --quiet|--flush|--return|--append) shift ;;
        *) exit 92 ;;
    esac
done
[[ -n $log && -n $command ]] || exit 93
bash -c "$command" >> "$log"
MOCK
cat > "$TEST_TMP/bin/fake shell's" <<'MOCK'
#!/usr/bin/env bash
[[ ${1:-} == -i ]] || exit 94
[[ $SHELL == "$0" ]] || exit 99
if { : >&9; } 2>/dev/null; then exit 95; fi
if { : >&8; } 2>/dev/null; then exit 96; fi
printf 'room=%s target=%s cwd=%s\n' "$ROOMSTART_ROOM" "$ROOMSTART_TARGET" "$PWD"
if [[ -n ${MOCK_RESIZE_READY:-} ]]; then
    printf 'ready\n' > "$MOCK_RESIZE_READY"
    sleep 2
fi
exit "${MOCK_EXIT:-0}"
MOCK
cat > "$TEST_TMP/bin/nc" <<'MOCK'
#!/usr/bin/env bash
[[ $# == 2 && $1 == -lvnp && $2 == 4444 ]] || exit 97
printf 'listener output\n'
exit "${MOCK_EXIT:-0}"
MOCK
cat > "$TEST_TMP/bin/nano" <<'MOCK'
#!/usr/bin/env bash
[[ $# == 1 && $1 == notes.md ]] || exit 98
printf 'Saved edit\n' >> "$1"
MOCK
chmod +x "$TEST_TMP/bin/"*
export PATH="$TEST_TMP/bin:$PATH"
# shellcheck source=../lib/runtime.sh
source "$ROOT/lib/runtime.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect_code() {
    local expected=$1 actual=0; shift
    "$@" || actual=$?
    [[ $actual == "$expected" ]] || fail "expected $expected, got $actual: $*"
}

rs_runtime_init "$ROOM"
expect_code 1 rs_role_active "$ROOM" main
touch "$ROOM/.roomstart/runtime/main.lock"
expect_code 1 rs_role_active "$ROOM" main
MOCK_FLOCK_RESULT=75
rs_role_active "$ROOM" main || fail 'held kernel lock must mean active'
printf 'test-session\n' > "$ROOM/.roomstart/runtime/main.session"
[[ $(rs_role_session "$ROOM" main) == "$SESSION" ]] || fail 'session path resolution'
printf '../../outside\n' > "$ROOM/.roomstart/runtime/main.session"
expect_code 2 rs_role_session "$ROOM" main
MOCK_FLOCK_RESULT=2
expect_code 2 rs_role_active "$ROOM" main
MOCK_FLOCK_RESULT=0

# Saving an arbitrary PID never changes the free-lock decision.
printf '%s\n' "$$" > "$ROOM/.roomstart/runtime/main.pid"
expect_code 1 rs_role_active "$ROOM" main
(exec 8>"$TEST_TMP/launch.lock"; bash "$ROOT/lib/session.sh" "$ROOM" "$SESSION" main "$TEST_TMP/bin/fake shell's")
[[ $(<"$SESSION/main.status") == completed ]] || fail 'main completion'
[[ $(<"$SESSION/main.exit") == 0 && -s "$SESSION/main.started" && -s "$SESSION/main.ended" ]] || fail 'main timestamps and status'
grep -Fq "room=A room; literal target=10.10.10.20 cwd=$ROOM" "$SESSION/main.log" || fail 'quoted arguments, environment or workdir'
grep -Fxq -- --log-out "$MOCK_ARGS" || fail 'output log required'
if grep -Eq -- '--log-in|--log-io' "$MOCK_ARGS"; then fail 'input logging must never be enabled'; fi
bash "$ROOT/lib/session.sh" "$ROOM" "$SESSION" main "$TEST_TMP/bin/fake shell's"
[[ $(grep -c '^room=' "$SESSION/main.log") == 2 ]] || fail 'reopening must append, not overwrite'

MOCK_FLOCK_RESULT=75
expect_code 75 bash "$ROOT/lib/session.sh" "$ROOM" "$SESSION" main "$TEST_TMP/bin/fake shell's"
[[ $(grep -c '^room=' "$SESSION/main.log") == 2 ]] || fail 'duplicate launch changed log'
MOCK_FLOCK_RESULT=0

# A resize signal while wait is pending must not end the role.
export MOCK_RESIZE_READY="$TEST_TMP/resize-ready"
bash "$ROOT/lib/session.sh" "$ROOM" "$SESSION" main "$TEST_TMP/bin/fake shell's" > "$TEST_TMP/resize-output" 2>&1 &
resize_wrapper=$!
for attempt in {1..100}; do [[ -s $MOCK_RESIZE_READY ]] && break; sleep 0.05; done
[[ -s $MOCK_RESIZE_READY ]] || fail 'resize child did not start'
kill -WINCH "$resize_wrapper"
wait "$resize_wrapper" || fail 'resize must not terminate the role'
[[ $(<"$SESSION/main.status") == completed ]] || fail 'resize changed successful completion'
unset MOCK_RESIZE_READY
MOCK_EXIT=7
expect_code 7 bash "$ROOT/lib/session.sh" "$ROOM" "$SESSION" listener 4444
[[ $(<"$SESSION/listener.status") == failed && $(<"$SESSION/listener.exit") == 7 ]] || fail 'failed listener must release its role'
MOCK_EXIT=0
bash "$ROOT/lib/session.sh" "$ROOM" "$SESSION" listener 4444
[[ $(<"$SESSION/listener.status") == completed ]] || fail 'listener completion'
bash "$ROOT/lib/session.sh" "$ROOM" "$SESSION" notes
[[ $(<"$SESSION/notes.status") == completed && ! -e "$SESSION/notes.log" ]] || fail 'notes must remain unrecorded'
grep -Fq 'Saved edit' "$ROOM/notes.md" || fail 'notes editor'
expect_code 2 bash "$ROOT/lib/session.sh" "$ROOM" "$SESSION" listener '4444; echo unsafe'
expect_code 2 bash "$ROOT/lib/session.sh" "$ROOM" "$TEST_TMP" main "$TEST_TMP/bin/fake shell's"
mkdir "$ROOM/.roomstart/runtime/notes.lock.invalid"
mv "$ROOM/.roomstart/runtime/notes.lock" "$TEST_TMP/notes.lock.saved"
mv "$ROOM/.roomstart/runtime/notes.lock.invalid" "$ROOM/.roomstart/runtime/notes.lock"
expect_code 2 rs_role_active "$ROOM" notes

if [[ $(uname -s) == Linux ]] && PATH="$ORIGINAL_PATH" command -v flock >/dev/null && PATH="$ORIGINAL_PATH" command -v script >/dev/null && PATH="$ORIGINAL_PATH" command -v setsid >/dev/null; then
    # On Linux: use real utilities, keep only our harmless target shell.
    PATH=$ORIGINAL_PATH
    export REAL_CHILD_MARKER="$TEST_TMP/live-child"
    cat > "$TEST_TMP/live-shell" <<'CHILD'
#!/usr/bin/env bash
printf '%s\n' "$$" > "$REAL_CHILD_MARKER"
if { : >&9; } 2>/dev/null; then exit 95; fi
trap '' TERM
while :; do sleep 1; done
CHILD
    chmod +x "$TEST_TMP/live-shell"
    LIVE_SESSION="$ROOM/.roomstart/sessions/linux-signal"
    mkdir "$LIVE_SESSION"
    bash "$ROOT/lib/session.sh" "$ROOM" "$LIVE_SESSION" main "$TEST_TMP/live-shell" > "$TEST_TMP/live-output" 2>&1 < /dev/null &
    wrapper=$!
    for attempt in {1..100}; do [[ -s "$REAL_CHILD_MARKER" ]] && break; sleep 0.1; done
    [[ -s "$REAL_CHILD_MARKER" ]] || fail 'real PTY shell did not start'
    rs_role_active "$ROOM" main || fail 'actual flock not held'
    expect_code 75 bash "$ROOT/lib/session.sh" "$ROOM" "$LIVE_SESSION" main "$TEST_TMP/live-shell"
    kill -TERM "$wrapper"
    expect_code 143 wait "$wrapper"
    [[ $(<"$LIVE_SESSION/main.status") == interrupted ]] || fail 'TERM must mark interrupted'
    expect_code 1 rs_role_active "$ROOM" main
    child=$(<"$REAL_CHILD_MARKER")
    if rs_runtime_read_proc "$child" && [[ $RS_PROC_STATE != Z ]]; then fail 'orphaned PTY child after wrapper exit'; fi
    printf 'PASS: real Linux locks, PTY and signal cleanup\n'
else
    printf 'SKIP: real util-linux locks, PTY and signal cleanup require Linux\n'
fi
printf 'PASS: runtime contracts, quoting, logs, duplicate and error handling\n'
