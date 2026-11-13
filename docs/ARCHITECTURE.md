# Architettura

```text
Home.razor → GetDemoOrderHandler / ApplyDiscountHandler → Domain
                                   ↓ IOrderRepository
Program.cs → InMemoryOrderRepository → Domain
```

Program.cs è il composition root e può conoscere Infrastructure. I componenti
invocano Application; Domain valida codice e percentuale prima di modificare
lo stato. Il repository in-memory è scoped: ogni circuito Blazor ha un ordine
indipendente. Un refresh riparte da 100 euro. Non è un archivio persistente.

GetDemoOrderHandler identifica il caso d'uso dimostrativo. Il repository riceve
l'ordine iniziale dal composition root e non espone ID di esempio alla UI.
Application gestisce ordine assente con null. La pagina mostra un messaggio e
non dichiara successo se l'ordine manca. DataAnnotations migliora l'esperienza;
Domain applica nuovamente i vincoli quando invocato senza UI.

ARCH001 e ARCH002 verificano riferimenti assembly e ProjectReference XML;
i controlli XML intercettano anche riferimenti mai usati nel codice.
