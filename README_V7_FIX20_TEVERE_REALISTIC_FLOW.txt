ROMA HEIGHTMAP BETA — FIX20 TEVERE REALISTIC FLOW

BASE: FIX19 only (FIX18 geometry/path + FIX19 animated water)

This pass changes ONLY the Tevere water material.

GOAL:
- Make the river visibly flow rather than merely shimmer.
- Keep Fortnite/stylized readability while adding a more natural moving-water look.

CHANGES:
- Layered longitudinal current bands moving along UV.x (the authored river path).
- Multiple wave scales: broad current, medium ripples, fine surface lines.
- Procedural animated normal perturbation for moving highlights.
- More controlled specular response for water highlights.
- Subtle animated foam streaks near both banks.
- Dark Roman-blue base with brighter moving surface highlights.

UNCHANGED:
- FIX18 river geometry/path.
- FIX18 bend handling.
- Heightmap RAW, Big-Endian.
- 2000x2000 m world.
- Vertex spacing 1.8518518 m.
- Height scale 48 m.
- Terrain3D.
- Manual terrain control map.
- Green/soil terrain system.
- Android project structure.

IMPORTANT:
This is shader-only water animation; no physics water simulation is added.
The package was not runtime-tested in Godot in this environment.
