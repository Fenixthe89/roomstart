#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || exit 1
source "$ROOT/state.sh"
source "$ROOT/runtime.sh"
source "$ROOT/notes.sh"
room=${ROOMSTART_ROOM:-}
[[ -n $room ]] && rs_state_safe "$room" || exit 1
[[ $# == 2 ]] || exit 2
case $1 in
    next)
        rs_state_set "$room" checkpoint "$2" || exit 1
        printf 'Prossimo passo salvato.\n'
        ;;
    note)
        [[ -n $2 && ${#2} -le 4096 ]] || exit 2
        # Separate journal avoids overwriting unsaved Nano edits in notes.md.
        journal="$room/appunti.md"
        [[ ! -L $journal && ( ! -e $journal || -f $journal ) ]] || exit 1
        exec 7>>"$journal" || exit 1
        flock -x 7 || exit 1
        printf '\n- [%s] %s\n' "$(date '+%Y-%m-%d %H:%M')" "$2" >&7 || exit 1
        printf 'Appunto salvato in appunti.md.\n'
        ;;
    target)
        [[ -n $2 ]] && rs_validate_target "$2" || { printf 'Target non valido.\n' >&2; exit 2; }
        rs_runtime_init "$room" || exit 1
        rs_runtime_regular "$room/.roomstart/runtime/launch.lock" || exit 1
        exec 7>>"$room/.roomstart/runtime/launch.lock" || exit 1
        flock -n 7 || exit 1
        rs_state_set "$room" target "$2" || exit 1
        if rs_role_active "$room" notes; then
            printf 'IP nelle note aggiornato alla prossima riapertura dell’editor.\n'
        else
            code=$?; [[ $code == 1 ]] || exit 1
            rs_notes_target "$room" "$2" || exit 1
        fi
        printf 'Target salvato: %s. I comandi già avviati mantengono il target precedente.\n' "$2"
        ;;
    *) exit 2 ;;
esac
