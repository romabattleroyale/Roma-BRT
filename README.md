# Roma Battle Royale — FIX22 Tevere Real Flow

## Official checkpoint
**FIX22 — Tevere Real Flow**

This repository is the working source-of-truth checkpoint for the Roma Battle Royale Terrain3D project.

### Runtime
- Godot 4.7.2
- Terrain3D active
- Android target
- 1081×1081 source heightmap
- 16-bit Big-Endian RAW
- 2000×2000 m terrain
- Vertex spacing: 1.85185185 m
- Vertical relief: 48 m

### Terrain invariant
The heightmap and terrain/control-map base are preserved from the confirmed FIX15/FIX18 lineage.

### Tevere invariant
The Tevere geometry is the confirmed FIX18 geometry, with the animated directional water material developed through FIX22.

### Important
Do not modify the heightmap, terrain/control map, or Tevere geometry unless explicitly authorized.

### Integration policy
The Roma-Royale V37 systems are being integrated selectively. Terrain creation from the source project is excluded; the existing Terrain3D remains authoritative. Road generation is staged for a later controlled pass. POIs, buildings, foliage, Fire Front, lighting, height sampling, and technical camera systems are adapted to the existing world.

### GitHub workflow
Use commits as checkpoints. Never commit `.godot/` or generated exports.
