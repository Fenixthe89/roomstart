#!/usr/bin/env bash
# Configures Roomstart without installing software or changing shell startup files.
set -uo pipefail

SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}") || exit 1
SCRIPT_DIR=$(dirname -- "$SCRIPT_PATH") || exit 1
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh" || exit 1

read_answer() {
    if ! IFS= read -r -p "$1" REPLY; then
        printf '\nConfigurazione annullata: input terminato. Nessun file di configurazione modificato.\n' >&2
        exit 1
    fi
}

read_geometry() {
    local role=$1 label=$2 key current line extra x y w h
    local -a parts=()
    for key in X Y W H; do
        key="ROOMSTART_${role}_${key}"
        parts+=("${!key}")
    done
    current="${parts[*]}"
    while true; do
        read_answer "$label [$current]: "
        line=${REPLY:-$current}
        read -r x y w h extra <<< "$line"
        if [[ -z ${extra:-} && ${x:-} =~ ^-?[0-9]{1,6}$ && ${y:-} =~ ^-?[0-9]{1,6}$ &&
              ${w:-} =~ ^[0-9]{1,6}$ && ${h:-} =~ ^[0-9]{1,6}$ ]] &&
           (( 10#$w > 0 && 10#$h > 0 )); then
            printf -v "ROOMSTART_${role}_X" '%s' "$x"
            printf -v "ROOMSTART_${role}_Y" '%s' "$y"
            printf -v "ROOMSTART_${role}_W" '%s' "$w"
            printf -v "ROOMSTART_${role}_H" '%s' "$h"
            return
        fi
        printf 'Inserisci quattro interi: X Y LARGHEZZA ALTEZZA. Larghezza e altezza devono essere positive.\n' >&2
    done
}

printf '== Configurazione di newroom / roomstart ==\n\n'
if [[ -f $CONFIG_FILE ]]; then
    printf 'Aggiorno la configurazione esistente: %s\n' "$CONFIG_FILE"
    printf 'Invio mantiene il valore attuale. Verrà conservata una copia del file precedente.\n\n'
fi

read_answer "Cartella dove creare le room [$ROOMSTART_BASE]: "
base=${REPLY:-$ROOMSTART_BASE}
case $base in
    '~') base=$HOME ;;
    '~/'*) base="$HOME/${base:2}" ;;
esac
ROOMSTART_BASE=$base

while true; do
    read_answer "Porta di default per il listener nc [$ROOMSTART_LISTENER_PORT]: "
    port=${REPLY:-$ROOMSTART_LISTENER_PORT}
    if [[ $port =~ ^[0-9]{1,5}$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 )); then
        ROOMSTART_LISTENER_PORT=$((10#$port))
        break
    fi
    printf 'La porta deve essere un numero tra 1 e 65535.\n' >&2
done

printf '\nLe coordinate del layout dipendono dai monitor; puoi leggerle con wmctrl -lG.\n'
printf 'Layout attuale: %s.\n' "$ROOMSTART_LAYOUT_ENABLED"
while true; do
    read_answer 'Configurare il layout? [s = configura, n = disabilita, invio = mantieni]: '
    case $REPLY in
        [sSyY]|[sS][iI]|[yY][eE][sS])
            ROOMSTART_LAYOUT_ENABLED=true
            printf 'Per ogni finestra inserisci X Y LARGHEZZA ALTEZZA; invio mantiene i valori.\n'
            read_geometry MAIN 'Terminale principale'
            read_geometry LISTENER 'Listener'
            read_geometry FIREFOX 'Firefox'
            read_geometry NOTES 'Note'
            break ;;
        [nN]|[nN][oO]) ROOMSTART_LAYOUT_ENABLED=false; break ;;
        '') break ;;
        *) printf 'Scegli s, n oppure premi invio.\n' >&2 ;;
    esac
done

roomstart_config_validate || exit 1
umask 077
mkdir -p -- "$ROOMSTART_BASE" "$CONFIG_DIR" || {
    printf 'Errore: impossibile creare la cartella delle room o della configurazione.\n' >&2
    exit 1
}
tmp=$(mktemp "$CONFIG_FILE.tmp.XXXXXX") || exit 1
trap 'if [[ -n ${tmp:-} ]]; then rm -f -- "$tmp"; fi' EXIT

write_config() {
    local key
    printf '# Configurazione Roomstart. File Bash locale: modifica solo contenuti fidati.\n' || return
    for key in ROOMSTART_BASE ROOMSTART_NEWROOM ROOMSTART_LISTENER_PORT ROOMSTART_LAYOUT_ENABLED \
               ROOMSTART_FIREFOX_X ROOMSTART_FIREFOX_Y ROOMSTART_FIREFOX_W ROOMSTART_FIREFOX_H \
               ROOMSTART_NOTES_X ROOMSTART_NOTES_Y ROOMSTART_NOTES_W ROOMSTART_NOTES_H \
               ROOMSTART_LISTENER_X ROOMSTART_LISTENER_Y ROOMSTART_LISTENER_W ROOMSTART_LISTENER_H \
               ROOMSTART_MAIN_X ROOMSTART_MAIN_Y ROOMSTART_MAIN_W ROOMSTART_MAIN_H; do
        printf '%s=%q\n' "$key" "${!key}" || return
    done
}

if ! write_config > "$tmp" || ! bash -n "$tmp"; then
    printf 'Errore: impossibile scrivere una configurazione valida.\n' >&2
    exit 1
fi
if [[ -f $CONFIG_FILE ]]; then
    backup=$(mktemp "$CONFIG_FILE.bak.$(date +%Y%m%d-%H%M%S).XXXXXX") || exit 1
    cp -p -- "$CONFIG_FILE" "$backup" || {
        printf 'Errore: backup non riuscito; configurazione precedente conservata.\n' >&2
        exit 1
    }
    printf 'Backup precedente: %s\n' "$backup"
fi
mv -f -- "$tmp" "$CONFIG_FILE" || exit 1
tmp=''

printf '\nConfigurazione salvata in: %s\nCartella room: %s\n' "$CONFIG_FILE" "$ROOMSTART_BASE"
printf '\nPer usare i comandi da qualsiasi cartella, consulta la sezione Installazione del README.\n'
