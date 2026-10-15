# Roma BRT — Colosseo Quality Lab

Isolated Godot 4.7.2 scene for iterating on the Colosseum district without changing the main Roma BRT project.

## Open and run
1. Download this branch as a ZIP or clone the repository.
2. Open the `quality_lab/project.godot` file in Godot 4.7.2.
3. Run the main scene.

## Controls
- **WASD / arrow keys:** move
- **Shift:** run
- **Space:** jump
- **Mouse:** rotate camera
- **Touch:** drag on the left half to move; drag on the right half to rotate the camera

## Preview renders
Every successful GitHub Actions run publishes three PNGs as the artifact `colosseo-quality-lab-preview`: exterior, interior and district overview. The preview is rendered by Godot itself in a virtual display, not a mock-up.

## Scope
This is a separate iteration area. It does not overwrite or replace the official `ROMA_BRT_FONDAMENTA_RIBASSATE_V6.zip` base project.
