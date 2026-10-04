#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT/lib/state.sh"
source "$ROOT/lib/notes.sh"
TEMP_BASE=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
TEST_ROOM=$(mktemp -d "$TEMP_BASE/roomstart-notes-test.XXXXXXXX")
cleanup() {
    local resolved
    resolved=$(realpath -- "$TEST_ROOM") || return
    [[ $resolved == "$TEMP_BASE"/roomstart-notes-test.* ]] && rm -rf -- "$resolved"
}
trap cleanup EXIT
mkdir "$TEST_ROOM/.roomstart"
printf '# Room\n## Target\nIP:\nDominio: esempio.lab\n## Appunti\nRisultato scritto a mano\nIP: riferimento storico\n' > "$TEST_ROOM/notes.md"
cp "$TEST_ROOM/notes.md" "$TEST_ROOM/original"
rs_notes_target "$TEST_ROOM" 10.10.1.2
grep -Fxq 'IP: 10.10.1.2' "$TEST_ROOM/notes.md"
grep -Fxq 'Dominio: esempio.lab' "$TEST_ROOM/notes.md"
grep -Fxq 'Risultato scritto a mano' "$TEST_ROOM/notes.md"
grep -Fxq 'IP: riferimento storico' "$TEST_ROOM/notes.md"
backup=$(find "$TEST_ROOM/.roomstart" -name 'notes-backup.*')
cmp "$backup" "$TEST_ROOM/original"
rs_notes_target "$TEST_ROOM" 10.10.1.2
[[ $(find "$TEST_ROOM/.roomstart" -name 'notes-backup.*' | wc -l) == 1 ]]
rs_notes_target "$TEST_ROOM" 10.10.1.3
grep -Fxq 'IP: 10.10.1.3' "$TEST_ROOM/notes.md"
rs_notes_target "$TEST_ROOM" ''
grep -Fxq 'IP: ' "$TEST_ROOM/notes.md"
printf '# Note libere\nTesto da conservare\n' > "$TEST_ROOM/notes.md"
rs_notes_target "$TEST_ROOM" 10.10.1.4
grep -Fxq 'Testo da conservare' "$TEST_ROOM/notes.md"
grep -Fxq 'IP: 10.10.1.4' "$TEST_ROOM/notes.md"
printf 'PASS: automatic target, preserved notes and backups\n'
