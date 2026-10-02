ROMA TERRAIN3D — V7 ROMAN NATURAL FIX 3

Keeps the complete Terrain3D project and original 1081x1081 R16 big-endian heightmap.

Visual pass:
- Grass is the autoshader base texture.
- Soil is the autoshader slope overlay only.
- Higher slope threshold reduces broad orange valley strips.
- Tevere is one opaque continuous ribbon.
- Water follows the lowest sampled point of each local river-bed cross-section, reducing burial by the terrain.
- No global WaterPlane.
- Heightmap remains untouched: 1081x1081, Big Endian, 2000x2000 m, spacing 1.8518518 m, 48 m relief.
