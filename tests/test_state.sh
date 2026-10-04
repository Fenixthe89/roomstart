#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../lib/state.sh
source "$ROOT/lib/state.sh"
TEMP_BASE=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
TEST_ROOT=$(mktemp -d "$TEMP_BASE/roomstart-state-test.XXXXXXXX")
cleanup() {
    local resolved
    resolved=$(realpath -- "$TEST_ROOT") || return
    case "$resolved" in
        "$TEMP_BASE"/roomstart-state-test.*) rm -rf -- "$resolved" ;;
        *) printf 'Refusing unexpected test cleanup: %s\n' "$resolved" >&2 ;;
    esac
}
trap cleanup EXIT
checks=0
ok() { "$@" || { printf 'FAIL: %s\n' "$*" >&2; exit 1; }; checks=$((checks + 1)); }
bad() { if "$@" 2>/dev/null; then printf 'UNEXPECTED SUCCESS: %s\n' "$*" >&2; exit 1; fi; checks=$((checks + 1)); }
same() { [[ "$1" == "$2" ]] || { printf 'FAIL equality: <%s> != <%s>\n' "$1" "$2" >&2; exit 1; }; checks=$((checks + 1)); }

ok rs_validate_name 'A room with spaces'
ok rs_validate_name 'Room_1-v2'
for name in '' .hidden .. ../escape '-option' 'a/b' 'a\b' $'bad\nname' $'bad\tname' $'bad\033name'; do
    bad rs_validate_name "$name"
done
for port in 1 4444 65535 00080; do ok rs_validate_port "$port"; done
for port in '' 0 65536 99999999999999999999 1x '+80' -1 ' 80'; do bad rs_validate_port "$port"; done
for target in '' 10.10.10.20 example.lab '2001:db8::1' '::1' 'fe80::1%eth0'; do ok rs_validate_target "$target"; done
for target in 'bad host' '-option' '$(touch sentinel)' ';echo' 'http://host' $'bad\nhost'; do bad rs_validate_target "$target"; done
for url in '' 'http://example.lab' 'https://example.lab/room?id=2&key=3'; do ok rs_validate_url "$url"; done
for url in 'javascript:alert(1)' 'ftp://host' 'https://' 'https:///path' 'https://bad host' $'https://host\n'; do bad rs_validate_url "$url"; done

base="$TEST_ROOT/rooms"
room=$(rs_room_path "$base" 'Existing Room')
same "$room" "$base/Existing Room"
ok test -d "$base"
ok test ! -e "$room"
mkdir -p -- "$room"
ok rs_state_init "$room" 4444
same "$(rs_state_get "$room" schema)" 1
same "$(rs_state_get "$room" port)" 4444
same "$(rs_state_get "$room" target fallback)" fallback
created=$(rs_state_get "$room" created)
ok test -n "$created"
ok rs_state_set "$room" port 8080
ok rs_state_init "$room" 1234
same "$(rs_state_get "$room" port)" 8080
same "$(rs_state_get "$room" created)" "$created"
bad rs_state_set "$room" ../outside value
bad rs_state_get "$room" ../outside fallback
bad rs_state_set "$room" port '; touch sentinel'
bad rs_state_set "$room" target '$(touch sentinel)'
bad rs_state_set "$room" url $'https://host\nmalicious'
bad rs_state_set "$room" checkpoint $'one\ntwo'
literal='$(touch sentinel); `touch sentinel`; "quotes"'
ok rs_state_set "$room" checkpoint "$literal"
same "$(rs_state_get "$room" checkpoint)" "$literal"
ok test ! -e "$ROOT/sentinel"
ok rs_state_set "$room" target '10.10.1.2'
ok rs_state_set "$room" url 'https://example.lab/room?name=one&mode=two'
session1=$(rs_new_session "$room")
session2=$(rs_new_session "$room")
ok test "$session1" != "$session2"
ok test -d "$session1"
same "$(cat "$session1/port")" 8080
same "$(cat "$session1/target")" '10.10.1.2'
same "$(cat "$session1/checkpoint")" "$literal"
same "$(rs_state_get "$room" last_session)" "${session2##*/}"
ok test -s "$session1/started"
ok rs_state_set "$room" target '10.10.2.3'
same "$(cat "$session1/target")" '10.10.1.2'
listing=$(rs_list_rooms "$base")
ok test "${listing#*Existing Room}" != "$listing"

# Use an isolated config directory; never read the user's real configuration.
export XDG_CONFIG_HOME="$TEST_ROOT/config"
export ROOMSTART_BASE="$base"
export ROOMSTART_LISTENER_PORT=4444
mkdir -p -- "$XDG_CONFIG_HOME"
ok bash "$ROOT/newroom" 'New Room'
ok test -s "$base/New Room/notes.md"
ok test -f "$base/New Room/report.md"
ok test -d "$base/New Room/scans"
printf 'Personal notes\nincluding arbitrary bytes \001\n' > "$base/New Room/notes.md"
printf 'Existing report\n' > "$base/New Room/report.md"
printf 'Preserved results\n' > "$base/New Room/scans/result.txt"
cp -- "$base/New Room/notes.md" "$TEST_ROOT/notes.expected"
cp -- "$base/New Room/report.md" "$TEST_ROOT/report.expected"
ok bash "$ROOT/newroom" 'New Room'
ok cmp "$TEST_ROOT/notes.expected" "$base/New Room/notes.md"
ok cmp "$TEST_ROOT/report.expected" "$base/New Room/report.md"
same "$(cat "$base/New Room/scans/result.txt")" 'Preserved results'
bad bash "$ROOT/newroom" '../escape'
bad bash "$ROOT/newroom" '-option'
bad bash "$ROOT/newroom" Name extra
ok test ! -e "$TEST_ROOT/escape"
mkdir -p -- "$XDG_CONFIG_HOME/roomstart"
printf 'ROOMSTART_LAYOUT_ENABLED=invalid\n' > "$XDG_CONFIG_HOME/roomstart/config.sh"
bad bash "$ROOT/newroom" 'Invalid Config'
ok test ! -e "$base/Invalid Config"
rm -- "$XDG_CONFIG_HOME/roomstart/config.sh"

# Real symlinks require OS support (Git Bash may instead copy the target).
mkdir -p -- "$TEST_ROOT/outside"
if ln -s -- "$TEST_ROOT/outside" "$base/Escape" 2>/dev/null && [[ -L "$base/Escape" ]]; then
    bad rs_room_path "$base" Escape
    bad bash "$ROOT/newroom" Escape
    ln -s -- "$room" "$base/Alias"
    same "$(rs_room_path "$base" Alias)" "$room"
    mkdir -p -- "$base/UnsafeState"
    ln -s -- "$TEST_ROOT/outside" "$base/UnsafeState/.roomstart"
    bad rs_state_init "$base/UnsafeState" 4444
    bad rs_state_get "$base/UnsafeState" port 4444
    ln -s -- "$TEST_ROOT/untouched" "$room/.roomstart/url.link"
    mv -fT -- "$room/.roomstart/url.link" "$room/.roomstart/url"
    bad rs_state_set "$room" url https://example.lab
    bad rs_state_get "$room" url fallback
    bad rs_state_init "$room" 4444
    ok test ! -e "$TEST_ROOT/untouched"
    mkdir -p -- "$base/UnsafeSessions/.roomstart"
    ln -s -- "$TEST_ROOT/outside" "$base/UnsafeSessions/.roomstart/sessions"
    bad rs_state_init "$base/UnsafeSessions" 4444
    bad rs_new_session "$base/UnsafeSessions"
    mkdir -p -- "$TEST_ROOT/bin"
    ln -s -- "$ROOT/newroom" "$TEST_ROOT/bin/newroom"
    ok bash "$TEST_ROOT/bin/newroom" 'Linked Entry'
    ok test -f "$base/Linked Entry/.roomstart/schema"
else
    printf 'SKIP: real symlinks unavailable on this host.\n'
fi

# Shared folders can provide normal files but reject every hard link.
ln() { return 1; }
shared="$base/Shared Folder"
mkdir -p -- "$shared"
ok rs_state_init "$shared" 4444
same "$(rs_state_get "$shared" schema)" 1
same "$(rs_state_get "$shared" port)" 4444
ok rs_state_set "$shared" port 8080
ok rs_state_init "$shared" 1234
same "$(rs_state_get "$shared" port)" 8080
unset -f ln

printf 'PASS: %s state/newroom assertions\n' "$checks"
