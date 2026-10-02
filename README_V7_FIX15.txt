ROMA TERRAIN3D — V7 FIX15

BASE: FIX14 ONLY.

This version stops changing Terrain3D autoshader thresholds. The repeated orange patches
were caused by local heightmap slope noise being evaluated directly by the autoshader.

FIX15 uses a MANUAL Terrain3D control map generated at runtime from the original RAW:
- Heightmap is NOT modified.
- A large-scale slope is measured over ~44 m to suppress micro-slope noise.
- Grass is the manual base texture (ID 0).
- Soil is the manual overlay texture (ID 1).
- Soil blend starts around 9 degrees and reaches full strength around 18 degrees.
- Riverbank soil is limited to a ~3.7 m dilation around the existing river centerline mask.
- Terrain3D autoshader is disabled for the biome mask.

UNCHANGED:
- original 1081x1081 16-bit BIG-ENDIAN RAW
- 2000 x 2000 m world
- vertex spacing 1.8518518 m
- height scale 48 m
- Terrain3D
- Android project structure
- river water mesh/path
- terrain geometry

This is a structural material-mask correction, not another auto_slope tweak.
