#!/usr/bin/env bash
# End-to-end CLI decisions against a simulated desktop. Real role supervisors
# and util-linux are exercised separately by test_runtime.sh on Linux.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TEMP_BASE=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
TEST_ROOT=$(mktemp -d "$TEMP_BASE/roomstart-cli-test.XXXXXXXX")
cleanup() {
    local path
    path=$(realpath -- "$TEST_ROOT") || return
    [[ $path == "$TEMP_BASE"/roomstart-cli-test.* ]] && rm -rf -- "$path"
}
trap cleanup EXIT
APP="$TEST_ROOT/app"
mkdir -p "$APP/lib" "$TEST_ROOT/bin" "$TEST_ROOT/properties" "$TEST_ROOT/config"
cp "$ROOT/roomstart" "$ROOT/newroom" "$APP/"
cp "$ROOT/lib/"*.sh "$APP/lib/"
chmod +x "$APP/roomstart" "$APP/newroom"
export ROOMSTART_BASE="$TEST_ROOT/rooms" XDG_CONFIG_HOME="$TEST_ROOT/config"
export ROOMSTART_LAYOUT_ENABLED=true ROOMSTART_LISTENER_PORT=4444
unset ROOMSTART_NEWROOM ROOMSTART_ROOM ROOMSTART_TARGET
export DISPLAY=:99 XDG_SESSION_TYPE=x11 SHELL=/bin/bash
export MOCK_DESKTOP="$TEST_ROOT/desktop" MOCK_CALLS="$TEST_ROOT/calls" MOCK_PROPERTIES="$TEST_ROOT/properties"
printf '%s\n' '0x01 0 qterminal.QTerminal host main' '0x999 0 Navigator.Firefox host unrelated browser' > "$MOCK_DESKTOP"
: > "$MOCK_CALLS"

cat > "$TEST_ROOT/bin/flock" <<'MOCK'
#!/usr/bin/env bash
if [[ $1 == -n ]]; then exit "${MOCK_LAUNCH_BUSY:-0}"; fi
lock=$(readlink "/proc/$$/fd/9") || exit 2
[[ ! -f $lock.held ]] || exit 75
MOCK
cat > "$TEST_ROOT/bin/wmctrl" <<'MOCK'
#!/usr/bin/env bash
if [[ $1 == -lx ]]; then cat "$MOCK_DESKTOP"; else printf 'wmctrl %s\n' "$*" >> "$MOCK_CALLS"; fi
MOCK
cat > "$TEST_ROOT/bin/xdotool" <<'MOCK'
#!/usr/bin/env bash
printf '0x01\n'
MOCK
cat > "$TEST_ROOT/bin/xprop" <<'MOCK'
#!/usr/bin/env bash
[[ $1 == -id ]] || exit 2
id=$2; shift 2
grep -q "^$id " "$MOCK_DESKTOP" || exit 1
case $1 in
    WM_CLASS) printf 'WM_CLASS(STRING) = "qterminal", "QTerminal"\n' ;;
    -f) printf '%s\n' "$6" > "$MOCK_PROPERTIES/$id" ;;
    _ROOMSTART_OWNER)
        [[ -f $MOCK_PROPERTIES/$id ]] || exit 1
        printf '_ROOMSTART_OWNER(STRING) = "%s"\n' "$(cat "$MOCK_PROPERTIES/$id")" ;;
    *) exit 2 ;;
esac
MOCK
cat > "$TEST_ROOT/bin/firefox" <<'MOCK'
#!/usr/bin/env bash
printf 'firefox %s\n' "$*" >> "$MOCK_CALLS"
printf '0x02 0 Navigator.Firefox host Room\n' >> "$MOCK_DESKTOP"
MOCK
cat > "$TEST_ROOT/bin/qterminal" <<'MOCK'
#!/usr/bin/env bash
[[ $1 == --workdir && $3 == -e ]] || exit 2
shift 3
role=$5
printf 'qterminal %s\n' "$role" >> "$MOCK_CALLS"
case $role in listener) id=0x03;; notes) id=0x04;; *) exit 2;; esac
printf '%s 0 qterminal.QTerminal host %s\n' "$id" "$role" >> "$MOCK_DESKTOP"
exec "$@"
MOCK
cat > "$TEST_ROOT/bin/script" <<'MOCK'
#!/usr/bin/env bash
[[ $1 == --help ]] || exit 2
printf 'script --log-out FILE\n'
MOCK
cat > "$TEST_ROOT/bin/ss" <<'MOCK'
#!/usr/bin/env bash
if [[ ${MOCK_PORT_BUSY:-false} == true ]]; then printf 'LISTEN 0 10 0.0.0.0:4444\n'; fi
exit 0
MOCK
for tool in nano nc setsid; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_ROOT/bin/$tool"
done
cat > "$APP/lib/session.sh" <<'MOCK'
#!/usr/bin/env bash
room=$1 session=$2 role=$3
printf 'role %s\n' "$role" >> "$MOCK_CALLS"
touch "$room/.roomstart/runtime/$role.lock" "$room/.roomstart/runtime/$role.lock.held"
printf '%s\n' "${session##*/}" > "$room/.roomstart/runtime/$role.session"
printf 'running\n' > "$session/$role.status"
printf 'preserved output\n' >> "$session/$role.log"
[[ $role != main ]] || printf '%s\n' "$ROOMSTART_TARGET" > "$session/environment-target"
[[ $role != main ]] || printf '%s\n' "$IP" > "$session/environment-ip"
MOCK
chmod +x "$TEST_ROOT/bin/"*
export PATH="$TEST_ROOT/bin:$PATH"
checks=0
ok() { "$@" || { printf 'FAIL: %s\n' "$*" >&2; exit 1; }; checks=$((checks+1)); }
bad() { if "$@" > "$TEST_ROOT/failure" 2>&1; then printf 'UNEXPECTED SUCCESS: %s\n' "$*" >&2; exit 1; fi; checks=$((checks+1)); }
same() { [[ $1 == "$2" ]] || { printf 'FAIL equality <%s> != <%s>\n' "$1" "$2" >&2; exit 1; }; checks=$((checks+1)); }

ok bash "$APP/roomstart" --help > "$TEST_ROOT/help"
ok grep -Fq -- --checkpoint "$TEST_ROOT/help"
bad bash "$APP/roomstart" --unknown
bad bash "$APP/roomstart" '--bad'
bad bash "$APP/roomstart" '../outside'
bad bash "$APP/roomstart" Room --port '4444;touch file'
bad bash "$APP/roomstart" Room --target '$(touch file)'
bad bash "$APP/roomstart" Room --url 'javascript:alert(1)'
bad bash "$APP/roomstart" Room --port
bad bash "$APP/roomstart" Missing --status
ok test ! -d "$ROOMSTART_BASE"

name='A room; literal'
room="$ROOMSTART_BASE/$name"
ok bash "$APP/roomstart" "$name" --target 10.10.10.20 --url 'https://example.lab/room?q=a&b=2' < /dev/null > "$TEST_ROOT/first"
ok test -f "$room/notes.md"
session_id=$(cat "$room/.roomstart/last_session")
session="$room/.roomstart/sessions/$session_id"
same "$(cat "$session/target")" 10.10.10.20
ok grep -Fxq 'IP: 10.10.10.20' "$room/notes.md"
same "$(cat "$session/environment-target")" 10.10.10.20
same "$(cat "$session/environment-ip")" 10.10.10.20
same "$(cat "$room/.roomstart/url")" 'https://example.lab/room?q=a&b=2'
same "$(grep -c '^firefox ' "$MOCK_CALLS")" 1
same "$(grep -c '^qterminal ' "$MOCK_CALLS")" 2
same "$(grep -c '^role main' "$MOCK_CALLS")" 1
if grep -q 'wmctrl -i -r 0x999' "$MOCK_CALLS"; then printf 'FAIL: unrelated Firefox window moved\n' >&2; exit 1; fi
printf '\nNotes retained\n' >> "$room/notes.md"
cp "$room/notes.md" "$TEST_ROOT/saved-notes"
ok bash "$APP/roomstart" "$name" < /dev/null > "$TEST_ROOT/reopen"
same "$(grep -c '^firefox ' "$MOCK_CALLS")" 1
same "$(grep -c '^qterminal ' "$MOCK_CALLS")" 2
same "$(grep -c '^role main' "$MOCK_CALLS")" 1
same "$(cat "$room/.roomstart/last_session")" "$session_id"
ok cmp "$room/notes.md" "$TEST_ROOT/saved-notes"

# Read-only/headless operations remain usable while the room is running.
checkpoint='Check /backup; $(touch sentinel) is literal'
ok env -u DISPLAY bash "$APP/roomstart" "$name" --checkpoint "$checkpoint" > "$TEST_ROOT/checkpoint"
same "$(cat "$room/.roomstart/checkpoint")" "$checkpoint"
ok test ! -e "$ROOT/sentinel"
ok env -u DISPLAY bash "$APP/roomstart" "$name" --status > "$TEST_ROOT/status"
ok grep -Fq "$checkpoint" "$TEST_ROOT/status"
ok grep -q 'main.*attivo' "$TEST_ROOT/status"
ok env -u DISPLAY bash "$APP/roomstart" --list > "$TEST_ROOT/list"
ok grep -Fq "$name" "$TEST_ROOT/list"
bad bash "$APP/roomstart" "$name" --status --target example.lab
bad bash "$APP/roomstart" "$name" --checkpoint hello --port 1234
bad bash "$APP/roomstart" "$name" --target 10.10.10.21
same "$(cat "$room/.roomstart/target")" 10.10.10.20

# One closed terminal gets recreated, while surviving roles are reused.
rm -f -- "$room/.roomstart/runtime/notes.lock.held"
sed '/^0x04 /d' "$MOCK_DESKTOP" > "$TEST_ROOT/desktop-new"
mv "$TEST_ROOT/desktop-new" "$MOCK_DESKTOP"
ok bash "$APP/roomstart" "$name" < /dev/null > "$TEST_ROOT/partial"
same "$(grep -c '^qterminal notes' "$MOCK_CALLS")" 2
same "$(grep -c '^qterminal listener' "$MOCK_CALLS")" 1

# Simulate all tools closing. A new session keeps old logs and uses new target.
rm -f -- "$room/.roomstart/runtime/"*.held
printf '%s\n' '0x01 0 qterminal.QTerminal host main' '0x999 0 Navigator.Firefox host unrelated browser' > "$MOCK_DESKTOP"
ok env -u DISPLAY bash "$APP/roomstart" "$name" --status > "$TEST_ROOT/closed-status"
ok grep -q 'main.*interrupted' "$TEST_ROOT/closed-status"
old_log=$(cat "$session/main.log")
ok bash "$APP/roomstart" "$name" --target 10.10.10.21 < /dev/null > "$TEST_ROOT/next"
next_session=$(cat "$room/.roomstart/last_session")
ok test "$next_session" != "$session_id"
same "$(cat "$session/main.log")" "$old_log"
same "$(cat "$session/target")" 10.10.10.20
same "$(cat "$room/.roomstart/sessions/$next_session/target")" 10.10.10.21
ok grep -Fxq 'IP: 10.10.10.21' "$room/notes.md"
ok grep -Fxq 'Notes retained' "$room/notes.md"

# An occupied port blocks tools before any browser/terminal is opened.
calls=$(wc -l < "$MOCK_CALLS")
bad env MOCK_PORT_BUSY=true bash "$APP/roomstart" Busy --port 4444 < /dev/null
same "$(wc -l < "$MOCK_CALLS")" "$calls"
bad env MOCK_LAUNCH_BUSY=1 bash "$APP/roomstart" Busy < /dev/null
same "$(wc -l < "$MOCK_CALLS")" "$calls"
bad env -u DISPLAY bash "$APP/roomstart" Headless < /dev/null
ok test ! -e "$ROOMSTART_BASE/Headless"

# A reused X11 ID without our property is never treated as our saved window.
source "$ROOT/lib/runtime.sh"
source "$ROOT/lib/windows.sh"
ok rs_window_get "$room" browser > /dev/null
printf 'different-owner\n' > "$MOCK_PROPERTIES/0x02"
bad rs_window_get "$room" browser
printf 'PASS: CLI/desktop orchestration (%s assertions)\n' "$checks"
