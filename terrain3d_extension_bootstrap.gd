extends Node
## Verifies that Terrain3D is available at runtime without loading the
## GDExtension a second time. Godot discovers terrain.gdextension automatically.

const EXTENSION_PATH := "res://addons/terrain_3d/terrain.gdextension"

func _init() -> void:
	var absolute_path: String = ProjectSettings.globalize_path(EXTENSION_PATH)
	if ClassDB.class_exists("Terrain3D"):
		print("TERRAIN3D GDExtension bootstrap status=ALREADY_LOADED path=", absolute_path)
		print("TERRAIN3D CLASSDB=AVAILABLE")
		return

	push_error("TERRAIN3D CLASSDB=UNAVAILABLE path=" + absolute_path)
