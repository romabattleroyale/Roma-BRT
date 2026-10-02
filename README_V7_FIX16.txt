ROMA HEIGHTMAP BETA — TERRAIN3D — V7 FIX16

BASE: FIX15 CONFIRMED GOOD ONLY.

TEVERE-ONLY PASS
- Water ribbon is slightly wider than FIX15: render width factor 1.25 instead of 1.15.
- River width is smoothed over neighboring path points to avoid abrupt narrowing/widening and make the banks/water edge read more naturally through bends.
- Water level logic is unchanged from FIX15.
- river_path.json is unchanged.
- river_mask.png is unchanged.
- Manual Terrain3D control-map generation is unchanged.
- Heightmap is unchanged.
- RAW remains 16-bit Big-Endian.
- World remains 2000 x 2000 m.
- Vertex spacing remains 1.8518518 m.
- Height scale remains 48 m.
- Terrain3D remains enabled.
- Android project remains unchanged.

No terrain/biome/autoshader changes were made in this pass.
