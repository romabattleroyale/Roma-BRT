# Roma Battle Royale — CITY LIBRARY

Libreria centrale modulare della città.

## Regola principale
Gli asset vengono creati e verificati come librerie indipendenti. Solo dopo l'approvazione entrano nella mappa principale.

## Struttura
- `buildings/houses/` — case e moduli residenziali
- `buildings/palazzi/` — palazzi e blocchi urbani
- `architecture/` — pareti, porte, finestre, scale, pavimenti, soffitti e moduli strutturali
- `roads/` — strada, marciapiede, incroci e raccordi
- `poi/` — POI esplorabili e relative varianti
- `interiors/` — moduli per interni esplorabili
- `props/` — arredi e oggetti urbani
- `vegetation/` — vegetazione e moduli ambientali
- `infrastructure/` — elementi urbani tecnici e di servizio

## Pipeline
1. Creazione della libreria in isolamento.
2. Test di collisioni, scala, pivot e connessioni.
3. Verifica Android/Godot 4.7.2.
4. Approvazione.
5. Inserimento nella City Library.
6. Il sistema di generazione della città potrà scegliere i moduli dalla libreria.

## Vincoli
- La City Library non modifica Terrain3D, heightmap, control map o Tevere.
- Nessun Road Generator: le strade saranno moduli/librerie controllati.
- Gli edifici devono essere posizionabili sul Terrain3D e successivamente correggere la quota Y in base al terreno.
- I POI devono essere completamente esplorabili quando approvati.
- I moduli devono essere riutilizzabili e compatibili tra loro.
- Target: Godot 4.7.2 + Android.

## Stato
La struttura della libreria è pronta per ricevere le librerie definitive. La libreria delle case già pronta va inserita in `buildings/houses/` senza ricrearla da zero.
