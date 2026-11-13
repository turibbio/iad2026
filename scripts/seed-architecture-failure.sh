#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
branch="$(git branch --show-current)"
if [[ "$branch" == "main" || "$branch" == "master" || -z "$branch" ]]; then
  echo "Switch to a working branch before seeding the failure." >&2
  exit 1
fi
if [[ -n "$(git status --porcelain -- src/Orders.Application)" ]]; then
  echo "Application has local changes; seed refused to preserve them." >&2
  exit 1
fi
cp demo-assets/unsafe-change/Orders.Application.csproj src/Orders.Application/Orders.Application.csproj
cp demo-assets/unsafe-change/InfrastructureShortcut.cs src/Orders.Application/InfrastructureShortcut.cs
echo "Intentionally injected ARCH001 in $branch. Run pwsh -NoProfile -File eng/verify.ps1"
