# Piano tecnico: sconto ordini

.NET 10, Interactive Server. Domain mantiene le regole; Application contiene
query ordine demo e comando sconto; Infrastructure implementa IOrderRepository.
Web usa Application e compone DI nel solo Program.cs. Repository scoped al circuito.

Test: limiti e persistenza xUnit, riferimenti assembly/MSBuild xUnit,
componenti bUnit isolati con stub, eventi reali in Chromium/Playwright.
Contratto locale e CI: pwsh -NoProfile -File eng/verify.ps1, evidenza in artifacts/verification.json.
La violazione ARCH001 è una dimostrazione separata e intenzionale.
