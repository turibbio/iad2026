# 002 Rimuovere lo sconto

Come presentatore voglio riportare un ordine scontato al suo subtotale tramite
un comando visibile, così posso ripetere una dimostrazione senza ricaricare.

## Criteri di accettazione

- Dopo SAVE20 al 20% su 100 euro, «Rimuovi sconto» riporta il totale a 100 euro.
- DiscountPercentage diventa 0; DiscountCode diventa null.
- Il comando ripetuto è idempotente e non cambia il subtotale.
- Ordine inesistente restituisce null senza salvataggi.
- UI invoca Application; il comando persiste tramite IOrderRepository.
- UI mostra «Sconto rimosso.» e cancella errori/conferme precedenti.
- Nuovi test Domain/Application, bUnit e browser coprono la modifica.
- pwsh -NoProfile -File eng/verify.ps1 deve passare; non cambiare gate o dipendenze vietate.

Fuori scope: storico sconti, database, autorizzazioni, cumulo degli sconti.
Questa feature è un esercizio live: la baseline non la include.
