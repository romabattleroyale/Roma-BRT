# Trastevere – Isola Tiberina — POI Test / Iteration 2

Isolated Godot 4.7.2 test project. Independent of Roma-BRT Main.

## Scope
- Only Isola Tiberina POI.
- Minimal test ground + fake WaterPlane + POI.
- No Main terrain, roads, HUD, gameplay, GridMap, MeshLibrary or splines.
- POI origin at (0,0,0).
- Low-poly procedural geometry; primitive elements stay below 500 triangles.
- StandardMaterial3D + NoiseTexture2D/FastNoiseLite, roughness 0.85, metallic 0.

## Iteration 2
1. Ship-shaped island body and individual travertine perimeter blocks.
2. Ponte Fabricio: two TorusMesh arch rings, 62 x 5 m deck, parapets, 3 Roman lamps.
3. Ponte Cestio: three TorusMesh arch rings, 70 x 8 m deck, peperino inserts, 4 lamps.
4. San Bartolomeo: central body, four columns, pronaos cornice, tile roof, bell tower, cross and wooden door.
5. Torre Caetani: brick tower, merlons, stone cornice and windows.
6. Six differentiated residential houses with roofs, windows, frames and doors.
7. Eighteen low-poly trees, hedges and ivy panels.
8. Three internal cobblestone paths with travertine sidewalks.
9. Lamps, benches, nasoni and four POI sign boards.

## Validation
The development container does not include the Godot 4.7.2 executable. Runtime/mobile validation must therefore be performed in Godot on the target device; no false validation claim is made here.

## Main safety
No Main scene or Main terrain file is required by this isolated project.
