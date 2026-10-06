extends Node
## Runtime-only launcher that guarantees Terrain3D is registered before
## the real main scene is parsed. This avoids relying on implicit GDExtension
## discovery order in headless/CI startup.

const EXTENSION_PATH := "res://addons/terrain_3d/terrain.gdextension"
const MAIN_SCENE := "res://main.tscn"

func _ready() -> void:
	var absolute_path: String = ProjectSettings.globalize_path(EXTENSION_PATH)
	var loaded_before: bool = ClassDB.class_exists("Terrain3D")
	print("TERRAIN3D LAUNCHER preloaded=", loaded_before)

	if not loaded_before:
		var status = GDExtensionManager.load_extension(absolute_path)
		print("TERRAIN3D LAUNCHER load_status=", status, " path=", absolute_path)

	if not ClassDB.class_exists("Terrain3D"):
		push_error("TERRAIN3D LAUNCHER FAILED: Terrain3D class is unavailable after GDExtension load")
		get_tree().quit(1)
		return

	print("TERRAIN3D LAUNCHER CLASSDB=AVAILABLE")
	call_deferred("_open_main_scene")

func _open_main_scene() -> void:
	var error: Error = get_tree().change_scene_to_file(MAIN_SCENE)
	if error != OK:
		push_error("RUNTIME LAUNCHER: failed to open main scene error=" + str(error))
		get_tree().quit(1)
