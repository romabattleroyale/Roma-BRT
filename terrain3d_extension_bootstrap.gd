extends Node
## Loads Terrain3D explicitly before the main scene scripts are parsed.
## This keeps the editor-only Terrain3D plugin disabled while guaranteeing
## that the runtime GDExtension is initialized in headless/CI and Android-safe runs.

const EXTENSION_PATH := "res://addons/terrain_3d/terrain.gdextension"

func _init() -> void:
	var absolute_path: String = ProjectSettings.globalize_path(EXTENSION_PATH)
	var manager := GDExtensionManager
	if not manager.is_extension_loaded(absolute_path):
		var status = manager.load_extension(absolute_path)
		print("TERRAIN3D GDExtension bootstrap status=", status, " path=", absolute_path)
	else:
		print("TERRAIN3D GDExtension bootstrap status=ALREADY_LOADED path=", absolute_path)

	if ClassDB.class_exists("Terrain3D"):
		print("TERRAIN3D CLASSDB=AVAILABLE")
	else:
		push_error("TERRAIN3D CLASSDB=UNAVAILABLE path=" + absolute_path)
