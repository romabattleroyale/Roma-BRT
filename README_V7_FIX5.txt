ROMA TERRAIN3D V7 ROMAN NATURAL — FIX5

Correzioni rispetto a FIX4:
- Autoshader: auto_slope 65° per rendere l'erba nettamente dominante e limitare il suolo alle pendenze molto forti.
- Blend sharpness 0.90.
- Tevere: corretto il calcolo dell'altezza dell'acqua. FIX4 inizializzava il minimo a 1 mentre i valori RAW reali sono 742..16031, quindi l'acqua finiva a ~0.85 m e veniva coperta dal terreno.
- Ora il minimo locale del letto viene realmente calcolato e l'acqua viene posizionata +1.10 m sopra quel minimo.
- Nessuna modifica alla heightmap.
- RAW originale: 1081x1081, 16-bit BIG-ENDIAN.
- Terrain3D: world 2000x2000 m, vertex spacing 1.8518518 m, height scale 48 m.
