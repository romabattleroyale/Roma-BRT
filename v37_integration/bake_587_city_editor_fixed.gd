@tool
extends EditorScript
## Single fixed entry point for the 587 V37 editor bake.
## The actual implementation is kept in bake_587_city_editor.gd so the two
## scripts cannot drift apart again.

func _run() -> void:
    var root := EditorInterface.get_edited_scene_root()
    if root == null or root.scene_file_path != "res://main.tscn":
        EditorInterface.open_scene_from_path("res://main.tscn")
        root = EditorInterface.get_edited_scene_root()
    if root == null:
        push_error("BAKE 587 FIXED: impossibile aprire res://main.tscn")
        return

    var script: Script = load("res://v37_integration/bake_587_city_editor.gd") as Script
    if script == null:
        push_error("BAKE 587 FIXED: canonical bake script not found")
        return
    var runner = script.new()
    if runner == null:
        push_error("BAKE 587 FIXED: cannot instantiate canonical bake script")
        return
    runner._run()
