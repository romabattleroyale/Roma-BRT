# Isola Tiberina — Iteration 3 Asset-Based

## Comandi smartphone
- ▲ AVANTI
- ▼ INDIETRO
- ◀ SINISTRA
- ▶ DESTRA
- Trascina nella metà destra dello schermo per ruotare la visuale a 360°.
- I quattro pulsanti sono touch e supportano pressione/rilascio.

## Asset-based
Gli edifici, ponti, case, percorsi, lampioni, panchine, fontane e alberi principali sono caricati come GLB da res://poi_test/assets/models/.
Il corpo principale dell'isola resta procedurale.

## Sketchfab
La lista completa con autore, licenza, triangoli e link è in SKETCHFAB_ASSET_MANIFEST.md.
Tutti gli asset selezionati rispettano CC0 o CC BY e il limite di 20.000 triangoli per modello.

## Download
Il workflow .github/workflows/fetch-sketchfab-iteration3.yml usa il secret SKETCHFAB_TOKEN per ottenere i modelli tramite la Download API ufficiale di Sketchfab. Il token non viene salvato nel repository.

## Limiti
Budget asset: massimo 100 MB. Nessun GridMap, MeshLibrary o spline. Nessun BoxMesh per edifici principali.

## Nota di verifica
Il container di sviluppo non dispone dell'eseguibile Godot 4.7.2, quindi non dichiaro una verifica runtime/mobile che non ho potuto eseguire qui.
