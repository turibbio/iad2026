# Contratto di verifica

`pwsh -NoProfile -File eng/verify.ps1` è il comando unico. Richiede SDK .NET 10, PowerShell 7.4+,
Node 22/npm e Chromium Playwright installato (vedere README).

Sequenza: test harness PowerShell, restore, build Release, format, unit, architecture,
bUnit, npm ci, browser. Test e browser continuano dopo un gate architetturale o
format fallito per fornire una diagnosi completa. Restore/build falliti impediscono
l'esecuzione dei controlli dipendenti. Nessun test di integrazione esterna è previsto.

`artifacts/verification.json`, schemaVersion 2.0, contiene sempre i gate pianificati:
ID, categoria, stato, blocking, message, file (null se non individuabile), log,
exitCode quando disponibile; test con counts e failures ricavati da TRX/JUnit e JSON dei test harness.
I fallimenti architetturali hanno anche ARCH001/ARCH002 nelle failures.

Stati gate: passed, failed, not_executed, environment_error. Lo stato skipped è
rilevato nei contatori dei test e rende il gate failed: questa suite non ammette
copertura obbligatoria saltata. Non ci sono gate facoltativi nella baseline.
Un exit code zero senza report test valido o senza test eseguiti non passa.

Log e risultati precedenti sono rimossi prima di ogni esecuzione; report finale
riscritto anche per tool mancanti/timeout (240 secondi per comando). Interruzioni
forzate del processo possono lasciare il report assente, che non va mai interpretato come verde.
Exit code 0 solo se tutti i gate obbligatori passano; altrimenti 1.

L'agente legge prima status e check falliti, poi failures/log; corregge il codice,
riesegue il comando e legge il nuovo JSON. Non modifica i controlli per aggirare
un errore. La CI produce una nuova esecuzione sul commit della PR usando lo
stesso contratto e gli stessi test del repository. Non esiste una suite segreta
separata. La review deve verificare anche che le aspettative dei test rappresentino
i requisiti; un risultato locale o CI verde non dimostra la copertura completa.

Runner e test dell'harness sono PowerShell e usano solo librerie standard .NET:
non servono Pester né moduli aggiuntivi. Il JSON dei test harness valida casi e
contatori; non interpreta il testo stdout.
