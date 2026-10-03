extends "res://terrain_runtime_android_safe.gd"

const RAW_PATH := "res://assets/heightmap.raw"

var probe_label: Label

func _ready() -> void:
	probe_label = Label.new()
	probe_label.position = Vector2(24, 24)
	probe_label.add_theme_font_size_override("font_size", 28)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(probe_label)
	_set_probe("T2-B: starting Terrain3D + RAW import...")
	call_deferred("_probe_setup")

func _set_probe(text: String) -> void:
	probe_label.text = text
	print(text)

func _probe_setup() -> void:
	if not ClassDB.class_exists("Terrain3D"):
		_set_probe("FAIL T2-B-01: Terrain3D class missing")
		return
	_set_probe("T2-B-02: creating Terrain3D...")
	terrain = Terrain3D.new()
	terrain.name = "Terrain3D_RAW_PROBE"
	terrain.region_size = Terrain3D.SIZE_512
	terrain.vertex_spacing = MAP_SIZE_M / 1080.0
	terrain.mesh_lods = 7
	terrain.show_checkered = false
	terrain.show_colormap = false
	terrain.show_grey = false
	add_child(terrain, true)
	await get_tree().process_frame
	if terrain.data == null:
		_set_probe("FAIL T2-B-03: Terrain3D data missing")
		return
	if not FileAccess.file_exists(RAW_PATH):
		_set_probe("FAIL T2-B-04: heightmap.raw missing")
		return
	_set_probe("T2-B-05: Terrain3D init OK; importing real RAW...")
	_import_raw(RAW_PATH)
	await get_tree().process_frame
	_set_probe("PASS T2-B: Terrain3D + real RAW import completed")
