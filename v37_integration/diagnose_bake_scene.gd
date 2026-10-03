@tool
extends EditorScript
## Runtime-safe diagnosis for the 587-city bake.
## Opens main.tscn, inspects the actual edited scene tree, and reports
## whether a real Terrain3D node exists before any building is constructed.

func _run() -> void:
    print("BAKE DIAG - avvio")
    EditorInterface.open_scene_from_path("res://main.tscn")
    var root := EditorInterface.get_edited_scene_root()
    if root == null:
        push_error("BAKE DIAG: edited scene root NULL after opening main.tscn")
        return

    print("BAKE DIAG - root: ", root.name)
    print("BAKE DIAG - root class: ", root.get_class())
    print("BAKE DIAG - root scene: ", root.scene_file_path)
    print("BAKE DIAG - direct children: ", root.get_child_count())

    var terrain_count := _walk(root, "")
    print("BAKE DIAG - Terrain3D count: ", terrain_count)

    if terrain_count == 0:
        push_error("BAKE DIAG: no Terrain3D exists in the edited main.tscn tree. main.tscn uses TerrainBootstrap, which creates Terrain3D dynamically at runtime.")
    else:
        print("BAKE DIAG: Terrain3D exists in editor scene.")

func _walk(node: Node, prefix: String) -> int:
    var class_name_text := node.get_class()
    var found := 1 if class_name_text == "Terrain3D" else 0
    print("BAKE DIAG NODE: ", prefix, node.name, " [", class_name_text, "]")
    if class_name_text == "Terrain3D":
        print("BAKE DIAG TERRAIN: ", node.get_path(), " data=", node.get("data"))
    for child in node.get_children():
        found += _walk(child, prefix + "  ")
    return found
