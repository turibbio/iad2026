# GitHub Actions e governance

Il workflow `quality-gates / verify` prepara .NET 10, Node 22 e Chromium, poi
esegue lo stesso comando locale `pwsh -NoProfile -File eng/verify.ps1`. Il YAML
prepara il runtime; la logica dei gate vive in PowerShell. Permessi
`contents: read`, timeout del job 15 minuti. Report JSON, TRX/JUnit, log e trace
browser dei test falliti sono pubblicati come artifact anche in caso di errore.

Il workflow da solo non impedisce un merge: lo rende obbligatorio il ruleset.

## Ruleset del branch principale

1. Settings → Rules → Rulesets → New branch ruleset, nome `main-quality`.
2. Enforcement *Active*; target il branch di default; nessun bypass non necessario.
3. *Require a pull request before merging*, con una approvazione.
4. *Dismiss stale approvals* e *Require approval of the most recent reviewable push*.
5. *Require review from Code Owners*: `CODEOWNERS` protegge workflow, `eng/`,
   test, script, constitution, `AGENTS.md` e proprietà di build.
6. *Require status checks to pass*: selezionare `verify` e richiedere il branch aggiornato.
7. *Block force pushes* e *Restrict deletions*. Verificare il ruleset con una PR.

Un owner non può approvare la propria PR: la review CODEOWNERS richiede almeno
un secondo maintainer con permessi di scrittura elencato in `CODEOWNERS`.
Su repository privati alcune protezioni dipendono dal piano GitHub.

## Controlli in sola lettura

```bash
gh pr checks <numero>
gh api repos/{owner}/{repo}/rulesets
gh api repos/{owner}/{repo}/branches/main/protection
```

Nessun merge automatico: la decisione resta al reviewer.
