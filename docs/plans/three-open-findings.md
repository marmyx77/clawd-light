# Piano per le tre voci aperte del riaudit Codex

**Data:** 31 agosto 2026
**Copre:** AUD2-002 (stato per harness), AUD2-003 (copertura della chiave),
AUD2-004 (prova che un probe indisponibile non cancella righe).
**Non copre:** AUD2-005, rimandato per decisione.

**Raccomando questo ordine: 3, poi 2, poi 1.** È l'inverso di quanto si vedono,
ed è deliberato: i primi due sono piccoli, chiusi e a rischio zero, e mettono in
sicurezza il codice che ho appena cambiato stanotte. Il terzo è il più grosso e
il più utile a una persona, e va fatto quando il resto non si muove più.

---

## 3. Un probe indisponibile non deve cancellare righe, e va provato

### Cos'è oggi

La regola c'è ed è quella giusta: se il probe di Codex non risponde, le righe che
c'era restano. In codice è una riga sola.

```swift
guard case .observed(let evidence) = result else { return }
```

Il difetto è che **non esiste niente che la sorvegli**. Chi tocca quel file fra
sei mesi può cancellarla e la suite resta verde: `.unavailable` non arriva mai in
un test, perché per produrlo servirebbe far impiantare `lsof` davvero.

### Cosa cambia

Il problema è che la regola vive in `LampBoardApp`, che la suite di dominio non
vede, e `CodexScanResult` con lei. La correzione è spostare in `LampBoardCore` i
**valori** e la **decisione**, lasciando in App soltanto l'I/O — che è esattamente
la divisione che il progetto già applica altrove (`DesktopConversation` decide,
`ClaudeDesktopScanner` cammina sul disco).

| File | Cosa |
|---|---|
| `LampBoardCore/Codex/CodexScanResult.swift` | nuovo: `CodexEvidence` e `CodexScanResult` si spostano qui da `CodexProcessScanner.swift`. Sono valori puri: metadati, percorso, pid, superficie, momento. |
| `LampBoardCore/Codex/CodexAdmission.swift` | nuovo: la decisione. `survivors(of:holding:)` risponde quali id restano dato un risultato e quello che il pannello ha già. `.unavailable` risponde "tutto quello che avevi", `.observed` risponde "solo questi". |
| `LampBoardApp/Runtime/StateStoreAdoption.swift` | chiama la decisione invece di contenerla. |

### Cosa lo prova

Un caso unitario nella suite di dominio con tre risultati: `.observed` con due
sessioni, `.observed([])`, `.unavailable`. Più la mutazione che lo dimostra:
trasformare `.unavailable` in "nessun sopravvissuto" deve far diventare rosso il
caso.

Resta fuori una cosa e la dichiaro: **"non blocca l'interfaccia" non è provato da
un test**, è provato dalla struttura (il probe sta su un actor suo) e dalla
misura che `SweepLog` stampa. Un test sul tempo sarebbe un test sull'hardware.

**Sforzo:** un'ora. **Rischio:** basso, è uno spostamento di file più una funzione
pura.

---

## 2. La chiave nuova va esercitata dove un errore di chiave si vede

### Cos'è oggi

La chiave che identifica un progetto è `Workspace.key`: il percorso per una
cartella locale, `host:/percorso` per una su un'altra macchina. Il test che ho
scritto stanotte prova **tre righe distinte, il nascondimento e il nome**.

Non prova lo **slot** numerato, il **mute** e il **riordino**. Usano la stessa
chiave, quindi in teoria vanno, e in teoria non è una prova.

### Una cosa che ho verificato e toglie una preoccupazione

**Il click non passa dalla chiave.** Una riga remota si apre leggendo
`workspace.host` direttamente, non l'id della riga, quindi un errore di chiave non
può mandarti sulla macchina sbagliata cliccando. Può mandartici **premendo un
numero**, perché lo slot sì che è tenuto per chiave. Lo slot è il caso da coprire.

### Cosa cambia

Nessuna riga di produzione. È solo copertura, e questo è il punto: se scrivendo i
test qualcosa si rompe, ho trovato un difetto vero.

| File | Cosa |
|---|---|
| `LampBoardTests/RemoteSessionsSuite.swift` | estendere il caso "three rows" con: slot assegnati e distinti, `RowOrder.moving` che sposta una riga sola, mute su una che non zittisce le altre. |
| `LampBoardTests/RowOrderSuite.swift` | un caso dedicato: tre chiavi con lo stesso percorso e host diversi ricevono tre posizioni e tre slot. |

### Cosa lo prova

Le stesse mutazioni che già mordono sulla chiave — riportare il raggruppamento al
solo percorso, e togliere l'host dalla chiave — devono far diventare rossi anche i
casi nuovi. Se non lo fanno, il caso è scritto male, e va riscritto finché non lo
fa.

**Sforzo:** un'ora. **Rischio:** nessuno, non tocca il prodotto.

---

## 1. Lo stato degli hook, per agente e con la fiducia dentro

Questa è la più grande e la più utile, e c'è una scoperta che la cambia.

### La scoperta

Fino a stamattina lo stato diceva, onestamente, che la fiducia di Codex non è
leggibile da qui. **Non è vero.** Codex la registra in `~/.codex/config.toml`, in
una tabella `[hooks.state]` con una voce per evento:

```toml
[hooks.state."/Users/dev/.codex/hooks.json:permission_request:0:0"]
trusted_hash = "sha256:a1470e29…"
```

La chiave contiene **il percorso del nostro file** e **il nome dell'evento**, in
snake_case dove il file usa il PascalCase. Su questa macchina: otto eventi
registrati, otto voci di stato, corrispondenza piena.

### Il limite, che va detto e non aggirato

**L'hash non è ricalcolabile da noi.** Ho provato otto forme plausibili
dell'ingresso — il comando, il comando con newline, la voce JSON in quattro
serializzazioni, il contenuto dello script, due combinazioni — e nessuna
corrisponde. Il formato non è documentato, e questo progetto ha già una regola per
i formati non documentati: si legge quello che si capisce e non si indovina il
resto.

Quindi la presenza di una voce dice **che l'approvazione c'è stata**, non che vale
ancora adesso: riscrivere `hooks.json` può invalidarla, e Codex quando rifiuta non
dice niente.

### Cosa possiamo dire con certezza

Tre stati, e il terzo è il valore vero di questa voce.

| Stato | Quando | Cosa significa per chi legge |
|---|---|---|
| **mai approvato** | nessuna voce in `[hooks.state]` per un evento che abbiamo registrato | quell'hook **non partirà**, con certezza |
| **approvato in passato** | la voce c'è | ha funzionato almeno una volta; se il file è cambiato dopo, potrebbe non valere più |
| **non leggibile** | `config.toml` assente o illeggibile | non lo sappiamo, e lo diciamo |

Il primo stato è quello che oggi non ha nome ed è la causa più probabile di una
riga Codex muta dopo un'installazione.

### Cosa cambia

| File | Cosa |
|---|---|
| `LampBoardCore/Codex/CodexTrust.swift` | nuovo: legge `[hooks.state]` da un testo TOML e risponde, per evento, quale dei tre stati. Puro: prende una stringa, non tocca il disco. |
| `LampBoardApp/Setup/HookSetup.swift` | l'esito per agente guadagna `installed(trust:)` invece del semplice `installed`. |
| `LampBoardApp/CommandLineInterface.swift` | `status` stampa la fiducia per evento invece di dire che non si può sapere. |
| `LampBoardApp/UI/PanelController.swift` | `panelFlags` porta un esito per agente al posto del booleano unico. |
| `LampBoardApp/UI/PanelRootView.swift` | il menu dice quale agente manca, invece di dire "gli hook". |

### Cosa lo prova

Una suite nuova su `CodexTrust`, con fixture prese dalla forma misurata qui e
anonimizzate: otto voci corrispondenti, una voce mancante, una voce per un evento
che non registriamo più, un TOML illeggibile. Più le mutazioni: togliere il
confronto sugli eventi deve far passare per approvato un evento che non lo è.

**Sforzo:** mezza giornata. **Rischio:** medio, perché tocca il menu e il primo
avvio, che sono le due cose che una persona vede per prime.

---

## Tre domande, prima di partire

1. **Il menu: una voce per agente, o una voce sola che si spiega meglio?** Due voci
   sono più precise e occupano il doppio in un menu già lungo. Consiglio: **una
   voce sola**, che dica *Install the hooks (Codex is missing)* quando manca uno
   solo.
2. **Posso verificare se una reinstallazione invalida la fiducia?** Il modo pulito
   è scrivere quello che l'installer scriverebbe in un file temporaneo e
   confrontarlo con `hooks.json`, senza toccare niente. Se sono identici, la
   fiducia non si perde e possiamo dirlo. **Non reinstallo davvero senza il tuo
   sì**, perché se la invalida tocca a te riapprovare in `/hooks`.
3. **La fiducia va anche nel pannello, o basta in `status`?** Consiglio: **solo in
   `status` e nel messaggio di installazione**. Una riga muta è rara, e mettere un
   quarto stato nel menu per un caso raro rende peggiore il caso comune.
