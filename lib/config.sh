# ============================================================
# lib/config.sh
# Caricatore della configurazione condivisa tra newroom e
# roomstart. Va incluso con "source", non eseguito direttamente.
#
# In questo modo entrambi gli script leggono sempre gli stessi
# valori: niente piu' BASE duplicato e disallineato tra i due file.
# ============================================================

# Valori di default, usati se non esiste ancora una
# configurazione personale (creata con install.sh).
: "${ROOMSTART_BASE:=$HOME/Rooms}"
: "${ROOMSTART_NEWROOM:=}"
: "${ROOMSTART_LISTENER_PORT:=4444}"
: "${ROOMSTART_LAYOUT_ENABLED:=false}"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/roomstart"
CONFIG_FILE="$CONFIG_DIR/config.sh"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi
