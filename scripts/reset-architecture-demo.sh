#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Refuse to erase anything except the exact, known seed.
cmp -s src/Orders.Application/Orders.Application.csproj demo-assets/unsafe-change/Orders.Application.csproj
cmp -s src/Orders.Application/InfrastructureShortcut.cs demo-assets/unsafe-change/InfrastructureShortcut.cs
git restore --source=HEAD -- src/Orders.Application/Orders.Application.csproj
rm src/Orders.Application/InfrastructureShortcut.cs
echo "Known seed removed. Run pwsh -NoProfile -File eng/verify.ps1"
