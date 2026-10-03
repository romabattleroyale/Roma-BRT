# Roma Architecture Library V11 — Houses Section

Imported from `RomaRoyale_Architecture_Library_V11_CLEARANCE_AUDIT_FIXED.zip`.

## What this library contains
- 24 building archetypes from `data/building_catalog.json`.
- Dimensional footprints from `data/footprints.csv`.
- Building generation system in `scripts/building_system.gd`.
- Original test/showroom scene and script retained for reference.
- All source textures used by the building system.
- Door/window/protected-opening clearance audits.

## Use in RomaCityLibrary
This is the approved source library for modular city buildings. When the city builder needs a house/building module, it should resolve the archetype from `data/building_catalog.json` and build it through `RomaBuildingSystem` instead of inventing a duplicate asset.

## Placement rule
The building footprint is defined by the catalog. Final world placement must sample the authoritative Terrain3D height and apply the required vertical correction; this library does not modify terrain, heightmap, control map or Tevere geometry.

## Runtime note
The source archive states that its original showroom was statically inspected and not runtime-tested in its original environment. This import registers the library without claiming a new runtime validation.
