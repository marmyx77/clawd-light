# Audit della rinomina LampBoard e dell'estensione a Codex

> Destinatario: agente che sviluppa LampBoard
>
> Data dell'audit: 30 agosto 2026
>
> Baseline di confronto: `c575513`
>
> Stato analizzato: `5185072` (`fix: two agents in one project are two rows`)

> Aggiornamento durante la stesura: dopo lo snapshot sono apparse modifiche
> locali non committate a `RowNames`, `ColumnLayout`, `StateStore`,
> `PanelController` e ai relativi test. Introducono nomi distinti per harness con
> fallback ai vecchi nomi di progetto. Non fanno parte di `5185072`, non sono
> state alterate da questo audit e vanno preservate. La sezione ROW-001 ne tiene
> conto. Al controllo finale i documenti del follow-up dichiarano 577 test di
> dominio e `Scripts/check-docs.sh` supera 10 controlli su 10; build e suite non
> sono state rieseguite da questo audit sul follow-up non committato.

## Decisione operativa

La rinomina da Clawd Light a LampBoard e il refactoring del dominio per supportare
più harness sono riusciti. L'estensione a Codex, invece, non è ancora completa
end-to-end.

Il dominio interpreta correttamente gli eventi Codex, mantiene separati i due
harness e dichiara onestamente i limiti del protocollo. I bordi applicativi
continuano però a dipendere da prove di esistenza, processi e finestre fornite da
Claude Code. Di conseguenza LampBoard è oggi **Codex-aware**, ma non ancora un
prodotto realmente dual-harness in discovery, focus, installazione, diagnostica e
test di sistema.

Prima di considerare conclusa l'estensione a Codex, completare almeno:

1. ammissione sicura delle sessioni Codex senza dipendere da `~/.claude`;
2. comportamento di focus che non inventi una superficie Codex;
3. installazione, rimozione, stato e self-test simmetrici per i due harness;
4. una catena E2E Codex che esegua lo script realmente generato;
5. un gate per il formato instabile dei rollout Codex.

## Lavoro svolto durante l'audit

L'analisi non ha modificato il codice applicativo. Ha seguito questi passaggi.

### Ho confrontato il progetto con la baseline precedente

Ho usato `c575513` come punto precedente alla rinomina e all'estensione Codex.
Allo stato `5185072`, il delta misurato è:

- 10 commit;
- 213 file modificati;
- 3.229 righe aggiunte e 1.106 rimosse;
- 181 file Swift, per 29.526 righe Swift;
- nessuna dipendenza Swift esterna;
- file più lungo: 768 righe.

Ho seguito la rinomina attraverso package, target, nomi dei tipi, bundle ID,
directory di supporto, script di build, release feed, Homebrew cask, documenti e
test. Ho poi cercato ogni riferimento residuo a `clawd-light` e `clawdlight`.
Quelli rimasti nel codice sono intenzionali e servono alla migrazione.

### Ho ricostruito la catena Codex dal file di configurazione alla riga

Ho letto e collegato:

- configurazione e script degli hook;
- header `X-LampBoard-Harness`;
- parsing del payload;
- policy sui transcript;
- risoluzione del workspace;
- reducer e liveness;
- composizione delle righe;
- scanner del rollout e anello del contesto;
- installazione, rimozione, `status` e `selftest`;
- test di dominio ed E2E.

Il percorso effettivo di un segnale locale Codex è questo:

```text
Codex
  -> ~/.lampboard/codex-hook.sh
  -> POST /signal + X-LampBoard-Harness: codex
  -> HookPayloadDecoder
  -> StateStore.handle
       -> cerca il cwd nei lock di ~/.claude/ide
       -> altrimenti cerca l'id in ~/.claude/sessions
       -> senza una delle due prove, scarta il segnale
  -> StateReducer
  -> ColumnLayout
```

Il parser e il reducer sono multi-harness. Il collo di bottiglia è
`StateStore.handle`, prima che il segnale raggiunga il reducer.

### Ho confrontato il codice con il contratto ufficiale Codex

Ho verificato la [documentazione ufficiale degli hook
Codex](https://learn.chatgpt.com/docs/hooks). In particolare:

- `PermissionRequest`, `PostToolUse`, `SubagentStart`, `SubagentStop`, `Stop` e
  `SessionEnd` sono eventi pubblicati;
- la tabella degli eventi non espone un evento di fallimento del turno;
- gli hook non gestiti devono essere esaminati e considerati attendibili prima
  di essere eseguiti;
- un hook che termina con codice `0` senza output è considerato riuscito e Codex
  continua normalmente;
- `session_id`, `transcript_path`, `cwd`, `hook_event_name` e `model` sono campi
  comuni documentati;
- il formato del transcript non è un'interfaccia stabile e può cambiare.

Questa verifica conferma la scelta di non inventare un rosso Codex dalla
silenziosità e conferma che il `PermissionRequest` osservato senza output non
decide al posto della persona. Mostra anche che il parser del rollout deve essere
trattato come integrazione instabile, non come contratto garantito.

### Ho eseguito build, test e gate documentali

Sul codice poi confluito in `5185072`:

| Verifica | Risultato |
|---|---|
| Build con `-warnings-as-errors` | superata |
| Test di dominio | 573 su 573 superati |
| Test E2E | 82 su 82 superati |
| `git diff --check` | nessun errore |
| `Scripts/check-docs.sh` dopo `5185072` | 10 controlli su 10 superati |

Il primo tentativo di build dentro la sandbox si è fermato prima del codice per
l'accesso negato alla cache dei moduli Swift. La stessa suite, eseguita
nell'ambiente autorizzato, ha compilato e raggiunto i test.

Durante la prima esecuzione completa, il gate documentale ha rilevato che due
nuovi test avevano portato il totale da 571 a 573. Il commit `5185072` ha poi
aggiornato README, code map, architettura, guida di lavoro e WORKLOG. Ho rieseguito
il gate documentale sul commit: tutti i controlli passano.

Non ho completato personalmente la fase `Scripts/bite.sh` dopo l'ultimo commit.
Il messaggio di commit dichiara 22 mutazioni intercettate, ma questo report non
presenta quel dato come verifica indipendente.

### Ho preservato il lavoro in corso

Lo stato del repository è cambiato mentre l'audit era in corso:

1. erano inizialmente presenti modifiche locali alla procedura dei permessi;
2. quelle modifiche sono confluite in `ac23344`;
3. è apparsa la correzione per due harness nello stesso progetto;
4. quella correzione è confluita in `5185072`, insieme ai conteggi documentali.
5. durante la verifica di questo report è iniziato un follow-up locale sui nomi
   distinti delle due righe.

Ho riletto HEAD e il diff dopo ogni cambiamento. Prima di creare questo report il
worktree era pulito. Nessun file dell'applicazione è stato sovrascritto o
ripristinato dall'audit.

## Valutazione dell'architettura corrente

### La base multi-harness è solida

[`Harness.swift`](../../Sources/LampBoardCore/Models/Harness.swift) centralizza:

- nome e identificatore del coding agent;
- root ammessa per i transcript;
- eventi da registrare;
- stati che l'harness non può riportare;
- dichiarazione della finestra di contesto.

`SessionState`, `HookSignal`, il reducer e il contratto `/sessions` trasportano
l'harness come dato. Questo evita di dedurlo dalla forma del payload e impedisce
che la riconciliazione Claude cancelli righe Codex.

La scelta è migliore di una serie di rami `if codex`: il comportamento diverso è
esplicito nel modello e può essere verificato in isolamento.

### La semantica degli stati Codex è prudente

[`Harness.cannotReport`](../../Sources/LampBoardCore/Models/Harness.swift#L51)
dichiara che Codex non può produrre il rosso. È la conclusione corretta: il
contratto ufficiale non offre un evento di fallimento e il silenzio non distingue
un crash da un turno lungo.

La stessa prudenza si vede in `PermissionRequest`:

- la richiesta mette la riga in attesa;
- `PostToolUse` prova che l'approvazione è stata superata;
- solo campi sicuri di `tool_input` raggiungono la UI;
- contenuti di patch e payload arbitrari non vengono mostrati.

### Il contesto Codex usa il dato giusto

[`CodexRolloutScanner`](../../Sources/LampBoardCore/Transcript/CodexRolloutScanner.swift)
usa `last_token_usage.input_tokens`, non il totale cumulativo della sessione, e
legge `model_context_window` dallo stesso record. La percentuale descrive quindi
il turno corrente, non tutta la cronologia.

La quota del piano resta separata dall'anello perché è un dato dell'account, non
della sessione. Anche questa separazione è corretta.

### La rinomina conserva i dati della persona

[`Preferences.migrateFromPreviousName`](../../Sources/LampBoardApp/Runtime/Preferences.swift#L81)
importa il dominio `com.clawdlight.app` prima di ogni lettura delle preferenze.
[`SupportDirectoryMigration`](../../Sources/LampBoardApp/Runtime/SupportDirectoryMigration.swift)
copia `remotes` e `inbox` senza cancellare la vecchia directory. Gli script non
vengono copiati perché devono essere rigenerati con nome, porta e harness
correnti.

È una migrazione conservativa e correttamente ordinata.

### Due harness nello stesso progetto non vengono più fusi

Il commit `5185072` raggruppa per progetto e harness, non più soltanto per
progetto. [`ColumnLayout.group`](../../Sources/LampBoardCore/Models/ColumnLayout.swift#L262)
mantiene così separati, per esempio, un Claude ancora al lavoro e un Codex già
terminato.

Nello snapshot `5185072` la correzione rispetta questa semantica:

- nome e slot restano proprietà del progetto;
- la lettera nell'anello distingue il harness;
- più sessioni dello stesso harness continuano a condividere una riga.

Il follow-up locale osservato durante la stesura mantiene lo slot sul progetto ma
porta il nome sulla coppia progetto-harness, conservando il vecchio nome del
progetto come fallback. È una scelta UX diversa da quella di `5185072`, non una
correzione necessaria per gli altri rilievi Codex. Va chiusa con test espliciti
sulla migrazione e sulla differenza fra il comando CLI, che rinomina il progetto,
e il menu, che rinomina la singola riga.

## Risultati da correggere

### COD-001, ammettere sessioni Codex senza una prova Claude

**Priorità: P1, blocca la promessa di supporto Codex.**

#### Evidenza

Per i segnali locali, [`StateStore.handle`](../../Sources/LampBoardApp/Runtime/StateStore.swift#L278)
risolve il `cwd` soltanto contro le finestre restituite da
[`IDEWindowReader`](../../Sources/LampBoardApp/Runtime/IDEWindowReader.swift).
Quel reader legge esclusivamente i lock che l'estensione Claude Code scrive in
`~/.claude/ide`.

Se nessuna finestra reclama il percorso, `terminalHome` cerca l'id della sessione
in [`LiveSessionReader`](../../Sources/LampBoardApp/Runtime/LiveSessionReader.swift),
che legge esclusivamente `~/.claude/sessions`.

Una sessione Codex non ha normalmente un record in nessuna delle due directory.
Il segnale viene quindi decodificato correttamente e poi scartato prima del
reducer.

#### Impatto

La tabella nel [README](../../README.md#two-harnesses-one-row) dichiara supporto
per Codex CLI, estensione VS Code e copia dentro ChatGPT. Oggi questo funziona
solo quando il `cwd` Codex coincide incidentalmente con una finestra già
dichiarata dai lock Claude Code, oppure quando il segnale arriva come remoto già
configurato.

Con soltanto Codex installato, una sessione locale può restare invisibile.
LampBoard avviato a sessione Codex già aperta, inoltre, non dispone di un reader
equivalente a quello Claude per adottarla: la riga nasce soltanto al prossimo
hook ammesso.

#### Vincolo di sicurezza

Non correggere il problema accettando ogni `cwd` assoluto ricevuto da `/signal`.
La route non è autenticata e la prova del workspace è oggi parte della barriera
che impedisce a un processo locale qualsiasi di creare righe arbitrarie.

Prima di allargare l'ammissione serve una prova sostitutiva. Possibili direzioni:

1. autenticare gli hook locali con un segreto dedicato o con il token esistente;
2. introdurre un `CodexSessionLocator` che verifichi una prova locale affidabile;
3. distinguere la prova necessaria a mostrare una riga da quella necessaria a
   dichiararla cliccabile;
4. mantenere una strategia esplicita per i segnali remoti, senza trasferire
   accidentalmente un segreto locale su ogni host.

La scelta va registrata nel threat model. Rimuovere il gate senza sostituirlo è
una regressione di sicurezza.

#### Criteri di accettazione

- Con `~/.claude` assente e Codex installato, un hook Codex attendibile crea la
  riga corretta.
- Un POST non autenticato o senza altra prova non può creare una riga per un
  percorso arbitrario.
- Una sessione Codex terminale può apparire quando la relativa opzione è attiva.
- `SessionEnd` rimuove la riga.
- Una sessione interrotta senza `SessionEnd` è rimossa da una regola di staleness
  documentata, senza inventare un fallimento.
- La riconciliazione Claude continua a non eliminare righe Codex.
- Il comportamento all'avvio con una sessione Codex già aperta è implementato o
  dichiarato esplicitamente come limite.

### COD-002, separare la presenza della riga dalla capacità di portare alla superficie giusta

**Priorità: P1, necessaria per CLI e ChatGPT.**

#### Evidenza

[`PanelController.activate`](../../Sources/LampBoardApp/UI/PanelController.swift#L320)
tratta una riga non terminale come finestra VS Code. Una riga terminale passa a
`SeatResolver`, che ritrova il processo attraverso il file live di Claude Code.

Il rollout di prova contiene `originator: codex_cli_rs`, ma
`CodexRolloutScanner` non legge quel campo e il modello della sessione non
conserva una superficie Codex. Il campo non fa nemmeno parte dei campi comuni
stabili degli hook ufficiali.

#### Impatto

Anche quando una riga Codex viene ammessa perché il progetto è aperto in VS Code,
il click non prova che la sessione viva in quella finestra. Una sessione della
ChatGPT app o del terminale può portare alla finestra sbagliata oppure risultare
impossibile da alzare.

#### Lavoro consigliato

Introdurre nel modello una capacità separata dallo stato, per esempio:

```text
session is observable: true
focus target: vscode | terminal seat | chatgpt | unknown
focus confidence: verified | inferred | unavailable
```

Non è necessario supportare subito il focus di ogni superficie. È necessario non
prometterlo quando non è dimostrabile. Una riga osservabile ma non cliccabile può
mostrare stato, contesto e richiesta, spiegando nel tooltip perché non può portare
alla finestra.

Non usare `originator` dal transcript come contratto stabile senza un gate: la
documentazione OpenAI dichiara instabile il formato del transcript.

#### Criteri di accettazione

- Il click su una riga Codex non apre VS Code solo perché il suo progetto è
  aperto lì.
- Una superficie verificata viene alzata con una strategia specifica.
- Una superficie sconosciuta lascia intatto lo stato della riga e spiega che il
  focus non è disponibile.
- CLI, estensione e ChatGPT hanno test distinti oppure il README limita la
  promessa alle superfici effettivamente verificate.
- Il contratto `/sessions` espone abbastanza informazione da permettere a un
  consumer di distinguere `unknown` da un target verificato.

### COD-003, coordinare installazione e diagnostica per harness

**Priorità: P1, problema di lifecycle e rimozione.**

#### Evidenza

[`CommandLineInterface.runInstall`](../../Sources/LampBoardApp/CommandLineInstall.swift#L12)
installa prima Claude e poi Codex soltanto se `~/.codex` esiste. Un errore Codex
viene stampato, ma il comando resta riuscito perché Claude è già installato.

[`runUninstall`](../../Sources/LampBoardApp/CommandLineInstall.swift#L49) rimuove
soltanto le registrazioni Claude. Il prompt al primo avvio e le azioni del menu
costruiscono anch'essi il solo `HookInstaller()` Claude.

[`status`](../../Sources/LampBoardApp/CommandLineInterface.swift#L157) e
[`selftest`](../../Sources/LampBoardApp/SelfTest.swift#L138) riportano soltanto
hook, processi e finestre Claude. Anche gli errori di `HookInstaller` nominano
sempre `~/.claude/settings.json`, compreso quando l'istanza sta operando su
`~/.codex/hooks.json`.

#### Impatto

- Installare Codex dopo LampBoard non produce un nuovo invito.
- Il menu può dichiarare gli hook installati mentre Codex non lo è.
- `selftest` può dire “All good” senza verificare Codex o il trust.
- `uninstall-hooks` lascia attive le registrazioni Codex.
- Il caveat Homebrew promette una rimozione che il comando non completa.
- Un errore Codex può indicare il file Claude sbagliato.

#### Lavoro consigliato

Creare un coordinatore di harness usato da CLI e UI. Il coordinatore deve
produrre un risultato per harness, non un singolo booleano globale:

```text
Claude Code: installed | absent | failed(reason)
Codex:       installed | absent | untrusted | failed(reason)
```

Il trust Codex non è automatizzabile, ma il coordinatore deve sempre stampare il
passaggio `/hooks` quando ha scritto o modificato la definizione.

#### Criteri di accettazione

- CLI, primo avvio e menu invocano lo stesso coordinatore.
- Installazione e rimozione sono idempotenti per entrambi gli harness.
- Un harness assente non impedisce di configurare l'altro.
- Un fallimento parziale è visibile e non viene sintetizzato come successo
  completo.
- `uninstall-hooks` rimuove per percorso esatto sia `hook.sh` sia
  `codex-hook.sh`, preservando tutti gli hook altrui.
- `status` e `selftest` riportano Claude e Codex separatamente.
- Gli errori nominano il file realmente letto o scritto.
- Esiste un comportamento documentato quando `~/.codex` compare dopo la prima
  installazione.

### COD-004, aggiungere una catena E2E Codex

**Priorità: P1, necessaria prima di dichiarare il supporto stabile.**

#### Evidenza

[`CodexContextSuite`](../../Sources/LampBoardTests/CodexContextSuite.swift) offre
buoni test di dominio per contesto, limite dei fallimenti, safelist della
richiesta e riconciliazione per harness.

[`InstallationSuite`](../../Sources/LampBoardE2E/InstallationSuite.swift), invece,
crea `~/.claude`, legge `settings.json`, esegue `hook.sh` e controlla soltanto il
percorso Claude. Nessun test E2E crea `~/.codex/hooks.json` o esegue
`codex-hook.sh`.

#### Matrice minima da aggiungere

| Caso | Prova richiesta |
|---|---|
| Installazione | preserva chiavi e hook esistenti in `~/.codex/hooks.json` |
| Idempotenza | due installazioni non duplicano gli handler |
| Script | `codex-hook.sh` è eseguibile, esce `0` e porta l'header `codex` |
| Catena HTTP | lo script reale crea o aggiorna una sessione Codex |
| PermissionRequest | la riga diventa amber e mostra solo i campi sicuri |
| PostToolUse | libera la richiesta pendente |
| Subagent | start e stop mantengono identità e contatore corretti |
| Stop | la riga diventa ready e non inventa un errore |
| Transcript policy | accetta solo path sotto la root Codex configurata |
| Context | rollout reale di fixture produce token, finestra, modello e piano |
| Solo Codex | l'intera prova funziona senza directory Claude |
| Rimozione | elimina solo le registrazioni LampBoard da Codex |
| Diagnostica | `status` e `selftest` descrivono lo stato Codex |
| Trust | il comando stampa sempre la procedura `/hooks` quando necessaria |

La E2E deve usare `LAMPBOARD_HOME` come quella Claude e non deve toccare il vero
`~/.codex`.

### COD-005, trattare il rollout come contratto instabile

**Priorità: P2, rischio di regressione silenziosa.**

#### Evidenza

`CodexRolloutScanner` dipende dalla forma:

```text
record.payload.type == token_count
record.payload.info.last_token_usage.input_tokens
record.payload.info.model_context_window
record.payload.rate_limits.primary.used_percent
```

Le fixture documentano Codex 0.151.0. La documentazione ufficiale garantisce il
campo `transcript_path`, ma dice esplicitamente che il formato del transcript può
cambiare.

La frase “nothing about it rests on us” è corretta per il denominatore, che viene
dichiarato dal harness, ma non per il percorso di estrazione, che dipende dal
formato del rollout.

#### Lavoro consigliato

- Limitare la promessa: “finestra dichiarata dal harness, letta da un formato
  best-effort”.
- Conservare fixture nominate per versione Codex.
- Aggiungere un controllo di contratto Codex separato da quello Claude.
- Fallire chiuso: nessun dato produce nessun anello, non `0%`.
- Registrare una diagnostica quando un rollout esiste ma nessun record noto viene
  trovato.
- Usare il campo `model` dell'hook, documentato ufficialmente, per ridurre dove
  possibile la dipendenza dal `turn_context` interno.
- Trattare `rate_limits` e `plan_type` come opzionali e non come requisito per la
  riga.

#### Criteri di accettazione

- Una fixture dell'ultima versione osservata passa.
- Una fixture con forma sconosciuta non produce numeri plausibili ma falsi.
- Il gate segnala quale campo è scomparso.
- Il pannello continua a mostrare lo stato anche quando il contesto non è
  leggibile.
- README e tooltip distinguono dato dichiarato e trasporto best-effort.

### REN-001, completare la rinomina fuori dal codice

**Priorità: P2.**

#### Stato positivo

Package, target, bundle ID, support directory, release feed, cask e URL di release
usano LampBoard. Le occorrenze legacy nel codice servono alla migrazione e non
vanno rimosse senza una decisione esplicita sulla compatibilità.

#### Residui operativi

- `origin` punta ancora a `https://github.com/marmyx77/clawd-light.git`.
- La directory locale conserva il vecchio nome. È cosmetico, ma può confondere
  script e istruzioni copiate.
- Il tracking locale riporta `main` 26 commit avanti a `origin/main` al momento
  dell'audit.
- Il comando di rimozione nel README contiene
  `"~/Library/Application Support/lampboard"`: la tilde tra virgolette non viene
  espansa dalla shell.

Il cambio di bundle ID non può trasferire automaticamente le autorizzazioni TCC.
La procedura introdotta in `ac23344` è quindi necessaria, non un difetto della
migrazione.

#### Criteri di accettazione

- Aggiornare il remote Git alla repository LampBoard effettiva.
- Verificare fetch, push, workflow, release e tap dal nuovo URL.
- Decidere se rinominare la directory locale; non è un requisito funzionale.
- Correggere il comando di rimozione usando
  `"$HOME/Library/Application Support/lampboard"`.
- Eseguire un upgrade reale da una build con bundle ID precedente e verificare
  preferenze, remoti, inbox, hook legacy e procedura TCC.

### ROW-001, chiudere la correzione delle due righe con test di interazione

**Priorità: P2, la correzione principale è già implementata.**

I test aggiunti in `5185072` provano che due harness nello stesso progetto
diventano due righe e che due sessioni dello stesso harness restano raggruppate.
Il follow-up locale successivo sta introducendo alias specifici per harness e il
fallback ai nomi di progetto esistenti. Mancano ancora test espliciti sugli altri
consumatori condivisi del percorso e sull'interazione completa.

Aggiungere casi per dimostrare che:

- un nome legacy del progetto resta visibile su entrambe le righe;
- rinominare una riga dal menu non rinomina l'altro harness;
- cancellare il nome specifico ripristina il nome legacy del progetto;
- `lampboard rename` continua a rinominare il progetto, con una distinzione
  documentata rispetto al menu;
- nascondere, silenziare o calmare il progetto influenza entrambe;
- le due righe condividono lo slot;
- `occupiedSlots` espone una sola assegnazione per progetto;
- `row(inSlot:)` sceglie in modo deterministico la riga più urgente;
- trascinare una delle due righe sposta il progetto e non soltanto il harness;
- gli identificatori delle righe restano stabili tra due rendering identici.

Questi test trasformano le garanzie oggi spiegate nei commenti in un contratto
eseguibile.

### SWIFT-001, pianificare il passaggio al language mode Swift 6

**Priorità: P3, debito tecnico non bloccante.**

[`Package.swift`](../../Package.swift#L1) usa Swift tools 6.0 ma mantiene tutti i
target in `swiftLanguageMode(.v5)`. È una scelta prudente per una codebase AppKit,
Combine e concorrenza, ma rinvia i controlli più forti sui confini degli actor e
sui tipi `Sendable`.

Non cambiare modalità insieme ai lavori Codex P1. Preparare una migrazione
separata:

1. compilazione sperimentale target per target;
2. inventario dei warning di concorrenza;
3. correzione dei confini `MainActor`, processi e callback server;
4. passaggio definitivo con warning-as-error.

## Sequenza di implementazione consigliata

### Onda 1, rendere vera la presenza Codex

1. **COD-001**: definire prova di ammissione e threat model.
2. **COD-003**: introdurre il coordinatore di installazione e diagnostica.
3. Aggiungere subito le prime E2E di **COD-004**: solo Codex, installazione,
   script e `/signal`.

COD-001 e COD-003 possono essere sviluppati separatamente, ma devono incontrarsi
nella stessa E2E prima di essere considerati completati.

### Onda 2, rendere onesto il click

1. **COD-002**: introdurre target e confidenza del focus.
2. Estendere la E2E alle superfici che possono essere simulate.
3. Ridurre temporaneamente le promesse nel README per le superfici non ancora
   verificate.

### Onda 3, rendere resistente il contratto

1. **COD-005**: fixture versionate, diagnostica e gate del rollout.
2. Completare i test di **ROW-001**.
3. Eseguire **REN-001** e la prova di upgrade.

### Onda 4, debito non bloccante

1. **SWIFT-001** in un cambiamento isolato.

## Gate di completamento dell'estensione Codex

Il lavoro può essere dichiarato concluso quando tutte queste affermazioni sono
vere:

- [ ] Una macchina con Codex e senza Claude Code mostra una sessione Codex.
- [ ] Un processo non attendibile non può creare righe arbitrarie tramite
      `/signal`.
- [ ] Una sessione Codex CLI non viene classificata come finestra VS Code senza
      prova.
- [ ] Una superficie non alzabile è descritta come tale e il click non cancella
      informazioni non lette.
- [ ] UI e CLI installano, diagnosticano e rimuovono entrambi gli harness.
- [ ] Un fallimento parziale dell'installazione è visibile.
- [ ] Codex non può restare registrato dopo `uninstall-hooks` senza che il comando
      lo dica.
- [ ] La catena E2E esegue `codex-hook.sh` e attraversa davvero HTTP, decoder,
      reducer e snapshot.
- [ ] La E2E copre richiesta di permesso, subagent, stop, transcript policy e
      contesto.
- [ ] Un cambiamento del rollout fallisce in modo diagnosticabile e non produce
      numeri inventati.
- [ ] Il README promette soltanto superfici verificate.
- [ ] Il remote Git, gli URL di release e il tap nominano tutti LampBoard.
- [ ] Build warning-as-error, conteggi di dominio ed E2E aggiornati, nuove E2E
      Codex, gate documentali e mutazioni `bite` passano nello stesso commit.

## Comandi di verifica finali

Eseguire dalla root del repository:

```bash
git status --short
git diff --check
./Scripts/test.sh
./Scripts/check-contract.sh
```

Se viene aggiunto un gate Codex separato, includerlo in `Scripts/test.sh` e in
`Scripts/bite.sh`. Un gate nuovo non è completo finché una mutazione controllata
non dimostra che sa fallire per il motivo atteso.

Per la prova manuale di installazione usare un home temporaneo, mai i file reali:

```bash
LAMPBOARD_HOME=/percorso/temporaneo lampboard install-hooks
```

La prova deve creare esplicitamente `.codex` nel home temporaneo, perché
l'installer corrente usa la presenza della directory per decidere se Codex è
installato.

## File da leggere prima di iniziare

1. [`Harness.swift`](../../Sources/LampBoardCore/Models/Harness.swift)
2. [`StateStore.swift`](../../Sources/LampBoardApp/Runtime/StateStore.swift)
3. [`HookInstaller.swift`](../../Sources/LampBoardApp/Setup/HookInstaller.swift)
4. [`CommandLineInstall.swift`](../../Sources/LampBoardApp/CommandLineInstall.swift)
5. [`PanelController.swift`](../../Sources/LampBoardApp/UI/PanelController.swift)
6. [`CodexRolloutScanner.swift`](../../Sources/LampBoardCore/Transcript/CodexRolloutScanner.swift)
7. [`CodexContextSuite.swift`](../../Sources/LampBoardTests/CodexContextSuite.swift)
8. [`InstallationSuite.swift`](../../Sources/LampBoardE2E/InstallationSuite.swift)
9. [Documentazione ufficiale degli hook Codex](https://learn.chatgpt.com/docs/hooks)

Il principio da conservare durante tutte le correzioni è quello già espresso dal
dominio: **un'assenza si dichiara, non si deduce**. Va applicato anche a presenza,
liveness e focus. Mostrare meno quando la prova manca è corretto; mostrare una
finestra, uno stato o una percentuale plausibile ma non dimostrata non lo è.
