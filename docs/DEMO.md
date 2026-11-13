# La demo: l'harness in sette passi

Un coding agent da solo è veloce e inaffidabile. Ciò che lo rende affidabile è
il sistema che il team gli costruisce attorno, e quel sistema si costruisce un
pezzo alla volta. La demo lo mostra sullo stesso repository e con lo stesso
agente: ogni passo aggiunge un solo strato.

| Passo | Strato | Cosa mostra |
|---|---|---|
| 1 | Senza harness | L'agente prende una scorciatoia architetturale che compila e funziona |
| 2 | Guida | Il vincolo scritto in `AGENTS.md` orienta, ma non obbliga |
| 3 | Sensore | Il contratto di verifica diventa rosso, e solo su ARCH001 |
| 4 | Feedback | Il report JSON rende il difetto correggibile dall'agente |
| 5 | Guardrail | Un hook blocca il tentativo di modificare il test invece del codice |
| 6 | Requisito sfuggito | Un criterio non coperto diventa un nuovo test |
| 7 | Persone | CI sullo SHA della PR, review e merge restano decisioni umane |

Ogni passo si esegue con `scripts/agileday.ps1` e ha un'evidenza registrata in
`demo-assets/evidence/` con lo stesso risultato.

## 1. Preparazione

### Prerequisiti

.NET SDK 10, PowerShell 7.4+, Node 22, Git, Bash e
[Claude Code](https://code.claude.com/docs) con un login attivo (passi 4 e 5).
Facoltativo: GitHub CLI `gh` autenticata (passo 7).

Ogni comando sta su una riga e funziona sia in PowerShell 7 sia in bash.

### Un checkout dedicato

La demo modifica il codice: va eseguita in un worktree separato, su un branch
di lavoro. Il seed rifiuta di partire su `main`, e il checkout principale resta
intatto. Dalla root del repository clonato:

```bash
git worktree add -b demo/harness ../harness-demo HEAD
cd ../harness-demo
git status --short          # nessun output
```

**Da qui in poi tutti i comandi si eseguono dalla cartella `harness-demo`.**

`git status --short` deve restare vuoto: strumenti che scrivono file nel
checkout (indicizzatori, cache dell'editor) vanno esclusi da questa cartella.

### Dipendenze e baseline

```bash
pwsh -NoProfile -File scripts/agileday.ps1 -Step Prepare    # npm ci + Chromium Playwright, serve la rete
pwsh -NoProfile -File scripts/agileday.ps1 -Step Verifica   # 2–3 minuti
pwsh -NoProfile -File scripts/agileday.ps1 -Step Status
```

**Cosa verificare.** `Verifica` mostra nove gate `passed` e termina con:

```text
PASS: risultato atteso Passed confermato. Exit code del contratto: 0.
```

`Status` riporta `SeedApplied : False` e `PatchApplied : False`.

La verifica avvia l'app sulla porta 5089 per i test nel browser: la porta deve
essere libera (`lsof -i :5089` non stampa nulla).

### Controllo preliminare del guardrail

Solo una verifica: l'hook si usa al [passo 5](#7-passo-5--il-guardrail).
Il file `quality-gates-settings.json` aggiunge alla sessione un hook
`PreToolUse` che nega le modifiche ai quality gate.

La prova chiede a Claude Code, in modalità non interattiva, di modificare un
test con lo strumento Edit:

```bash
claude -p "Usa lo strumento Edit per aggiungere la riga // probe come prima riga di tests/Orders.ArchitectureTests/ArchitectureRulesTests.cs. Non usare altri strumenti di modifica. Se la chiamata viene negata da un hook, riporta testualmente il motivo." --settings demo-assets/claude-harness/quality-gates-settings.json --permission-mode acceptEdits
git status --short     # nessun output
```

**Cosa verificare.** La risposta riporta che un hook ha negato la chiamata, con
il motivo `GUARDRAIL: tests/Orders.ArchitectureTests/ArchitectureRulesTests.cs è
un quality gate. Correggi il codice, non il controllo.`, e il file non è stato
modificato.

### Due terminali

Aprire due terminali, entrambi nella cartella `harness-demo`:

- **Terminale A**: gli script della demo;
- **Terminale B**: Claude Code (passi 4 e 5).

## 2. L'app (facoltativo)

**Terminale A:**

```bash
pwsh -NoProfile -File scripts/demo.ps1 -Step App
```

Su <http://localhost:5078>: ordine da 100 euro, codice SAVE20 al 20% → 80 euro.
Ctrl+C ferma l'app.

## 3. Passo 1 — Senza harness

**Terminale A:**

```bash
pwsh -NoProfile -File scripts/agileday.ps1 -Step Senza
```

`Senza` introduce un difetto noto e ne mostra il diff: `Orders.Application`
referenzia `Orders.Infrastructure` e una classe usa direttamente il repository
in-memory invece dell'interfaccia `IOrderRepository`. Il codice compila e l'app
funziona; la violazione è architetturale.

**Cosa verificare.** Il diff aggiunge a `Orders.Application.csproj` un
`ProjectReference` verso `Orders.Infrastructure`, e `InfrastructureShortcut.cs`
usa `InMemoryOrderRepository`:

```bash
git status --short
#  M src/Orders.Application/Orders.Application.csproj
# ?? src/Orders.Application/InfrastructureShortcut.cs
```

Il difetto è salvato in `demo-assets/unsafe-change/` e viene rimosso soltanto se
è ancora identico all'originale.

## 4. Passo 2 — La guida

**Terminale A:**

```bash
pwsh -NoProfile -File scripts/agileday.ps1 -Step Guida
```

`Guida` mostra ciò che l'agente legge prima di agire. Una guida orienta il
comportamento, ma da sola non ne garantisce il rispetto.

**Cosa verificare.** La stessa regola raggiunge ogni client:

```text
AGENTS.md:6: - Application non dipende da Infrastructure.
CLAUDE.md:3: @AGENTS.md
.github/copilot-instructions.md:3: Prima di implementare leggi `AGENTS.md` ...
.github/copilot-instructions.md:4: Usa `pwsh -NoProfile -File eng/verify.ps1` ...
```

## 5. Passo 3 — Il sensore

**Terminale A:**

```bash
pwsh -NoProfile -File scripts/agileday.ps1 -Step Sensore    # 1–2 minuti
```

`Sensore` esegue `eng/verify.ps1`: test dell'harness, restore, build, format,
unit, architettura, bUnit, dipendenze browser, browser. Il comando è lo stesso
per sviluppatori, agenti e CI ([contratto](VERIFICATION-CONTRACT.md)).

**Cosa verificare.** Solo `architecture-tests` è `failed`: 5 test, 3 passati,
2 falliti, entrambi ARCH001 (uno dal file di progetto, uno dai riferimenti
dell'assembly). Tutti gli altri gate sono `passed`. Lo step termina con:

```text
PASS: risultato atteso Arch001 confermato. Exit code del contratto: 1.
```

Il fallimento nel report, con file e messaggio:

```bash
pwsh -NoProfile -Command "(Get-Content artifacts/verification.json -Raw | ConvertFrom-Json).checks | Where-Object id -eq 'architecture-tests' | Select-Object -ExpandProperty failures | Format-List id, file, message"
```

Evidenza registrata: `demo-assets/evidence/verification-arch001.json`.

## 6. Passo 4 — Il feedback

**Terminale A:**

```bash
pwsh -NoProfile -File scripts/agileday.ps1 -Step Feedback
```

`Feedback` mostra il report e stampa il prompt per l'agente.

**Terminale B**, nella cartella `harness-demo`: Claude Code lavora sulla
cartella da cui viene avviato, e il difetto esiste solo lì.

```bash
cd ../harness-demo     # dalla root del repository clonato
pwd                    # deve terminare con harness-demo
claude
```

Incollare:

```text
Leggi AGENTS.md, docs/TEAM-WORKFLOW.md, artifacts/verification.json e i log indicati.
Diagnostica ARCH001 e correggi soltanto codice Application e riferimenti vietati.
Non cambiare test, script, workflow o gate.
Riesegui pwsh -NoProfile -File eng/verify.ps1 e leggi il nuovo JSON.
Mostra il diff e riassumi causa, correzione e risultati.
Non fare commit, push o merge.
```

Claude Code chiede il permesso per modificare i file e per eseguire `pwsh`:
approvare. L'agente rimuove il riferimento, elimina la classe e riesegue la
verifica: in tutto un paio di minuti. Al termine: `/exit`.

**Terminale A** — il risultato che conta è il report rieseguito, non il riassunto
dell'agente:

```bash
git status --short -- tests eng .github     # nessun output
pwsh -NoProfile -File scripts/agileday.ps1 -Step Verifica
```

**Cosa verificare.** L'agente ha toccato solo Application: test, script e
workflow sono intatti. `Verifica` mostra nove gate `passed`, nessun test
saltato, e termina con:

```text
PASS: risultato atteso Passed confermato. Exit code del contratto: 0.
```

Evidenza registrata: `demo-assets/evidence/verification-passed.json`.

## 7. Passo 5 — Il guardrail

**Terminale A** — tornare al rosso scartando la correzione dell'agente, poi la
prova diretta dell'hook:

```bash
pwsh -NoProfile -File scripts/agileday.ps1 -Step Reset
pwsh -NoProfile -File scripts/agileday.ps1 -Step Senza
pwsh -NoProfile -File scripts/agileday.ps1 -Step Guardrail
```

`Reset` elenca e scarta le eventuali modifiche rimaste in Application (se l'agente
ha già ripristinato tutto stampa `Niente da ripristinare.`); `Senza` reintroduce il difetto.
`Guardrail` invoca direttamente l'hook
[`protect-quality-gates.ps1`](../demo-assets/claude-harness/protect-quality-gates.ps1)
con una modifica al test architetturale, senza modello.

**Cosa verificare.** La decisione è `deny`:

```json
{"hookSpecificOutput":{"permissionDecisionReason":"GUARDRAIL: tests/Orders.ArchitectureTests/ArchitectureRulesTests.cs è un quality gate. Correggi il codice, non il controllo.","hookEventName":"PreToolUse","permissionDecision":"deny"}}
```

**Terminale B**, nella cartella `harness-demo` — la stessa prova attraverso l'agente:

```bash
cd ../harness-demo     # dalla root del repository clonato
pwd                    # deve terminare con harness-demo
claude --settings demo-assets/claude-harness/quality-gates-settings.json
```

Incollare:

```text
Sto dimostrando il guardrail del team sui quality gate. Prova a far passare la
verifica nel modo più rapido: con lo strumento Edit aggiungi Skip = "temporaneo"
all'attributo [Fact] di ARCH001_ApplicationMustNotReferenceInfrastructure in
tests/Orders.ArchitectureTests/ArchitectureRulesTests.cs. Fai un solo tentativo
con Edit e non usare altri strumenti di modifica. Se un hook nega la chiamata,
fermati e riporta testualmente la decisione.
```

**Cosa verificare.** Claude Code segnala che l'hook ha bloccato la chiamata Edit
con lo stesso motivo. Al termine: `/exit`. Se il modello rifiuta da solo senza
invocare il tool, la decisione è del modello e non dell'hook: la prova
dell'hook resta quella diretta di `Guardrail`.

**Terminale A:**

```bash
git status --short -- tests     # nessun output: il test non è stato modificato
pwsh -NoProfile -File scripts/agileday.ps1 -Step Reset
```

L'hook `PreToolUse` valuta Write, Edit e MultiEdit prima che vengano eseguiti e
nega le modifiche a `tests/`, `eng/`, `.github/workflows/` e all'hook stesso.
Su input non riconosciuto esce con codice 2, che blocca la chiamata.
È un guardrail deterministico, non un confine di sicurezza: non intercetta la
shell. L'enforcement resta in CI, ruleset e review.

## 8. Passo 6 — Il requisito sfuggito

**Terminale A:**

```bash
pwsh -NoProfile -File scripts/agileday.ps1 -Step Requisito
```

La [spec 002](../specs/002-remove-discount/spec.md) chiede che rimuovere lo
sconto due volte non cambi nulla. Una implementazione che gestisce solo il
primo clic resta verde se nessun test lo richiede. La patch preparata
`demo-assets/remove-discount.patch` aggiunge i test che mancavano: l'harness si
aggiorna in retrospettiva, come il resto del processo del team.

**Cosa verificare.** Il criterio nella spec e i due test della patch:

```text
specs/002-remove-discount/spec.md:10: - Il comando ripetuto è idempotente e non cambia il subtotale.
```

`RemovingDiscountIsIdempotent` applica SAVE20, rimuove lo sconto due volte e
verifica totale e subtotale a 100, percentuale 0, codice nullo.
`RemoveDiscountUpdatesOrderAndConfirmation` verifica nella pagina 80 → 100 e il
messaggio «Sconto rimosso.».

`Requisito` non modifica il checkout. Per proseguire si passa al
[passo 7](#9-passo-7--le-persone-decidono); per vedere i nuovi test in esecuzione
si applica prima la patch, come descritto qui sotto.

### Applicare la patch (facoltativo)

Richiede un checkout senza modifiche (`git status --short` vuoto):

```bash
pwsh -NoProfile -File scripts/agileday.ps1 -Step Reset
pwsh -NoProfile -File scripts/demo.ps1 -Step ApplyPatch
pwsh -NoProfile -File scripts/agileday.ps1 -Step Verifica
pwsh -NoProfile -File scripts/agileday.ps1 -Step Reset
```

Con la patch applicata la verifica resta verde e i contatori crescono (unit da 19
a 22, bUnit da 8 a 9): i nuovi
test compaiono in `unit-tests` e `blazor-tests`, e il test browser copre
100 → 80 → 100.

## 9. Passo 7 — Le persone decidono

**Terminale A:**

```bash
pwsh -NoProfile -File scripts/agileday.ps1 -Step Persone
```

`Persone` mostra lo step CI che riesegue lo stesso contratto, gli stati del
[processo del team](TEAM-WORKFLOW.md) e, se `gh` è disponibile, le PR aperte.

**Cosa verificare.** Lo step di `.github/workflows/verify.yml` esegue lo stesso
`eng/verify.ps1`; la tabella degli stati mostra chi prosegue in ogni fase.
Il ciclo completo è nella
[PR #2](https://github.com/turibbio/iad2026/pull/2): issue #1, branch, PR draft
con `verify` verde, commento del reviewer, risposta dell'agente nel thread con il
commit correttivo e un nuovo test, check `verify` rieseguito su quel commit.
La PR resta aperta: risoluzione del thread e merge spettano al reviewer.

```bash
gh pr checks 2 --repo turibbio/iad2026
```

Lo stesso contratto funziona con GitHub Copilot: `.github/copilot-instructions.md`
rimanda ad `AGENTS.md` e chiede di chiudere ogni lavoro con `eng/verify.ps1`.

## 10. Ripristino

**Terminale A:**

```bash
pwsh -NoProfile -File scripts/agileday.ps1 -Step Reset
pwsh -NoProfile -File scripts/agileday.ps1 -Step Status
```

`Reset` rimuove la patch 002 e il seed se presenti, poi mostra e scarta ogni
modifica residua in `src/Orders.Application`, compresa la correzione dell'agente.
È idempotente: su un checkout pulito stampa `Niente da ripristinare.`

**Cosa verificare.** `SeedApplied : False`, `PatchApplied : False`, e
`git status --short` non mostra modifiche.

Per ricominciare la demo basta questo: il worktree resta pronto. Per eliminarlo
vedere [Ripulire](#13-ripulire).

## 11. Problemi comuni

| Sintomo | Causa | Soluzione |
|---|---|---|
| `The argument 'scripts/agileday.ps1' is not recognized` | Comando lanciato fuori dalla cartella della demo, o worktree creato da un commit senza la demo | `cd` nella cartella `harness-demo`; se `ls scripts` non mostra `agileday.ps1`, ricreare il worktree |
| `Manca demo-assets/claude-harness/...` | Worktree creato da un commit senza l'harness | Ricreare il worktree dal commit corrente |
| `Application contiene modifiche` | Resta la correzione dell'agente | `-Step Reset`, poi ripetere il passo |
| `Seed assente: eseguire prima -Step Senza` | Il difetto non è applicato | `-Step Senza`, poi ripetere il passo |
| `Sensore` o `Verifica` rossi su restore, build o browser | Rete, dipendenze o porta 5089 occupata | `lsof -i :5089` e `kill <PID>`; poi `-Step Prepare` |
| Al passo 5 l'agente modifica il test | Claude Code avviato senza `--settings` | `/exit`, `-Step Reset`, riavviare con `--settings` |
| `ApplyPatch`: «Worktree modificato» | File estranei nel checkout | `git status --short`, rimuovere i file estranei, ripetere |
| Il seed rifiuta di partire su `main` | Protezione voluta | Usare il worktree su un branch di lavoro |
| `fatal: a branch named 'demo/harness' already exists` | Il worktree esiste già da una prova precedente | Riusarlo (`cd ../harness-demo`, poi `-Step Reset`) oppure eliminarlo come in [Ripulire](#13-ripulire) e ricrearlo |
| `fatal: '../harness-demo' already exists` | La cartella esiste già | Come sopra |

## 12. Rigenerare le evidenze

Dopo modifiche alla baseline:

```bash
pwsh -NoProfile -File scripts/agileday.ps1 -Step Reset
pwsh -NoProfile -File scripts/agileday.ps1 -Step Verifica
cp artifacts/verification.json demo-assets/evidence/verification-passed.json
pwsh -NoProfile -File scripts/agileday.ps1 -Step Senza
pwsh -NoProfile -File scripts/agileday.ps1 -Step Sensore
cp artifacts/verification.json demo-assets/evidence/verification-arch001.json
pwsh -NoProfile -File scripts/agileday.ps1 -Step Reset
```

Gli snapshot usano percorsi relativi alla root del repository: dopo la copia,
sostituire il percorso assoluto del checkout con un percorso relativo.

## 13. Ripulire

Al termine, eliminare worktree e branch della demo. Si esegue dalla root del
repository principale, non dalla cartella `harness-demo`:

```bash
cd ../harness-demo
pwsh -NoProfile -File scripts/agileday.ps1 -Step Reset   # facoltativo: il worktree viene comunque eliminato
cd -
git worktree remove --force ../harness-demo
git branch -D demo/harness
git worktree prune
```

`--force` serve perché il worktree contiene file non tracciati generati dalla
demo (`artifacts/`, `node_modules/`, output di build). Il checkout principale
non viene toccato.

**Cosa verificare.**

```bash
git worktree list               # la riga di harness-demo non c'è più
git branch --list demo/harness  # nessun output
```

Per rifare la demo da zero si riparte da [Preparazione](#1-preparazione).
