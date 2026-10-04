# roomstart

Un comando per aprire il tuo ambiente CTF: Firefox, terminale principale,
listener e note in finestre separate, con il layout che hai scelto.
Quando torni sulla stessa room, Roomstart conserva materiali, impostazioni
e registrazioni delle sessioni precedenti.

```bash
roomstart NomeRoom --target 10.10.10.20 --url https://tryhackme.com/room/esempio
# Alla prossima apertura:
roomstart NomeRoom
```

## Cosa cambia

- **Creazione e riapertura:** una room nuova riceve cartelle e modello delle
  note; una room esistente viene riaperta senza sovrascrivere il lavoro.
- **Impostazioni per room:** target, URL e porta del listener restano associati
  alla room. Le opzioni passate al comando aggiornano i valori salvati.
- **Sessioni registrate:** il terminale principale e il listener avviati da
  Roomstart salvano il proprio output mentre lavori.
- **Checkpoint:** lasci una frase su dove sei arrivato e la ritrovi nel
  riepilogo all'apertura.
- **Avvio ripetuto:** Roomstart riconosce i propri strumenti ancora attivi ed
  evita di avviarne altre copie; può riaprire quelli mancanti.

`newroom` rimane disponibile per creare soltanto cartelle e note. Ripetere
il comando sulla stessa room è sicuro: le note esistenti vengono conservate.

## Requisiti

Per aprire l'ambiente completo:

- Linux con Bash 4 o successivo e una sessione grafica **X11**.
- `firefox`, `qterminal`, `nano`, `nc`.
- `wmctrl`, `xdotool`, `xprop` per riconoscere e disporre le finestre.
- util-linux: `script` con supporto a `--log-out`, `flock` e `setsid`.
- iproute2: `ss` per verificare la porta del listener.
- I normali strumenti GNU di sistema, inclusi `readlink`, `mktemp` e `date`.

I nomi dei pacchetti dipendono dalla distribuzione: per esempio `nc` può
essere fornito da netcat-openbsd e `xprop` da x11-utils.
L'installer configura Roomstart; non installa pacchetti.

`newroom`, `--status`, `--list` e `--checkpoint` si possono usare senza
ambiente grafico. L'avvio completo non supporta Wayland puro, Windows
nativo o macOS. VS Code è facoltativo e serve soltanto se lo vuoi usare
per modificare il progetto.

## Installazione

```bash
git clone https://github.com/Fenixthe89/roomstart.git
cd roomstart
chmod +x roomstart newroom install.sh
./install.sh
```

L'installer chiede la cartella delle room, la porta predefinita e se vuoi
configurare il layout. Salva la configurazione in
`${XDG_CONFIG_HOME:-$HOME/.config}/roomstart/config.sh`.

Se la configurazione esiste, invio mantiene i valori attuali. Prima di
sostituirla viene creata una copia `config.sh.bak.*`. Un file malformato
viene segnalato e conservato: correggilo prima di ripetere l'installazione.
Anche il percorso personalizzato `ROOMSTART_NEWROOM` viene mantenuto.

Per usare i comandi da qualsiasi cartella:

```bash
mkdir -p ~/.local/bin
ln -s "$(pwd)/newroom" ~/.local/bin/newroom
ln -s "$(pwd)/roomstart" ~/.local/bin/roomstart
```

Assicurati che `~/.local/bin` sia nel tuo `PATH`. I collegamenti richiedono
che la cartella del progetto rimanga al suo posto. Se un collegamento
esiste già, verifica dove punta prima di sostituirlo.

## Uso

### Iniziare o riprendere

```bash
roomstart NomeRoom
roomstart NomeRoom --target 10.10.10.20 --url https://tryhackme.com/room/esempio --port 4444
```

La prima apertura crea la room usando la porta predefinita; target e URL
sono facoltativi. Le aperture successive recuperano i valori salvati.
Firefox apre il collegamento della room quando è disponibile.

Se la piattaforma assegna un indirizzo diverso:

```bash
roomstart NomeRoom --target 10.10.10.35
```

Questo aggiorna il target per il lavoro successivo; i dati delle sessioni
già registrate conservano i valori originali. Roomstart non modifica
automaticamente i tuoi comandi, file di scansione o appunti.

Una porta occupata da un altro processo viene segnalata: scegli una porta
libera con `--port`. Roomstart non termina processi estranei.

### Lasciare un checkpoint

```bash
roomstart NomeRoom --checkpoint "Controllare la directory trovata prima di continuare"
```

Il comando aggiorna il checkpoint senza aprire finestre. È un appunto
facoltativo: il salvataggio di configurazione e log non dipende da questo
passaggio. Il checkpoint esprime cosa vuoi ricordare; Roomstart non deduce
automaticamente se un tentativo ha avuto successo.

### Consultare senza aprire l'ambiente

```bash
roomstart --list
roomstart NomeRoom --status
roomstart --help
newroom NomeRoom
```

`--list` mostra le room presenti; `--status` mostra i dati salvati e lo
stato degli strumenti della room. Le consultazioni non avviano programmi
né creano una nuova sessione.

## Come sono conservati i dati

La struttura delle room rimane leggibile anche senza Roomstart:

```text
NomeRoom/
├── notes.md
├── scans/
├── loot/
├── exploit/
├── screenshots/
└── .roomstart/
    ├── target, url, port, checkpoint
    ├── created, last_session, schema
    ├── sessions/
    │   └── <identificativo-sessione>/
    │       └── ... dati della sessione e log dei terminali
    └── runtime/
        └── ... riferimenti agli strumenti attivi
```

I metadati della room sono file di testo, non comandi da eseguire.
Le vecchie cartelle create da `newroom` vengono adottate aggiungendo i
metadati mancanti: note e materiali rimangono al loro posto.

Per conservare o trasferire una room, copia l'intera cartella includendo
`.roomstart`. I file in `runtime` descrivono processi locali, non
connessioni o programmi trasferibili su un altro computer.

## Cosa significa riprendere

| Situazione | Risultato |
| --- | --- |
| Gli strumenti della room sono ancora aperti | Roomstart prova a riportare in primo piano le proprie finestre senza duplicarle. |
| Hai chiuso uno strumento | Alla riapertura può avviare quello mancante. |
| Hai chiuso tutto o riavviato Linux | Apre nuovi strumenti e recupera i file e le impostazioni conservati. |
| Una scansione o una shell remota si è interrotta | Il log rimane consultabile; l'attività non viene rieseguita e la connessione non viene ricreata. |

Questa versione non mantiene processi attivi attraverso il riavvio del
computer e non usa tmux. Lo stato salvato di una sessione non basta a
considerarla ancora attiva: contano i suoi processi effettivamente in vita.

Target, URL e porta si possono cambiare quando i terminali della room sono
chiusi. Se la room ha strumenti ancora attivi, Roomstart chiede di chiuderli
prima: le shell già aperte manterrebbero altrimenti le vecchie impostazioni.
Un checkpoint può invece essere aggiornato anche durante il lavoro.

## Note e registrazioni

Le nuove room usano un modello breve: target, appunti e risultati,
credenziali e flag, prossimo passo. Sono sezioni libere e facoltative.
Il target inserito all'avvio viene scritto automaticamente nel campo `IP:`.
Quando il target cambia, viene aggiornato soltanto quel campo; il resto delle
note viene conservato e una copia precedente rimane in `.roomstart/notes-backup.*`.
Le note già aperte in nano vengono lasciate intatte: l'aggiornamento avviene
alla riapertura dell'editor. I modelli lunghi delle vecchie room vengono conservati.

- Le note sono aperte con nano. **Salvale nell'editor**: i log non sono
  un autosalvataggio del testo ancora non salvato in nano.
- Viene registrato solo l'output dei terminali principali e dei listener
  avviati e gestiti da Roomstart. I terminali aperti autonomamente e
  l'attività del browser non vengono registrati.
- I log sono registrazioni del terminale: possono contenere colori ANSI,
  ritorni del cursore e schermate interattive. Non sono resoconti già
  ripuliti o pronti da pubblicare.
- La registrazione dell'output può includere comandi visibili, credenziali
  stampate, flag e risultati. Controlla i log prima di condividerli.
  L'input nascosto da un programma non viene registrato come flusso di input.
- Non è prevista una cancellazione automatica dei log: occupano spazio
  finché li conservi. Evita di rimuovere log o dati di runtime mentre
  quella room è ancora aperta.

## Configurazione del layout

Le opzioni esistenti rimangono disponibili in
[config.sh.example](config.sh.example). La configurazione personale è un
file Bash locale e va modificata solo con contenuti fidati.

`ROOMSTART_LAYOUT_ENABLED=true` abilita il posizionamento automatico.
Ogni finestra ha coordinate `X`, `Y`, `W`, `H`; le coordinate possono
essere negative su monitor secondari, larghezza e altezza devono essere
positive. I valori di esempio vanno adattati ai tuoi monitor.

Per misurare le finestre dopo averle disposte:

```bash
wmctrl -lG
```

Con layout disabilitato gli strumenti vengono comunque aperti, lasciando
il posizionamento al gestore delle finestre.

## Verifiche di sviluppo

Le verifiche automatiche coprono metadati, creazione non distruttiva,
lock dei processi, registrazione e CLI:

```bash
bash tests/test_state.sh
bash tests/test_runtime.sh
bash tests/test_cli.sh
bash tests/test_install.sh
```

La pipeline GitHub esegue questi controlli su Linux. Il posizionamento
reale delle finestre e il comportamento del desktop richiedono anche una
prova manuale in X11: apri una room, avviala una seconda volta, chiudi
uno strumento, riaprila e verifica che note e materiali restino presenti.

## Target nei comandi

Il terminale della room espone la variabile `IP`, valorizzata con il target salvato (IP o hostname). Esempio: `nmap -sV "$IP"`. Il valore viene ripristinato quando riapri la room; la variabile è disponibile nei terminali avviati da Roomstart.

## Comandi nella room (Bash e Zsh)

Il terminale mostra il checkpoint salvato all'apertura. Per aggiornarlo:

```bash
roomnext "Controllare il sito sulla porta 8080"
roomnote "Porta 8080: Tomcat"
roomtarget 10.10.10.25
nmap -sV "$IP"
```

`roomnote` salva appunti datati in `appunti.md`, separato da `notes.md` per non
perdere modifiche non salvate nell'editor. `roomtarget` aggiorna il target salvato
e `$IP` nella shell corrente; le altre shell e i comandi gi� in esecuzione
mantengono il valore precedente. Se Nano � aperto, il campo IP in `notes.md`
viene aggiornato al prossimo avvio dell'editor. Le registrazioni delle sessioni
conservano il target iniziale come riferimento storico.
Le cartelle `scans`, `loot`, `exploit` e `screenshots` sono gi� create da newroom.
