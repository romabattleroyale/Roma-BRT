# Incoming Libraries

Questa cartella è l'ingresso per le librerie ZIP del progetto Roma-BRT.

## Flusso
1. Carica un solo `.zip` in questa cartella.
2. GitHub Actions avvia automaticamente `City Library Ingest`.
3. Il workflow controlla sicurezza ZIP, struttura, cataloghi e policy del progetto.
4. La libreria viene copiata nella sezione corretta di `city_library/`.
5. Il workflow crea automaticamente il commit.

Per un caricamento manuale da Actions puoi anche usare `workflow_dispatch` e indicare il percorso del ZIP.

## Policy
- Il pacchetto non deve contenere `.godot/` o `project.godot`.
- Nessun Road Generator.
- Le librerie devono essere modulari e riutilizzabili.
- Per le case è obbligatorio `data/building_catalog.json`.
- I file singoli oltre 90 MiB vengono rifiutati per evitare problemi con i limiti GitHub.

Dopo l'ingestione, il file ZIP può essere rimosso manualmente dalla cartella `incoming_libraries/` per non conservarne una seconda copia nel repository.
