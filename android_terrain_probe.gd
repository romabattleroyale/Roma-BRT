extends Node3D
## TEST 2 diagnostic: isolate the exact Terrain3D initialization point on Android.
## No city, V37 buildings, POIs, roads, Tevere, or baked scene.

const MAP_SIZE_M := 2000.0
const HEIGHT_SCALE_M := 48.0
const RAW_PATH := "res://assets/heightmap.raw"

var terrain: Terrain3D
var status_label: Label

func _ready() -> void:
	status_label = get_node_or_null("Status")
	call_deferred("_start_probe")

func _show_step(text: String) -> void:
	_set_status(text)
	await get_tree().process_frame

func _start_probe() -> void:
	await _show_step("T2-01: before Terrain3D class check")
	if not ClassDB.class_exists("Terrain3D"):
		_set_status("FAIL T2-01: Terrain3D class unavailable")
		push_error("ANDROID TERRAIN PROBE: Terrain3D class unavailable")
		return

	await _show_step("T2-02: before Terrain3D.new()")
	terrain = Terrain3D.new()
	await _show_step("T2-03: Terrain3D.new() OK")

	await _show_step("T2-04: before region_size")
	terrain.region_size = Terrain3D.SIZE_512
	await _show_step("T2-05: region_size OK")

	await _show_step("T2-06: before vertex_spacing")
	terrain.vertex_spacing = MAP_SIZE_M / 1080.0
	await _show_step("T2-07: vertex_spacing OK")

	await _show_step("T2-08: before mesh_lods")
	terrain.mesh_lods = 7
	await _show_step("T2-09: mesh_lods OK")

	await _show_step("T2-10: before display flags")
	terrain.show_checkered = false
	terrain.show_colormap = false
	terrain.show_grey = false
	await _show_step("T2-11: display flags OK")

	await _show_step("T2-12: before add_child")
	add_child(terrain, true)
	await _show_step("T2-13: add_child OK")

	await _show_step("T2-14: before terrain assets load")
	var roman_assets: Terrain3DAssets = load("res://terrain_materials/terrain_assets_roman_natural.tres")
	await _show_step("T2-15: assets load returned")
	if roman_assets:
		terrain.assets = roman_assets
	await _show_step("T2-16: assets assignment OK")

	await _show_step("T2-17: before material auto_shader")
	terrain.material.auto_shader = false
	await _show_step("T2-18: material auto_shader OK")

	if terrain.data == null:
		_set_status("FAIL T2-19: Terrain3D Data unavailable")
		push_error("ANDROID TERRAIN PROBE: Terrain3D Data unavailable")
		return

	await _show_step("T2-20: Terrain3D init PASS — before RAW")
	if not FileAccess.file_exists(RAW_PATH):
		_set_status("FAIL T2-20: heightmap.raw missing")
		push_error("ANDROID TERRAIN PROBE: missing " + RAW_PATH)
		return

	_set_status("PASS T2: Terrain3D init OK — RAW not imported in this diagnostic")
	print("ANDROID TERRAIN PROBE T2 PASS: Terrain3D initialization completed")

func _set_status(text: String) -> void:
	if status_label and is_instance_valid(status_label):
		status_label.text = text
