#!/usr/bin/env bash
# Evaluate the real verification contract against the known ARCH001 mutation.
set -euo pipefail
cd "$(dirname "$0")/.."
repo_root="$PWD"
for tool in git pwsh; do
  command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done
mkdir -p artifacts
probe_root="$(mktemp -d "$repo_root/artifacts/architecture-sensor.XXXXXX")"
probe_branch="demo/sensor-$(basename "$probe_root")"
worktree_created=false
branch_created=false
cleanup() {
  if $worktree_created; then
    # Only this script's disposable worktree contains the intentional mutation.
    git -C "$repo_root" worktree remove --force "$probe_root/worktree" || return 1
  fi
  if $branch_created; then
    git -C "$repo_root" branch -D "$probe_branch" >/dev/null || return 1
  fi
}
trap cleanup EXIT
git worktree add -b "$probe_branch" "$probe_root/worktree" HEAD
worktree_created=true
branch_created=true
cd "$probe_root/worktree"
echo "Evaluating committed SHA $(git rev-parse HEAD); uncommitted changes are excluded."
bash scripts/seed-architecture-failure.sh
verify_exit=0
pwsh -NoProfile -File eng/verify.ps1 || verify_exit=$?
# Keep evidence after removing the mutated worktree, including logs and test reports.
if [[ -d artifacts ]]; then cp -R artifacts "$probe_root/evidence"; fi
if [[ "$verify_exit" != 1 ]]; then
  echo "Expected verification exit 1, received $verify_exit. Evidence: $probe_root/evidence" >&2
  exit 1
fi
cat > "$probe_root/assert-report.ps1" <<'POWERSHELL'
param([Parameter(Mandatory)][string]$ReportPath)
$ErrorActionPreference = 'Stop'
$report = Get-Content -Raw -LiteralPath $ReportPath | ConvertFrom-Json
$expectedChecks = @('harness-tests', 'restore', 'build', 'format', 'unit-tests',
    'architecture-tests', 'blazor-tests', 'browser-restore', 'browser-tests')
if ($report.checks.Count -ne $expectedChecks.Count -or
    @(Compare-Object $expectedChecks @($report.checks.id)).Count -ne 0) {
    throw 'Expected all nine checks from the current verification contract.'
}
if ($report.schemaVersion -ne '2.0' -or $report.status -ne 'failed') {
    throw 'Expected a failed schema 2.0 report.'
}
$unexpected = @($report.checks | Where-Object { $_.id -ne 'architecture-tests' -and $_.status -ne 'passed' })
$architecture = @($report.checks | Where-Object id -eq 'architecture-tests')
if ($unexpected.Count -ne 0 -or $architecture.Count -ne 1) {
    throw 'Expected all gates other than architecture-tests to pass.'
}
if ($architecture[0].status -ne 'failed' -or
    @($architecture[0].failures | Where-Object id -eq 'ARCH001').Count -eq 0) {
    throw 'The architecture sensor did not report ARCH001.'
}
Write-Output 'PASS: the real contract detected ARCH001 and all other gates passed.'
POWERSHELL
pwsh -NoProfile -File "$probe_root/assert-report.ps1" "$probe_root/evidence/verification.json"
echo "Evidence retained at $probe_root/evidence"
