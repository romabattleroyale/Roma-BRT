extends "res://terrain_runtime.gd"
## Android-safe runtime bootstrap.
## Uses the project RAW directly instead of opening a FileDialog on startup.
## Terrain geometry, heightmap values, control-map result and Tevere generation
## remain unchanged; only the control-map implementation is optimized.

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

# Exact-result optimization of the inherited control-map algorithm.
# The original 5x5 bank dilation is separable, so horizontal+vertical sliding
# windows produce the same mask with O(N) work instead of ~25*N checks.
func _build_manual_control_map(values: PackedFloat32Array, width: int, height: int) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(width * height * 4)
	var spacing := MAP_SIZE_M / float(width - 1)
	var radius := 12
	var slope_start := 9.0
	var slope_full := 18.0

	var bank := Image.load_from_file("res://terrain_materials/river_mask.png")
	var bank_flags := PackedByteArray()
	bank_flags.resize(width * height)
	if bank == null:
		push_warning("river_mask.png non disponibile: bank mask disattivata")
	else:
		for z in range(height):
			for x in range(width):
				bank_flags[z * width + x] = 1 if bank.get_pixel(x, z).r > 0.5 else 0

	# Exact 5-pixel horizontal dilation.
	var horizontal := PackedByteArray()
	horizontal.resize(width * height)
	for z in range(height):
		var window := 0
		for x in range(-2, mini(2, width - 1) + 1):
			if x >= 0 and bank_flags[z * width + x] != 0:
				window += 1
		for x in range(width):
			if x + 2 < width and x + 2 >= 0 and x + 2 > 2:
				window += bank_flags[z * width + x + 2]
			if x - 3 >= 0:
				window -= bank_flags[z * width + x - 3]
			horizontal[z * width + x] = 1 if window > 0 else 0

	# Exact 5-pixel vertical dilation of the horizontal result.
	var bank_dilated := PackedByteArray()
	bank_dilated.resize(width * height)
	for x in range(width):
		var window := 0
		for z in range(-2, mini(2, height - 1) + 1):
			if z >= 0 and horizontal[z * width + x] != 0:
				window += 1
		for z in range(height):
			if z + 2 < height and z + 2 > 2:
				window += horizontal[(z + 2) * width + x]
			if z - 3 >= 0:
				window -= horizontal[(z - 3) * width + x]
			bank_dilated[z * width + x] = 1 if window > 0 else 0

	for z in range(height):
		var z0: int = maxi(0, z - radius)
		var z1: int = mini(height - 1, z + radius)
		for x in range(width):
			var x0: int = maxi(0, x - radius)
			var x1: int = mini(width - 1, x + radius)
			var dx_dist := float(x1 - x0) * spacing
			var dz_dist := float(z1 - z0) * spacing
			var dx := 0.0 if dx_dist <= 0.0 else ((values[z * width + x1] - values[z * width + x0]) * HEIGHT_SCALE_M / dx_dist)
			var dz := 0.0 if dz_dist <= 0.0 else ((values[z1 * width + x] - values[z0 * width + x]) * HEIGHT_SCALE_M / dz_dist)
			var slope_deg := rad_to_deg(atan(sqrt(dx * dx + dz * dz)))
			var soil_weight := smoothstep(slope_start, slope_full, slope_deg)
			if bank_dilated[z * width + x] != 0:
				soil_weight = maxf(soil_weight, 0.42)
			var blend := clampi(int(round(soil_weight * 255.0)), 0, 255)
			var packed: int = ((1 & 0x1F) << 22) | ((blend & 0xFF) << 14)
			bytes.encode_u32((z * width + x) * 4, packed)

	return Image.create_from_data(width, height, false, Image.FORMAT_RF, bytes)
