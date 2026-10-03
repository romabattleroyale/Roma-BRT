extends Node3D

const RAW_PATH := "res://assets/heightmap.raw"
const RAW_SIZE := 1081
const MAP_SIZE_M := 2000.0
const HEIGHT_SCALE := 48.0
const CITY_PATH := "res://baked_city/roma_city_587.tscn"

var terrain
var label: Label

func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 28)
	layer.add_child(label)
	_set("T3: starting Terrain3D + RAW + 587 city...")
	call_deferred("_setup")

func _set(text: String) -> void:
	label.text = text
	print(text)

func _setup() -> void:
	if not ClassDB.class_exists("Terrain3D"):
		_set("FAIL T3-01: Terrain3D class missing")
		return
	terrain = Terrain3D.new()
	terrain.name = "Terrain3D"
	terrain.region_size = Terrain3D.SIZE_512
	terrain.vertex_spacing = MAP_SIZE_M / float(RAW_SIZE - 1)
	terrain.mesh_lods = 7
	terrain.show_grid = false
	terrain.show_gizmos = false
	add_child(terrain, true)
	_set("T3-02: Terrain3D init OK")
	if not FileAccess.file_exists(RAW_PATH):
		_set("FAIL T3-03: heightmap.raw missing")
		return
	var f := FileAccess.open(RAW_PATH, FileAccess.READ)
	if f == null:
		_set("FAIL T3-04: cannot open RAW")
		return
	var expected := RAW_SIZE * RAW_SIZE * 2
	if f.get_length() != expected:
		_set("FAIL T3-05: RAW size mismatch")
		f.close()
		return
	var raw := f.get_buffer(expected)
	f.close()
	var values := PackedFloat32Array()
	values.resize(RAW_SIZE * RAW_SIZE)
	var min_v := 65535.0
	var max_v := 0.0
	for i in range(RAW_SIZE * RAW_SIZE):
		var v := float((int(raw[i * 2]) << 8) | int(raw[i * 2 + 1]))
		values[i] = v
		min_v = min(min_v, v)
		max_v = max(max_v, v)
	var span := max_v - min_v
	if span <= 0.0:
		_set("FAIL T3-06: RAW has no height range")
		return
	for i in range(values.size()):
		values[i] = clampf((values[i] - min_v) / span, 0.0, 1.0)
	var image := Image.create_from_data(RAW_SIZE, RAW_SIZE, false, Image.FORMAT_RF, values.to_byte_array())
	_set("T3-07: importing real RAW...")
	await get_tree().process_frame
	if terrain.data == null:
		_set("FAIL T3-08: Terrain3D data missing")
		return
	var maps: Array[Image]
	maps.resize(Terrain3DRegion.TYPE_MAX)
	maps[Terrain3DRegion.TYPE_HEIGHT] = image
	terrain.data.import_images(maps, Vector3.ZERO, 0.0, HEIGHT_SCALE)
	terrain.data.calc_height_range(true)
	_set("T3-09: terrain imported; loading baked 587 city...")
	await get_tree().process_frame
	if not FileAccess.file_exists(CITY_PATH):
		_set("FAIL T3-10: baked city scene missing")
		return
	var packed := load(CITY_PATH) as PackedScene
	if packed == null:
		_set("FAIL T3-11: cannot load baked city")
		return
	var city := packed.instantiate()
	city.name = "RomaCity_BAKED_587"
	add_child(city, true)
	_set("PASS T3: Terrain3D + RAW + baked 587 city loaded")
