extends SceneTree
## DIAGNOSTIC ONLY — runtime Terrain3D/building/road surface alignment.
## Installs the existing runtime-only alignment script into main.tscn at runtime.
## No scene, placement, Terrain3D, river or road assets are saved by this script.

const MAIN_SCENE := "res://main.tscn"
const ALIGN_SCRIPT := "res://v37_integration/terrain_surface_alignment.gd"

func _initialize() -> void:
    print("=== LINUX TERRAIN SURFACE ALIGN DIAGNOSTICS — START ===")
    var err: Error = change_scene_to_file(MAIN_SCENE)
    print("ALIGN DIAG change_scene_to_file error=", err)
    await create_timer(8.0).timeout

    var root := current_scene
    if root == null:
        print("TERRAIN SURFACE ALIGN DIAG: scene=<null>")
        quit(2)
        return

    var alignment := Node3D.new()
    alignment.name = "RuntimeTerrainSurfaceAlignmentDiagnostic"
    alignment.set_script(load(ALIGN_SCRIPT))
    root.add_child(alignment)
    print("TERRAIN SURFACE ALIGN DIAG: installed runtime-only alignment script")

    await create_timer(20.0).timeout
    print("=== LINUX TERRAIN SURFACE ALIGN DIAGNOSTICS — END ===")
    quit(0)
