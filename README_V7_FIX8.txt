ROMA TERRAIN3D V7 ROMAN NATURAL — FIX8

FIX8 corregge la mappatura dell'Auto Shader Terrain3D.

La formula ufficiale dell'autoshader usa auto_blend=1 sulle superfici piatte; quindi il texture ID overlay deve essere l'erba, mentre il base deve essere il suolo. Nelle versioni recenti erano stati invertiti, producendo le grandi macchie arancioni viste negli screenshot.

Valori FIX8:
- auto_base_texture = 1 (soil)
- auto_overlay_texture = 0 (grass)
- auto_slope = 5.0
- blend_sharpness = 0.86
- auto_height_reduction = 0.0
- heightmap invariata
- Tevere FIX7 invariato
