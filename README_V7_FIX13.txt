ROMA TERRAIN3D — FIX13

BASE ESCLUSIVA: FIX12

Unica correzione rispetto a FIX12: mapping corretto dell'autoshader Terrain3D.

Terrain3D lightweight.gdshader usa:
- auto_blend = 1 sulle superfici piatte
- auto_blend = 0 aumentando la pendenza
- base texture riceve il peso complementare
- overlay texture riceve il peso auto_blend

Per ottenere VERDE dominante:
- base texture = ID 1 (Soil)
- overlay texture = ID 0 (Grass)

Quindi:
- terreno piano -> Grass
- pendenza forte -> Soil

Parametri mantenuti:
- auto_slope = 8.0
- blend_sharpness = 0.90
- heightmap invariata
- RAW Big Endian invariato
- 2000x2000 m invariato
- altezza 48 m invariata
- Tevere invariato
- Terrain3D e progetto Android invariati
