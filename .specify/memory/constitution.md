# Orders Demo Constitution

> Versione 1.0.0 — ratificata il 2026-10-10. Integrazioni Spec Kit 1.1.3; regole operative condivise in AGENTS.md.

## Domain first
Domain non dipende da Application o Infrastructure. Application non dipende da Infrastructure.
Verifica: ARCH001 e ARCH002.

## Comportamento verificabile
Sconto tra 0 e 30%, codice non vuoto, totale non negativo, UI tramite Application.
Verifica: unit test e review criteri di accettazione.

## Un contratto di verifica
Agenti e sviluppatori eseguono pwsh -NoProfile -File eng/verify.ps1; GitHub Actions esegue lo stesso comando.
Un report verde non prova la correttezza al di fuori dei casi coperti.

## Separazione delle responsabilità
Istruzioni e specifiche orientano gli agenti, non impongono vincoli. Modifiche ai gate richiedono review indipendente.

## Complessità proporzionata
Partire da un agente; introdurre specialisti solo quando hanno valore misurabile.
