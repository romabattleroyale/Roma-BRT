extends SceneTree
## One-time CI bake of the real Terrain3D data directory.
## The runtime uses this directory afterward, so Android/Linux no longer
## decode/import the 1081x1081 RAW and rebuild the control map on every launch.

const DATA_DIR := "res://terrain_data"
const TIMEOUT_SEC := 180.0

var main_instance: Node

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var packed: PackedScene = load("res://main.tscn")
	if packed == null:
		push_error("TERRAIN DATA BAKE: impossibile caricare main.tscn")
		quit(10)
		return

	main_instance = packed.instantiate()
	root.add_child(main_instance)
	print("TERRAIN DATA BAKE: main scene avviata")

	var deadline := Time.get_ticks_msec() + int(TIMEOUT_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var bootstrap := main_instance.get_node_or_null("TerrainBootstrap")
		if bootstrap == null:
			continue
		var terrain = bootstrap.get("terrain")
		if terrain == null or terrain.data == null:
			continue
		if terrain.data.get_region_locations().size() == 0:
			continue

		var abs_dir := ProjectSettings.globalize_path(DATA_DIR)
		DirAccess.make_dir_recursive_absolute(abs_dir)
		print("TERRAIN DATA BAKE: regioni attive=", terrain.data.get_region_locations().size())
		print("TERRAIN DATA BAKE: salvataggio in ", DATA_DIR)
		terrain.data.save_directory(DATA_DIR)
		await process_frame
		print("TERRAIN DATA BAKE: SAVE COMPLETATO")
		quit(0)
		return

	push_error("TERRAIN DATA BAKE: timeout dopo %.0f s" % TIMEOUT_SEC)
	quit(20)
