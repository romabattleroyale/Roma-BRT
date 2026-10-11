# Godot 4.7 — catalogo sistemi completi da valutare per Roma-BRT

Scopo: riutilizzare sistemi Godot già funzionanti invece di riscrivere tutto da zero. Nessun progetto esterno va copiato alla cieca nel gioco principale: prima si verifica licenza, versione, dipendenze, renderer Mobile/Android e si prova in una scena isolata.

## Priorità 1 — generazione terreno, acqua, vegetazione e collisioni

**MapGen — generatore procedurale Godot 4.7**
- Repository: https://github.com/MarcelloMorettoni/mapgen
- README: https://github.com/MarcelloMorettoni/mapgen#readme
- Codice da studiare: `addons/mapgen/core/heightfield.gd`, `terrain_mesh.gd`, `materials.gd`, `scatter.gd`, `vegetation.gd`, `water.gd`, `flow.gd`, `prop_colliders.gd`, `exporter.gd`; shader `terrain.gdshader` e `water.gdshader`.
- Include un test headless: `godot --headless --path . --script res://tests/verify.gd`.
- Stato licenza: **da verificare prima di copiare codice o asset**; non ho trovato un file LICENSE nella root del repository.
- Compatibilità: il README dichiara Godot 4.7 e Forward+. Va provato con il renderer e l'hardware Android del progetto prima di adottarlo.
- Uso previsto: laboratorio separato per confrontare shader del terreno, vegetazione instanziata e acqua. Non sostituire direttamente Terrain3D né la heightmap reale di Roma.

## Priorità 2 — gioco 3D completo con sistemi riutilizzabili

**Open Theft Auto — sandbox open-world Godot 4.7**
- Repository: https://github.com/mehulkapadia5/open-theft-auto
- Include città procedurale, veicoli, fiume e ponti, ciclo giorno/notte, HUD, controlli touch, salvataggi e gameplay.
- Licenza del codice dichiarata MIT: https://github.com/mehulkapadia5/open-theft-auto/blob/main/LICENSE
- Non importare l'intero gioco in Roma-BRT: studiare e isolare solo sistemi indipendenti dopo verifica di licenze di ogni asset, dipendenze e performance Android.
- È un riferimento di architettura e sistemi gameplay, non una base geografica della città di Roma.

## Priorità 3 — controller personaggio 3D pronto

**GDQuest — Godot 4 3D Third-Person Controller**
- Repository: https://github.com/gdquest-demos/godot-4-3d-third-person-controller
- Codice e scene sotto MIT; modelli e texture sotto CC-BY-NC-SA 4.0, quindi **non utilizzare gli asset artistici in un gioco commerciale** senza un'autorizzazione/licenza compatibile.
- Valutare solo controller, camera e logica, dopo confronto con i controlli già presenti in Roma-BRT.

## Sistemi già presenti nel progetto da non duplicare

- Terrain3D è già una dipendenza del progetto: non installare un secondo sistema terrain in parallelo.
- Il percorso Tevere runtime esiste già, ma l'importazione geografica OSM ha fallito in precedenza. Prima si deve far passare l'importazione e controllare la geometria generata.
- Le strade hanno già codice locale: prima di importare un generatore esterno, va verificato come collegarlo alla rete reale senza duplicare o sovrapporre le strade.

## Procedura automatizzata obbligatoria per ogni candidato

1. Leggere README e licenza effettiva.
2. Controllare versione Godot, renderer, dipendenze native/GDExtension e uso su Android.
3. Scaricare/provare in una cartella di laboratorio separata, senza modificare la scena principale.
4. Eseguire il test headless del progetto, se presente; registrare errori e tempi.
5. Portare in Roma-BRT soltanto moduli isolati che superano i controlli.
6. Conservare attribuzioni e licenze degli asset.

## Prossimo ordine tecnico

1. Recuperare e verificare i sistemi MapGen in un progetto laboratorio.
2. Confrontare acqua/vegetazione/terrain shader con Terrain3D e il Tevere esistenti.
3. Riutilizzare soltanto le parti compatibili e misurare il costo su Android.
4. Sistemare la pipeline OSM con validazione automatica prima di generare dati di città.

Questo catalogo è una lista operativa di candidati verificati a livello di repository/README, non una dichiarazione che siano già integrati o che abbiano superato i test sul dispositivo.
