#!/usr/bin/env bash
# X11 windows are owned through an opaque property, never by title alone.

rs_window_ids() {
    wmctrl -lx | awk '{print $1}'
}

rs_window_remember() {
    local roomdir=$1 role=$2 id=$3 token tmp
    rs_runtime_regular "$roomdir/.roomstart/runtime/$role.window" || return 1
    [[ $id =~ ^(0x)?[[:xdigit:]]+$ ]] || return 1
    xprop -id "$id" WM_CLASS >/dev/null 2>&1 || return 1
    token="roomstart-${BASHPID}-${RANDOM}-${RANDOM}"
    xprop -id "$id" -f _ROOMSTART_OWNER 8s -set _ROOMSTART_OWNER "$token" >/dev/null 2>&1 || return 1
    tmp=$(mktemp "$roomdir/.roomstart/runtime/.window.XXXXXX") || return 1
    printf '%s\n%s\n' "$id" "$token" > "$tmp" &&
        mv -fT -- "$tmp" "$roomdir/.roomstart/runtime/$role.window"
}

rs_window_get() {
    local roomdir=$1 role=$2 record id token property
    record="$roomdir/.roomstart/runtime/$role.window"
    [[ -f $record && ! -L $record ]] || return 1
    { IFS= read -r id; IFS= read -r token; } < "$record" || return 1
    [[ $id =~ ^(0x)?[[:xdigit:]]+$ && $token =~ ^roomstart-[0-9]+-[0-9]+-[0-9]+$ ]] || return 1
    property=$(xprop -id "$id" _ROOMSTART_OWNER 2>/dev/null) || return 1
    [[ $property == "_ROOMSTART_OWNER(STRING) = \"$token\"" ]] || return 1
    printf '%s\n' "$id"
}

rs_window_new() {
    local before=$1 class=$2 title=${3:-} attempt id desktop wmclass host rest count
    local -a matches
    for ((attempt=0; attempt<40; attempt++)); do
        matches=()
        while read -r id desktop wmclass host rest; do
            [[ ${wmclass,,} == *"${class,,}"* ]] || continue
            [[ -z $title || $rest == "$title" ]] || continue
            if ! grep -Fxq -- "$id" <<< "$before"; then matches+=("$id"); fi
        done < <(wmctrl -lx 2>/dev/null)
        count=${#matches[@]}
        if ((count == 1)); then
            printf '%s\n' "${matches[0]}"
            return 0
        elif ((count > 1)); then
            return 1
        fi
        sleep 0.1
    done
    return 1
}

rs_window_layout() {
    local roomdir=$1 role=$2 id prefix xvar yvar wvar hvar
    [[ ${ROOMSTART_LAYOUT_ENABLED:-false} == true ]] || return 0
    id=$(rs_window_get "$roomdir" "$role") || return 0
    case $role in
        browser) prefix=FIREFOX ;;
        main) prefix=MAIN ;;
        listener) prefix=LISTENER ;;
        notes) prefix=NOTES ;;
        *) return 1 ;;
    esac
    xvar="ROOMSTART_${prefix}_X"; yvar="ROOMSTART_${prefix}_Y"
    wvar="ROOMSTART_${prefix}_W"; hvar="ROOMSTART_${prefix}_H"
    wmctrl -i -r "$id" -b remove,maximized_vert,maximized_horz || return 1
    wmctrl -i -r "$id" -e "0,${!xvar},${!yvar},${!wvar},${!hvar}"
}

rs_window_focus() {
    local id
    id=$(rs_window_get "$1" "$2") || return 1
    wmctrl -i -a "$id"
}
