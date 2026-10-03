@tool
extends EditorScript
## Single fixed entry point for the 587 V37 editor bake.
## The actual implementation is kept in bake_587_city_editor.gd so the two
## scripts cannot drift apart again.

func _run() -> void:
    var script: Script = load("res://v37_integration/bake_587_city_editor.gd") as Script
    if script == null:
        push_error("BAKE 587 FIXED: canonical bake script not found")
        return
    var runner = script.new()
    if runner == null:
        push_error("BAKE 587 FIXED: cannot instantiate canonical bake script")
        return
    runner._run()
