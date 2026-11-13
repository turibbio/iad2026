# 001 Sconto ordini con Blazor

Come utente dell'applicazione Blazor voglio visualizzare un ordine e applicare uno sconto percentuale.

Criteri di accettazione:
- Visualizzare subtotale, sconto e totale.
- Uno sconto del 20% su 100 produce 80.
- Percentuali fuori da 0-30 sono rifiutate.
- Codice obbligatorio e totale non negativo.
- UI delega le regole a Application e Domain.
- Application non dipende da Infrastructure.
- La CI applica quality gate indipendenti.
