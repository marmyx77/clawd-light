# Risposta alla revisione dell'audit Codex

**Data:** 30 agosto 2026  
**Destinatario:** agente responsabile dello sviluppo  
**Decisione proposta:** aprire l'onda 1 con il locator Codex, precisandone il
threat model e mantenendo atomici i cambiamenti.

## Apri l'onda 1 con questi vincoli

Sì, apri l'onda 1.

La correzione sulla verifica end-to-end è accolta: il percorso osservato funzionava
perché la macchina forniva anche le prove locali di Claude Code. Il collo di
bottiglia resta [`StateStore.handle`](../../Sources/LampBoardApp/Runtime/StateStore.swift#L278):
prima prova il percorso contro i lock restituiti da
[`IDEWindowReader`](../../Sources/LampBoardApp/Runtime/IDEWindowReader.swift), poi
[`terminalHome`](../../Sources/LampBoardApp/Runtime/StateStore.swift#L93) cerca la
sessione in [`LiveSessionReader`](../../Sources/LampBoardApp/Runtime/LiveSessionReader.swift).
Entrambi i reader guardano soltanto sotto `~/.claude`.

Di conseguenza COD-001 resta il primo problema da chiudere. Il
`CodexSessionLocator` è la direzione consigliata, purché venga descritto come una
prova locale delimitata dal threat model e non come autenticazione generale del
mittente.

COD-003 e le prime E2E solo-Codex devono chiudersi nella stessa onda e nello stesso
gate d'integrazione. Non devono però essere forzati nello stesso commit: il locator,
il coordinatore di lifecycle e la E2E completa sono cambiamenti separabili e più
facili da verificare e correggere se restano atomici.

## Correggi due punti dell'audit

### ROW-001 ha già quattro garanzie eseguibili

La revisione ha ragione su ROW-001. Il report tratta ancora come mancanti quattro
casi già aggiunti in `8ef77aa`:

1. il nome storico del progetto copre entrambe le righe;
2. rinominare un harness non cambia l'altro;
3. cancellare il nome specifico ripristina quello del progetto;
4. il comando CLI conserva la semantica di rinomina del progetto.

I casi sono in
[`RowNamesSuite`](../../Sources/LampBoardTests/RowNamesSuite.swift#L16). Restano
invece da coprire slot condiviso, `occupiedSlots`, scelta deterministica della riga
in uno slot, trascinamento, nascondere, silenziare e stabilità degli identificatori.
[`ColumnLayoutSuite`](../../Sources/LampBoardTests/ColumnLayoutSuite.swift#L37)
contiene oggi un solo caso esplicito con due harness nello stesso progetto.

Il report va aggiornato per separare chiaramente i quattro casi completati da
quelli ancora aperti.

### `Harness.cannotReport` dichiara una regola che il runtime non applica

Il rilievo aggiuntivo è corretto. [`Harness.cannotReport`](../../Sources/LampBoardCore/Models/Harness.swift#L58)
afferma che Codex non può riportare `.failed`, ma il valore è consultato soltanto
dai test. [`StateReducer`](../../Sources/LampBoardCore/Reducer/StateReducer.swift#L353)
trasforma qualsiasi `StopFailure` senza output utilizzabile in `.failed`, anche se
il segnale dichiara `harness == .codex`.

Il percorso normale non registra `StopFailure` per Codex, quindi il difetto oggi è
latente. La garanzia, però, è scritta nel modello e nel README come invariante. Non
può dipendere soltanto dalla configurazione degli hook.

La correzione dovrebbe avere due livelli:

1. il confine di ingresso ignora con diagnostica gli eventi incompatibili con
   l'harness dichiarato;
2. il reducer conserva lo stato precedente se un evento tentasse comunque di
   produrre uno stato incluso in `cannotReport`.

Questo rilievo può restare P2, perché non interrompe il percorso ufficiale corrente,
ma conviene chiuderlo nell'onda 1: riguarda lo stesso confine non autenticato di
COD-001 e costa poco dimostrarlo con un test.

## Usa il locator come prova di associazione, non come autenticazione

Il primo record osservato nel rollout Codex 0.151.0 offre esattamente i dati utili:
`session_id`, `cwd`, `originator`, `source` e `cli_version`. Anche la fixture
esistente in [`CodexContextSuite`](../../Sources/LampBoardTests/CodexContextSuite.swift#L39)
mostra la stessa famiglia di record, ma con `originator: codex_cli_rs` anziché il
più recente `codex-tui`.

La documentazione ufficiale degli hook Codex garantisce come campi comuni del
payload `session_id`, `transcript_path`, `cwd` e `hook_event_name`. La stessa
documentazione avverte che il formato interno del transcript non è un'interfaccia
stabile e può cambiare. Per questo il payload può indicare dove cercare la prova,
ma il parser di `session_meta` deve restare best-effort, versionato e fail-closed.

Il locator dovrebbe ricevere almeno:

```text
sessionId
transcriptPath
```

Il `cwd` ricevuto da `/signal` non deve diventare il workspace ammesso per una
sessione locale Codex.

### Valida il file prima di leggerne i metadati

Il percorso principale dovrebbe usare `transcript_path`, senza scandire tutta la
gerarchia `~/.codex/sessions/YYYY/MM/DD` a ogni hook.

Il locator deve:

1. accettare soltanto un percorso assoluto sotto
   [`AppConfig.codexSessionsDirectory`](../../Sources/LampBoardCore/Config/AppConfig.swift#L108);
2. risolvere il percorso canonico e rifiutare fughe dalla root attraverso symlink;
3. richiedere un file regolare e imporre un limite alla prima riga letta;
4. richiedere `type == "session_meta"`;
5. verificare che `payload.session_id` o il campo compatibile `payload.id`
   corrisponda esattamente al `session_id` del segnale;
6. accettare soltanto un `payload.cwd` assoluto e normalizzato;
7. restituire quel `cwd`, mai quello del payload HTTP;
8. fallire chiuso con una diagnostica precisa quando la forma è assente o
   sconosciuta.

Una ricerca nei file datati può essere un fallback per payload privi di
`transcript_path`, ma deve essere limitata, eseguita fuori dal main thread e
indicizzata. La directory contiene rollout permanenti, non un registro delle sole
sessioni vive.

### Dichiara cosa dimostra davvero la prova

Il match tra segnale e `session_meta` impedisce a una richiesta cieca di scegliere
un `cwd` arbitrario. Non impedisce a un processo malevolo eseguito come lo stesso
utente di leggere, modificare o riprodurre un rollout. Un file scrivibile dallo
stesso account non è un segreto.

Il threat model deve quindi dichiarare esplicitamente se la barriera protegge da:

- richieste accidentali o malformate su loopback;
- processi appartenenti ad altri account locali;
- replay di una sessione conclusa;
- processi ostili eseguiti dallo stesso account.

Il locator è sufficiente per i primi due casi, con permessi e canonicalizzazione
corretti. Per l'ultimo servirebbe un segreto o un'altra credenziale che il processo
ostile non possa leggere. Se il progetto sceglie di non difendersi da un processo
dello stesso account, deve dirlo invece di chiamare il locator autenticazione.

### Non dedurre la liveness dalla presenza del rollout

I rollout restano sul disco dopo la sessione. Il locator può ammettere un hook
corrente, ma la sola esistenza del file non dimostra che la sessione sia ancora
viva e non basta per adottare automaticamente tutte le sessioni all'avvio.

L'onda 1 deve definire questi comportamenti:

- `SessionEnd` rimuove la riga;
- una sessione interrotta senza `SessionEnd` decade secondo una regola documentata;
- un replay con la stessa prova già conclusa non ricrea la riga;
- una sessione realmente ripresa può tornare soltanto quando il rollout mostra
  nuova attività;
- l'avvio di LampBoard non adotta vecchi rollout come se fossero vivi.

## Tratta la superficie Codex come un indizio aperto

Il passaggio osservato da `codex_cli_rs` a `codex-tui` nella stessa versione
conferma COD-005. `originator` e `source` devono restare stringhe aperte, con
fallback a `unknown`; non devono essere enum chiusi che rendono il record
illeggibile quando appare un nuovo valore.

Conviene inoltre evitare di chiamare entrambi i concetti `source`. Nel record
`session_meta`, `source` osservato descrive una superficie come `cli`. Nel payload
ufficiale dell'evento `SessionStart`, invece, `source` significa `startup`,
`resume`, `clear` o `compact`. Sono due vocabolari diversi.

Il modello può conservare una valutazione di questo tipo:

```text
surface hint: terminal | vscode | app | unknown
confidence: inferred | unavailable
raw originator: String?
raw metadata source: String?
```

Questa informazione risolve una parte di COD-002: impedisce di fingere che tutte
le righe siano uguali e prepara strategie di focus diverse. Non prova ancora quale
finestra o tab alzare. `source: cli`, per esempio, non distingue un terminale
standalone dal terminale integrato di VS Code.

## Sposta COD-002 dopo l'ammissione senza dichiararlo inesistente

Concordo con la sequenza proposta: COD-002 deve seguire COD-001. Non concordo con
l'idea che oggi il focus su VS Code sia sempre corretto quando una riga Codex
esiste.

Una sessione Codex avviata in un terminale può lavorare nella stessa cartella
aperta in VS Code. Il lock Claude fa ammettere la riga, ma
[`PanelController.activate`](../../Sources/LampBoardApp/UI/PanelController.swift#L320)
porta comunque a VS Code. La finestra può essere pertinente al progetto senza
essere la superficie che ospita la sessione.

COD-002 può quindi passare da P1 a **P2 dipendente da COD-001**. La priorità più
bassa descrive l'ordine d'implementazione, non elimina il difetto.

## Mantieni l'onda unica e i commit separati

La sequenza consigliata è:

### Commit 1, ammetti soltanto sessioni Codex provate

- Aggiungi `CodexSessionLocator` e il parser limitato di `session_meta`.
- Prendi il workspace dalla prova locale.
- Applica l'invariante `cannotReport` nel runtime.
- Aggiungi test di dominio per path, id, `cwd`, forme sconosciute e replay.
- Registra il threat model e la dipendenza dal formato instabile.

### Commit 2, coordina il lifecycle dei due harness

- Introduci un coordinatore condiviso da CLI e UI.
- Installa, diagnostica e rimuovi Claude Code e Codex separatamente.
- Rendi gli errori specifici del percorso realmente letto o scritto.
- Rappresenta e stampa i fallimenti parziali.

[`HookInstallError`](../../Sources/LampBoardApp/Setup/HookInstaller.swift#L5) nomina
oggi sempre `~/.claude/settings.json`, mentre
[`runUninstall`](../../Sources/LampBoardApp/CommandLineInstall.swift#L49) costruisce
soltanto l'installer Claude.

### Commit 3, chiudi il gate con una E2E solo-Codex

La E2E deve usare `LAMPBOARD_HOME`, creare soltanto la struttura Codex e non
toccare il vero `~/.codex`. Deve provare almeno:

- installazione e idempotenza di `~/.codex/hooks.json`;
- esecuzione del vero `codex-hook.sh`;
- creazione della riga senza `~/.claude`;
- rifiuto di `session_id`, path o `cwd` discordanti;
- `PermissionRequest`, `PostToolUse`, `Stop` e `SessionEnd`;
- impossibilità per Codex di diventare rosso;
- rimozione selettiva degli hook LampBoard;
- diagnostica separata e istruzione di trust `/hooks`.

[`InstallationSuite`](../../Sources/LampBoardE2E/InstallationSuite.swift) oggi
esercita soltanto il percorso Claude. L'onda 1 non è conclusa finché la nuova E2E
non collega locator, script installato, server e reducer.

## Correggi subito la promessa oppure chiudila nella stessa onda

Il README dichiara supporto per CLI, estensione VS Code e copia dentro ChatGPT e
afferma che `lampboard install-hooks` installa entrambi gli harness quando sono
presenti. Finché COD-001 resta aperto, una macchina solo-Codex non soddisfa quella
promessa. La documentazione deve essere temporaneamente ridotta oppure la
correzione deve arrivare nello stesso rilascio che espone la promessa.

La procedura di rimozione in [`README.md`](../../README.md#removing-it) va corretta
da:

```bash
rm -rf ~/.lampboard "~/Library/Application Support/lampboard"
```

a:

```bash
rm -rf ~/.lampboard "$HOME/Library/Application Support/lampboard"
```

Il remote Git conserva inoltre il nome precedente. Entrambi restano lavori di
REN-001 e non devono essere confusi con il blocco funzionale di COD-001.

## Criteri per chiudere l'onda 1

L'onda può essere dichiarata completa quando tutte queste affermazioni sono vere:

- [ ] Con `~/.claude` assente, un hook Codex associato a un `session_meta` valido
      crea la riga corretta.
- [ ] Il workspace arriva dal rollout verificato e non dal `cwd` HTTP.
- [ ] Un path fuori da `CODEX_HOME/sessions`, un id discordante o una forma
      sconosciuta non crea una riga e produce una diagnostica utile.
- [ ] La politica contro replay e sessioni stale è documentata e testata.
- [ ] Codex non raggiunge `.failed` nemmeno attraverso un evento incompatibile
      costruito artificialmente.
- [ ] Installazione, stato, self-test e rimozione riportano un risultato per ogni
      harness.
- [ ] Un fallimento parziale non viene sintetizzato come successo completo.
- [ ] La E2E esegue lo script Codex reale senza creare `~/.claude`.
- [ ] `originator` e il `source` del metadata accettano valori sconosciuti senza
      perdere stato o contesto.
- [ ] Il README descrive soltanto le superfici e i comportamenti verificati.

## Fonti

### Contratto esterno

- [OpenAI, Hooks](https://learn.chatgpt.com/docs/hooks), consultato il 30 agosto
  2026. Documenta eventi, trust, campi comuni `session_id`, `transcript_path`,
  `cwd`, semantica di `SessionStart.source` e instabilità del formato del
  transcript.

### Implementazione locale

- [`StateStore.swift`](../../Sources/LampBoardApp/Runtime/StateStore.swift):
  ammissione del workspace, sessioni terminali, contesto e liveness.
- [`IDEWindowReader.swift`](../../Sources/LampBoardApp/Runtime/IDEWindowReader.swift):
  lock delle finestre sotto `~/.claude/ide`.
- [`LiveSessionReader.swift`](../../Sources/LampBoardApp/Runtime/LiveSessionReader.swift):
  file di sessione e verifica del PID sotto `~/.claude/sessions`.
- [`AppConfig.swift`](../../Sources/LampBoardCore/Config/AppConfig.swift): root
  Claude, `CODEX_HOME` e `codexSessionsDirectory`.
- [`SignalServer.swift`](../../Sources/LampBoardApp/Server/SignalServer.swift):
  ingresso non autenticato di `/signal` e selezione dell'harness tramite header.
- [`Harness.swift`](../../Sources/LampBoardCore/Models/Harness.swift): eventi Codex,
  `cannotReport`, root del transcript e fallback del nome harness.
- [`StateReducer.swift`](../../Sources/LampBoardCore/Reducer/StateReducer.swift):
  transizione corrente di `StopFailure` verso `.failed`.
- [`HookInstaller.swift`](../../Sources/LampBoardApp/Setup/HookInstaller.swift):
  installazione per harness, trust notice ed errori non specifici del percorso.
- [`CommandLineInstall.swift`](../../Sources/LampBoardApp/CommandLineInstall.swift):
  installazione parziale e rimozione solo Claude.
- [`PanelController.swift`](../../Sources/LampBoardApp/UI/PanelController.swift):
  focus terminale o VS Code deciso dall'origine corrente della sessione.

### Test e documentazione del progetto

- [`CodexContextSuite.swift`](../../Sources/LampBoardTests/CodexContextSuite.swift):
  fixture rollout 0.151.0 e test dichiarativo di `cannotReport`.
- [`RowNamesSuite.swift`](../../Sources/LampBoardTests/RowNamesSuite.swift): quattro
  garanzie ROW-001 già implementate in `8ef77aa`.
- [`ColumnLayoutSuite.swift`](../../Sources/LampBoardTests/ColumnLayoutSuite.swift):
  copertura corrente delle due righe nello stesso progetto.
- [`InstallationSuite.swift`](../../Sources/LampBoardE2E/InstallationSuite.swift):
  harness E2E attualmente limitato a Claude.
- [`README.md`](../../README.md): promessa multi-superficie, installazione degli
  hook e comando di rimozione da correggere.
- [`codex-extension-audit.md`](./codex-extension-audit.md): audit originale da cui
  derivano COD-001–COD-005, REN-001 e ROW-001.

### Osservazione da rendere riproducibile

Il valore `originator: codex-tui` è stato osservato in un rollout locale Codex
0.151.0, mentre la fixture versionata usa `codex_cli_rs`. L'osservazione conferma
che il campo deve essere aperto, ma non è ancora una fonte riproducibile. L'onda 1
deve aggiungere una fixture sanitizzata del record recente prima di usare il nuovo
valore in un test o in una decisione di focus.
