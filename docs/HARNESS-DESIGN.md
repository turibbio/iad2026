# Progettare e far evolvere l'harness

Il contratto di verifica è una parte dell'harness. L'harness comprende anche
specifiche, istruzioni, strumenti, permessi e review: tutto ciò che il team
costruisce attorno all'agente perché il suo lavoro sia affidabile.

## Guide, sensori, persone

Birgitta Böckeler distingue le guide, che orientano il lavoro prima che avvenga,
dai sensori, che restituiscono feedback dopo, e descrive un ciclo umano di
miglioramento dell'harness
([Harness engineering for coding agent users](https://martinfowler.com/articles/harness-engineering.html)).
In Orders la distinzione si traduce così:

| Esigenza | Guida | Sensore o controllo | Cosa resta alla review |
|---|---|---|---|
| Requisiti sullo sconto | spec/plan/tasks in `specs/` | Unit, bUnit e browser | I casi di test rappresentano il requisito? |
| Dipendenze tra livelli | `AGENTS.md`, `ARCHITECTURE.md` | Test architetturali ARCH001/ARCH002 | Scelte progettuali non codificate in regole |
| Diagnosi dell'agente | `VERIFICATION-CONTRACT.md` | JSON 2.0, exit code e log | Il verde vale per i controlli eseguiti su quello SHA |
| Correzioni sulla PR | `TEAM-WORKFLOW.md` | Commento, commit correttivo, CI corrente | Accettazione del reviewer |
| Autorizzazione al merge | `GITHUB-SETUP.md` | Ruleset, required check, CODEOWNERS | Decisione umana |

I controlli automatici applicano regole ripetibili. Requisiti, usabilità e
tradeoff richiedono il giudizio di una persona. Una review svolta da un modello
aggiunge un parere, non un'autorizzazione al merge.

## Due distinzioni da non confondere

- **Harness del client e harness del progetto.** Il client (Claude Code, Copilot,
  Codex) fornisce tool, permessi e hook. Il team definisce specifiche, contratto
  e processo. Il secondo sopravvive al cambio del primo.
- **Feedback durante il lavoro e valutazione del risultato.** Lo stesso report
  serve all'agente per correggersi in locale e al reviewer per valutare la PR.

## Mettere alla prova il sensore

Un sensore che non è mai stato visto fallire non è un sensore. Da una baseline
committata:

```bash
bash scripts/check-architecture-sensor.sh
```

Lo script crea un worktree temporaneo sullo SHA corrente, applica il difetto
ARCH001 ed esegue il contratto completo. Riesce soltanto se il report fallisce
per `architecture-tests` con ARCH001 e tutti gli altri gate passano. Conserva
report e log sotto `artifacts/architecture-sensor.*/evidence`, poi rimuove
worktree e branch. Un fallimento di altri gate o dell'ambiente fa fallire la
prova: non dimostra che il sensore funzioni.

## L'harness impara dagli errori

Quando un difetto supera i controlli, il team lo riconduce al criterio della
specifica e al controllo che avrebbe dovuto rilevarlo, distinguendo tra
requisito ambiguo, controllo assente, falso positivo e problema d'ambiente.
La correzione aggiorna la guida o il test pertinente e include un caso che
riproduce il problema. Non si allenta mai un controllo per far passare un diff:
le modifiche ai gate sono incarichi separati con review indipendente.

La feature 002 ne è l'esempio: «rimuovi sconto» deve essere idempotente, e una
versione che gestisce solo il primo clic sarebbe verde senza un test dedicato.
La patch preparata aggiunge quel test. Ripetere la stessa istruzione all'agente
senza capire perché non ha funzionato non aggiunge un controllo.

## Il verde e il requisito

La CI esegue lo stesso contratto locale sul commit remoto: non esiste una suite
nascosta all'agente. Una nuova esecuzione conferma la riproducibilità, non che
i valori attesi nei test siano quelli del requisito. Se codice e test si
aspettassero entrambi 90 euro per SAVE20 al 20% su 100, sarebbero coerenti tra
loro e sbagliati rispetto alla specifica. È la review a ricondurre i valori
attesi al requisito e a cercare i casi mancanti.

## Contesto e ripresa del lavoro

Una richiesta come «aggiungi un pulsante per togliere lo sconto» lascia impliciti
comportamenti importanti. Prima di implementare conviene far esplicitare le attese:

```text
Leggi AGENTS.md, .specify/memory/constitution.md e spec, plan e tasks in
specs/002-remove-discount. Indica il comportamento atteso, i livelli coinvolti
e i controlli pertinenti. Non fare modifiche in questa fase.
```

La risposta va confrontata con la specifica: totale ripristinato, stato dello
sconto azzerato, comando idempotente, ordine assente senza salvataggi, messaggi
puliti, logica in Domain/Application e Razor che invoca Application.

Per riprendere il lavoro in un'altra sessione, un riepilogo con dati reali:

```text
Obiettivo: rimuovere lo sconto, spec 002
Branch e HEAD: <branch> / <SHA>
Working tree: <pulito oppure modifiche non committate>
Completato: <criteri coperti e file modificati>
Verifica locale: <risultato e SHA verificato>
CI: <URL run, SHA, stato>
Feedback: <URL commento oppure nessuno>
Prossimo passo: <azione concreta>
```

Il riepilogo orienta; branch, diff e report effettivi restano la fonte di verità.
Se il codice è cambiato dopo la verifica, il contratto va rieseguito.

## Valore e costo

Ogni controllo ha un costo: scriverlo, mantenerlo, attenderlo. Naresh Jain ne
discute in [Are Harnesses Worth the Cost?](https://martinfowler.com/articles/are-harnesses-worth-the-cost.html).
Per valutare l'harness di un progetto conviene registrare insieme risultati e
risorse impiegate:

| Dato | A cosa serve |
|---|---|
| Compito, baseline e SHA | Identificare il lavoro osservato |
| Client, modello e impostazioni | Descrivere le condizioni |
| Criteri soddisfatti ed esito dei gate | Valutare il risultato |
| Tempo fino alla PR verificata | Osservare il ciclo completo |
| Correzioni e interventi umani | Misurare il lavoro dopo il primo tentativo |
| Preparazione e manutenzione di guide e test | Valutare il costo del processo |
| Token e costo del modello | Descrivere l'uso del modello, con il metodo di stima |

Un singolo tentativo non misura la regolarità: il confronto richiede più prove
con compito, condizioni iniziali e criteri espliciti. Il punto di partenza
consigliato è il vincolo che ha già causato un problema reale.

## Esecuzione locale e runner dedicati

Un runner in VM o container isola checkout e dipendenze e rende l'esecuzione
ripetibile; permessi, credenziali, aggiornamenti e pulizia vanno comunque gestiti.
Il luogo in cui gira il codice è distinto dal servizio che fornisce il modello.
Qui il contratto gira in locale e su GitHub Actions; runner dedicati sono
un'evoluzione da motivare con esigenze concrete.
