# Spec Kit

Il repository include gli asset di [Spec Kit](https://github.com/github/spec-kit)
1.1.3 con script PowerShell: skill, template, script e constitution sono già
tracciati, quindi un clone basta per usarli. Non servono Python, `uv` o la CLI
`specify`. Gli adapter per Copilot, Claude Code e Codex sono generati con
`--script ps`.

Spec Kit organizza il lavoro; il contratto `eng/verify.ps1` lo verifica.

## Uso

Flusso: constitution → specification → plan → tasks → implementation → verifica.

In Copilot e Claude Code: `/speckit-constitution`, `/speckit-specify`,
`/speckit-plan`, `/speckit-tasks`, `/speckit-implement`, `/speckit-converge`.
In Codex le skill corrispondenti (`$speckit-plan`, ecc.).

Per lavorare su una feature esistente senza creare branch, selezionarla in modo esplicito:

```powershell
$env:SPECIFY_FEATURE_DIRECTORY = Join-Path $PWD 'specs/002-remove-discount'
./.specify/scripts/powershell/check-prerequisites.ps1 -Json -RequireSpec -RequireTasks
./.specify/scripts/powershell/setup-plan.ps1 -Json
./.specify/scripts/powershell/setup-tasks.ps1 -Json
```

Gli script preservano il piano esistente. `pwsh -NoProfile -File scripts/demo.ps1 -Step Spec`
esegue il controllo dei prerequisiti e mostra spec, plan e tasks della feature 002.

## Aggiornare gli asset

Per rigenerarli con la CLI ufficiale (richiede Python 3.11+, in un ambiente separato):

```bash
specify init artifacts/spec-kit-preview --script ps --integration copilot --ignore-agent-tools --non-interactive
cd artifacts/spec-kit-preview
specify integration install claude --script ps --force
specify integration install codex --script ps --force --integration-options='--skills'
```

Confrontare i file prima di copiarli e preservare constitution e istruzioni custom.
`.specify/scripts/powershell/common.ps1` è adattato: il parser dei preset YAML
usa `ConvertFrom-Yaml` invece di un processo Python. Il modulo `powershell-yaml`
serve solo a chi aggiunge preset YAML; i test coprono composizione e validazione
dei preset con un parser sostitutivo. Poiché il file differisce dall'upstream,
una verifica d'integrità basata sugli hash dei manifest lo segnala come modificato.
