#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TEMP_BASE=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
TEST_ROOT=$(mktemp -d "$TEMP_BASE/roomstart-install-test.XXXXXXXX")
cleanup() {
    local path
    path=$(realpath -- "$TEST_ROOT") || return
    [[ $path == "$TEMP_BASE"/roomstart-install-test.* ]] && rm -rf -- "$path"
}
trap cleanup EXIT
cd "$TEST_ROOT"
export XDG_CONFIG_HOME=./config ROOMSTART_BASE=./rooms
export ROOMSTART_NEWROOM='./custom launcher' ROOMSTART_LISTENER_PORT=4444 ROOMSTART_LAYOUT_ENABLED=false
config=./config/roomstart/config.sh
mkdir -p ./config
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
same() { [[ $1 == "$2" ]] || fail "<$1> != <$2>"; }

literal='./rooms $(touch injected) and spaces'
printf '%s\n\n\n' "$literal" | bash "$ROOT/install.sh" > install.out
[[ -f $config && -d $literal && ! -e injected ]] || fail 'literal path / installation'
loaded=$(bash -c 'source "$1"; printf "%s" "$ROOMSTART_BASE"' _ "$config")
same "$loaded" "$literal"
loaded=$(bash -c 'source "$1"; printf "%s" "$ROOMSTART_NEWROOM"' _ "$config")
same "$loaded" './custom launcher'
cp "$config" previous

if bash "$ROOT/install.sh" < /dev/null > /dev/null 2>&1; then fail 'EOF accepted'; fi
cmp "$config" previous || fail 'EOF changed configuration'
printf '\n\n\n' | bash "$ROOT/install.sh" > update.out
backup_count=$(find ./config -name 'config.sh.bak.*' | wc -l)
same "$backup_count" 1
backup=$(find ./config -name 'config.sh.bak.*')
cmp "$backup" previous || fail 'backup did not preserve exact contents'

printf '\n65536\n8080\ns\n0 0 100 100 extra\n-100 0 800 600\n\n\n\n' | bash "$ROOT/install.sh" > geometry.out 2>&1
values=$(bash -c 'source "$1"; printf "%s %s %s" "$ROOMSTART_LISTENER_PORT" "$ROOMSTART_MAIN_X" "$ROOMSTART_LAYOUT_ENABLED"' _ "$config")
same "$values" '8080 -100 true'
grep -q 'quattro interi' geometry.out || fail 'invalid geometry not rejected'
printf 'ROOMSTART_BASE="unterminated\n' > "$config"
cp "$config" malformed
if printf '\n\n\n' | bash "$ROOT/install.sh" > /dev/null 2>&1; then fail 'malformed configuration accepted'; fi
cmp "$config" malformed || fail 'malformed configuration overwritten'
printf 'PASS: installer quoting, validation, backup and cancellation\n'
