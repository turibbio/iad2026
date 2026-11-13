# Harness .NET 10 e Blazor

- Orders.Web è una Blazor Web App con render mode Interactive Server.
- La UI deve invocare Application; non inserire logiche di business nei componenti Razor.
- Domain non dipende da Application né Infrastructure.
- Application non dipende da Infrastructure.
- Ogni modifica richiede pwsh -NoProfile -File eng/verify.ps1 e analisi di artifacts/verification.json.
- Non indebolire test, controlli o workflow per rendere la pipeline verde.
- I ruoli Implementation, Verification e Review sono opzionali. Un solo agente è sufficiente.
- Istruzioni e constitution non sono enforcement: applicare i controlli mediante GitHub Actions e ruleset.

- Per incarichi, PR e feedback umano seguire docs/TEAM-WORKFLOW.md: avvio/ripresa manuali, evidenze sullo SHA corrente, nessun merge automatico.
