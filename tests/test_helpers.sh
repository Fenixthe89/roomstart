#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT/lib/state.sh"
source "$ROOT/lib/runtime.sh"
TEST_TMP=$(mktemp -d)
# No recursive deletion: remove only the files this test creates.
if ! command -v flock >/dev/null 2>&1; then
    mkdir "$TEST_TMP/bin"
    cat > "$TEST_TMP/bin/flock" <<'MOCK'
#!/usr/bin/env bash
[[ $* != *--nonblock* || ${MOCK_NOTES_ACTIVE:-false} != true ]] || exit 75
exit 0
MOCK
    chmod +x "$TEST_TMP/bin/flock"
    export PATH="$TEST_TMP/bin:$PATH"
    MOCK_LOCKS=true
fi
export ROOMSTART_ROOM="$TEST_TMP"
rs_state_init "$TEST_TMP" 4444
rs_runtime_init "$TEST_TMP"
printf '# Notes\n\n## Target\nIP: old\n' > "$TEST_TMP/notes.md"
export ROOMSTART_HELPER="$ROOT/lib/helper.sh" IP=old ROOMSTART_TARGET=old
source "$ROOT/lib/interactive.sh"
roomnote 'Literal $(touch unsafe) ; note'
grep -Fq 'Literal $(touch unsafe) ; note' "$TEST_TMP/appunti.md"
roomnext 'Check port 8080'
[[ $(cat "$TEST_TMP/.roomstart/checkpoint") == 'Check port 8080' ]]
roomtarget 10.10.10.25
[[ $IP == 10.10.10.25 && $ROOMSTART_TARGET == 10.10.10.25 ]]
[[ $(cat "$TEST_TMP/.roomstart/target") == 10.10.10.25 ]]
grep -Fxq 'IP: 10.10.10.25' "$TEST_TMP/notes.md"
if roomtarget '-bad'; then exit 1; fi
[[ $IP == 10.10.10.25 ]]
# An editor holding the role lock must keep its note file untouched.
exec 6>>"$TEST_TMP/.roomstart/runtime/notes.lock"
flock -x 6
[[ ${MOCK_LOCKS:-false} != true ]] || export MOCK_NOTES_ACTIVE=true
roomtarget 10.10.10.26
[[ $IP == 10.10.10.26 ]]
grep -Fxq 'IP: 10.10.10.25' "$TEST_TMP/notes.md"
exec 6>&-
printf 'PASS: room helpers, literal notes, checkpoint and live target\n'
