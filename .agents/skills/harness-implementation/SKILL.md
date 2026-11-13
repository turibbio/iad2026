---
name: harness-implementation
description: Implementare una modifica .NET conforme alla specifica e verificarla.
---

# Harness implementation

Leggi `AGENTS.md`, constitution e specifica del task in `specs/` (baseline: `001-discount-code`).
Implementa il task in modo minimale. Esegui `pwsh -NoProfile -File eng/verify.ps1`, leggi il JSON
e presenta diff, test, rischi. Mai modificare i quality gate per renderli verdi.

Questa skill è un workflow riusabile per Codex, non un subagente autonomo.

Per incarichi e feedback sulla PR seguire `docs/TEAM-WORKFLOW.md`.
