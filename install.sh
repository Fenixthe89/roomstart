#!/bin/bash
# ============================================================
# Script: install.sh
# Scopo: crea/aggiorna la configurazione personale di
#        newroom e roomstart in ~/.config/roomstart/config.sh
# ============================================================

set -uo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/roomstart"
CONFIG_FILE="$CONFIG_DIR/config.sh"

echo "== Configurazione di newroom / roomstart =="
echo

mkdir -p "$CONFIG_DIR"

if [ -f "$CONFIG_FILE" ]; then
    echo "Trovata una configurazione esistente in:"
    echo "  $CONFIG_FILE"
    read -r -p "Vuoi ripartire da zero invece di modificarla? [y/N] " reset
    case "$reset" in
        [yY]*) ;;
        *)
            # shellcheck source=/dev/null
            source "$CONFIG_FILE"
            ;;
    esac
    echo
fi

# --- Cartella base delle room ---
default_base="${ROOMSTART_BASE:-$HOME/Rooms}"
read -r -p "Cartella dove creare le room [$default_base]: " base
base="${base:-$default_base}"
base="${base/#\~/$HOME}"

# --- Porta listener ---
default_port="${ROOMSTART_LISTENER_PORT:-4444}"
read -r -p "Porta di default per il listener nc [$default_port]: " port
port="${port:-$default_port}"

# --- Posizionamento finestre ---
echo
echo "roomstart puo' posizionare automaticamente le finestre di"
echo "Firefox, Notes, Listener e Terminale (richiede wmctrl e xdotool)."
echo "Le coordinate dipendono dal tuo monitor/risoluzione: puoi trovarle"
echo "spostando le finestre dove vuoi e leggendo i valori con 'wmctrl -lG'."
read -r -p "Vuoi configurarlo adesso? [y/N] " setup_layout

layout_enabled="${ROOMSTART_LAYOUT_ENABLED:-false}"
firefox_x="${ROOMSTART_FIREFOX_X:-800}";   firefox_y="${ROOMSTART_FIREFOX_Y:-0}"
firefox_w="${ROOMSTART_FIREFOX_W:-1400}";  firefox_h="${ROOMSTART_FIREFOX_H:-800}"
notes_x="${ROOMSTART_NOTES_X:-1400}";      notes_y="${ROOMSTART_NOTES_Y:-0}"
notes_w="${ROOMSTART_NOTES_W:-400}";       notes_h="${ROOMSTART_NOTES_H:-800}"
listener_x="${ROOMSTART_LISTENER_X:-0}";   listener_y="${ROOMSTART_LISTENER_Y:-800}"
listener_w="${ROOMSTART_LISTENER_W:-700}"; listener_h="${ROOMSTART_LISTENER_H:-280}"
main_x="${ROOMSTART_MAIN_X:-0}";           main_y="${ROOMSTART_MAIN_Y:-0}"
main_w="${ROOMSTART_MAIN_W:-700}";         main_h="${ROOMSTART_MAIN_H:-800}"

case "$setup_layout" in
    [yY]*)
        layout_enabled=true
        echo
        echo "Per ogni finestra inserisci: X Y LARGHEZZA ALTEZZA"
        echo "separati da spazio (invio vuoto = tieni il valore mostrato)."
        echo

        read -r -p "Terminale principale [$main_x $main_y $main_w $main_h]: " line
        [ -n "$line" ] && read -r main_x main_y main_w main_h <<< "$line"

        read -r -p "Listener           [$listener_x $listener_y $listener_w $listener_h]: " line
        [ -n "$line" ] && read -r listener_x listener_y listener_w listener_h <<< "$line"

        read -r -p "Firefox            [$firefox_x $firefox_y $firefox_w $firefox_h]: " line
        [ -n "$line" ] && read -r firefox_x firefox_y firefox_w firefox_h <<< "$line"

        read -r -p "Notes              [$notes_x $notes_y $notes_w $notes_h]: " line
        [ -n "$line" ] && read -r notes_x notes_y notes_w notes_h <<< "$line"
        ;;
    *)
         echo "Ok, mantengo la configurazione attuale del posizionamento automatico."
        ;;
esac

cat > "$CONFIG_FILE" << EOF
# Generato da install.sh il $(date +%Y-%m-%d)

ROOMSTART_BASE="$base"
ROOMSTART_NEWROOM=""
ROOMSTART_LISTENER_PORT=$port

ROOMSTART_LAYOUT_ENABLED=$layout_enabled

ROOMSTART_FIREFOX_X=$firefox_x
ROOMSTART_FIREFOX_Y=$firefox_y
ROOMSTART_FIREFOX_W=$firefox_w
ROOMSTART_FIREFOX_H=$firefox_h

ROOMSTART_NOTES_X=$notes_x
ROOMSTART_NOTES_Y=$notes_y
ROOMSTART_NOTES_W=$notes_w
ROOMSTART_NOTES_H=$notes_h

ROOMSTART_LISTENER_X=$listener_x
ROOMSTART_LISTENER_Y=$listener_y
ROOMSTART_LISTENER_W=$listener_w
ROOMSTART_LISTENER_H=$listener_h

ROOMSTART_MAIN_X=$main_x
ROOMSTART_MAIN_Y=$main_y
ROOMSTART_MAIN_W=$main_w
ROOMSTART_MAIN_H=$main_h
EOF

mkdir -p "$base"

echo
echo "Configurazione salvata in: $CONFIG_FILE"
echo "Cartella room: $base"
echo
echo "Se vuoi lanciare i comandi da qualsiasi cartella:"
echo "  chmod +x newroom roomstart"
echo "  mkdir -p ~/.local/bin"
echo "  ln -s \"\$(pwd)/newroom\"   ~/.local/bin/newroom"
echo "  ln -s \"\$(pwd)/roomstart\" ~/.local/bin/roomstart"
echo "(assicurati che ~/.local/bin sia nel tuo PATH)"
