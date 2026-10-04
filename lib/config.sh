# Shared configuration. Source this file and check its return status.
# Only the user's own config.sh is executable Bash. Room metadata is plain text.

: "${ROOMSTART_BASE:=$HOME/Rooms}"
: "${ROOMSTART_NEWROOM:=}"
: "${ROOMSTART_LISTENER_PORT:=4444}"
: "${ROOMSTART_LAYOUT_ENABLED:=false}"

: "${ROOMSTART_FIREFOX_X:=800}"
: "${ROOMSTART_FIREFOX_Y:=0}"
: "${ROOMSTART_FIREFOX_W:=1400}"
: "${ROOMSTART_FIREFOX_H:=1315}"
: "${ROOMSTART_NOTES_X:=2177}"
: "${ROOMSTART_NOTES_Y:=0}"
: "${ROOMSTART_NOTES_W:=372}"
: "${ROOMSTART_NOTES_H:=1243}"
: "${ROOMSTART_LISTENER_X:=10}"
: "${ROOMSTART_LISTENER_Y:=1059}"
: "${ROOMSTART_LISTENER_W:=813}"
: "${ROOMSTART_LISTENER_H:=282}"
: "${ROOMSTART_MAIN_X:=10}"
: "${ROOMSTART_MAIN_Y:=97}"
: "${ROOMSTART_MAIN_W:=812}"
: "${ROOMSTART_MAIN_H:=988}"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/roomstart"
CONFIG_FILE="$CONFIG_DIR/config.sh"

roomstart_config_validate() {
    local key value role axis
    if [[ -z $ROOMSTART_BASE || $ROOMSTART_BASE == *$'\n'* || $ROOMSTART_BASE == *$'\r'* ]]; then
        printf 'Errore: ROOMSTART_BASE deve essere un percorso non vuoto su una sola riga.\n' >&2
        return 1
    fi
    if [[ $ROOMSTART_NEWROOM == *$'\n'* || $ROOMSTART_NEWROOM == *$'\r'* ]]; then
        printf 'Errore: ROOMSTART_NEWROOM deve essere un percorso su una sola riga.\n' >&2
        return 1
    fi
    if [[ ! $ROOMSTART_LISTENER_PORT =~ ^[0-9]{1,5}$ ]] ||
       (( 10#$ROOMSTART_LISTENER_PORT < 1 || 10#$ROOMSTART_LISTENER_PORT > 65535 )); then
        printf 'Errore: ROOMSTART_LISTENER_PORT deve essere compresa tra 1 e 65535.\n' >&2
        return 1
    fi
    case $ROOMSTART_LAYOUT_ENABLED in
        true|false) ;;
        *) printf 'Errore: ROOMSTART_LAYOUT_ENABLED deve essere true oppure false.\n' >&2; return 1 ;;
    esac
    for role in FIREFOX NOTES LISTENER MAIN; do
        for axis in X Y W H; do
            key="ROOMSTART_${role}_${axis}"
            value=${!key}
            if [[ ! $value =~ ^-?[0-9]{1,6}$ ]]; then
                printf 'Errore: %s deve essere un numero intero (massimo sei cifre).\n' "$key" >&2
                return 1
            fi
            if [[ $axis == W || $axis == H ]]; then
                if [[ $value == -* ]] || (( 10#$value < 1 )); then
                    printf 'Errore: %s deve essere maggiore di zero.\n' "$key" >&2
                    return 1
                fi
            fi
        done
    done
}

if [[ -e $CONFIG_FILE || -L $CONFIG_FILE ]]; then
    if [[ ! -f $CONFIG_FILE || ! -r $CONFIG_FILE ]] || ! bash -n "$CONFIG_FILE"; then
        printf 'Errore: configurazione illeggibile o non valida: %s\n' "$CONFIG_FILE" >&2
        return 1
    fi
    # shellcheck source=/dev/null
    if ! source "$CONFIG_FILE"; then
        printf 'Errore durante il caricamento della configurazione: %s\n' "$CONFIG_FILE" >&2
        return 1
    fi
fi

roomstart_config_validate
