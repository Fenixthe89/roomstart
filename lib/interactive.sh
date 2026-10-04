# Sourced only by the room's interactive Bash or Zsh.
roomnote() {
    [[ $# -gt 0 ]] || { printf 'Uso: roomnote "Appunto"\n'; return 2; }
    bash "$ROOMSTART_HELPER" note "$*"
}
roomtarget() {
    [[ $# == 1 ]] || { printf 'Uso: roomtarget IP-o-hostname\n'; return 2; }
    bash "$ROOMSTART_HELPER" target "$1" || return
    export IP="$1" ROOMSTART_TARGET="$1"
}
roomnext() {
    [[ $# -gt 0 ]] || { printf 'Uso: roomnext "Prossimo passo"\n'; return 2; }
    bash "$ROOMSTART_HELPER" next "$*"
}
printf '\nRoomstart: IP=%s\n' "${IP:-non impostato}"
if [[ -s "$ROOMSTART_ROOM/.roomstart/checkpoint" ]]; then
    printf 'Prossimo passo: '; cat -- "$ROOMSTART_ROOM/.roomstart/checkpoint"; printf '\n'
fi
printf 'Appunti: roomnote "testo" | Promemoria: roomnext "testo" | Target: roomtarget IP\n\n'
