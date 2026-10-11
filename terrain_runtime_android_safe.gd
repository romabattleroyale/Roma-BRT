extends "res://terrain_runtime.gd"
## Android-safe runtime bootstrap.
## If the persistent Terrain3D data directory exists, load it directly.
## RAW import remains only as a first-run/CI fallback; normal Play no longer
## rebuilds the 1081x1081 control map on every startup.

const TERRAIN_DATA_DIR := "res://terrain_data"
const TERRAIN_CACHE_MARKER := "res://terrain_data/READY.txt"

func _setup() -> void:
	if not ClassDB.class_exists("Terrain3D"):
		push_error("Terrain3D non disponibile: controlla il plugin/GDExtension.")
		_set_status("ERRORE: Terrain3D non disponibile")
		return

	terrain = ClassDB.instantiate("Terrain3D") as Node3D
	terrain.name = "Terrain3D_HEIGHTMAP_2000x2000"
	terrain.set("region_size", 512)
	terrain.vertex_spacing = MAP_SIZE_M / 1080.0
	terrain.mesh_lods = 5 # Android performance: fewer Terrain3D LOD levels while retaining the full heightmap
	terrain.show_checkered = false
	terrain.show_colormap = false
	terrain.show_grey = false
	# Reload assets without reusing a potentially stale cached resource.
	# Terrain3D builds texture arrays at runtime, so log the actual source textures.
	var roman_assets: Resource = ResourceLoader.load(
		"res://terrain_materials/terrain_assets_roman_natural.tres",
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if roman_assets:
		terrain.assets = roman_assets
		var texture_list: Array = roman_assets.get("texture_list")
		print("TERRAIN MATERIAL DIAGNOSTIC: texture slots=", texture_list.size())
		for i in range(texture_list.size()):
			var asset = texture_list[i]
			if asset:
				var albedo: Texture2D = asset.get("albedo_texture")
				var normal: Texture2D = asset.get("normal_texture")
				print("TERRAIN MATERIAL DIAGNOSTIC: slot=", i, " name=", asset.get("name"), " albedo=", (str(albedo.get_size()) if albedo else "MISSING"), " normal=", (str(normal.get_size()) if normal else "MISSING"))
	else:
		push_error("TERRAIN MATERIAL ERROR: asset list could not be loaded")
	# Keep Terrain3D on its built-in shader; a custom override can render the terrain black.
	terrain.material.shader_override_enabled = false
	# Android compatibility: this project has 25 saved regions; keep the
	# Terrain3D region uniform array small for mobile GPU/driver limits.
	terrain.material.set("max_regions", 64)
	terrain.material.auto_shader = false
	print("ANDROID TERRAIN MATERIAL: Roman Natural slots (0=grass, 1=soil, 2=rock); shader_override=false max_regions=64 auto_shader=false")
	terrain.material.set_shader_param("macro_variation1", Vector3(0.985, 1.00, 0.96))
	terrain.material.set_shader_param("macro_variation2", Vector3(1.015, 1.00, 0.985))

	# CRITICAL: attach only after the five terrain texture assets and shader
	# configuration are assigned. Terrain3D may initialize native GPU texture
	# arrays on entering the scene tree; doing that with empty/default assets can
	# leave the terrain surface black on Vulkan.
	add_child(terrain, true)
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

	# FORCE NATURAL MASK REBUILD:
	# The shipped cache contains an old control map with large orange square patches.
	# Loading that cache would ignore the updated biome thresholds. Re-import the
	# original heightmap and regenerate its control map so the old mask is discarded.
	# This deliberately prioritizes correct terrain appearance over stale-cache speed.
	if FileAccess.file_exists(TERRAIN_CACHE_MARKER):
		print("ANDROID SAFE TERRAIN: ignoring stale cached control map; rebuilding natural mask from RAW")
	_set_status("Ricostruzione terreno naturale e maschera…")
	print("ANDROID SAFE TERRAIN: import automatico ", RAW_PATH)
	await get_tree().process_frame
	_import_raw(RAW_PATH)

func _read_normalized_raw(path: String) -> PackedFloat32Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedFloat32Array()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.size() == 0 or bytes.size() % 2 != 0:
		return PackedFloat32Array()
	var samples := bytes.size() / 2
	var side := int(sqrt(float(samples)))
	if side * side != samples:
		return PackedFloat32Array()
	var values := PackedFloat32Array()
	values.resize(samples)
	var min_u := 65535
	var max_u := 0
	for i in range(samples):
		var u := (int(bytes[i * 2]) << 8) | int(bytes[i * 2 + 1])
		if u < min_u:
			min_u = u
		if u > max_u:
			max_u = u
		values[i] = float(u)
	var source_range := maxf(1.0, float(max_u - min_u))
	for i in range(samples):
		values[i] = clampf((values[i] - float(min_u)) / source_range, 0.0, 1.0)
	return values

# Exact-result optimization of the inherited control-map algorithm.
# The original 5x5 bank dilation is separable, so horizontal+vertical sliding
# windows produce the same mask with O(N) work instead of ~25*N checks.
func _build_manual_control_map(values: PackedFloat32Array, width: int, height: int) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(width * height * 4)
	var spacing := MAP_SIZE_M / float(width - 1)
	var radius := 12
	var slope_start := 28.0
	var slope_full := 42.0

	var bank := Image.load_from_file("res://terrain_materials/river_mask.png")
	var bank_flags := PackedByteArray()
	bank_flags.resize(width * height)
	if bank == null:
		push_warning("river_mask.png non disponibile: bank mask disattivata")
	else:
		for z in range(height):
			for x in range(width):
				bank_flags[z * width + x] = 1 if bank.get_pixel(x, z).r > 0.5 else 0

	var horizontal := PackedByteArray()
	horizontal.resize(width * height)
	for z in range(height):
		var window := 0
		for x in range(-2, mini(2, width - 1) + 1):
			if x >= 0 and bank_flags[z * width + x] != 0:
				window += 1
		for x in range(width):
			if x + 2 < width and x + 2 > 2:
				window += bank_flags[z * width + x + 2]
			if x - 3 >= 0:
				window -= bank_flags[z * width + x - 3]
			horizontal[z * width + x] = 1 if window > 0 else 0

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
			var soil_weight := 0.0 # Flat terrain stays grass; no square soil patches from heightmap noise.
			if bank_dilated[z * width + x] != 0:
				soil_weight = maxf(soil_weight, 0.24)
			var blend := clampi(int(round(soil_weight * 255.0)), 0, 255)
			var packed: int = ((1 & 0x1F) << 22) | ((blend & 0xFF) << 14)
			bytes.encode_u32((z * width + x) * 4, packed)

	return Image.create_from_data(width, height, false, Image.FORMAT_RF, bytes)
