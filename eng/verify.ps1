#Requires -Version 7.4
# One verification contract for humans, agents and CI. No modules required.
$ErrorActionPreference = 'Stop'

function Invoke-CommandProcess {
    param([string[]]$Command, [string]$Root, [int]$TimeoutSeconds = 240)
    $executable = (Get-Command $Command[0] -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $executable
    $arguments = @($Command | Select-Object -Skip 1)
    # Windows npm is a .cmd shim; PowerShell handles its native argument quoting.
    if ([IO.Path]::GetExtension($executable) -in '.cmd', '.bat') {
        $start.FileName = Join-Path $PSHOME 'pwsh.exe'
        foreach ($argument in @('-NoProfile', '-CommandWithArgs', '$exe=$args[0]; $nativeArgs=@($args | Select-Object -Skip 1); & $exe @nativeArgs; exit $LASTEXITCODE', $executable)) {
            $start.ArgumentList.Add($argument)
        }
    }
    foreach ($argument in $arguments) { $start.ArgumentList.Add($argument) }
    $start.WorkingDirectory = $Root
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw [TimeoutException]::new("Command timed out after $TimeoutSeconds seconds")
        }
        return @{ exitCode = $process.ExitCode; output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult() }
    }
    finally { $process.Dispose() }
}

function Read-TestEvidence {
    param([string]$Path, [ValidateSet('trx', 'junit', 'harness')][string]$Kind = 'trx')
    if ($Kind -eq 'harness') {
        $report = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
        $counts = $report.counts
        if ($null -eq $counts -or @($report.cases).Count -ne $counts.total) { throw 'Invalid harness test evidence' }
        foreach ($state in 'passed', 'failed', 'skipped') {
            $actual = @($report.cases | Where-Object status -eq $state).Count
            if ($counts[$state] -ne $actual) { throw "Invalid harness count: $state" }
        }
        if ($counts.total -ne ($counts.passed + $counts.failed + $counts.skipped)) { throw 'Invalid test total' }
        return @{ counts = $counts; failures = @($report.cases | Where-Object status -ne 'passed') }
    }
    [xml]$xml = [IO.File]::ReadAllText($Path)
    $counts = @{ total = 0; passed = 0; failed = 0; skipped = 0 }
    $failures = [Collections.Generic.List[object]]::new()
    $tag = if ($Kind -eq 'trx') { 'UnitTestResult' } else { 'testcase' }
    foreach ($node in $xml.SelectNodes("//*[local-name()='$tag']")) {
        $counts.total++
        $failure = $node.SelectSingleNode('./failure|./error')
        $state = if ($Kind -eq 'trx') {
            switch ($node.GetAttribute('outcome')) { 'Passed' { 'passed' } 'Failed' { 'failed' } default { 'skipped' } }
        } else {
            if ($null -ne $failure) { 'failed' } elseif ($null -ne $node.SelectSingleNode('./skipped')) { 'skipped' } else { 'passed' }
        }
        $counts[$state]++
        if ($state -eq 'failed') {
            $name = $node.GetAttribute($(if ($Kind -eq 'trx') { 'testName' } else { 'name' }))
            $messageNode = if ($Kind -eq 'trx') { $node.SelectSingleNode(".//*[local-name()='Message']") } else { $failure }
            $message = if ($null -ne $messageNode) { $messageNode.InnerText } else { '' }
            $rule = [regex]::Match($name + $message, 'ARCH\d{3}')
            $file = [regex]::Match($message, '(?:[/\\][^\s:]+)+\.(?:csproj|cs|razor)')
            $failures.Add(@{
                id = $(if ($rule.Success) { $rule.Value } else { $name })
                file = $(if ($file.Success) { $file.Value } else { $null })
                message = $message.Substring(0, [Math]::Min(4000, $message.Length)); blocking = $true
            })
        }
    }
    return @{ counts = $counts; failures = $failures.ToArray() }
}

function Invoke-Check {
    param([Collections.IDictionary]$Check, [string[]]$Command, [string]$Root,
          [string]$Result, [string]$Kind = 'trx', [scriptblock]$ProcessRunner = ${function:Invoke-CommandProcess},
          [int]$TimeoutSeconds = 240)
    Write-Host "`n>>> $($Check.id): $($Command -join ' ')"
    try {
        $process = & $ProcessRunner $Command $Root $TimeoutSeconds
        $output = [string]$process.output
        $Check.exitCode = $process.exitCode
        $Check.status = if ($process.exitCode -eq 0) { 'passed' } else { 'failed' }
        $Check.message = if ($process.exitCode -eq 0) { 'Completed' } else { 'Command failed; inspect log' }
    } catch {
        $output = $_.Exception.Message
        $Check.status = 'environment_error'
        $Check.message = $output
    }
    $log = if ([IO.Path]::IsPathRooted($Check.log)) { $Check.log } else { Join-Path $Root $Check.log }
    [IO.File]::WriteAllText($log, $output)
    Write-Host $output.Substring([Math]::Max(0, $output.Length - 3000))
    if ($Result -and $Check.status -ne 'environment_error') {
        try {
            $evidence = Read-TestEvidence -Path $Result -Kind $Kind
            $Check.counts = $evidence.counts
            $Check.failures = @($evidence.failures)
            if ($evidence.counts.total -eq 0 -or $evidence.counts.failed -gt 0 -or $evidence.counts.skipped -gt 0) {
                $Check.status = 'failed'
                $Check.message = 'Tests failed, skipped or not executed'
            }
        } catch {
            $Check.status = 'failed'
            $Check.message = "Missing or invalid test evidence: $($_.Exception.Message)"
        }
    }
    return $Check.status -eq 'passed'
}

function Invoke-Verification {
    param([string]$Root = (Split-Path $PSScriptRoot -Parent), [scriptblock]$ProcessRunner = ${function:Invoke-CommandProcess})
    $artifacts = Join-Path $Root 'artifacts'
    foreach ($name in 'logs', 'test-results', 'browser-results') {
        $folder = Join-Path $artifacts $name
        if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
        [void](New-Item -ItemType Directory -Path $folder -Force)
    }
    $reportPath = Join-Path $artifacts 'verification.json'
    Remove-Item -LiteralPath $reportPath -ErrorAction SilentlyContinue
    $checks = [ordered]@{}
    foreach ($definition in @(
        @('harness-tests', 'harness'), @('restore', 'dependencies'), @('build', 'build'), @('format', 'style'),
        @('unit-tests', 'unit'), @('architecture-tests', 'architecture'), @('blazor-tests', 'components'),
        @('browser-restore', 'dependencies'), @('browser-tests', 'browser')
    )) {
        $id = $definition[0]
        $checks[$id] = [ordered]@{ id = $id; category = $definition[1]; status = 'not_executed'; blocking = $true
            message = 'Prerequisite did not pass'; file = $null; log = "artifacts/logs/$id.log" }
    }
    $invoke = @{ Root = $Root; ProcessRunner = $ProcessRunner }
    try {
        $harnessResult = Join-Path $artifacts 'test-results/harness-tests.json'
        [void](Invoke-Check $checks['harness-tests'] @((Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })), '-NoProfile', '-File', 'eng/tests/verify.tests.ps1', '-ResultPath', $harnessResult) @invoke -Result $harnessResult -Kind harness)
        if (Invoke-Check $checks.restore @('dotnet', 'restore', 'Orders.slnx') @invoke) {
            if (Invoke-Check $checks.build @('dotnet', 'build', 'Orders.slnx', '-c', 'Release', '--no-restore') @invoke) {
                [void](Invoke-Check $checks.format @('dotnet', 'format', 'Orders.slnx', '--verify-no-changes', '--no-restore') @invoke)
                foreach ($project in @(@('unit-tests', 'Unit'), @('architecture-tests', 'Architecture'), @('blazor-tests', 'Blazor'))) {
                    $label = $project[0]
                    $result = Join-Path $artifacts "test-results/$label.trx"
                    [void](Invoke-Check $checks[$label] @('dotnet', 'test', "tests/Orders.$($project[1])Tests", '-c', 'Release', '--no-build', '--no-restore', '--results-directory', (Split-Path $result), '--logger', "trx;LogFileName=$label.trx") @invoke -Result $result)
                }
                if (Invoke-Check $checks['browser-restore'] @('npm', 'ci', '--prefix', 'tests/browser', '--no-audit', '--no-fund') @invoke) {
                    [void](Invoke-Check $checks['browser-tests'] @('npm', 'test', '--prefix', 'tests/browser') @invoke -Result (Join-Path $artifacts 'test-results/browser.xml') -Kind junit)
                }
            }
        }
    } catch {
        $checks['internal-error'] = @{ id = 'internal-error'; category = 'harness'; status = 'environment_error'; blocking = $true; message = $_.Exception.Message }
    }
    $success = @($checks.Values | Where-Object { $_.blocking -and $_.status -ne 'passed' }).Count -eq 0
    $report = [ordered]@{ schemaVersion = '2.0'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
        status = $(if ($success) { 'passed' } else { 'failed' }); checks = @($checks.Values) }
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 20) + "`n")
    Write-Host "`nReport: artifacts/verification.json"
    return $(if ($success) { 0 } else { 1 })
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-Verification) }
