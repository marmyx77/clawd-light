# Riaudit dell'estensione Codex dopo i fix

**Data:** 30 agosto 2026  
**Commit esaminato:** `bcc81833495229bcb6ec5bafa521dce9a87e96c0` (`bcc8183`)  
**Baseline del primo audit:** `5185072bdf2c6ce84c775c25ebb809edfd3f2e88` (`5185072`)  
**Delta esaminato:** 26 commit  
**Verdetto:** **non dichiarerei ancora chiusa l'estensione Codex**

## Sintesi esecutiva

I fix hanno risolto il difetto funzionale più visibile del primo audit: una macchina
con Codex e senza `~/.claude` può oggi creare una riga partendo da un processo
`codex` che tiene aperto il proprio rollout. Il disegno processo → descrittore →
`session_meta` → superficie è sostanzialmente corretto, fallisce chiuso quando non
riesce a provare i dati e distingue un risultato vuoto da un probe indisponibile.

Sono migliorati anche il vincolo `Harness.cannotReport`, l'installazione CLI, la
diagnostica, il focus per superficie e la copertura E2E senza hook. Il probe eseguito
durante questo riaudit ha visto rollout vivi sulle tre superfici promesse: CLI,
estensione VS Code e app ChatGPT.

Restano però **tre rilievi P1**:

1. un hook Codex può ancora sostituire il `cwd` provato dal rollout con un'altra
   cartella aperta nell'IDE;
2. il menu e il primo avvio installano e rimuovono soltanto gli hook Claude, mentre
   la CLI gestisce entrambi gli harness;
3. il raggruppamento usa solo il path e fonde local e remote — o due host remoti —
   quando hanno lo stesso percorso assoluto.

Il quarto rischio da trattare prima di una release è prestazionale: lo scanner
sincrono può bloccare il `MainActor` fino al timeout del comando, e viene chiamato
ogni cinque secondi.

La raccomandazione è quindi **go per continuare lo sviluppo, no-go per dichiarare
chiuso l'audit o pubblicare la matrice di supporto corrente come interamente
verificata**.

## Stato dei rilievi originali

| ID | Stato dopo i fix | Valutazione |
|---|---|---|
| COD-001 | **parziale, nucleo funzionale risolto** | La discovery solo-Codex funziona; l'ancoraggio del workspace può ancora essere sovrascritto da `/signal`. |
| COD-002 | **parziale** | Il click distingue le superfici, ma le capability della riga e alcune azioni continuano a derivare da `origin`, che per le sessioni scanner Codex resta `.editor`. |
| COD-003 | **parziale** | CLI, status, self-test ed errori sono per harness; primo avvio e menu restano Claude-only. |
| COD-004 | **parziale** | Esiste una vera E2E scanner-driven senza hook; mancano prove negative sulla correlazione e prove di piattaforma riproducibili per ogni superficie dichiarata. |
| COD-005 | **parziale** | Esiste un gate sul rollout reale, ma non un corpus di fixture versionate; il probe reale ha già mostrato una forma subagente non modellata. |
| REN-001 | **parziale** | Il comando di rimozione nel README è corretto; il remote Git è ancora `clawd-light.git`. |
| ROW-001 | **parziale** | La copertura del blocco e delle rinomine è cresciuta; resta un difetto di identità local/remote e mancano alcuni test di interazione richiesti. |
| SWIFT-001 | **aperto, non bloccante per Codex** | Tutti i target restano esplicitamente in Swift language mode 5. |

## Cosa considero risolto o ben impostato

### Discovery e liveness Codex non dipendono più da Claude

[`CodexProcessScanner`](../../Sources/LampBoardApp/Runtime/CodexProcessScanner.swift#L31)
parte dai processi `codex`, interroga i descrittori aperti con `lsof`, accetta solo
file `.jsonl` sotto la radice delle sessioni Codex, legge `session_meta` e ricava la
superficie dal percorso dell'eseguibile. Non scandisce l'intero archivio storico.

[`StateStore.adoptCodexSessions`](../../Sources/LampBoardApp/Runtime/StateStore.swift#L136)
adotta la sessione in stato `idle`, usa il `cwd` del file e riconcilia soltanto
l'harness Codex. Un probe `.unavailable` non cancella le righe: questa distinzione
evita di trasformare un timeout in una falsa conclusione di morte.

La E2E
[`CodexScannerSuite`](../../Sources/LampBoardE2E/CodexScannerSuite.swift#L5)
crea un rollout, avvia un vero processo chiamato `codex` che lo tiene aperto e
verifica la comparsa e la rimozione della riga senza chiamare `/signal`. Questo
chiude la falla strutturale della vecchia suite interamente hook-driven.

### La superficie viene dedotta da un fatto locale

[`CodexSurface`](../../Sources/LampBoardCore/Codex/CodexSurface.swift#L3) non usa
`originator` come enum chiuso. La scelta è corretta: quel campo è diagnostico e il
formato del transcript non è stabile. Il focus distingue app ChatGPT, estensione e
CLI in [`PanelActivation`](../../Sources/LampBoardApp/UI/PanelActivation.swift#L32).

Sul Mac della verifica, `/Applications/ChatGPT.app/Contents/Info.plist` dichiara:

```text
CFBundleIdentifier = com.openai.codex
CFBundleName       = ChatGPT
version            = 26.825.51511
```

Il bundle identifier usato dal codice è quindi corretto per la versione installata.

### Codex non può più diventare rosso per costruzione

[`StateReducer`](../../Sources/LampBoardCore/Reducer/StateReducer.swift#L195)
consulta ora `Harness.cannotReport` prima di applicare lo stato. La suite prova sia
che un segnale costruito apposta non renda Codex `.failed`, sia che Claude possa
ancora riportare un fallimento. Questa parte dell'invariante è chiusa.

### La CLI è finalmente per harness

`install-hooks`, `uninstall-hooks`, `status` e `self-test` ispezionano Codex
separatamente. In particolare
[`runUninstall`](../../Sources/LampBoardApp/CommandLineInstall.swift#L49) tenta
entrambi gli harness e restituisce errore se anche uno solo non viene rimosso. Gli
errori di [`HookInstaller`](../../Sources/LampBoardApp/Setup/HookInstaller.swift#L4)
nominano ora il file realmente coinvolto.

## Rilievi P1

### AUD2-001 — Un hook Codex può spostare la riga fuori dal workspace provato

**Impatto:** integrità della correlazione e focus verso il progetto sbagliato.  
**Stato:** riproducibile per lettura del flusso; non coperto dalla E2E corrente.

Il commento del codice afferma che il workspace resta quello con cui la riga è
stata ammessa e non quello del segnale. L'implementazione fa il contrario quando
il `cwd` del segnale corrisponde a una finestra IDE:

1. [`StateStore.handle`](../../Sources/LampBoardApp/Runtime/StateStore.swift#L358)
   risolve prima `signal.cwd` tramite i lock dell'editor;
2. il workspace già noto viene usato soltanto se quella risoluzione restituisce
   `nil` ([righe 411–417](../../Sources/LampBoardApp/Runtime/StateStore.swift#L411));
3. [`StateReducer`](../../Sources/LampBoardCore/Reducer/StateReducer.swift#L225)
   applica poi `.with(workspace: workspace)` alla sessione esistente.

Caso minimo:

```text
rollout della sessione S: cwd = /project-a
finestra IDE aperta:       /project-b
hook di S:                 cwd = /project-b
risultato corrente:        la riga S passa a /project-b
```

Non serve che il segnale crei una nuova riga: gli basta conoscere un `session_id`
già ammesso. La route `/signal` non è autenticata; il threat model può escludere un
processo ostile dello stesso utente, ma non può contemporaneamente affermare che
il payload non decide mai la destinazione.

La E2E alle
[`righe 171–223`](../../Sources/LampBoardE2E/CodexScannerSuite.swift#L171) invia un
hook con lo stesso `cwd` del rollout, quindi resta verde anche con questo difetto.

**Correzione richiesta:** per una sessione già nota con `harness == .codex`, il
workspace, il transcript e la superficie devono restare quelli dell'evidenza dello
scanner. L'hook può aggiornare soltanto lo stato e i dettagli del turno. Aggiungere
una E2E con rollout in A, finestra aperta in B e hook della stessa sessione in B;
la riga deve restare in A.

### AUD2-002 — Il lifecycle UI resta Claude-only

**Impatto:** l'installazione riuscita dipende dal percorso scelto dalla persona;
dal primo avvio Codex resta senza stati hook-driven.  
**Stato:** confermato in primo avvio, menu, stato del menu e reinstallazione.

La CLI gestisce due installer, ma l'app ne possiede uno solo:

- [`AppDelegate.shouldPromptForInstallation`](../../Sources/LampBoardApp/AppDelegate.swift#L126)
  consulta soltanto `HookInstaller()` e il prompt nomina esclusivamente
  `~/.claude/settings.json`;
- [`AppDelegate.promptForInstallation`](../../Sources/LampBoardApp/AppDelegate.swift#L201)
  installa soltanto Claude;
- [`PanelController.panelFlags`](../../Sources/LampBoardApp/UI/PanelController.swift#L197)
  espone un singolo `hooksInstalled`, calcolato sull'installer Claude;
- le azioni alle
  [`righe 673–713`](../../Sources/LampBoardApp/UI/PanelController.swift#L673)
  installano e rimuovono soltanto Claude;
- [`PanelRootView`](../../Sources/LampBoardApp/UI/PanelRootView.swift#L301) mostra
  esplicitamente “Install/Remove the hooks in/from Claude Code”.

Anche la reinstallazione quando cambia il message delivery consulta soltanto
Claude, alle
[`righe 621–628`](../../Sources/LampBoardApp/UI/PanelController.swift#L621). In
questo caso Codex non deve ricevere il listener Claude, ma lo stato UI deve comunque
restare per harness anziché derivare da un booleano unico.

**Correzione richiesta:** introdurre un coordinatore che restituisca lo stato e
l'esito per harness e usarlo da CLI, primo avvio e menu. Il risultato deve
distinguere almeno `not present`, `not installed`, `installed`, `partial failure` e,
per Codex, `trust unknown`. Un errore Codex durante `runInstall` oggi viene stampato
ma il comando restituisce comunque `0`
([righe 24–42](../../Sources/LampBoardApp/CommandLineInstall.swift#L24)); decidere e
documentare esplicitamente se il successo parziale debba avere un exit code
distinto.

### AUD2-003 — Due macchine con lo stesso path vengono fuse in una riga

**Impatto:** riga, click, slot, nome, hide e mute possono riferirsi alla macchina
sbagliata.  
**Stato:** difetto certo nel dominio; il test esistente prova soltanto `Workspace`.

[`Workspace`](../../Sources/LampBoardCore/Models/Workspace.swift#L9) include
correttamente `host` in `Equatable` e `Hashable` e dichiara che il medesimo path su
due macchine non deve collassare. Il raggruppamento annulla però quella proprietà:

```swift
let key = session.workspace.path
```

La chiave è usata in
[`ColumnLayout.group`](../../Sources/LampBoardCore/Models/ColumnLayout.swift#L317)
per il dizionario, l'id della riga, slot, alias e ordine delle conversazioni. Hide,
mute, drag e notifiche usano anch'essi solo `workspace.path`.

Il test chiamato “The same path on two hosts is two workspaces”
([`RemoteSessionsSuite`](../../Sources/LampBoardTests/RemoteSessionsSuite.swift#L126))
controlla soltanto che due valori `Workspace` siano diversi; non passa quei valori
a `ColumnLayout.render`. Oggi quindi:

```text
local:       /w/project
host node:   /w/project
risultato:   un solo blocco, workspace preso dal membro più urgente
```

Se cambia l'urgenza può cambiare anche la macchina rappresentata dal blocco.

**Correzione richiesta:** introdurre una chiave stabile `WorkspaceKey` composta da
host normalizzato e path normalizzato. Usarla in layout e preferenze, con migrazione
delle vecchie chiavi locali basate sul solo path. Il gate minimo deve renderizzare
local e due host remoti con lo stesso path e verificarne righe, slot, rename, hide,
mute e click indipendenti.

## Rilievi P2

### AUD2-004 — Lo scanner sincrono gira sul MainActor ogni cinque secondi

`StateStore` è `@MainActor`; [`poll()`](../../Sources/LampBoardApp/Runtime/StateStore.swift#L562)
chiama direttamente `adoptCodexSessions`, che chiama direttamente
`codexScanner.scan()`. Il probe esegue `lsof` in modo sincrono con timeout di cinque
secondi ([`CodexProcessScanner`](../../Sources/LampBoardApp/Runtime/CodexProcessScanner.swift#L56)).

[`Command.run`](../../Sources/LampBoardCore/System/Command.swift#L123) aspetta il
deadline, poi concede fino a due secondi dopo `terminate` e altri due dopo
`SIGKILL`. Il caso peggiore è quindi vicino a nove secondi di blocco del thread UI,
su un poll configurato ogni cinque secondi. Il codice stesso documenta che `lsof`
può fermarsi su descrittori collocati su mount non raggiungibili.

**Correzione richiesta:** eseguire il probe fuori dal `MainActor`, impedire due scan
contemporanei, applicare il risultato sul main actor e conservare l'ultimo risultato
valido quando il probe è indisponibile. Aggiungere un test con scanner iniettato che
rimane bloccato o restituisce `.unavailable`.

### AUD2-005 — Le capability della riga non rappresentano la superficie Codex

Le sessioni adottate dallo scanner sono costruite senza `origin`, quindi ricevono il
default `.editor`
([`StateStore`](../../Sources/LampBoardApp/Runtime/StateStore.swift#L139)).
[`ColumnRow.isTerminal`](../../Sources/LampBoardCore/Models/ColumnLayout.swift#L88)
dipende soltanto da `primary.origin`.

Di conseguenza una riga Codex CLI o ChatGPT locale soddisfa la condizione che mostra
“New conversation here”
([`TrafficLightRow`](../../Sources/LampBoardApp/UI/TrafficLightRow.swift#L331)).
L'azione prima attiva la superficie corretta, poi chiama sempre
`VSCodeFocuser.openNewConversation`
([`PanelController`](../../Sources/LampBoardApp/UI/PanelController.swift#L441)). Per
una sessione CLI il risultato può essere: terminale portato davanti e subito dopo
nuova conversazione aperta in VS Code.

**Correzione richiesta:** modellare capability esplicite per sessione/superficie,
per esempio `canFocus`, `canOpenEditorConversation`, `canOpenChat` e
`stateEvidence`. Non usare `origin` come sostituto. Il comando “New conversation
here” deve essere disponibile soltanto quando la superficie ospita davvero quel
tipo di conversazione.

### AUD2-006 — Il formato reale dei subagenti produce identità duplicate

Il probe reale ha restituito 11 evidenze su CLI, VS Code e ChatGPT, ma soltanto 10
`sessionId` distinti. Due rollout aperti dallo stesso processo avevano questa forma
sanitizzata:

```json
{"session_id":"P","id":"P","source":"vscode"}
{"session_id":"P","id":"C","source":{"subagent":{"other":"guardian"}}}
```

[`CodexSessionMetaReader`](../../Sources/LampBoardCore/Codex/CodexSessionMeta.swift#L56)
preferisce sempre `session_id` a `id` e legge `source` soltanto se è una stringa.
Il rollout del subagente viene quindi trasformato in una seconda evidenza della
sessione padre. Se arriva prima del rollout principale, può diventare il
`transcriptPath` e la sorgente dell'attività o del contesto mostrato per il padre.

La documentazione hook ufficiale specifica che nei hook dei subagenti `session_id`
è quello del padre e avverte che il formato del transcript può cambiare. Questo non
documenta il rollout come API, ma spiega perché assumere l'uguaglianza tra
`session_id` e `id` non è sicuro: [OpenAI, Hooks — common input fields](https://learn.chatgpt.com/docs/hooks#common-input-fields).

**Correzione richiesta:** rappresentare separatamente `id` del rollout,
`parentSessionId` e tipo della sorgente. Poi scegliere esplicitamente se ignorare i
rollout subagente o aggregarli al padre; in entrambi i casi deduplicare in modo
deterministico e preferire il rollout principale per transcript e contesto.
Aggiungere una fixture versionata con questa forma e una E2E con padre e figlio
aperti nello stesso processo.

### AUD2-007 — Il gate Codex non è deterministico e fallisce prima dello skip

[`check-contract.sh`](../../Scripts/check-contract.sh#L667) cerca il rollout più
recente sul computer locale. Questo è utile come smoke test, ma non sostituisce
fixture versionate in CI. Inoltre:

```bash
ROLLOUT="$(find "$CODEX_SESSIONS" ... | sort | tail -1)"
```

è eseguito sotto `set -euo pipefail`. Con una home senza `~/.codex/sessions`, la
prova negativa di questo riaudit termina con exit `1` prima di raggiungere il ramo
che dovrebbe stampare “skipped”.

Il gate controlla che esistano `session_id` **oppure** `id`, ma non controlla il
caso in cui entrambi esistano e differiscano, appena osservato nel runtime reale.

**Correzione richiesta:**

- gestire esplicitamente la directory assente prima di `find`;
- mantenere il probe sul rollout locale come smoke test;
- aggiungere un corpus piccolo di fixture versionate, comprese top-level,
  subagente e forme invalide;
- eseguire il parser di produzione sulle fixture, invece di duplicarne solo alcune
  assunzioni in Python;
- far fallire il gate quando un nuovo shape non è classificato.

### AUD2-008 — La matrice di supporto e alcune istruzioni sono più forti delle prove

Il README dichiara “Tested: yes” per CLI, VS Code e ChatGPT
([`README`](../../README.md#L101)), ma la E2E scanner-driven usa soltanto una copia
di `/usr/bin/tail` chiamata `codex`, quindi dimostra la superficie `commandLine`.
[`CodexSurfaceSuite`](../../Sources/LampBoardTests/CodexSurfaceSuite.swift#L4)
dimostra la classificazione di path, non il focus di vere finestre ChatGPT e VS
Code. Il probe reale di questa revisione dimostra discovery e classificazione sulle
tre superfici, non il click end-to-end.

La stessa tabella dice che il focus CLI è “declared unavailable” e il paragrafo
successivo dice che non viene deliberatamente alzato
([`README`](../../README.md#L139)); il codice ora tenta invece il focus via ancestry
([`PanelActivation`](../../Sources/LampBoardApp/UI/PanelActivation.swift#L55)).

Altre discrepanze:

- il primo avvio e la tabella permessi descrivono soltanto Claude, mentre la sezione
  installazione promette entrambi gli harness;
- la sezione di rimozione dice ancora che `uninstall-hooks` modifica solo
  `~/.claude/settings.json`, ma la CLI rimuove anche Codex;
- “nothing unauthenticated is believed” è troppo assoluto: un hook non autenticato
  può aggiornare lo stato di una sessione Codex già nota;
- non è presente nel repository un artefatto riproducibile dello smoke test dal
  bundle firmato citato nel piano. Il probe ripetuto qui usa il binario debug.

**Correzione richiesta:** separare nelle docs `unit tested`, `E2E deterministic`,
`runtime smoke-tested` e `focus platform-tested`. Aggiornare subito le righe CLI e
lifecycle, senza aspettare gli altri fix.

## Rilievi P3 e debito residuo

### AUD2-009 — La classificazione dell'estensione è troppo larga

[`CodexSurface.of`](../../Sources/LampBoardCore/Codex/CodexSurface.swift#L79)
classifica come `editorExtension` qualsiasi eseguibile il cui path contenga un
segmento `.vscode` o `.cursor`, anche fuori dalla struttura delle extension. Il
prefisso versionato `openai.chatgpt-` è un'evidenza migliore; i segmenti generici
possono classificare un binario autonomo dentro un progetto o una directory di
tooling. Restringere la regola alla struttura attesa e aggiungere fixture spoof.

### AUD2-010 — Rinomina e dettagli dell'installer restano incompleti

`git remote -v` punta ancora a:

```text
https://github.com/marmyx77/clawd-light.git
```

Il comando README con `Application Support` è stato corretto, e i riferimenti
legacy nel codice risultano intenzionali per la migrazione. Il nome del remote va
però risolto o dichiarato esplicitamente come eccezione a REN-001.

I backup Codex sono ancora chiamati
`settings.json.lampboard-backup-*`
([`HookInstaller`](../../Sources/LampBoardApp/Setup/HookInstaller.swift#L294)), anche
quando il file sorgente è `hooks.json`. Non rompe il contenuto, ma rende la
diagnostica meno chiara.

## Copertura test residua

La suite è ampia e ha guadagnato test importanti, ma i cancelli del piano non sono
tutti rappresentati da test indipendenti:

- nessun test di `ColumnLayout` usa lo stesso path su host diversi;
- nessun test Codex invia un hook con `cwd` diverso dal rollout;
- nessuna E2E usa una forma subagente con `session_id != id`;
- non c'è uno scanner iniettabile che provi `.unavailable` conservando le righe;
- la ricerca di `occupiedSlots` non trova test dedicati;
- mancano test combinati per slot, hide, mute e drag su un blocco che contiene
  entrambi gli harness;
- non c'è una prova automatica del click su finestre reali ChatGPT, estensione e
  terminale; una smoke manuale può essere ammessa, ma deve produrre un risultato
  conservato e versionato.

## Verifiche eseguite

| Verifica | Esito | Nota |
|---|---|---|
| `git diff --check` | **PASS** | Nessun errore di whitespace. |
| `./Scripts/check-docs.sh` | **PASS** | 10 controlli; 645 casi domain e 89 E2E dichiarati coerenti. |
| `.build/debug/LampBoardTests` | **PASS** | 645 test passati sul binario preesistente. |
| `.build/debug/LampBoardE2E --port 9899` | **PASS** | 89 test passati fuori sandbox, necessaria per listener loopback e processi. |
| `./Scripts/check-contract.sh` | **PASS con limite** | 11 controlli; parte `--live` saltata; rollout locale Codex 0.151.0-alpha.7.2 accettato. |
| `LampBoardApp codex-probe` | **PASS con rilievo** | Tre superfici osservate; emersa la duplicazione padre/subagente descritta in AUD2-006. |
| home senza `~/.codex/sessions` | **FAIL atteso, gate difettoso** | Exit 1 prima del messaggio di skip; conferma AUD2-007. |
| `./Scripts/test.sh` | **NON ESEGUIBILE dall'inizio** | Il build si ferma prima delle suite per toolchain/SDK incompatibili. |
| `./Scripts/bite.sh` | **INCOMPLETO** | 18/22 guardie dimostrate; 4 mutazioni non compilano a causa dello stesso problema toolchain. |

Il problema di build osservato è ambientale ma blocca una verifica pulita dei
sorgenti correnti:

```text
compiler: swiftlang-6.2.0.19.9
SDK:      swiftlang-6.2.0.17.14
errore:   this SDK is not supported by the compiler
```

I due binari di test preesistenti hanno timestamp coerente con l'ultimo commit e
passano, ma non equivalgono a una ricompilazione del checkout durante questo audit.
Prima della chiusura occorre riallineare Command Line Tools e SDK, poi rieseguire
`./Scripts/test.sh` interamente.

## Sequenza di correzione consigliata

### Onda 1 — Ripristinare le invarianti di identità

1. fissare il workspace Codex all'evidenza scanner e aggiungere la E2E con `cwd`
   discordante;
2. introdurre `WorkspaceKey(host, path)` e migrare tutte le preferenze per progetto;
3. modellare e deduplicare esplicitamente i rollout di subagente.

Questi tre interventi evitano destinazioni o transcript convincenti ma sbagliati.

### Onda 2 — Completare lifecycle e capability

1. creare il coordinatore di installazione per harness;
2. collegarlo a CLI, primo avvio, menu, status e self-test;
3. sostituire `origin` come gate delle azioni con capability per superficie;
4. definire l'exit code del successo parziale.

### Onda 3 — Rendere scanner e contratto resistenti

1. spostare lo scan fuori dal `MainActor` e coalescere i poll;
2. introdurre fixture versionate top-level/subagente/invalide;
3. riparare il caso directory assente nel gate;
4. aggiungere prove di indisponibilità e di più rollout per processo.

### Onda 4 — Allineare prove, README e rinomina

1. correggere immediatamente la matrice di supporto e le istruzioni lifecycle;
2. registrare smoke test di piattaforma distinti dalla E2E deterministica;
3. decidere il remote definitivo;
4. riallineare toolchain e SDK, poi ottenere un `./Scripts/test.sh` interamente
   verde.

## Gate di chiusura riscritti

L'estensione può essere dichiarata chiusa quando sono veri contemporaneamente
questi punti:

- [ ] con `~/.claude` assente, un rollout top-level aperto crea la riga corretta;
- [ ] un hook della stessa sessione non può cambiare workspace, transcript,
  harness o superficie;
- [ ] padre e subagente aperti non duplicano né sostituiscono la riga del padre;
- [ ] local e due host remoti con lo stesso path producono tre identità indipendenti;
- [ ] installazione, rimozione e stato UI dichiarano l'esito per entrambi gli
  harness;
- [ ] CLI, ChatGPT ed editor espongono soltanto azioni supportate dalla propria
  superficie;
- [ ] un probe lento o indisponibile non blocca l'interfaccia e non cancella righe;
- [ ] la E2E scanner-driven continua a non chiamare `/signal`;
- [ ] fixture versionate e smoke su rollout reale passano entrambe;
- [ ] ogni riga “Tested” del README indica quale livello di prova la sostiene;
- [ ] `./Scripts/test.sh` passa da un checkout pulito, inclusa la prova che i gate
  mordono.

## Fonti

### Contratto esterno

- [OpenAI — Hooks](https://learn.chatgpt.com/docs/hooks): eventi, campi comuni,
  semantica di `session_id` per subagenti e avvertenza che il transcript non è
  un'interfaccia stabile.
- [OpenAI — ChatGPT desktop app](https://learn.chatgpt.com/docs/app): superficie
  desktop distinta; la pagina non costituisce una garanzia che ogni superficie
  esegua gli stessi hook.

### Implementazione locale principale

- [`CodexProcessScanner.swift`](../../Sources/LampBoardApp/Runtime/CodexProcessScanner.swift)
- [`CodexSessionMeta.swift`](../../Sources/LampBoardCore/Codex/CodexSessionMeta.swift)
- [`CodexSurface.swift`](../../Sources/LampBoardCore/Codex/CodexSurface.swift)
- [`StateStore.swift`](../../Sources/LampBoardApp/Runtime/StateStore.swift)
- [`StateReducer.swift`](../../Sources/LampBoardCore/Reducer/StateReducer.swift)
- [`ColumnLayout.swift`](../../Sources/LampBoardCore/Models/ColumnLayout.swift)
- [`PanelActivation.swift`](../../Sources/LampBoardApp/UI/PanelActivation.swift)
- [`HookInstaller.swift`](../../Sources/LampBoardApp/Setup/HookInstaller.swift)
- [`CommandLineInstall.swift`](../../Sources/LampBoardApp/CommandLineInstall.swift)

### Test e gate locali

- [`CodexScannerSuite.swift`](../../Sources/LampBoardE2E/CodexScannerSuite.swift)
- [`CodexSessionMetaSuite.swift`](../../Sources/LampBoardTests/CodexSessionMetaSuite.swift)
- [`CodexSurfaceSuite.swift`](../../Sources/LampBoardTests/CodexSurfaceSuite.swift)
- [`ColumnLayoutSuite.swift`](../../Sources/LampBoardTests/ColumnLayoutSuite.swift)
- [`RemoteSessionsSuite.swift`](../../Sources/LampBoardTests/RemoteSessionsSuite.swift)
- [`check-contract.sh`](../../Scripts/check-contract.sh)
- [`check-docs.sh`](../../Scripts/check-docs.sh)
- [`test.sh`](../../Scripts/test.sh)
- [`bite.sh`](../../Scripts/bite.sh)

## Conclusione

Il cambio architetturale principale è valido: Codex ora può essere scoperto senza
Claude e senza hook, e questa è una correzione reale, non cosmetica. I fix non
chiudono ancora l'audit perché l'identità provata dallo scanner viene indebolita
dopo l'ammissione, il lifecycle grafico non è multi-harness e la chiave di progetto
perde l'host.

Chiuderei prima AUD2-001, AUD2-003 e AUD2-002, poi porterei lo scanner fuori dal
main actor. Solo dopo aggiornerei la matrice README a “yes” per le tre superfici.
