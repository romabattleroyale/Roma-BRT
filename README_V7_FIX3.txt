ROMA TERRAIN3D — V7 ROMAN NATURAL FIX 3

Corrections after Android test:
- Autoshader mapping fixed definitively: grass is BASE texture 0, soil is OVERLAY texture 1.
- Autoshader slope threshold raised to 10 degrees-equivalent setting, following the Terrain3D demo pattern, so shallow river valleys remain grass rather than becoming wide orange strips.
- Blend sharpened slightly for a cleaner Fortnite-like transition.
- Tevere water height now samples the LOWEST terrain point across each local river-bed cross-section instead of using only the centerline sample. This prevents the water ribbon from being buried by the terrain.
- No heightmap changes.
- Terrain3D plugin and Android project preserved.
