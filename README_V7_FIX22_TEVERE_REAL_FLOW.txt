FIX22 — TEVERE REAL FLOW

BASE: FIX21.

Only the water shader was changed.
UV.x is the river axis. The new shader uses stronger elongated downstream streaks, multi-scale phase distortion, moving bank foam, animated surface normals and moving Fresnel/sun highlights. The goal is visible continuous flow rather than static reflections or tiled/square patterns.

Unchanged: FIX18 river geometry, heightmap, 2000x2000m, 48m relief, Terrain3D, manual control map, Android project.

Runtime testing must be performed in Godot/Android; no Godot runtime is available in the build environment.
