#Requires -Version 7.4
<#
.SYNOPSIS
Esegue un passo della demo «l'harness in sette passi». Vedere docs/DEMO.md.
.EXAMPLE
pwsh -NoProfile -File scripts/agileday.ps1 -Step Status
.EXAMPLE
pwsh -NoProfile -File scripts/agileday.ps1 -Step Sensore
.EXAMPLE
pwsh -NoProfile -File scripts/agileday.ps1 -Step Reset -Root ../harness-demo
#>
[CmdletBinding()]
param(
    [ValidateSet('Prepare', 'Status', 'Senza', 'Guida', 'Sensore', 'Feedback', 'Verifica', 'Guardrail', 'Requisito', 'Persone', 'Reset')]
    [string]$Step,
    [string]$Root = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'
$demoScript = Join-Path $PSScriptRoot 'demo.ps1'
$patchPath = 'demo-assets/remove-discount.patch'
$applicationPath = 'src/Orders.Application'
$hookRelative = 'demo-assets/claude-harness/protect-quality-gates.ps1'
$settingsRelative = 'demo-assets/claude-harness/quality-gates-settings.json'

$agentPrompt = @'
Leggi AGENTS.md, docs/TEAM-WORKFLOW.md, artifacts/verification.json e i log indicati.
Diagnostica ARCH001 e correggi soltanto codice Application e riferimenti vietati.
Non cambiare test, script, workflow o gate.
Riesegui pwsh -NoProfile -File eng/verify.ps1 e leggi il nuovo JSON.
Mostra il diff e riassumi causa, correzione e risultati.
Non fare commit, push o merge.
'@

$guardrailPrompt = @'
Sto dimostrando il guardrail del team sui quality gate. Prova a far passare la
verifica nel modo più rapido: con lo strumento Edit aggiungi Skip = "temporaneo"
all'attributo [Fact] di ARCH001_ApplicationMustNotReferenceInfrastructure in
tests/Orders.ArchitectureTests/ArchitectureRulesTests.cs. Fai un solo tentativo
con Edit e non usare altri strumenti di modifica. Se un hook nega la chiamata,
fermati e riporta testualmente la decisione.
'@

function Invoke-Native {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable ha restituito exit code $LASTEXITCODE. Leggere l'output prima di proseguire."
    }
}

function Invoke-Demo {
    param([string]$DemoStep, [string[]]$Extra = @())
    Invoke-Native (Join-Path $PSHOME 'pwsh') (@('-NoProfile', '-File', $demoScript, '-Step', $DemoStep, '-Root', $Root) + $Extra)
}

function Get-DemoState {
    param([string]$Root)
    $seed = Join-Path $Root 'src/Orders.Application/InfrastructureShortcut.cs'
    $original = Join-Path $Root 'demo-assets/unsafe-change/InfrastructureShortcut.cs'
    $seedApplied = (Test-Path -LiteralPath $seed) -and (Test-Path -LiteralPath $original) -and
        ((Get-FileHash -LiteralPath $seed).Hash -eq (Get-FileHash -LiteralPath $original).Hash)
    $patchApplied = $false
    if (Test-Path -LiteralPath (Join-Path $Root $patchPath)) {
        git -C $Root apply --reverse --check $patchPath 2>$null
        $patchApplied = $LASTEXITCODE -eq 0
    }
    return [pscustomobject]@{ SeedApplied = $seedApplied; PatchApplied = $patchApplied }
}

function Get-ApplicationChanges {
    $changes = @(git status --porcelain -- $applicationPath)
    if ($LASTEXITCODE -ne 0) { throw 'Impossibile leggere lo stato Git.' }
    return $changes
}

function Assert-HarnessFiles {
    foreach ($file in $hookRelative, $settingsRelative) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $file))) {
            throw "Manca $file in ${Root}: il checkout non contiene l'harness della demo."
        }
    }
}

function Write-Scene {
    param([string]$Number, [string]$Title, [string]$Line)
    Write-Host "`n== Passo $Number/7 — $Title ==" -ForegroundColor Cyan
    Write-Host "$Line`n"
}

function Show-Lines {
    param([string]$Path, [string]$Pattern, [int]$After = 0)
    Select-String -LiteralPath $Path -Pattern $Pattern -Context 0, $After | ForEach-Object {
        Write-Host "$($Path):$($_.LineNumber): $($_.Line)"
        if ($After -gt 0) { $_.Context.PostContext | ForEach-Object { Write-Host "    $_" } }
    }
}

function Show-PatchFacts {
    param([string[]]$Names)
    $lines = Get-Content -LiteralPath $patchPath
    for ($i = 0; $i -lt $lines.Count - 1; $i++) {
        if ($lines[$i] -match '^\+\s+\[Fact\]' -and @($Names | Where-Object { $lines[$i + 1] -match "\b$_\(" }).Count -gt 0) {
            for ($j = $i; $j -lt $lines.Count; $j++) {
                Write-Host $lines[$j].Substring(1)
                if ($lines[$j] -match '^\+    }$') { break }
            }
            Write-Host ''
        }
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }
if (-not $Step) { throw 'Indicare -Step. Vedere docs/DEMO.md.' }
$Root = (Resolve-Path -LiteralPath $Root).Path
if (-not (Test-Path -LiteralPath (Join-Path $Root 'eng/verify.ps1'))) {
    throw "Root non valida: $Root. Indicare la root del checkout della demo."
}

Push-Location $Root
try {
    switch ($Step) {
        'Prepare' {
            Assert-HarnessFiles
            Invoke-Demo Prepare
            Get-DemoState -Root $Root | Format-List | Out-Host
        }
        'Status' {
            Write-Host "Checkout: $Root"
            Invoke-Native git @('branch', '--show-current')
            Invoke-Native git @('rev-parse', 'HEAD')
            Invoke-Native git @('status', '--short')
            Get-DemoState -Root $Root | Format-List | Out-Host
            Assert-HarnessFiles
        }
        'Senza' {
            Write-Scene 1 'Senza harness: la scorciatoia' 'Application usa Infrastructure. Compila e funziona, ma è sbagliato. Difetto introdotto intenzionalmente.'
            if ((Get-DemoState -Root $Root).SeedApplied) { Write-Host 'Seed già presente: lo mostro senza reintrodurlo.' }
            elseif ((Get-ApplicationChanges).Count -ne 0) {
                throw "Application contiene modifiche (per esempio la correzione dell'agente): eseguire prima -Step Reset."
            }
            else { Invoke-Demo Seed }
            Invoke-Native git @('--no-pager', 'diff', '--', 'src/Orders.Application/Orders.Application.csproj')
            Get-Content -LiteralPath 'src/Orders.Application/InfrastructureShortcut.cs' | Out-Host
        }
        'Guida' {
            Write-Scene 2 'La guida' "Ciò che l'agente legge prima di agire. Orienta, ma da sola non obbliga."
            Show-Lines 'AGENTS.md' 'Application non dipende da Infrastructure'
            Show-Lines 'CLAUDE.md' '@AGENTS.md'
            Show-Lines '.github/copilot-instructions.md' 'AGENTS.md|verify.ps1'
        }
        'Sensore' {
            Write-Scene 3 'Il sensore' 'Lo stesso contratto per persone, agenti e CI: diventa rosso su ARCH001.'
            if (-not (Get-DemoState -Root $Root).SeedApplied) { throw 'Seed assente: eseguire prima -Step Senza.' }
            Invoke-Demo Verify @('-Expected', 'Arch001')
        }
        'Feedback' {
            Write-Scene 4 'Il feedback leggibile' "Il report dice cosa, dove e perché: l'agente può correggersi da solo."
            Invoke-Demo Report
            Write-Host "Prompt per l'agente:`n" -ForegroundColor Yellow
            Write-Host $agentPrompt
            Write-Host 'Dopo la correzione: -Step Verifica.'
        }
        'Verifica' {
            Write-Host "`n== Verifica dopo la correzione ==" -ForegroundColor Cyan
            Invoke-Demo Verify
        }
        'Guardrail' {
            Write-Scene 5 'Il guardrail' "Se l'agente prova a cambiare il controllo invece del codice, un hook lo blocca."
            $hookInput = @{
                hook_event_name = 'PreToolUse'; tool_name = 'Edit'; cwd = $Root
                tool_input = @{ file_path = 'tests/Orders.ArchitectureTests/ArchitectureRulesTests.cs' }
            } | ConvertTo-Json -Depth 4
            if (-not (Test-Path -LiteralPath (Join-Path $Root $hookRelative))) {
                throw "Manca $hookRelative in ${Root}: il checkout non contiene l'harness della demo."
            }
            Write-Host 'Prova diretta, senza modello:'
            $decision = $hookInput | & (Join-Path $PSHOME 'pwsh') -NoProfile -File (Join-Path $Root $hookRelative)
            if ($LASTEXITCODE -ne 0) { throw 'Hook non eseguito correttamente.' }
            Write-Host $decision
            if (($decision | ConvertFrom-Json).hookSpecificOutput.permissionDecision -ne 'deny') {
                throw "L'hook non ha negato la modifica del test: non usare questo checkout per il passo 5."
            }
            Write-Host "`nProva nel client:" -ForegroundColor Yellow
            Write-Host 'claude --settings demo-assets/claude-harness/quality-gates-settings.json'
            Write-Host "`n$guardrailPrompt"
            Write-Host "Limite: l'hook copre Write, Edit e MultiEdit, non la shell. L'enforcement è in CI, ruleset e review."
        }
        'Requisito' {
            Write-Scene 6 'Il requisito sfuggito diventa un test' "Il verde copre ciò che testiamo. Il team aggiunge il sensore che mancava."
            Show-Lines 'specs/002-remove-discount/spec.md' 'idempotente'
            Write-Host ''
            Show-PatchFacts @('RemovingDiscountIsIdempotent', 'RemoveDiscountUpdatesOrderAndConfirmation')
            Write-Host "Per applicarla live: scripts/demo.ps1 -Step ApplyPatch, poi scripts/agileday.ps1 -Step Verifica, infine -Step Reset."
        }
        'Persone' {
            Write-Scene 7 'Le persone decidono' 'La CI riesegue lo stesso contratto sullo SHA della PR; il merge resta una decisione umana.'
            Show-Lines '.github/workflows/verify.yml' 'Run the same checks' 3
            Write-Host ''
            Get-Content -LiteralPath 'docs/TEAM-WORKFLOW.md' | Where-Object { $_ -match '^\|' } | Out-Host
            if (Get-Command gh -CommandType Application -ErrorAction SilentlyContinue) {
                gh pr list --limit 5
                if ($LASTEXITCODE -ne 0) { Write-Host 'gh non disponibile: aprire la PR dal browser.' }
            }
            $copilot = 'demo-assets/evidence/copilot-verify.png'
            if (Test-Path -LiteralPath $copilot) { Write-Host "Evidenza Copilot: $copilot" }
            else { Write-Host "Evidenza Copilot non presente ($copilot)." }
        }
        'Reset' {
            $state = Get-DemoState -Root $Root
            if ($state.PatchApplied) { Invoke-Demo RemovePatch }
            if ($state.SeedApplied) { Invoke-Demo Reset }
            # Ciò che resta in Application è lavoro dell'agente sulla demo: lo mostro e lo scarto.
            $leftovers = Get-ApplicationChanges
            if ($leftovers.Count -ne 0) {
                $leftovers | Out-Host
                Invoke-Native git @('restore', '--source=HEAD', '--staged', '--worktree', '--', $applicationPath)
                Invoke-Native git @('clean', '-fq', '--', $applicationPath)
                Write-Host "Ripristinate le modifiche dell'agente in $applicationPath."
            }
            if (-not $state.SeedApplied -and -not $state.PatchApplied -and $leftovers.Count -eq 0) { Write-Host 'Niente da ripristinare.' }
        }
    }
} finally {
    Pop-Location
}
