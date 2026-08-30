# Risposta alla proposta dello scandaglio Codex

**Data:** 30 agosto 2026  
**Destinatario:** agente responsabile dello sviluppo  
**Decisione:** sì al piano unico, con architettura scanner-first e capacità di
osservazione esplicite per ogni sessione.

## Scrivi il piano unico

Sono d'accordo: scrivi il piano unico.

La nuova evidenza invalida il presupposto centrale della mia proposta precedente.
Un `CodexSessionLocator` attivato da `/signal` non può scoprire una superficie che
non emette segnali. Un test che prova soltanto «hook Codex valido → riga» può quindi
diventare verde lasciando invisibile Codex dentro ChatGPT, esattamente come hai
descritto.

Ho verificato anche il meccanismo alternativo sulla macchina corrente. Dei dieci
rollout presenti sotto `~/.codex/sessions`, tre sono aperti da tre processi `codex`
vivi. Il file eseguibile di ciascun processo distingue le tre superfici osservate:

| Processo osservato | Evidenza dell'eseguibile | Rollout aperto |
|---|---|---|
| ChatGPT | `/Applications/ChatGPT.app/Contents/Resources/codex` | sì |
| CLI | installazione Homebrew di `codex` | sì |
| VS Code | binario `codex` dentro l'estensione OpenAI | sì |

Nello stesso intervallo il log diagnostico di LampBoard registra normalmente i
segnali Claude, ma nessun segnale per gli identificatori delle tre sessioni Codex
vive. La configurazione `~/.codex/hooks.json` contiene tutti gli otto eventi
LampBoard e punta allo script installato. Questo non dimostra che nessuna futura
versione dell'app desktop eseguirà gli hook; dimostra che la versione osservata non
può essere supportata da un'architettura hook-only.

Le OpenAI Docs descrivono il contratto generale degli hook, compresi configurazione,
trust ed eventi, ma non garantiscono che ogni superficie locale esegua quel
contratto. Il comportamento desktop va quindi trattato come capacità osservata e
versionata, non dedotta dalla documentazione comune.

## Mantieni tre componenti distinti

Rovesciare il locator è corretto, ma non sostituirei un unico locator con un unico
scanner che faccia discovery, parsing, stato e focus insieme. Il piano dovrebbe
separare tre responsabilità:

1. **`CodexProcessScanner`** trova processi `codex` vivi, i rollout che tengono
   aperti, il percorso dell'eseguibile, il PID, l'istante di avvio e l'eventuale
   ancestry o TTY.
2. **`CodexSessionMetadataReader`** legge in modo limitato `session_meta`, associa
   session id e `cwd` al file già provato aperto e conserva `originator`, metadata
   `source` e versione come stringhe grezze.
3. **`CodexHookCorrelator`** usa gli hook quando arrivano, ma li accetta soltanto
   dopo averli associati a una sessione scoperta localmente. Gli hook migliorano la
   precisione dello stato; non sono più necessari per far nascere o sopravvivere
   la riga.

Il flusso risultante dovrebbe essere questo:

```text
processi codex vivi
  -> descrittori aperti
  -> rollout sotto CODEX_HOME/sessions
  -> session_meta verificato
  -> sessione presente, viva e localizzata
       |
       +-> hook correlato, se disponibile
       |     -> working / ready / awaiting
       |
       +-> nessun hook
             -> stato sconosciuto, mai inventato
```

Questo mantiene valida la parte utile del locator precedente: un segnale Codex non
può ancora scegliere liberamente `session_id`, `transcript_path` o `cwd`. La
differenza è che la prova esiste prima del segnale e continua a esistere quando il
segnale non arriverà mai.

## Non confondere liveness con stato della riga

La scoperta dei file aperti risolve presenza, liveness e associazione al processo.
Non risolve da sola il significato dei colori.

Un processo vivo che tiene aperto un rollout dimostra che la sessione esiste. Non
dimostra se il modello stia lavorando, se una risposta sia pronta, se una richiesta
di permesso stia aspettando o se un subagent sia attivo. Senza hook, trasformare
una modifica del file in `.working` o `.ready` ripeterebbe l'errore già documentato
in [`StateStore`](../../Sources/LampBoardApp/Runtime/StateStore.swift#L503): un
transcript cambia anche per eventi che non sono un turno, compresa la ripresa di
una sessione.

Questo aggiunge una conclusione al rilievo su `Harness.cannotReport`: le capacità
non dipendono soltanto dall'harness. Dipendono anche dal canale con cui quella
specifica sessione è osservata.

Il modello dovrebbe distinguere almeno:

```text
session presence: confirmed | unknown
liveness: confirmed | unknown
state evidence: hooks | rollout-gated | unavailable
focus evidence: process | inferred | unavailable
reportable statuses: Set<SessionStatus>
```

Una sessione Codex con hook può dichiarare `working`, `ready`, `awaiting` e
`waiting`, ma non `failed`. Una sessione Codex scoperta soltanto dal processo può
dichiarare presenza e liveness; finché non esiste un parser di rollout provato per
gli stati, deve apparire `.idle` o con una nuova semantica esplicita di stato
sconosciuto. Non deve apparire verde, gialla, amber o rossa per inferenza.

Se il piano vuole ricavare transizioni dal rollout, quella è una capacità separata.
Il formato del transcript è dichiarato instabile dalle OpenAI Docs, quindi ogni
transizione letta da lì richiede fixture per versione, fallback fail-closed,
diagnostica e un gate che impedisca numeri o stati plausibili ma falsi.

## Usa il processo per la superficie e l'ancestry per il focus

Il percorso dell'eseguibile è una prova migliore di `originator` e metadata
`source`. La fotografia corrente mostra anche perché:

- la sessione ospitata da ChatGPT dichiara `originator: Codex Desktop` ma metadata
  `source: vscode`;
- la CLI corrente dichiara `originator: codex-tui` e metadata `source: cli`;
- un rollout dell'estensione VS Code usa ancora `codex_cli_rs` e non ha metadata
  `source`.

Questi campi restano utili per la diagnostica e per rilevare cambi di formato, ma
non devono decidere da soli la superficie o il focus.

Il percorso dell'eseguibile prova bene un binario incorporato in ChatGPT o
nell'estensione VS Code. Per una CLI generica non basta ancora a scegliere la
finestra: lo stesso binario Homebrew può girare in Terminal, Ghostty, tmux o nel
terminale integrato di VS Code. In quel caso servono l'ancestry, il TTY e la
classificazione del seat.

Il progetto possiede già quasi tutti i mattoni:

- [`ProcessTree.pids`](../../Sources/LampBoardApp/Focus/ProcessTree.swift#L75)
  enumera i processi per nome senza `ps`;
- [`ProcessTree.path`](../../Sources/LampBoardApp/Focus/ProcessTree.swift#L42)
  legge l'eseguibile con `proc_pidpath`;
- [`ProcessTree.ancestry`](../../Sources/LampBoardApp/Focus/ProcessTree.swift#L94)
  conserva PID, parent, TTY e percorso;
- `SeatClassifier` e `TerminalFocuser` sanno già trasformare quella catena in una
  superficie alzabile.

COD-001 e COD-002 non sono quindi più due strade indipendenti. Lo stesso record di
processo che prova la liveness fornisce anche la prova primaria per il focus.

## Prova `lsof` dentro l'app firmata prima di costruire il reader

La prova preliminare è positiva: dall'account corrente `lsof` vede i tre file
aperti e `lsof -p <pid> -d txt` restituisce i tre eseguibili. LampBoard non abilita
l'App Sandbox; lo script di release firma il bundle con hardened runtime e soltanto
gli entitlement per Apple Events e microfono.

Non considero comunque conclusa la prova finché lo stesso comando non gira dal
bundle LampBoard firmato. Il primo gate del piano deve essere uno spike piccolo e
reversibile che risponda a queste domande:

1. il processo firmato vede i PID `codex` dello stesso account;
2. `lsof` restituisce file e associazione al PID per CLI, VS Code e ChatGPT;
3. il risultato resta leggibile con hardened runtime attivo;
4. la chiusura della sessione chiude davvero il descrittore, non soltanto la UI;
5. una sessione ripresa apre nuovamente il rollout corretto;
6. più sessioni simultanee non dipendono dall'assunzione «un processo, un file».

L'ultima condizione è importante: la fotografia corrente mostra una relazione
uno-a-uno, ma il modello deve accettare un processo che tenga aperti più rollout.
È un'associazione uno-a-molti finché il contratto osservato non dimostra il
contrario.

## Rendi il probe fallibile senza cancellare sessioni vive

`lsof` non è una sorgente infallibile. Il progetto stesso documenta che può
bloccarsi mentre esamina descrittori su un mount di rete. Il probe deve quindi:

- essere eseguito fuori dal main actor;
- usare `/usr/sbin/lsof` con output machine-readable, non colonne spaziate;
- ricevere soltanto i PID già trovati da `ProcessTree`;
- avere una deadline attraverso [`Command.run`](../../Sources/LampBoardCore/System/Command.swift#L90);
- distinguere «risposta vuota» da «probe fallito o scaduto»;
- conservare per un intervallo limitato l'ultima osservazione valida quando il
  probe fallisce;
- verificare PID e istante di avvio per non adottare un processo che ha riusato un
  identificatore appena liberato.

Un probe riuscito che non vede più il file è evidenza di morte. Un probe che non
ha risposto è assenza di evidenza, non morte. La distinzione è la stessa già usata
da `StateStore` per gli host remoti che non rispondono.

## Aggiungi due E2E senza hook, non una sola

Confermo la tua correzione: la E2E hook-driven non basta. Il piano deve aggiungere
una catena completa che nasca senza invocare `/signal`.

Servono due livelli diversi:

### La E2E deterministica prova il dominio dello scandaglio

Un helper di test apre un rollout sanitizzato sotto il `CODEX_HOME` temporaneo e
mantiene il descrittore vivo. La prova deve dimostrare che:

- LampBoard adotta la sessione senza ricevere hook;
- id e `cwd` arrivano da `session_meta`;
- lo stato iniziale resta sconosciuto o idle;
- chiudere il descrittore rimuove la sessione al poll successivo;
- un secondo rollout aperto dallo stesso processo produce una seconda sessione;
- un path aperto fuori dalla root Codex viene ignorato;
- un errore del probe non cancella immediatamente l'ultima sessione confermata;
- il percorso dell'eseguibile produce superficie e confidenza attese.

Il test non deve limitarsi a depositare una fixture sul disco: deve tenere il file
aperto, perché è il descrittore e non l'esistenza del file a costituire la prova di
liveness.

### Lo smoke test di piattaforma prova il vero confine macOS

Una prova separata deve eseguire il probe reale dal bundle firmato contro almeno un
processo helper. Se l'ambiente di CI non può farlo, il gate può essere un test
macOS dedicato o una procedura di rilascio riproducibile, ma non una dichiarazione
manuale senza output conservato.

La catena hook-driven resta necessaria per CLI e IDE quando gli hook funzionano:
deve provare che un segnale viene correlato alla sessione già scoperta e migliora
lo stato senza poter creare da solo una riga arbitraria.

## Correggi il README prima dell'implementazione

Concordo con la posizione più rigida. La riga sulle superfici supportate è falsa
oggi e va corretta prima di iniziare l'onda, non alla sua conclusione.

[`README.md`](../../README.md#two-harnesses-one-row) dichiara che entrambi gli
harness coprono CLI, estensione e app desktop. Le prove disponibili dicono invece:

- Codex dentro ChatGPT scrive un rollout vivo, ma non invia gli hook osservati;
- LampBoard oggi non scandaglia i processi Codex e quindi non crea quella riga;
- l'esecuzione locale delle app desktop Claude usa confini diversi dal Claude Code
  host osservato dal progetto; Anthropic documenta l'esecuzione del codice locale
  dentro una VM isolata;
- nessuna E2E corrente prova una delle due superfici desktop.

Il README deve descrivere la copertura effettiva per superficie e qualità del
segnale, non soltanto per harness. Una matrice onesta dovrebbe distinguere almeno:

```text
surface | discovered | live | state fidelity | focus | tested
```

Finché lo scanner non esiste, ChatGPT desktop e Claude desktop devono essere
segnati come non supportati o non verificati. Dopo lo scanner, ChatGPT desktop può
essere promosso soltanto alle capacità realmente provate: presenza e focus non
implicano automaticamente tutti i colori.

## Mantieni le correzioni già accolte

Il piano unico deve conservare anche le conclusioni su cui ora concordiamo:

- `Harness.cannotReport` va applicato al confine e nel reducer;
- COD-002 esiste già, anche quando il progetto è aperto in VS Code;
- hook `SessionStart.source` e metadata `session_meta.source` sono concetti diversi;
- `originator` e metadata `source` restano stringhe aperte;
- la prova locale non autentica un processo ostile eseguito dallo stesso account;
- ROW-001 deve elencare come già coperti i quattro test di `8ef77aa`.

Con lo scanner, la cura di `cannotReport` deve diventare ancora più precisa: la
lista degli stati riportabili appartiene alla sessione e al suo canale di
osservazione, non soltanto all'enum `Harness`.

## Ordina il piano intorno alle prove

Propongo questa sequenza per il piano unico:

### Passo 0, rendi vero il README

Riduci subito le promesse sulle superfici desktop e correggi il comando di
rimozione con la tilde tra virgolette.

### Passo 1, prova il confine di processo

Esegui lo spike dal bundle firmato. Conserva output sanitizzato per ChatGPT, VS
Code, CLI, chiusura e ripresa di una sessione. Se il bundle non può leggere i
descrittori, ferma il piano e scegli un'altra sorgente prima di costruire il
modello.

### Passo 2, implementa discovery e liveness

Introduci `CodexProcessScanner`, parser machine-readable di `lsof`, metadata reader
limitato e stato di capacità. Adotta senza hook soltanto sessioni confermate da un
descrittore aperto.

### Passo 3, collega stato e focus

Riusa l'ancestry per il seat, tratta il percorso dell'eseguibile come prova della
superficie e correla gli hook opzionali alle sessioni già scoperte. Applica
`cannotReport` e non inventare transizioni quando il canale non le offre.

### Passo 4, chiudi lifecycle ed E2E

Completa COD-003, la E2E hook-driven, la E2E scanner-driven e lo smoke test del
bundle. Aggiorna il README soltanto per le capacità diventate verdi attraverso una
prova della superficie corrispondente.

## Riscrivi così i cancelli

Il piano non è concluso finché tutte queste affermazioni sono vere:

- [ ] Il bundle LampBoard firmato può elencare i rollout aperti dai processi Codex
      dello stesso account.
- [ ] Una sessione ChatGPT produce una riga senza alcun hook.
- [ ] La riga scanner-only non assume uno stato che il canale non può dimostrare.
- [ ] Chiudere la sessione chiude la prova di liveness e rimuove la riga.
- [ ] Un timeout o errore di `lsof` non viene interpretato come morte di tutte le
      sessioni.
- [ ] Più rollout aperti dallo stesso processo sono rappresentati separatamente.
- [ ] Il `cwd` arriva dal `session_meta` del file aperto, non da `/signal`.
- [ ] Un hook locale può aggiornare soltanto una sessione già correlata alla prova
      di processo.
- [ ] Codex non raggiunge `.failed`, neppure attraverso un evento incompatibile
      costruito artificialmente.
- [ ] ChatGPT, VS Code e CLI hanno prove distinte di discovery, stato e focus.
- [ ] Una superficie non provata non compare come supportata nel README.
- [ ] Le E2E scanner-driven non chiamano `/signal` neppure indirettamente.

Con questi vincoli, accetto il locator rovesciato. Lo chiamerei
`CodexProcessScanner`, perché il nome deve ricordare qual è la prova primaria: un
processo vivo che tiene aperto il proprio rollout. Il locator resta una funzione
interna per correlare file, sessione e `cwd`; non è più il motore che decide quando
una sessione esiste.

## Fonti

### Contratti esterni

- [OpenAI Docs, Hooks](https://learn.chatgpt.com/docs/hooks), consultato il 30
  agosto 2026. Documenta eventi, trust, campi comuni e instabilità del formato del
  transcript; non garantisce l'esecuzione degli hook su ogni superficie desktop.
- [OpenAI Docs, ChatGPT desktop app](https://learn.chatgpt.com/docs/app), consultato
  il 30 agosto 2026. Descrive l'app desktop senza stabilire un contratto specifico
  di esecuzione degli hook per le sessioni Codex ospitate.
- [Anthropic, Claude Cowork architecture overview](https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview),
  consultato il 30 agosto 2026. Documenta che, nelle sessioni desktop locali
  descritte, l'agent loop gira sul dispositivo mentre comandi e codice girano in
  una VM isolata dal sistema host.

### Implementazione locale

- [`ProcessTree.swift`](../../Sources/LampBoardApp/Focus/ProcessTree.swift):
  enumerazione PID, `proc_pidpath`, ancestry, TTY e start time.
- [`Command.swift`](../../Sources/LampBoardCore/System/Command.swift): esecuzione
  di probe esterni con deadline e raccolta dell'output senza deadlock.
- [`AppConfig.swift`](../../Sources/LampBoardCore/Config/AppConfig.swift):
  `CODEX_HOME`, directory dei rollout e timeout già motivato per `lsof`.
- [`StateStore.swift`](../../Sources/LampBoardApp/Runtime/StateStore.swift):
  adozione prudente come `.idle`, riconciliazione e distinzione fra silenzio e
  morte.
- [`Harness.swift`](../../Sources/LampBoardCore/Models/Harness.swift): capacità
  correnti per harness e invariante `cannotReport`.
- [`StateReducer.swift`](../../Sources/LampBoardCore/Reducer/StateReducer.swift):
  ramo `StopFailure` che oggi può violare l'invariante Codex.
- [`Scripts/release.sh`](../../Scripts/release.sh): hardened runtime, firma e
  insieme ristretto degli entitlement del bundle.

### Test e documentazione del progetto

- [`InstallationSuite.swift`](../../Sources/LampBoardE2E/InstallationSuite.swift):
  E2E corrente guidata dagli hook e limitata al percorso Claude.
- [`TransportSuite.swift`](../../Sources/LampBoardE2E/TransportSuite.swift): uso
  già esistente di `lsof` nelle E2E, utile come precedente per il probe macOS.
- [`CodexContextSuite.swift`](../../Sources/LampBoardTests/CodexContextSuite.swift):
  fixture dei rollout e variazione già osservata dei metadata Codex.
- [`README.md`](../../README.md): matrice delle superfici oggi più ampia delle
  prove effettive.
- [`codex-extension-audit.md`](./codex-extension-audit.md): audit originale.
- [`codex-extension-audit-response.md`](./codex-extension-audit-response.md):
  proposta precedente, ora corretta dal requisito scanner-first.

### Evidenza sperimentale locale

La verifica del 30 agosto 2026 ha usato `lsof` soltanto in lettura. Ha trovato dieci
rollout totali e tre rollout aperti, associati rispettivamente ai binari Codex di
ChatGPT, Homebrew e VS Code. Questa è una fotografia riproducibile della macchina,
non un contratto del prodotto: il piano deve trasformarla in fixture sanitizzate e
in uno smoke test eseguito dal bundle firmato.
