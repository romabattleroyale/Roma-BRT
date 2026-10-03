extends Node3D

const RAW_PATH := "res://assets/heightmap.raw"
const RAW_SIZE := 1081
const MAP_SIZE_M := 2000.0
const HEIGHT_SCALE := 48.0

var terrain
var label: Label

func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 28)
	layer.add_child(label)
	_set("T2-B: starting Terrain3D + RAW import...")
	call_deferred("_setup")

func _set(text: String) -> void:
	label.text = text
	print(text)

func _setup() -> void:
	if not ClassDB.class_exists("Terrain3D"):
		_set("FAIL T2-B-01: Terrain3D class missing")
		return
	_set("T2-B-02: creating Terrain3D...")
	terrain = Terrain3D.new()
	terrain.name = "Terrain3D"
	terrain.region_size = Terrain3D.SIZE_512
	terrain.vertex_spacing = MAP_SIZE_M / float(RAW_SIZE - 1)
	terrain.mesh_lods = 7
	terrain.show_grid = false
	terrain.show_gizmos = false
	add_child(terrain, true)
	_set("T2-B-03: Terrain3D init OK; checking RAW...")
	if not FileAccess.file_exists(RAW_PATH):
		_set("FAIL T2-B-04: heightmap.raw missing")
		return
	var f := FileAccess.open(RAW_PATH, FileAccess.READ)
	if f == null:
		_set("FAIL T2-B-05: cannot open RAW")
		return
	var expected := RAW_SIZE * RAW_SIZE * 2
	if f.get_length() != expected:
		_set("FAIL T2-B-06: RAW size mismatch: " + str(f.get_length()))
		f.close()
		return
	var raw := f.get_buffer(expected)
	f.close()
	_set("T2-B-07: RAW read OK; converting heightmap...")
	var image := Image.create(RAW_SIZE, RAW_SIZE, false, Image.FORMAT_RF)
	var min_v := 65535.0
	var max_v := 0.0
	for i in range(RAW_SIZE * RAW_SIZE):
		var v := float((int(raw[i * 2]) << 8) | int(raw[i * 2 + 1]))
		min_v = min(min_v, v)
		max_v = max(max_v, v)
	var span := max_v - min_v
	if span <= 0.0:
		_set("FAIL T2-B-08: RAW has no height range")
		return
	for y in range(RAW_SIZE):
		for x in range(RAW_SIZE):
			var idx := y * RAW_SIZE + x
			var v := float((int(raw[idx * 2]) << 8) | int(raw[idx * 2 + 1]))
			image.set_pixel(x, y, Color(((v - min_v) / span) * HEIGHT_SCALE, 0.0, 0.0, 1.0))
	_set("T2-B-09: heightmap ready; importing into Terrain3D...")
	await get_tree().process_frame
	if terrain.data == null:
		_set("FAIL T2-B-10: Terrain3D data missing")
		return
	if not terrain.data.has_method("import_heightmap"):
		_set("FAIL T2-B-11: import_heightmap unavailable")
		return
	var result = terrain.data.import_heightmap(image, Vector3.ZERO, Vector3(MAP_SIZE_M, HEIGHT_SCALE, MAP_SIZE_M))
	if result != null and result != OK:
		_set("FAIL T2-B-12: heightmap import failed")
		return
	_set("PASS T2-B: Terrain3D + RAW heightmap import OK")
