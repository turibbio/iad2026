#Requires -Version 7.4
param([string]$ResultPath)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../verify.ps1"
. "$PSScriptRoot/../../.specify/scripts/powershell/common.ps1"
$cases = [Collections.Generic.List[object]]::new()
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('harness-tests-' + [guid]::NewGuid())
[void](New-Item -ItemType Directory -Path $testRoot)

function Assert-True { param([bool]$Condition, [string]$Message = 'Assertion failed'); if (-not $Condition) { throw $Message } }
function Assert-Throws { param([scriptblock]$Action); $thrown = $false; try { & $Action } catch { $thrown = $true }; Assert-True $thrown 'Expected an exception' }
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    try { & $Action; $cases.Add(@{ id = $Name; status = 'passed' }); Write-Host "PASS $Name" }
    catch { $cases.Add(@{ id = $Name; status = 'failed'; message = $_.Exception.Message }); Write-Host "FAIL ${Name}: $_" }
}
function Read-Fixture {
    param([string]$Xml, [string]$Kind = 'trx')
    $path = Join-Path $testRoot 'fixture.xml'
    [IO.File]::WriteAllText($path, $Xml)
    Read-TestEvidence $path $Kind
}
function New-Check { return @{ id = 'fixture'; log = (Join-Path $testRoot 'fixture.log') } }
function Write-HarnessFixture {
    param([string]$Path, [int]$Total = 1, [object[]]$Cases = @(@{ id = 'fixture'; status = 'passed' }))
    @{ counts = @{ total = $Total; passed = $Total; failed = 0; skipped = 0 }; cases = $Cases } |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path
}
function Invoke-FixtureProcess {
    param($Command, $Root, $TimeoutSeconds)
    if ($Command[0] -eq 'dotnet') { return @{ exitCode = 1; output = 'Restore failure fixture' } }
    Write-HarnessFixture $Command[-1]
    return @{ exitCode = 0; output = 'Misleading fixture output: zero tests' }
}
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$pwshPath = (Get-Process -Id $PID).Path
function Invoke-GateHook {
    param($HookEvent)
    $json = if ($HookEvent -is [string]) { $HookEvent } else { $HookEvent | ConvertTo-Json -Depth 5 }
    $output = $json | & $pwshPath -NoProfile -File (Join-Path $repoRoot 'demo-assets/claude-harness/protect-quality-gates.ps1') 2>$null
    return @{ exitCode = $LASTEXITCODE; output = ($output -join "`n").Trim() }
}
function New-GateEvent {
    param([string]$File, [string]$Tool = 'Write', [string]$Cwd = $repoRoot)
    return @{ hook_event_name = 'PreToolUse'; tool_name = $Tool; cwd = $Cwd; tool_input = @{ file_path = $File; content = 'x' } }
}
function Assert-GateDenied {
    param([string]$File)
    $r = Invoke-GateHook (New-GateEvent $File)
    Assert-True ($r.exitCode -eq 0) "Exit $($r.exitCode) for $File"
    $decision = ($r.output | ConvertFrom-Json).hookSpecificOutput
    Assert-True ($decision.permissionDecision -eq 'deny') "Not denied: $File"
    return $decision
}

try {
    Test-Case 'TRX namespace, ARCH001 ID and file' {
        $e = Read-Fixture '<Results xmlns="http://microsoft.com/trx"><UnitTestResult testName="ProjectReferences" outcome="Failed"><Message>ARCH001: /repo/src/Orders.Application/Orders.Application.csproj references Infrastructure</Message></UnitTestResult></Results>'
        Assert-True ($e.counts.failed -eq 1 -and $e.failures[0].id -eq 'ARCH001')
        Assert-True ($e.failures[0].file -eq '/repo/src/Orders.Application/Orders.Application.csproj')
    }
    Test-Case 'Skipped TRX is distinct from passed' {
        $e = Read-Fixture '<Results><UnitTestResult outcome="NotExecuted" /></Results>'
        Assert-True ($e.counts.skipped -eq 1 -and $e.counts.passed -eq 0)
    }
    Test-Case 'Empty evidence contains zero tests' {
        Assert-True ((Read-Fixture '<Results />').counts.total -eq 0)
    }
    Test-Case 'JUnit failure, error and skip counts' {
        $e = Read-Fixture '<testsuite><testcase/><testcase name="bad"><failure>bad</failure></testcase><testcase name="error"><error>error</error></testcase><testcase><skipped/></testcase></testsuite>' junit
        Assert-True ($e.counts.total -eq 4 -and $e.counts.passed -eq 1 -and $e.counts.failed -eq 2 -and $e.counts.skipped -eq 1)
    }
    Test-Case 'Malformed XML fails' { Assert-Throws { Read-Fixture '<invalid' } }
    Test-Case 'Missing native tool is an environment error' {
        $check = New-Check
        Assert-True (-not (Invoke-Check $check @('harness-missing-tool-7853') $testRoot))
        Assert-True ($check.status -eq 'environment_error')
    }
    Test-Case 'Nonzero exit preserves failure and log' {
        $check = New-Check
        Assert-True (-not (Invoke-Check $check @('fixture') $testRoot -ProcessRunner { @{ exitCode = 7; output = 'failure fixture' } }))
        Assert-True ($check.exitCode -eq 7 -and $check.status -eq 'failed')
        Assert-True ((Get-Content -LiteralPath $check.log -Raw) -eq 'failure fixture')
    }
    Test-Case 'Zero exit without evidence fails' {
        $check = New-Check
        Assert-True (-not (Invoke-Check $check @('fixture') $testRoot -Result (Join-Path $testRoot 'missing.trx') -ProcessRunner { @{ exitCode = 0; output = '' } }))
        Assert-True ($check.status -eq 'failed')
    }
    Test-Case 'Zero tests cannot pass a test gate' {
        $path = Join-Path $testRoot 'empty.trx'; [IO.File]::WriteAllText($path, '<Results/>')
        Assert-True (-not (Invoke-Check (New-Check) @('fixture') $testRoot -Result $path -ProcessRunner { @{ exitCode = 0; output = '' } }))
    }
    Test-Case 'Skipped tests cannot pass a test gate' {
        $path = Join-Path $testRoot 'skip.trx'; [IO.File]::WriteAllText($path, '<Results><UnitTestResult outcome="NotExecuted" /></Results>')
        Assert-True (-not (Invoke-Check (New-Check) @('fixture') $testRoot -Result $path -ProcessRunner { @{ exitCode = 0; output = '' } }))
    }
    Test-Case 'Real process timeout becomes an environment error' {
        $check = New-Check
        Assert-True (-not (Invoke-Check $check @((Get-Process -Id $PID).Path, '-NoProfile', '-Command', 'Start-Sleep -Seconds 10') $testRoot -TimeoutSeconds 1))
        Assert-True ($check.status -eq 'environment_error' -and $check.message -match 'timed out')
    }
    Test-Case 'Restore failure removes stale evidence and marks dependencies' {
        $root = Join-Path $testRoot 'restore-failure'
        $old = Join-Path $root 'artifacts/test-results/unit-tests.trx'
        [void](New-Item -ItemType Directory -Path (Split-Path $old) -Force)
        [IO.File]::WriteAllText($old, '<Results><UnitTestResult outcome="Passed" /></Results>')
        Assert-True ((Invoke-Verification $root ${function:Invoke-FixtureProcess}) -eq 1)
        $r = Get-Content (Join-Path $root 'artifacts/verification.json') -Raw | ConvertFrom-Json
        Assert-True ($r.status -eq 'failed' -and -not (Test-Path $old))
        Assert-True (($r.checks | Where-Object id -eq 'restore').status -eq 'failed')
        Assert-True (($r.checks | Where-Object id -eq 'unit-tests').status -eq 'not_executed')
    }
    Test-Case 'Missing dotnet still writes a failed report' {
        $root = Join-Path $testRoot 'missing-dotnet'
        $runner = { param($Command, $Root, $TimeoutSeconds)
            if ($Command[0] -eq 'dotnet') { throw 'dotnet missing fixture' }
            Write-HarnessFixture $Command[-1]
            return @{ exitCode = 0; output = '' }
        }
        Assert-True ((Invoke-Verification $root $runner) -eq 1)
        $r = Get-Content (Join-Path $root 'artifacts/verification.json') -Raw | ConvertFrom-Json
        Assert-True (($r.checks | Where-Object id -eq 'restore').status -eq 'environment_error')
        Assert-True (($r.checks | Where-Object id -eq 'browser-tests').status -eq 'not_executed')
    }
    Test-Case 'Harness uses structured evidence rather than fixture stdout' {
        $path = Join-Path $testRoot 'harness.json'; Write-HarnessFixture $path
        $check = New-Check
        Assert-True (Invoke-Check $check @('fixture') $testRoot -Result $path -Kind harness -ProcessRunner { @{ exitCode = 0; output = 'Ran zero tests in fake stdout' } })
        Assert-True ($check.counts.total -eq 1)
    }
    Test-Case 'Zero harness tests fail' {
        $path = Join-Path $testRoot 'harness-empty.json'; Write-HarnessFixture $path 0 @()
        Assert-True (-not (Invoke-Check (New-Check) @('fixture') $testRoot -Result $path -Kind harness -ProcessRunner { @{ exitCode = 0; output = '' } }))
    }
    Test-Case 'Inconsistent harness counts fail' {
        $path = Join-Path $testRoot 'harness-invalid.json'; Write-HarnessFixture $path 2
        Assert-Throws { Read-TestEvidence $path harness }
    }
    Test-Case 'Spec Kit core templates need no YAML module' {
        $root = Join-Path $testRoot 'core-template'
        [void](New-Item -ItemType Directory -Path "$root/.specify/templates" -Force)
        [IO.File]::WriteAllText("$root/.specify/templates/plan-template.md", 'core')
        Assert-True ((Resolve-TemplateContent plan-template $root) -eq 'core')
    }
    Test-Case 'Spec Kit composes a validated preset with PowerShell' {
        $root = Join-Path $testRoot 'yaml-preset'
        [void](New-Item -ItemType Directory -Path "$root/.specify/templates" -Force)
        [void](New-Item -ItemType Directory -Path "$root/.specify/presets/demo" -Force)
        [IO.File]::WriteAllText("$root/.specify/templates/plan-template.md", 'core')
        [IO.File]::WriteAllText("$root/.specify/presets/demo/preset.yml", 'fixture parsed by test double')
        [IO.File]::WriteAllText("$root/.specify/presets/demo/wrapper.md", 'before {CORE_TEMPLATE} after')
        function ConvertFrom-Yaml { param([Parameter(ValueFromPipeline)]$InputObject)
            @{ provides = @{ templates = @(@{ type = 'template'; name = 'plan-template'; file = 'wrapper.md'; strategy = 'wrap' }) } }
        }
        Assert-True ((Resolve-TemplateContent plan-template $root) -eq 'before core after')
    }
    Test-Case 'Spec Kit rejects an invalid preset strategy' {
        $root = Join-Path $testRoot 'yaml-preset'
        function ConvertFrom-Yaml { param([Parameter(ValueFromPipeline)]$InputObject)
            @{ provides = @{ templates = @(@{ type = 'template'; name = 'plan-template'; file = 'wrapper.md'; strategy = 'invalid' }) } }
        }
        Assert-Throws { Resolve-TemplateContent plan-template $root }
    }
    Test-Case 'Multiple PATH matches select the first executable' {
        function Get-Command { param($Name, $CommandType, $ErrorAction); @(@{ Source = (Get-Process -Id $PID).Path }, @{ Source = '/missing/second/tool' }) }
        $p = Invoke-CommandProcess @('fixture-tool', '-NoProfile', '-Command', 'exit 0') $testRoot
        Assert-True ($p.exitCode -eq 0)
    }
    Test-Case 'Native arguments preserve spaces and Unicode' {
        $p = Invoke-CommandProcess @((Get-Process -Id $PID).Path, '-NoProfile', '-CommandWithArgs', '$args | ConvertTo-Json -Compress', 'SAVE 20', 'città') $testRoot
        $values = $p.output | ConvertFrom-Json
        Assert-True ($p.exitCode -eq 0 -and $values[0] -eq 'SAVE 20' -and $values[1] -eq 'città')
    }
    Test-Case 'Gate hook denies Write on a test file' {
        $d = Assert-GateDenied (Join-Path $repoRoot 'tests/Orders.ArchitectureTests/ArchitectureRulesTests.cs')
        Assert-True ($d.hookEventName -eq 'PreToolUse')
        Assert-True ($d.permissionDecisionReason.Contains('tests/Orders.ArchitectureTests/ArchitectureRulesTests.cs'))
    }
    Test-Case 'Gate hook denies Edit on eng and workflows' {
        foreach ($file in 'eng/verify.ps1', '.github/workflows/verify.yml') {
            $r = Invoke-GateHook (New-GateEvent (Join-Path $repoRoot $file) 'Edit')
            Assert-True (($r.output | ConvertFrom-Json).hookSpecificOutput.permissionDecision -eq 'deny') "Not denied: $file"
        }
    }
    Test-Case 'Gate hook protects itself' {
        $null = Assert-GateDenied (Join-Path $repoRoot 'demo-assets/claude-harness/quality-gates-settings.json')
    }
    Test-Case 'Gate hook allows Application source' {
        $r = Invoke-GateHook (New-GateEvent (Join-Path $repoRoot 'src/Orders.Application/ApplyDiscountHandler.cs'))
        Assert-True ($r.exitCode -eq 0 -and $r.output -eq '')
    }
    Test-Case 'Gate hook resolves relative and parent paths' {
        $null = Assert-GateDenied 'src/../tests/x.cs'
    }
    Test-Case 'Gate hook matches case-insensitively on macOS and Windows' {
        $r = Invoke-GateHook (New-GateEvent (Join-Path $repoRoot 'Tests/x.cs'))
        if ($IsMacOS -or $IsWindows) {
            Assert-True (($r.output | ConvertFrom-Json).hookSpecificOutput.permissionDecision -eq 'deny')
        } else {
            Assert-True ($r.exitCode -eq 0 -and $r.output -eq '')
        }
    }
    Test-Case 'Gate hook ignores Bash' {
        $r = Invoke-GateHook (New-GateEvent (Join-Path $repoRoot 'tests/x.cs') 'Bash')
        Assert-True ($r.exitCode -eq 0 -and $r.output -eq '')
    }
    Test-Case 'Gate hook fails closed on malformed input' {
        Assert-True ((Invoke-GateHook '{').exitCode -eq 2)
        $missing = @{ hook_event_name = 'PreToolUse'; tool_name = 'Write'; cwd = $repoRoot; tool_input = @{} }
        Assert-True ((Invoke-GateHook $missing).exitCode -eq 2)
        foreach ($raw in '{}', 'null', '[]', '') { Assert-True ((Invoke-GateHook $raw).exitCode -eq 2) "Allowed: '$raw'" }
    }
    Test-Case 'Gate hook denies MultiEdit on a test file' {
        $r = Invoke-GateHook (New-GateEvent (Join-Path $repoRoot 'tests/x.cs') 'MultiEdit')
        Assert-True (($r.output | ConvertFrom-Json).hookSpecificOutput.permissionDecision -eq 'deny')
    }
    $agileDayScript = Join-Path $repoRoot 'scripts/agileday.ps1'
    Test-Case 'Agile Day script exposes the session steps' {
        $ast = [Management.Automation.Language.Parser]::ParseFile($agileDayScript, [ref]$null, [ref]$null)
        $step = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Step' }
        $set = $step.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
        $values = @($set.PositionalArguments | ForEach-Object Value)
        $expected = 'Prepare', 'Status', 'Senza', 'Guida', 'Sensore', 'Feedback', 'Verifica', 'Guardrail', 'Requisito', 'Persone', 'Reset'
        Assert-True (@(Compare-Object $expected $values -SyncWindow 0).Count -eq 0) "Steps: $($values -join ', ')"
    }
    $demoRepo = Join-Path $testRoot 'agileday-repo'
    function New-DemoRepo {
        if (Test-Path $demoRepo) { Remove-Item -LiteralPath $demoRepo -Recurse -Force }
        foreach ($dir in 'eng', 'scripts', 'demo-assets/unsafe-change', 'src/Orders.Application') { [void](New-Item -ItemType Directory -Force -Path (Join-Path $demoRepo $dir)) }
        Set-Content (Join-Path $demoRepo 'eng/verify.ps1') ''
        Set-Content (Join-Path $demoRepo 'demo-assets/unsafe-change/InfrastructureShortcut.cs') '// seed'
        Set-Content (Join-Path $demoRepo 'demo-assets/unsafe-change/Orders.Application.csproj') '<Project seed="true" />'
        Set-Content (Join-Path $demoRepo 'src/Orders.Application/Orders.Application.csproj') '<Project />'
        Copy-Item (Join-Path $repoRoot 'scripts/reset-architecture-demo.sh') (Join-Path $demoRepo 'scripts/')
        git -C $demoRepo init -q -b demo/test
        git -C $demoRepo add -A
        git -C $demoRepo -c user.name=harness -c user.email=harness@example.invalid commit -q -m baseline
    }
    function Invoke-AgileDay {
        param([string]$Step)
        $output = & $pwshPath -NoProfile -File $agileDayScript -Step $Step -Root $demoRepo 2>&1
        # Error messages are colored and wrap at the console width with a "|" gutter:
        # strip the colors and rejoin the lines so assertions do not depend on the terminal.
        $text = ($output -join "`n") -replace '\e\[[0-9;?]*[A-Za-z]', ''
        return @{ exitCode = $LASTEXITCODE; output = ($text -replace '\s*\n\s*\|\s*', ' ') }
    }
    function Add-DemoSeed {
        Copy-Item (Join-Path $demoRepo 'demo-assets/unsafe-change/InfrastructureShortcut.cs') (Join-Path $demoRepo 'src/Orders.Application/')
        Copy-Item (Join-Path $demoRepo 'demo-assets/unsafe-change/Orders.Application.csproj') (Join-Path $demoRepo 'src/Orders.Application/')
    }
    Test-Case 'Agile Day state detects seed' {
        New-DemoRepo
        . $agileDayScript
        $seed = Join-Path $demoRepo 'src/Orders.Application/InfrastructureShortcut.cs'
        Copy-Item (Join-Path $demoRepo 'demo-assets/unsafe-change/InfrastructureShortcut.cs') $seed
        Assert-True ((Get-DemoState -Root $demoRepo).SeedApplied)
        Remove-Item $seed
        $state = Get-DemoState -Root $demoRepo
        Assert-True (-not $state.SeedApplied -and -not $state.PatchApplied)
    }
    Test-Case 'Agile Day reset restores agent edits in Application' {
        New-DemoRepo
        Set-Content (Join-Path $demoRepo 'src/Orders.Application/Orders.Application.csproj') '<Project agent="fixed" />'
        Set-Content (Join-Path $demoRepo 'src/Orders.Application/Leftover.cs') '// agent'
        $r = Invoke-AgileDay Reset
        Assert-True ($r.exitCode -eq 0) "Exit $($r.exitCode): $($r.output)"
        Assert-True ($r.output.Contains('Ripristinate'))
        Assert-True ((Get-Content (Join-Path $demoRepo 'src/Orders.Application/Orders.Application.csproj')) -eq '<Project />')
        Assert-True (-not (Test-Path (Join-Path $demoRepo 'src/Orders.Application/Leftover.cs')))
    }
    Test-Case 'Agile Day reset from seed works twice' {
        New-DemoRepo
        Add-DemoSeed
        $first = Invoke-AgileDay Reset
        Assert-True ($first.exitCode -eq 0) "Exit $($first.exitCode): $($first.output)"
        Assert-True (-not (Test-Path (Join-Path $demoRepo 'src/Orders.Application/InfrastructureShortcut.cs')))
        $second = Invoke-AgileDay Reset
        Assert-True ($second.exitCode -eq 0 -and $second.output.Contains('Niente da ripristinare'))
    }
    Test-Case 'Agile Day Senza shows an existing seed without reseeding' {
        New-DemoRepo
        Add-DemoSeed
        $r = Invoke-AgileDay Senza
        Assert-True ($r.exitCode -eq 0) "Exit $($r.exitCode): $($r.output)"
        Assert-True ($r.output.Contains('Seed già presente') -and -not $r.output.Contains('Intentionally injected'))
    }
    Test-Case 'Agile Day Senza refuses a dirty Application with a hint' {
        New-DemoRepo
        Set-Content (Join-Path $demoRepo 'src/Orders.Application/Orders.Application.csproj') '<Project agent="fixed" />'
        $r = Invoke-AgileDay Senza
        Assert-True ($r.exitCode -ne 0 -and $r.output.Contains('-Step Reset')) "Exit $($r.exitCode): $($r.output)"
    }
    Test-Case 'Agile Day guardrail uses the checkout hook and asserts deny' {
        New-DemoRepo
        $missing = Invoke-AgileDay Guardrail
        Assert-True ($missing.exitCode -ne 0 -and $missing.output.Contains('protect-quality-gates.ps1')) "Exit $($missing.exitCode): $($missing.output)"
        $hookDir = Join-Path $demoRepo 'demo-assets/claude-harness'
        [void](New-Item -ItemType Directory -Force -Path $hookDir)
        Copy-Item (Join-Path $repoRoot 'demo-assets/claude-harness/protect-quality-gates.ps1') $hookDir
        $ok = Invoke-AgileDay Guardrail
        Assert-True ($ok.exitCode -eq 0 -and $ok.output.Contains('"permissionDecision":"deny"')) "Exit $($ok.exitCode): $($ok.output)"
    }
    Test-Case 'Agile Day reset is a no-op when clean' {
        New-DemoRepo
        foreach ($attempt in 1, 2) {
            $output = & $pwshPath -NoProfile -File $agileDayScript -Step Reset -Root $demoRepo 2>&1
            Assert-True ($LASTEXITCODE -eq 0) "Exit $LASTEXITCODE on attempt ${attempt}: $output"
            Assert-True (($output -join "`n").Contains('Niente da ripristinare'))
        }
    }
}
finally { Remove-Item -LiteralPath $testRoot -Recurse -Force }
$failed = @($cases | Where-Object status -eq 'failed').Count
$report = @{ counts = @{ total = $cases.Count; passed = $cases.Count - $failed; failed = $failed; skipped = 0 }; cases = $cases.ToArray() }
if ($ResultPath) { [IO.File]::WriteAllText($ResultPath, ($report | ConvertTo-Json -Depth 10) + "`n") }
Write-Host "Harness tests: $($cases.Count - $failed)/$($cases.Count) passed"
exit $(if ($failed) { 1 } else { 0 })
