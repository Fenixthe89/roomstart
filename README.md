# roomstart

Script per automatizzare la creazione e l'avvio del workspace per le room
di hacking/CTF (TryHackMe, HackTheBox, ecc.).

## Cosa fanno

- **newroom** crea la struttura di cartelle (`scans`, `loot`, `exploit`,
  `screenshots`) e un file `notes.md` con un template pronto all'uso.
- **roomstart** chiama `newroom`, apre Firefox, un terminale con un
  listener `nc` e un editor per le note, e — se lo configuri — le
  posiziona sullo schermo.

## Requisiti

- bash
- ambiente grafico **X11** (wmctrl e xdotool non funzionano su Wayland puro)
- `wmctrl`, `xdotool`, `qterminal`, `firefox`, `nc`, `nano`

`newroom` da solo non ha bisogno di ambiente grafico e funziona ovunque.

## Installazione

```bash
git clone <url-del-repo>
cd roomstart
chmod +x newroom roomstart install.sh
./install.sh
```

`install.sh` chiede dove creare le room, la porta del listener e,
facoltativamente, la disposizione delle finestre. Salva tutto in
`~/.config/roomstart/config.sh` (vedi `config.sh.example` per la lista
completa delle opzioni).

Per usare i comandi da qualsiasi cartella:

```bash
mkdir -p ~/.local/bin
ln -s "$(pwd)/newroom"   ~/.local/bin/newroom
ln -s "$(pwd)/roomstart" ~/.local/bin/roomstart
```

(assicurati che `~/.local/bin` sia nel tuo `PATH`)

## Uso

```bash
newroom NomeRoom      # crea solo la struttura di cartelle/note
roomstart NomeRoom    # crea la struttura e apre il workspace
```

## Configurazione

Tutte le opzioni sono in `~/.config/roomstart/config.sh`, generato da
`install.sh`. Puoi rilanciare `install.sh` in qualsiasi momento per
aggiornarla, oppure modificare il file a mano.
