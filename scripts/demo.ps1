#Requires -Version 7.4
<#
.SYNOPSIS
Esegue un singolo passaggio della demo Orders. Vedere docs/DEMO.md.
.EXAMPLE
pwsh -NoProfile -File scripts/demo.ps1 -Step Verify
.EXAMPLE
pwsh -NoProfile -File scripts/demo.ps1 -Step Verify -Expected Arch001
.EXAMPLE
pwsh -NoProfile -File scripts/demo.ps1 -Step Report -Root ../harness-demo
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Prepare', 'Verify', 'Report', 'App', 'Seed', 'Reset', 'Spec', 'ApplyPatch', 'RemovePatch')]
    [string]$Step,
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [ValidateSet('Passed', 'Arch001')]
    [string]$Expected = 'Passed'
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path -LiteralPath $Root).Path
if (-not (Test-Path -LiteralPath (Join-Path $Root 'eng/verify.ps1'))) {
    throw "Root non valida: $Root. Indicare la root del checkout della demo."
}

function Invoke-Native {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable ha restituito exit code $LASTEXITCODE. Leggere l'output prima di proseguire."
    }
}

function Show-Report {
    $report = Get-Content -LiteralPath 'artifacts/verification.json' -Raw | ConvertFrom-Json
    $report | Select-Object generatedAt, schemaVersion, status | Format-List | Out-Host
    $report.checks | Format-Table id, status, exitCode | Out-Host
    $report.checks | Where-Object counts | Select-Object id, counts | Format-Table -Wrap | Out-Host
    foreach ($check in @($report.checks | Where-Object status -ne 'passed')) {
        Write-Host "Gate: $($check.id); log: $($check.log)"
        $check.failures | Format-List * | Out-Host
    }
    return $report
}

function Assert-Report {
    param($Report, [int]$VerifyExit)
    $gateIds = @('harness-tests', 'restore', 'build', 'format', 'unit-tests',
        'architecture-tests', 'blazor-tests', 'browser-restore', 'browser-tests')
    if ($Report.schemaVersion -ne '2.0' -or $Report.checks.Count -ne $gateIds.Count -or
        @(Compare-Object $gateIds @($Report.checks.id)).Count -ne 0) {
        throw 'Report incompleto o schema inatteso. Leggere il JSON.'
    }
    if ($Expected -eq 'Passed') {
        if ($VerifyExit -ne 0 -or $Report.status -ne 'passed' -or
            @($Report.checks | Where-Object status -ne 'passed').Count -ne 0 -or
            @($Report.checks | Where-Object { $_.counts.failed -gt 0 -or $_.counts.skipped -gt 0 }).Count -ne 0) {
            throw 'Verifica non verde. Leggere JSON e log.'
        }
    } else {
        $architecture = @($Report.checks | Where-Object id -eq 'architecture-tests')[0]
        if ($VerifyExit -ne 1 -or $Report.status -ne 'failed' -or
            $architecture.status -ne 'failed' -or
            @($architecture.failures | Where-Object id -eq 'ARCH001').Count -eq 0 -or
            @($Report.checks | Where-Object { $_.id -ne 'architecture-tests' -and $_.status -ne 'passed' }).Count -ne 0) {
            throw 'Atteso solo architecture-tests fallito con ARCH001. Diagnosticare il risultato diverso.'
        }
    }
}

Push-Location $Root
try {
    Write-Host "Checkout: $Root"
    switch ($Step) {
        'Prepare' {
            foreach ($tool in 'git', 'dotnet', 'node', 'npm', 'bash') {
                [void](Get-Command $tool -CommandType Application -ErrorAction Stop)
            }
            Invoke-Native git @('branch', '--show-current')
            Invoke-Native git @('rev-parse', 'HEAD')
            Invoke-Native git @('status', '--short')
            Invoke-Native dotnet @('--version')
            Invoke-Native node @('--version')
            Invoke-Native npm @('ci', '--prefix', 'tests/browser')
            Push-Location tests/browser
            try {
                $installArgs = if ($IsLinux) { @('playwright', 'install', '--with-deps', 'chromium') }
                    else { @('playwright', 'install', 'chromium') }
                Invoke-Native npx $installArgs
            } finally { Pop-Location }
            Write-Host 'Dipendenze preparate. Prossimo passo: Verify.'
        }
        'Verify' {
            & (Join-Path $PSHOME 'pwsh') -NoProfile -File eng/verify.ps1
            $verifyExit = $LASTEXITCODE
            $report = Show-Report
            Assert-Report $report $verifyExit
            Write-Host "PASS: risultato atteso $Expected confermato. Exit code del contratto: $verifyExit."
        }
        'Report' {
            $null = Show-Report
            Write-Host 'Report esistente: questa azione non esegue una nuova verifica.'
        }
        'App' {
            Write-Host "Aprire http://localhost:5078. Ctrl+C arresta l'app. Porta 5089 riservata ai test."
            Invoke-Native dotnet @('run', '--project', 'src/Orders.Web', '--launch-profile', 'http')
        }
        'Seed' {
            Invoke-Native bash @('scripts/seed-architecture-failure.sh')
            Write-Host 'Difetto intenzionale introdotto. Prossimo passo: Verify -Expected Arch001.'
        }
        'Reset' {
            Invoke-Native bash @('scripts/reset-architecture-demo.sh')
            Write-Host 'Seed esatto rimosso. Prossimo passo: Verify.'
        }
        'Spec' {
            # Un processo figlio imposta la feature senza modificare la sessione chiamante.
            & (Join-Path $PSHOME 'pwsh') -NoProfile -Command {
                $env:SPECIFY_FEATURE_DIRECTORY = Join-Path $PWD 'specs/002-remove-discount'
                & ./.specify/scripts/powershell/check-prerequisites.ps1 -Json -RequireSpec -RequireTasks
                exit $LASTEXITCODE
            }
            if ($LASTEXITCODE -ne 0) { throw 'Prerequisiti Spec Kit non soddisfatti.' }
            foreach ($name in 'spec.md', 'plan.md', 'tasks.md') {
                Write-Host "`n=== $name ==="
                Get-Content -LiteralPath (Join-Path 'specs/002-remove-discount' $name)
            }
        }
        'ApplyPatch' {
            $changes = @(git status --porcelain)
            if ($LASTEXITCODE -ne 0) { throw 'Impossibile leggere lo stato Git.' }
            if ($changes.Count -ne 0) { throw 'Worktree modificato: usare una nuova baseline pulita.' }
            Invoke-Native git @('apply', '--check', 'demo-assets/remove-discount.patch')
            Invoke-Native git @('apply', 'demo-assets/remove-discount.patch')
            Write-Host 'Patch preparata applicata. Prossimo passo: Verify.'
        }
        'RemovePatch' {
            Invoke-Native git @('apply', '--reverse', '--check', 'demo-assets/remove-discount.patch')
            Invoke-Native git @('apply', '--reverse', 'demo-assets/remove-discount.patch')
            Write-Host 'Patch rimossa. Prossimo passo: Verify.'
        }
    }
} finally {
    Pop-Location
}
