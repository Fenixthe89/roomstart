#!/usr/bin/env bash
# Room metadata is literal text, never shell configuration.

rs_error() { printf 'Roomstart: %s\n' "$*" >&2; }

rs_validate_name() {
    local value=${1-}
    [[ -n "$value" && "$value" != .* && "$value" != -* &&
       "$value" != */* && "$value" != *\\* && ! "$value" =~ [[:cntrl:]] ]]
}

rs_validate_port() {
    local value=${1-}
    [[ "$value" =~ ^[0-9]{1,5}$ ]] || return 1
    (( 10#$value >= 1 && 10#$value <= 65535 ))
}

rs_validate_target() {
    local value=${1-}
    [[ -z "$value" ]] && return 0
    # Targets are labels, IPs or hostnames; never a command or an option.
    [[ "$value" =~ ^[a-zA-Z0-9:][a-zA-Z0-9.:%_-]*$ ]]
}

rs_validate_url() {
    local value=${1-}
    [[ -z "$value" ]] && return 0
    [[ "$value" =~ ^https?://[^/[:space:][:cntrl:]]+ &&
       ! "$value" =~ [[:space:][:cntrl:]] ]]
}

rs_room_path() {
    local base=${1-} name=${2-} canonical_base candidate
    rs_validate_name "$name" || { rs_error 'Nome room non valido.'; return 1; }
    [[ -n "$base" ]] || { rs_error 'Cartella base vuota.'; return 1; }
    mkdir -p -- "$base" || return 1
    canonical_base=$(cd -- "$base" && pwd -P) || return 1
    candidate=$(realpath -m -- "$canonical_base/$name") || return 1
    # A room must resolve to a proper descendant, including symlink targets.
    if [[ "$canonical_base" != / && "$candidate" != "$canonical_base/"* ]] ||
       [[ "$candidate" == "$canonical_base" ]]; then
        rs_error "La room '$name' esce dalla cartella base."
        return 1
    fi
    if [[ -e "$candidate" && ! -d "$candidate" ]]; then
        rs_error "Il percorso della room non e' una cartella: $candidate"
        return 1
    fi
    printf '%s\n' "$candidate"
}

rs_state_key_valid() {
    case ${1-} in
        target|url|port|checkpoint|created|last_session|schema) return 0 ;;
        *) rs_error "Campo di stato non valido: ${1-}"; return 1 ;;
    esac
}

rs_state_safe() {
    local room=${1-} state
    [[ -n "$room" && -d "$room" ]] || { rs_error 'Cartella room assente.'; return 1; }
    state=$room/.roomstart
    if [[ -L "$state" || ( -e "$state" && ! -d "$state" ) ]]; then
        rs_error "Cartella di stato non sicura: $state"
        return 1
    fi
}

rs_state_field_safe() {
    local room=$1 key=$2 field
    rs_state_key_valid "$key" && rs_state_safe "$room" || return 1
    field=$room/.roomstart/$key
    if [[ -L "$field" || ( -e "$field" && ! -f "$field" ) ]]; then
        rs_error "Campo di stato non sicuro: $key"
        return 1
    fi
}

rs_state_get() {
    local room=${1-} key=${2-} fallback=${3-}
    rs_state_field_safe "$room" "$key" || return 1
    if [[ -f "$room/.roomstart/$key" ]]; then
        cat -- "$room/.roomstart/$key"
    else
        printf '%s\n' "$fallback"
    fi
}

rs_state_value_valid() {
    local key=$1 value=$2
    # One field per file, one line per field. Punctuation stays literal.
    [[ ! "$value" =~ [[:cntrl:]] ]] || return 1
    case "$key" in
        target) rs_validate_target "$value" ;;
        url) rs_validate_url "$value" ;;
        port) rs_validate_port "$value" ;;
        schema) [[ "$value" == 1 ]] ;;
        last_session) [[ -z "$value" || "$value" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] ;;
        checkpoint|created) return 0 ;;
        *) return 1 ;;
    esac
}

rs_state_write() (
    # Subshell keeps the private umask and cleanup trap out of the caller.
    local room=$1 key=$2 value=$3 mode=${4:-replace} temp
    rs_state_field_safe "$room" "$key" || return 1
    rs_state_value_valid "$key" "$value" || { rs_error "Valore non valido per $key."; return 1; }
    [[ -d "$room/.roomstart" ]] || { rs_error 'Stato non inizializzato.'; return 1; }
    umask 077
    temp=$(mktemp "$room/.roomstart/.write.XXXXXXXX") || return 1
    trap 'rm -f -- "$temp"' EXIT
    printf '%s\n' "$value" > "$temp" || return 1
    rs_state_field_safe "$room" "$key" || return 1
    if [[ "$mode" == missing ]]; then
        # Prefer atomic hard-link creation. VirtualBox shared folders may
        # reject hard links, so fall back to exclusive, no-clobber creation.
        if ln -- "$temp" "$room/.roomstart/$key" 2>/dev/null; then
            return 0
        fi
        rs_state_field_safe "$room" "$key" || return 1
        if [[ ! -e "$room/.roomstart/$key" ]]; then
            if (set -o noclobber; printf '%s\n' "$value" > "$room/.roomstart/$key") 2>/dev/null; then
                return 0
            fi
        fi
        rs_state_field_safe "$room" "$key" || return 1
        [[ -f "$room/.roomstart/$key" ]] || { rs_error "Impossibile inizializzare $key."; return 1; }
    else
        mv -fT -- "$temp" "$room/.roomstart/$key" || return 1
    fi
)

rs_state_set() {
    [[ $# -eq 3 ]] || { rs_error 'rs_state_set richiede room, campo e valore.'; return 1; }
    rs_state_write "$1" "$2" "$3" replace
}

rs_state_init() (
    local room=${1-} port=${2:-4444} key
    rs_validate_port "$port" || { rs_error 'Porta listener non valida.'; return 1; }
    rs_state_safe "$room" || return 1
    umask 077
    mkdir -p -- "$room/.roomstart" || return 1
    rs_state_safe "$room" || return 1
    for key in target url port checkpoint created last_session schema; do
        rs_state_field_safe "$room" "$key" || return 1
    done
    if [[ -L "$room/.roomstart/sessions" ||
          ( -e "$room/.roomstart/sessions" && ! -d "$room/.roomstart/sessions" ) ]]; then
        rs_error 'Cartella sessioni non sicura.'
        return 1
    fi
    mkdir -p -- "$room/.roomstart/sessions" || return 1
    rs_state_write "$room" schema 1 missing || return 1
    [[ $(rs_state_get "$room" schema) == 1 ]] || { rs_error 'Versione stato non supportata.'; return 1; }
    rs_state_write "$room" port "$port" missing || return 1
    rs_state_write "$room" created "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" missing || return 1
)

rs_new_session() (
    local room=${1-} session key value started
    rs_state_safe "$room" || return 1
    room=$(cd -- "$room" && pwd -P) || return 1
    if [[ ! -d "$room/.roomstart/sessions" || -L "$room/.roomstart/sessions" ]]; then
        rs_error 'Cartella sessioni non inizializzata o non sicura.'
        return 1
    fi
    umask 077
    started=$(date -u '+%Y-%m-%dT%H:%M:%SZ') || return 1
    session=$(mktemp -d "$room/.roomstart/sessions/$(date -u '+%Y%m%dT%H%M%SZ')-XXXXXXXX") || return 1
    for key in target url port checkpoint; do
        value=$(rs_state_get "$room" "$key" '') || return 1
        printf '%s\n' "$value" > "$session/$key" || return 1
    done
    printf '%s\n' "$started" > "$session/started" || return 1
    rs_state_set "$room" last_session "${session##*/}" || return 1
    printf '%s\n' "$session"
)

rs_list_rooms() {
    local base=${1-} entry room name previous checkpoint
    [[ -d "$base" ]] || return 0
    printf '%-28s  %-32s  %s\n' 'ROOM' 'ULTIMA SESSIONE (UTC)' 'CHECKPOINT'
    for entry in "$base"/*; do
        [[ -d "$entry" && ( -f "$entry/notes.md" || -d "$entry/.roomstart" ) ]] || continue
        name=${entry##*/}
        room=$(rs_room_path "$base" "$name") || continue
        previous=$(rs_state_get "$room" last_session '-') || continue
        checkpoint=$(rs_state_get "$room" checkpoint '-') || continue
        # Imported text must not be able to send control codes to the terminal.
        previous=$(printf '%s' "$previous" | LC_ALL=C tr -d '\000-\037\177')
        checkpoint=$(printf '%s' "$checkpoint" | LC_ALL=C tr -d '\000-\037\177')
        printf '%-28s  %-32s  %s\n' "$name" "$previous" "$checkpoint"
    done
}
