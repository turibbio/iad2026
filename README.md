# Harness engineering per coding agent — .NET 10 e Blazor

Come rendere affidabile un coding agent: non con un prompt migliore, ma con il
sistema che il team gli costruisce attorno. Guide che orientano prima, sensori
che osservano dopo, persone che decidono.

Il repository contiene un'applicazione reale (Orders, Blazor Web App) e l'harness
completo che la circonda: istruzioni per gli agenti, un contratto di verifica
unico per persone, agenti e CI, un guardrail per Claude Code e un processo di
review su GitHub. È il materiale della sessione «Harness engineering: come
rendere affidabile un coding agent» presentata ad Agile Day 2026, Cosenza.

Slide della sessione: [PDF](slides/harness-engineering-agile-day-2026.pdf).

## La demo in sette passi

```bash
pwsh -NoProfile -File scripts/agileday.ps1 -Step Status
```

| Passo | Comando `-Step` | Strato |
|---|---|---|
| 1 | `Senza` | Senza harness: la scorciatoia architetturale |
| 2 | `Guida` | `AGENTS.md` orienta l'agente |
| 3 | `Sensore` | Il contratto di verifica diventa rosso su ARCH001 |
| 4 | `Feedback`, `Verifica` | Il report JSON guida la correzione dell'agente |
| 5 | `Guardrail` | Un hook nega le modifiche ai quality gate |
| 6 | `Requisito` | Un criterio non coperto diventa un test |
| 7 | `Persone` | CI, PR e review: il merge resta umano |

`Reset` riporta il checkout alla baseline. Dettagli, prompt ed evidenze:
[docs/DEMO.md](docs/DEMO.md).

## Avvio e verifica

Prerequisiti: .NET SDK 10 (`global.json`), PowerShell 7.4+, Node 22, Git.

```bash
npm ci --prefix tests/browser
npm exec --prefix tests/browser -- playwright install chromium
pwsh -NoProfile -File eng/verify.ps1
cat artifacts/verification.json
dotnet run --project src/Orders.Web --launch-profile http
```

Su Linux: `npm exec --prefix tests/browser -- playwright install --with-deps chromium`.
L'app è su <http://localhost:5078>: ordine da 100 euro, codice SAVE20 al 20% → 80 euro.
Il repository è in-memory e scoped al circuito Blazor: ogni visita riparte da 100.

`eng/verify.ps1` esegue nove gate (test dell'harness, restore, build, format,
unit, architettura, bUnit, npm, browser) e scrive un report JSON con stato,
contatori, fallimenti e log di ciascuno. GitHub Actions esegue lo stesso comando
sullo SHA della PR.

## Struttura

| Percorso | Ruolo nell'harness |
|---|---|
| `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md` | Guide: vincoli letti dall'agente prima di agire |
| `.specify/`, `specs/` | Guide: constitution e specifiche Spec Kit |
| `eng/verify.ps1`, `tests/` | Sensori: contratto di verifica e test a più livelli |
| `demo-assets/claude-harness/` | Guardrail: hook `PreToolUse` per Claude Code |
| `.github/workflows/`, `.github/CODEOWNERS`, template | Persone: CI, ownership e review |
| `.claude/agents/`, `.github/agents/`, `.agents/skills/` | Ruoli facoltativi per Claude Code, Copilot e Codex |
| `scripts/`, `demo-assets/` | Regia della demo, difetto seminato, patch ed evidenze |

## Documentazione

- [La demo in sette passi](docs/DEMO.md)
- [Progettare e far evolvere l'harness](docs/HARNESS-DESIGN.md)
- [Contratto di verifica](docs/VERIFICATION-CONTRACT.md)
- [Architettura di Orders](docs/ARCHITECTURE.md)
- [Un agente nel processo del team](docs/TEAM-WORKFLOW.md)
- [Ruoli facoltativi degli agenti](docs/AGENT-ROLES.md)
- [Spec Kit](docs/SPECKIT-SETUP.md)
- [GitHub Actions e governance](docs/GITHUB-SETUP.md)

## Riferimenti

- Birgitta Böckeler, [Harness engineering for coding agent users](https://martinfowler.com/articles/harness-engineering.html), martinfowler.com
- Naresh Jain, [Are Harnesses Worth the Cost?](https://martinfowler.com/articles/are-harnesses-worth-the-cost.html), martinfowler.com

## Autore

Antonio Liccardi — CTO @ Blexin, Microsoft MVP for Dev Technologies.
Per percorsi di formazione e affiancamento sull'harness engineering con coding
agent: <antonio.liccardi@blexin.com>.
