# Ruoli facoltativi

Un solo agente basta: legge `AGENTS.md`, constitution e specifica; implementa e
testa; esegue `pwsh -NoProfile -File eng/verify.ps1`; legge JSON e log; corregge;
propone il diff.

| Ruolo | Output | Uso |
|---|---|---|
| Implementation | Codice, test, evidenza | Percorso principale |
| Verification | ID del gate, prova, diagnosi, fix minimo | Dopo un report fallito |
| Review | Problemi concreti, gravità, file | Contesto separato sul diff |

La fonte di verità operativa è `AGENTS.md`: i profili rimandano alle stesse
specifiche e allo stesso contratto, senza copiare le regole di business.

| Client | Dove | Note |
|---|---|---|
| GitHub Copilot | `.github/agents/*.agent.md` | Review e verification limitate a read/search ([docs](https://docs.github.com/en/copilot/reference/custom-agents-configuration)) |
| Claude Code | `.claude/agents/*.md` | Review e verification limitate a Read/Grep/Glob ([docs](https://code.claude.com/docs/en/sub-agents)) |
| Codex | `.agents/skills/harness-*/SKILL.md` | Skill riusabili, non subagenti ([docs](https://developers.openai.com/codex/skills)) |

Le skill Spec Kit generate sono separate da questi tre workflow.

Delegare ha senso per una lettura del diff con contesto separato o per diagnosi
parallele davvero indipendenti. Aggiunge costo, coordinamento e rischio di
modifiche concorrenti: per una modifica piccola non serve.

Le istruzioni non sono una sandbox. Un agente che rivede aggiunge un parere ma
non sostituisce la review umana richiesta dal processo; la CI riesegue lo stesso
contratto sul commit remoto e le policy GitHub applicano le condizioni di merge.
