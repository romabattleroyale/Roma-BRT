ROMA HEIGHTMAP BETA — TERRAIN3D + CONTROLLI ANDROID
Godot 4.7.2

CORREZIONE IMPORTANTE:
- La RAW fornita è 1081x1081, 16-bit UNSIGNED BIG-ENDIAN.
- La verifica del contenuto mostra un range reale circa 742..16031.
- Il precedente import little-endian produceva le strisce/spikes.
- Ora i due byte vengono decodificati come BIG-ENDIAN e il range reale viene normalizzato.

Mappa:
- 2000x2000 m
- vertex spacing 1.8518518 m
- height scale beta 120 m

Android:
- joystick sinistro = movimento
- trascina nella metà destra = visuale
- pulsante CORRI = boost

PC:
- WASD/frecce = movimento
- tasto destro + mouse = visuale
- SHIFT = boost

La RAW originale resta in assets/heightmap.raw.
