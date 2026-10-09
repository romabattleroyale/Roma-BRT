# Character integration checkpoint

## Source assets and expected project paths

Copy the supplied source assets into the Godot project at these paths:

- `assets/characters/Superhero_Male_FullBody.gltf`
- `assets/characters/Superhero_Male_FullBody.bin`
- The seven texture files referenced by the character glTF, in the same directory (preserve their original filenames).
- `assets/animations/UAL1_Standard.glb`

The loader is configured to look for the character and animation library at those locations. Keep the source animation library intact.

## Compatibility check completed

The character glTF and UAL1_Standard.glb each declare 65 skin joints. Their ordered joint-name lists match, beginning with `root`, `pelvis`, `spine_01`, `spine_02`, `spine_03`, `neck_01`, and `Head`. This is a strong structural compatibility signal, but it does **not** prove that Godot's imported animation track paths will bind correctly at runtime.

The UAL library contains the expected clips `Idle_Loop`, `Jog_Fwd_Loop`, `Sprint_Loop`, `Crouch_Idle_Loop`, and `Crouch_Fwd_Loop`.

## Required in-editor verification

1. Open the project with the target Godot 4.7.x version and allow the glTF/GLB imports to finish.
2. Run the main scene and inspect the Output panel for `CharacterVisualLoader` warnings.
3. Confirm the mesh appears at the player position and that all five clips are present in the character's AnimationPlayer.
4. Verify the animation actually moves the character skeleton (not merely that the clip name exists). Check idle, jog, sprint and crouch; look for foot sliding, wrong facing direction, root-motion drift, or a mesh offset.
5. Test movement on uneven terrain and on Android touch controls. Keep the existing camera and terrain-following logic unchanged.

Do not consider the character integration complete until these runtime checks pass. The supplied binary assets are not included in this repository yet; this note does not claim a successful runtime test.
