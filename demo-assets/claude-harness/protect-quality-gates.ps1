#Requires -Version 7.4
# PreToolUse guardrail: denies Write/Edit/MultiEdit on quality gates.
# Covers only the Write, Edit and MultiEdit tools, not Bash or other tools: it is not a
# security boundary. Enforcement stays in CI, rulesets and human review.
$ErrorActionPreference = 'Stop'
try {
    $call = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if ($call -isnot [pscustomobject] -or [string]::IsNullOrWhiteSpace($call.hook_event_name) -or
        [string]::IsNullOrWhiteSpace($call.tool_name)) {
        throw 'Missing hook_event_name or tool_name in hook input.'
    }
    if ($call.hook_event_name -ne 'PreToolUse' -or $call.tool_name -notin 'Write', 'Edit', 'MultiEdit') {
        exit 0
    }
    $root = [IO.Path]::GetFullPath((Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
    $file = [string]$call.tool_input.file_path
    if ([string]::IsNullOrWhiteSpace($file)) { throw 'Missing file_path in hook input.' }
    $cwd = [string]$call.cwd
    if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = $root }
    $target = [IO.Path]::GetFullPath($file, $cwd)
    $comparison = if ($IsWindows -or $IsMacOS) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $relative = [IO.Path]::GetRelativePath($root, $target).Replace('\', '/')
    $protected = 'tests/', 'eng/', '.github/workflows/', 'demo-assets/claude-harness/'
    if (@($protected | Where-Object { $relative.StartsWith($_, $comparison) }).Count -gt 0) {
        @{
            hookSpecificOutput = @{
                hookEventName = 'PreToolUse'
                permissionDecision = 'deny'
                permissionDecisionReason = "GUARDRAIL: $relative è un quality gate. Correggi il codice, non il controllo."
            }
        } | ConvertTo-Json -Depth 4 -Compress
    }
    exit 0
} catch {
    [Console]::Error.WriteLine("Quality gate hook input error: $($_.Exception.Message)")
    exit 2
}
