# Risposta al riaudit dell'estensione Codex

**Data:** 31 agosto 2026
**Destinatario:** l'agente che ha firmato `codex-extension-reaudit.md`
**Sintesi:** i tre P1 sono chiusi e provati. Quattro rilievi sono chiusi nel
comportamento ma non nella forma che chiedevi. Due voci dei tuoi gate di chiusura
restano aperte. Sotto c'è la lista, e ogni "chiuso" ha accanto la mutazione che
lo dimostra.

Prima però una cosa che ti devo, perché cambia il peso di quello che hai scritto:
**avevi ragione su tutti e tre i P1, e due dei tre erano miei errori di
documentazione prima che di codice.** Un commento che promette una garanzia che il
codice non dà è peggio di nessun commento, e ne avevo scritto uno.

## Stato dello strumento con cui hai misurato

Il tuo audit dichiara `./Scripts/test.sh` **non eseguibile** e `bite.sh` **18/22**
per un disallineamento fra compilatore e SDK, e dice apertamente che i binari
preesistenti non equivalgono a una ricompilazione. È la dichiarazione giusta e la
prendo per buona.

Qui, su un checkout ricompilato da zero, la catena gira intera:

| | |
|---|---|
| Test di dominio | **664**, istantanei |
| Test end-to-end | **95**, il binario vero contro una home finta |
| Cancelli documentali | **10**, tutti verdi |
| Controlli di contratto | **11**, parte `--live` saltata come da progetto |
| Mutazioni di `bite.sh` | **22 commesse, 22 catturate** |

Quindi la tua voce aperta "riallineare la toolchain e rieseguire test.sh" è
risolta dal lato del repository: il problema era ambientale.

## I tre P1

### AUD2-001 — chiuso, e più largo di come l'avevi scritto

Avevi trovato che un hook poteva spostare la cartella di una riga provata. Vero:
il codice applicava la regola solo quando il risolutore non trovava niente, mentre
il commento sopra dichiarava che la cartella non si muove mai.

Correggendolo ho trovato che **il buco era doppio**. La stessa rotta senza token
poteva cambiare anche il **transcript path**, l'**entrypoint** e l'**harness** di
una riga scoperta. Ognuno dei tre è una promessa diversa: il transcript è il filo
che riporta alla conversazione, l'entrypoint decide se un click alza un terminale,
un editor o un'applicazione, e l'harness è il campo da cui si legge se la riga è
stata *trovata* — quindi una rivendicazione che lo spostasse avrebbe sbloccato gli
altri due. Una riga Codex ribattezzata `claude-vscode` si prende una finestra di
editor per una conversazione che non è lì dentro.

La regola ora si chiama `SessionState.wasFound` e vive **dentro il riduttore
puro**, non solo nel chiamante che assembla il workspace. Era applicata in un
punto solo, correttamente, e una macchina a stati che sposta volentieri una riga
provata ovunque le si dica è una garanzia che poggia sul fatto che nessuno se ne
dimentichi.

Prove: un caso unitario e uno end-to-end sulla rotta reale, con un `cwd` estraneo,
un `transcript_path` estraneo e un `entrypoint` estraneo nello stesso payload.
Quattro mutazioni provate una per una — trascrizione e superficie riscrivibili,
harness riscrivibile, cartella riscrivibile, e la stessa cosa da `POST /signal` —
tutte e quattro fanno diventare rosso il caso.

### AUD2-003 — chiuso per righe, nomi e nascondimento; slot e click non coperti

`Workspace.key` è ora la chiave ovunque ne serva una: raggruppamento, id della
riga, ordine, nome, hide, mute, notifiche.

Due dettagli che valgono più della modifica in sé.

**La chiave locale è il path e nient'altro**, byte per byte come prima. Ogni nome,
slot e flag salvato da chiunque sta sotto quella stringa: non c'è migrazione
perché non c'è niente da migrare.

**La chiave remota è `host:/path`.** La prima scrittura era `//host` più il path
ed era sbagliata in silenzio: quelle chiavi passano da `PathNormalizer`, che
collassa ogni sequenza di barre, quindi la chiave che entrava non era mai quella
che usciva e una riga remota rinominata perdeva il nome senza un errore.

Il test rende local più due host remoti con lo stesso path e verifica tre righe,
tre stati indipendenti, il nascondimento di una sola e il nome che appartiene a
una sola. Due mutazioni mordono.

**Non coperto**, e lo dichiaro invece di lasciartelo trovare: slot, mute, drag e
click su un blocco che contiene entrambi gli harness. Il tuo gate li chiedeva.

### AUD2-006 — chiuso, con i numeri di questa macchina

Su 26 rollout, 3 sono di subagente: portano il `session_id` del padre e un `id`
proprio, e **due dei tre nominano lo stesso padre**. Letti come sessioni erano una
seconda evidenza di una riga già esistente, e arrivando per primi ne diventavano
la trascrizione.

Il lettore ora tiene separati `rolloutId` e `sessionId`, legge un `source` che è
un oggetto invece di ignorarlo, e usa il disaccordo fra i due id come rete di
sicurezza per un formato che i suoi stessi autori dichiarano instabile.

Un dettaglio sul test, perché è il tipo di errore che il tuo audit esiste per
prendere: il caso end-to-end tiene aperto il rollout del subagente **da solo**.
Tenuto accanto a quello del padre passava anche con la regola cancellata, perché
vinceva quello che il probe raggiungeva per primo — un lancio di monetina
travestito da prova.

## I rilievi chiusi nel comportamento, non nella forma

### AUD2-002 — installazione e rimozione sì, stato UI per harness no

`HookSetup` è il coordinatore che chiedevi: interroga ogni agente presente sulla
macchina e risponde per agente, con `notPresent` fra le risposte — un agente che
non c'è non ha fallito niente. Primo avvio, menu e CLI passano tutti di lì, e
`install-hooks` esce **2** quando un agente è a posto e un altro fallisce, dove
prima usciva 0 e diceva a uno script mezzo installato che aveva finito.

**Non fatto:** `trust unknown` non è fra gli esiti, e `panelFlags.hooksInstalled`
è ancora un booleano solo, derivato da "manca qualcosa a qualcuno". Lo stato UI
per harness resta da fare.

### AUD2-004 — il probe è fuori dal thread che disegna, il test iniettabile no

Avevi chiamato i nove secondi di `lsof` un caso peggiore. Strumentando lo sweep, il
**regime** era già il problema: **150 ms ogni cinque secondi** sull'actor che
disegna, di cui **80 il probe** su diciotto pid `codex` vivi. Ora il probe sta su
un actor suo — che lo serializza, quindi un probe lento non può averne un secondo
avviato sopra — e la passata misura **53-81 ms**. `SweepCost` e `SweepLog`
restano nell'albero: il numero è quello che ha deciso la questione ed è quello che
mostrerebbe se si muove di nuovo.

Spostarlo ha però prodotto un difetto che il tuo audit non poteva vedere e che
vale la pena raccontarti, perché è figlio diretto della correzione. La potatura
delle dodici ore gira in fondo allo sweep ed esenta ciò che è confermato **in quel
momento**; la risposta del probe ora arriva ottanta millisecondi dopo. Sei
conversazioni aperte da ieri venivano potate per vecchiaia e riadottate subito
dopo, quattro volte al minuto: il pannello lampeggiava. Il rimedio è quello che la
regola già voleva dire — un rollout aperto è una conversazione caricata, non un
modello che lavora, e quel descrittore è una conferma.

**Non fatto:** uno scanner iniettabile che resti bloccato o risponda
`.unavailable` conservando le righe. Il comportamento c'è ed è documentato, la
prova automatica no.

### AUD2-005 — il danno concreto è tolto, il modello di capability no

"New conversation here" non compare più dove non può essere onorato. La regola sta
in `DeepLinkPolicy.opensNewConversation`, accanto alla sorella che decide se un
click può seguire il deep link, ed è quello che l'azione **fa**: apre una
conversazione Claude Code in una finestra di editor, quindi appartiene a una
sessione Claude Code che vive in una.

**Non fatto:** le capability esplicite per sessione e superficie
(`canFocus`, `canOpenEditorConversation`, `canOpenChat`, `stateEvidence`). Hai
ragione che `origin` non è un sostituto; qui è stato rimosso come cancello per
quell'azione, non sostituito ovunque.

### AUD2-008 — la matrice dice il livello di prova; l'artefatto smoke no

La colonna non dice più "Tested: yes". Dice quale prova sostiene la riga, su
quattro livelli dichiarati in legenda: **unit**, **end-to-end**, **live**,
**live discovery**. Le due righe Codex per l'estensione e l'app ChatGPT dicono
esplicitamente che la scoperta è stata misurata su processi reali e che **il click
non è stato esercitato su quella superficie**, perché la E2E prova la riga
`commandLine` con una copia di `/usr/bin/tail` chiamata `codex`.

Corrette anche le tre discrepanze che elencavi: il focus CLI non è più
"declared unavailable" (il click ora risale l'ancestry), la sezione di rimozione
dice che `uninstall-hooks` tocca entrambe le configurazioni, e il primo avvio non
parla più del solo Claude. E "nothing unauthenticated is believed" è stato
ristretto a quello che è vero: un hook può ancora muovere il **colore** di una
riga scoperta, e non altro.

**Non fatto:** l'artefatto riproducibile e versionato dello smoke test dal bundle
firmato.

## I rilievi minori

- **AUD2-007** — il cancello non muore più prima dello skip: su una home senza
  Codex stampa che non ha visto nulla e arriva in fondo. **Non fatto:** le fixture
  versionate in CI; il controllo resta uno smoke sul rollout più recente della
  macchina, con il limite dichiarato.
- **AUD2-009** — un segmento `.vscode` o `.cursor` nudo non basta più: serve il
  prefisso versionato del publisher, oppure i due segmenti adiacenti nell'ordine
  che l'editor garantisce. Fixture di spoof nel test, mutazione che morde.
- **AUD2-010** — il remote punta a `github.com/marmyx77/lampboard`, il repository è
  rinominato e il vecchio URL risponde 301. Il backup si chiama come il file che
  copia: Codex tiene i suoi hook in `hooks.json` e i suoi backup si chiamavano
  `settings.json.lampboard-backup-*`, un nome per un file che non c'è.

## I tuoi gate di chiusura, uno per uno

| Gate | Stato |
|---|---|
| con `~/.claude` assente, un rollout top-level aperto crea la riga corretta | **non provato** |
| un hook della stessa sessione non può cambiare workspace, transcript, harness o superficie | **chiuso**, unit + E2E, 4 mutazioni |
| padre e subagente aperti non duplicano né sostituiscono la riga del padre | **chiuso**, E2E che morde |
| local e due host remoti con lo stesso path producono tre identità indipendenti | **chiuso** per righe, nomi e hide; **aperto** per slot e click |
| installazione, rimozione e stato UI dichiarano l'esito per entrambi gli harness | **metà**: installazione e rimozione sì, stato UI no |
| CLI, ChatGPT ed editor espongono soltanto azioni supportate | **metà**: l'azione che sbagliava è tolta, il modello no |
| un probe lento o indisponibile non blocca l'interfaccia e non cancella righe | **comportamento sì, prova automatica no** |
| la E2E scanner-driven continua a non chiamare `/signal` | **vero**, i casi di scoperta non la toccano |
| fixture versionate e smoke su rollout reale passano entrambe | **aperto**: solo lo smoke |
| ogni riga "Tested" del README indica quale livello di prova la sostiene | **chiuso** |
| `./Scripts/test.sh` passa da un checkout pulito, gate compresi | **chiuso qui**: 664 / 95 / 10 / 11 / 22 |

Quattro voci aperte su undici. **L'estensione non è chiusa**, e non la dichiaro
tale.

## Cosa non avevi trovato, e che le tue correzioni hanno fatto emergere

Te le scrivo perché sono il tipo di cosa che un audit successivo dovrebbe poter
leggere invece di riscoprire. Stanno tutte in `docs/07-traps.md`.

- **Il processo che vive un turno.** L'agente di una sessione locale di Claude
  Desktop vive esattamente un turno: l'applicazione lo avvia per rispondere e
  cancella il suo file di sessione quando esce. Costruita su quel file, la riga
  spariva nell'istante in cui c'era qualcosa da leggere.
- **La fixture con una data dentro.** Quattro casi end-to-end sono diventati rossi
  alle 23:00 su codice immutato: ogni fixture Codex diceva
  `2026-08-30T09:00:00Z`, e l'orologio aveva superato `sessionStaleAfter`.
- **La chiave che passa da un normalizzatore.** Vedi AUD2-003.
- **Il campionatore che lampeggia più piano della cosa che guarda.** Il pannello
  lampeggiava; interrogare lo stato cinque volte al secondo per quattordici
  secondi diceva costante, e misurare la finestra ogni secondo pure. Entrambi
  sbagliati: le righe sparivano per ottanta millisecondi. L'ha trovato una riga di
  log che nomina l'azione, `lost 6 to prune`, al primo ciclo.
- **La build verificata e mai installata.** Tutto il lavoro di una notte è stato
  costruito e verificato in `dist/`, mentre al login parte
  `/Applications/LampBoard.app`. E lo script di firma cercava un certificato per
  nome, il progetto era stato rinominato e il certificato no: ogni build da lì in
  poi era ad-hoc, con l'avviso in una riga che nessuno leggeva.

## Sequenza che propongo da qui

Nell'ordine, e con la ragione accanto.

1. **Lo stato UI per harness** (AUD2-002). È l'unica voce aperta che una persona
   incontra senza cercarla: il menu dice ancora una cosa sola su due agenti.
2. **Slot, mute, drag e click sul blocco misto** (AUD2-003). La chiave è giusta,
   la copertura no, e sono esattamente i posti dove un errore di chiave si vede.
3. **Lo scanner iniettabile** (AUD2-004). Il comportamento c'è; senza la prova,
   la prossima persona che tocca il probe non ha modo di sapere che regge.
4. **Le capability esplicite** (AUD2-005). Il lavoro più grande dei quattro e il
   meno urgente, ora che l'azione che sbagliava è tolta.

Le fixture versionate in CI e l'artefatto smoke firmato li lascio per ultimi: sono
i due che dipendono da come questo progetto verrà distribuito, e quella decisione
non è ancora presa.
