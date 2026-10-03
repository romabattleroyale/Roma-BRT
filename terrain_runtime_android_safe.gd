extends "res://terrain_runtime.gd"
## Android-safe runtime bootstrap.
## Uses the project RAW directly instead of opening a FileDialog on startup.
## Terrain geometry, heightmap values, control-map algorithm and Tevere generation
## remain inherited from terrain_runtime.gd.

func _setup() -> void:
	if not ClassDB.class_exists("Terrain3D"):
		push_error("Terrain3D non disponibile: controlla il plugin/GDExtension.")
		_set_status("ERRORE: Terrain3D non disponibile")
		return

	terrain = Terrain3D.new()
	terrain.name = "Terrain3D_HEIGHTMAP_2000x2000"
	terrain.region_size = Terrain3D.SIZE_512
	terrain.vertex_spacing = MAP_SIZE_M / 1080.0
	terrain.mesh_lods = 7
	terrain.show_checkered = false
	terrain.show_colormap = false
	terrain.show_grey = false
	add_child(terrain, true)

	var roman_assets: Terrain3DAssets = load("res://terrain_materials/terrain_assets_roman_natural.tres")
	if roman_assets:
		terrain.assets = roman_assets
	terrain.material.auto_shader = false
	terrain.material.set_shader_param("macro_variation1", Vector3(0.985, 1.00, 0.96))
	terrain.material.set_shader_param("macro_variation2", Vector3(1.015, 1.00, 0.985))

	await get_tree().process_frame
	if terrain.data == null:
		push_error("Terrain3D Data non inizializzato.")
		_set_status("ERRORE: Terrain3D Data non inizializzato")
		return

	const RAW_PATH := "res://assets/heightmap.raw"
	if not FileAccess.file_exists(RAW_PATH):
		push_error("RAW non trovato: " + RAW_PATH)
		_set_status("ERRORE: heightmap.raw non trovato")
		return

	_set_status("Caricamento heightmap RAW…")
	print("ANDROID SAFE TERRAIN: import automatico ", RAW_PATH)
	await get_tree().process_frame
	_import_raw(RAW_PATH)
