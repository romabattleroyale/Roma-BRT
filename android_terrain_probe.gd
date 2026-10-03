extends Node3D
## TEST 2: Terrain3D + real RAW heightmap only.
## No city, V37 buildings, POIs, roads, Tevere, or baked scene.

const MAP_SIZE_M := 2000.0
const HEIGHT_SCALE_M := 48.0
const RAW_PATH := "res://assets/heightmap.raw"
const RAW_MAX := 65535.0

var terrain: Terrain3D
var status_label: Label

func _ready() -> void:
	status_label = get_node_or_null("Status")
	call_deferred("_start_probe")

func _start_probe() -> void:
	_set_status("Terrain3D probe: starting…")
	if not ClassDB.class_exists("Terrain3D"):
		_set_status("FAIL: Terrain3D class unavailable")
		push_error("ANDROID TERRAIN PROBE: Terrain3D class unavailable")
		return

	terrain = Terrain3D.new()
	terrain.name = "Terrain3D_ANDROID_PROBE"
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

	await get_tree().process_frame
	if terrain.data == null:
		_set_status("FAIL: Terrain3D Data unavailable")
		push_error("ANDROID TERRAIN PROBE: Terrain3D Data unavailable")
		return

	if not FileAccess.file_exists(RAW_PATH):
		_set_status("FAIL: heightmap.raw missing")
		push_error("ANDROID TERRAIN PROBE: missing " + RAW_PATH)
		return

	_set_status("Terrain3D probe: loading RAW…")
	var f := FileAccess.open(RAW_PATH, FileAccess.READ)
	if f == null:
		_set_status("FAIL: cannot open RAW")
		push_error("ANDROID TERRAIN PROBE: cannot open RAW")
		return

	var bytes := f.get_buffer(f.get_length())
	f.close()

	if bytes.size() == 0 or bytes.size() % 2 != 0:
		_set_status("FAIL: invalid RAW size")
		push_error("ANDROID TERRAIN PROBE: invalid RAW size=" + str(bytes.size()))
		return

	var samples: int = bytes.size() / 2
	var side: int = int(sqrt(float(samples)))
	if side * side != samples:
		_set_status("FAIL: RAW is not square")
		push_error("ANDROID TERRAIN PROBE: RAW is not square")
		return

	var values := PackedFloat32Array()
	values.resize(samples)
	var min_u := 65535
	var max_u := 0
	for i in range(samples):
		var u: int = (int(bytes[i * 2]) << 8) | int(bytes[i * 2 + 1])
		values[i] = float(u)
		min_u = mini(min_u, u)
		max_u = maxi(max_u, u)

	var source_range := maxf(1.0, float(max_u - min_u))
	for i in range(samples):
		values[i] = clampf((values[i] - float(min_u)) / source_range, 0.0, 1.0)

	var height_image := Image.create_from_data(side, side, false, Image.FORMAT_RF, values.to_byte_array())
	if height_image == null:
		_set_status("FAIL: cannot create height image")
		push_error("ANDROID TERRAIN PROBE: Image.create_from_data failed")
		return

	var maps: Array[Image]
	maps.resize(Terrain3DRegion.TYPE_MAX)
	maps[Terrain3DRegion.TYPE_HEIGHT] = height_image

	terrain.data.import_images(maps, Vector3.ZERO, 0.0, HEIGHT_SCALE_M)
	terrain.data.calc_height_range(true)

	_set_status("PASS: Terrain3D + RAW %dx%d — keep app open" % [side, side])
	print("ANDROID TERRAIN PROBE PASS")
	print("  dimensions=", side, "x", side)
	print("  raw min/max=", min_u, "/", max_u)
	print("  height scale=", HEIGHT_SCALE_M)
	print("  region size=512")
