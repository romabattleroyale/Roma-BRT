extends Node3D

# Isolated Colosseo quality lab. Procedural architectural study, not a replacement for the main map.
const SEGMENTS := 56
const FLOORS := 4
const RX := 32.0
const RZ := 24.0
var stone: StandardMaterial3D
var trim: StandardMaterial3D
var shadow_stone: StandardMaterial3D
var terracotta: StandardMaterial3D
var asphalt: StandardMaterial3D
var _box_mesh_cache: Dictionary = {}
var _box_shape_cache: Dictionary = {}
var _cylinder_mesh_cache: Dictionary = {}

func _ready() -> void:
	_make_materials()
	_make_environment()
	_make_ground()
	_make_plaza_paving()
	_make_colosseum()
	_make_neighbourhood()
	_make_roman_skyline()
	_make_street_furniture()
	_make_vehicles()
	_make_showcase_figures()
	_make_player()
	_make_hud()

func _mat(c: Color, rough := 0.88, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _make_materials() -> void:
	stone = _mat(Color("#c9a879"))
	trim = _mat(Color("#ead0a0"))
	shadow_stone = _mat(Color("#80664b"))
	terracotta = _mat(Color("#a94f32"))
	asphalt = _mat(Color("#35302c"))
	stone.albedo_texture = _procedural_stone_texture(Color("#c9a879"), 41)
	trim.albedo_texture = _procedural_stone_texture(Color("#ead0a0"), 83)
	shadow_stone.albedo_texture = _procedural_stone_texture(Color("#80664b"), 117)
	terracotta.albedo_texture = _procedural_brick_texture()
	stone.normal_enabled = true
	stone.normal_texture = _procedural_surface_normal(41, false)
	stone.normal_scale = 0.055
	trim.normal_enabled = true
	trim.normal_texture = _procedural_surface_normal(83, false)
	trim.normal_scale = 0.045
	shadow_stone.normal_enabled = true
	shadow_stone.normal_texture = _procedural_surface_normal(117, false)
	shadow_stone.normal_scale = 0.05
	terracotta.normal_enabled = true
	terracotta.normal_texture = _procedural_surface_normal(2026, true)
	terracotta.normal_scale = 0.055
	asphalt.albedo_texture = _procedural_asphalt_texture()
	asphalt.uv1_scale = Vector3(40, 40, 1)

func _procedural_stone_texture(base: Color, seed_value: int) -> Texture2D:
	# Broad, subtle stone variation rather than per-pixel noise: readable masonry at game distance.
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var block_tones: Array[Color] = []
	for block_y in range(8):
		for block_x in range(4):
			var variation := rng.randf_range(-0.025, 0.025)
			block_tones.append(Color(
				clampf(base.r + variation, 0.0, 1.0),
				clampf(base.g + variation, 0.0, 1.0),
				clampf(base.b + variation, 0.0, 1.0), 1.0))
	for y in range(256):
		for x in range(256):
			var cell_x := x % 64
			var cell_y := y % 32
			var mortar := cell_x < 2 or cell_y < 2
			var tile_x := int(x / 64)
			var tile_y := int(y / 32)
			var c := base.darkened(0.22) if mortar else block_tones[tile_y * 4 + tile_x]
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _procedural_surface_normal(seed_value: int, brick: bool) -> Texture2D:
	# Large-scale relief keeps the masonry tactile without the noisy, glittering surface of pixel noise.
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var heights: Array[float] = []
	for block_y in range(16):
		for block_x in range(8):
			heights.append(rng.randf_range(0.47, 0.53))
	for y in range(256):
		for x in range(256):
			var mortar: bool
			if brick:
				var row := int(y / 32)
				var offset := 32 if row % 2 else 0
				mortar = ((x + offset) % 64) < 3 or (y % 32) < 3
			else:
				mortar = (x % 64) < 2 or (y % 32) < 2
			var tile_x := int(x / 32)
			var tile_y := int(y / 16)
			var height_value: float = 0.30 if mortar else heights[tile_y * 8 + tile_x]
			img.set_pixel(x, y, Color(height_value, height_value, height_value, 1.0))
	img.bump_map_to_normal_map(0.55)
	return ImageTexture.create_from_image(img)

func _procedural_asphalt_texture() -> Texture2D:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4481
	for y in range(256):
		for x in range(256):
			var variation := rng.randf_range(-0.025, 0.025)
			if rng.randf() < 0.035:
				variation += rng.randf_range(-0.02, 0.02)
			var base := Color("#3a3b3b")
			img.set_pixel(x, y, Color(
				clampf(base.r + variation, 0.0, 1.0),
				clampf(base.g + variation, 0.0, 1.0),
				clampf(base.b + variation, 0.0, 1.0), 1.0))
	return ImageTexture.create_from_image(img)

func _procedural_brick_texture() -> Texture2D:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for y in range(256):
		for x in range(256):
			var row := int(y / 32)
			var offset := 32 if row % 2 else 0
			var cell_x := (x + offset) % 64
			var mortar := cell_x < 3 or y % 32 < 3
			var v := rng.randf_range(-0.07, 0.07)
			var c := Color("#613a2d") if mortar else Color(
				clampf(0.66 + v, 0.0, 1.0),
				clampf(0.28 + v * 0.6, 0.0, 1.0),
				clampf(0.17 + v * 0.4, 0.0, 1.0), 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, bevel := false) -> MeshInstance3D:
	var mesh_key := str(size.x, "_", size.y, "_", size.z)
	if not _box_mesh_cache.has(mesh_key):
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		_box_mesh_cache[mesh_key] = box_mesh
	var n := MeshInstance3D.new()
	n.mesh = _box_mesh_cache[mesh_key] as BoxMesh
	n.position = pos
	n.material_override = material
	parent.add_child(n)
	if bevel:
		if not _box_shape_cache.has(mesh_key):
			var box_shape := BoxShape3D.new()
			box_shape.size = size
			_box_shape_cache[mesh_key] = box_shape
		var body := StaticBody3D.new()
		body.position = pos
		var shape := CollisionShape3D.new()
		shape.shape = _box_shape_cache[mesh_key] as BoxShape3D
		body.add_child(shape)
		parent.add_child(body)
	return n

func _cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material, radial := 12) -> MeshInstance3D:
	var mesh_key := str(radius, "_", height, "_", radial)
	if not _cylinder_mesh_cache.has(mesh_key):
		var cylinder_mesh := CylinderMesh.new()
		cylinder_mesh.top_radius = radius
		cylinder_mesh.bottom_radius = radius
		cylinder_mesh.height = height
		cylinder_mesh.radial_segments = radial
		cylinder_mesh.rings = 1
		_cylinder_mesh_cache[mesh_key] = cylinder_mesh
	var n := MeshInstance3D.new()
	n.mesh = _cylinder_mesh_cache[mesh_key] as CylinderMesh
	n.position = pos
	n.material_override = material
	parent.add_child(n)
	return n

func _make_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#27365d")
	sky_mat.sky_horizon_color = Color("#f1ad76")
	sky_mat.ground_bottom_color = Color("#3a2b2a")
	sky_mat.ground_horizon_color = Color("#c98960")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.82
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.25
	env.ssao_power = 1.35
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.94
	env.fog_enabled = true
	env.fog_light_color = Color("#d8a07b")
	env.fog_light_energy = 0.72
	env.fog_density = 0.003
	env.fog_sky_affect = 0.38
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, -28, 0)
	sun.light_color = Color("#ffd9b0")
	sun.light_energy = 0.62
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)

func _make_ground() -> void:
	_box(self, Vector3(240, 1, 240), Vector3(0, -0.65, 0), asphalt, true)
	# travertine plaza apron, sidewalks and four main roads
	_box(self, Vector3(82, 0.22, 68), Vector3(0, -0.03, 0), stone)
	for z in [-48.0, 48.0]:
		_box(self, Vector3(240, 0.18, 12), Vector3(0, -0.05, z), shadow_stone)
		_box(self, Vector3(240, 0.22, 2.0), Vector3(0, 0.03, z + (7 if z < 0 else -7)), trim)
	for x in [-54.0, 54.0]:
		_box(self, Vector3(12, 0.18, 240), Vector3(x, -0.05, 0), shadow_stone)
		_box(self, Vector3(2.0, 0.22, 240), Vector3(x + (7 if x < 0 else -7), 0.03, 0), trim)
	for x in range(-110, 111, 14):
		_box(self, Vector3(5, 0.025, 0.18), Vector3(x, -0.11, -48), trim)
		_box(self, Vector3(5, 0.025, 0.18), Vector3(x, -0.11, 48), trim)

func _make_plaza_paving() -> void:
	# Travertine slab paving in the approach plaza, with narrow joints and subtle color variation.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1407
	var slabs: Array[Material] = [
		_mat(Color("#c9b18a"), 0.92),
		_mat(Color("#d5bf9b"), 0.92),
		_mat(Color("#bda47c"), 0.92),
		_mat(Color("#c4ad85"), 0.92)
	]
	for row in range(9):
		for col in range(25):
			var x := -36.0 + col * 3.0 + (1.5 if row % 2 else 0.0)
			var z := 29.0 + row * 1.75
			var slab_size := Vector3(rng.randf_range(2.88, 2.96), 0.035, rng.randf_range(1.66, 1.72))
			_box(self, slab_size, Vector3(x, 0.105, z), slabs[rng.randi_range(0, slabs.size() - 1)])

func _make_colosseum() -> void:
	var col := Node3D.new()
	col.name = "COLOSSEO_ARCHITECTURE"
	add_child(col)
	# elliptical stepped podium
	for layer in range(4):
		_elliptical_ring(col, RX + 2.2 - layer * 0.48, RZ + 2.2 - layer * 0.48, 0.55, -0.1 + layer * 0.48, trim if layer % 2 == 0 else stone, true)
	# tiered facade with real open bays: piers, capitals, archivolts and horizontal entablatures
	for tier in range(FLOORS):
		var y := 1.15 + tier * 5.25
		var rx := RX - tier * 0.65
		var rz := RZ - tier * 0.5
		for i in range(SEGMENTS):
			var a := TAU * float(i) / SEGMENTS
			var p := Vector3(cos(a) * rx, y + 2.25, sin(a) * rz)
			var tangent := Vector3(-sin(a), 0, cos(a))
			var radial := Vector3(cos(a), 0, sin(a)).normalized()
			var pier := _box(col, Vector3(0.92, 4.5, 1.35), p, trim, true)
			if i % 2 == 0:
				_cylinder(col, 0.24, 4.1, p + radial * 0.78, trim, 12)
				_cylinder(col, 0.38, 0.22, p + radial * 0.78 + Vector3(0, 2.08, 0), stone, 12)
				_cylinder(col, 0.36, 0.20, p + radial * 0.78 - Vector3(0, 2.08, 0), stone, 12)
				for flute_offset in [-0.13, 0.0, 0.13]:
					_cylinder(col, 0.026, 3.7, p + radial * 0.96 + tangent * flute_offset, trim, 6)
			pier.look_at(p + tangent, Vector3.UP)
			_box(col, Vector3(1.25, 0.35, 1.65), p + Vector3(0, 2.2, 0), stone, true)
			_box(col, Vector3(1.18, 0.28, 1.58), p + Vector3(0, -2.18, 0), stone, true)
			# carved cornice profiles and shadow reveals at each storey
			_box(col, Vector3(1.48, 0.16, 1.78), p + Vector3(0, 2.38, 0), trim)
			_box(col, Vector3(1.42, 0.12, 1.72), p + Vector3(0, -2.38, 0), shadow_stone)
			# deep shadowed bay behind each opening
			var inner := Vector3(cos(a) * (rx - 0.42), y + 2.35, sin(a) * (rz - 0.42))
			var bay := _box(col, Vector3(0.24, 3.25, 0.24), inner, shadow_stone)
			bay.look_at(inner + tangent, Vector3.UP)
			# upper-floor window recesses and lintel detail
			if tier > 0 and i % 2 == 0:
				var win := _box(col, Vector3(0.12, 1.5, 0.9), p + Vector3(0, 0.15, 0), shadow_stone)
				win.look_at(p + tangent, Vector3.UP)
				var lintel := _box(col, Vector3(0.2, 0.16, 1.15), p + Vector3(0, 0.98, 0), trim)
				lintel.look_at(p + tangent, Vector3.UP)
		# five voussoirs over each opening form a readable Roman arcade rhythm
		for bay in range(SEGMENTS):
			var a0 := TAU * float(bay) / SEGMENTS
			var a1 := TAU * float(bay + 1) / SEGMENTS
			var mid_a := (a0 + a1) * 0.5
			var tangent_arch := Vector3(-sin(mid_a), 0, cos(mid_a))
			for stone_idx in range(7):
				var theta := PI - PI * float(stone_idx) / 6.0
				var arc_pos := Vector3(cos(mid_a) * rx, y + 2.55 + sin(theta) * 1.30, sin(mid_a) * rz) + tangent_arch * (cos(theta) * 1.30)
				var voussoir := _box(col, Vector3(0.58, 0.42, 1.42), arc_pos, trim)
				voussoir.look_at(arc_pos + tangent_arch, Vector3.UP)
				voussoir.rotate_object_local(Vector3(1, 0, 0), theta - PI * 0.5)
		# Continuous projecting stringcourse with small dentils below each tier.
		_elliptical_ring(col, rx + 0.55, rz + 0.55, 0.22, y + 4.42, stone)
		for dentil_idx in range(SEGMENTS):
			var dentil_a := TAU * float(dentil_idx) / SEGMENTS
			var dentil_pos := Vector3(cos(dentil_a) * (rx + 0.62), y + 4.18, sin(dentil_a) * (rz + 0.62))
			var dentil := _box(col, Vector3(0.20, 0.22, 0.24), dentil_pos, trim)
			dentil.look_at(dentil_pos + Vector3(-sin(dentil_a), 0, cos(dentil_a)), Vector3.UP)
		_elliptical_ring(col, rx + 0.35, rz + 0.35, 0.45, y + 4.65, trim)
	# Small pale-stone statuary on the main ledges breaks up the repeated arcade rhythm.
	var statue_stone := _mat(Color("#e1d1b0"), 0.82)
	for tier in [1, 2]:
		var y_statue: float = 1.15 + float(tier) * 5.25 + 4.72
		var rx_statue: float = RX - float(tier) * 0.65 + 0.48
		var rz_statue: float = RZ - float(tier) * 0.5 + 0.48
		for idx in range(12):
			var a := PI * 0.10 + float(idx) * PI * 0.80 / 11.0
			var radial := Vector3(cos(a), 0, sin(a)).normalized()
			var tangent := Vector3(-sin(a), 0, cos(a))
			var base := Vector3(cos(a) * rx_statue, y_statue, sin(a) * rz_statue)
			var statue := Node3D.new()
			statue.position = base
			statue.look_at(base + tangent, Vector3.UP)
			col.add_child(statue)
			_box(statue, Vector3(0.42, 0.28, 0.42), Vector3(0, 0.14, 0), trim)
			_box(statue, Vector3(0.38, 0.82, 0.30), Vector3(0, 0.68, 0), statue_stone)
			var statue_head := MeshInstance3D.new()
			var statue_head_mesh := SphereMesh.new()
			statue_head_mesh.radius = 0.15
			statue_head_mesh.height = 0.30
			statue_head.mesh = statue_head_mesh
			statue_head.position = Vector3(0, 1.22, 0)
			statue_head.material_override = statue_stone
			statue.add_child(statue_head)
			for side in [-1.0, 1.0]:
				var arm := _cylinder(statue, 0.075, 0.46, Vector3(side * 0.24, 0.78, 0), statue_stone, 7)
				arm.rotation.z = -side * 0.18

	# Upper attic course: solid travertine parapet with regularly spaced small openings.
	# This is distinct from the four lower arcades and breaks the repetitive silhouette.
	for i in range(SEGMENTS):
		var a := TAU * float(i) / SEGMENTS
		var tangent := Vector3(-sin(a), 0, cos(a))
		var radial := Vector3(cos(a), 0, sin(a)).normalized()
		var rx_attic := RX - 2.0
		var rz_attic := RZ - 1.55
		var center := Vector3(cos(a) * rx_attic, 22.0, sin(a) * rz_attic)
		var attic_panel := _box(col, Vector3(0.55, 2.3, 2.15), center, stone)
		attic_panel.look_at(center + tangent, Vector3.UP)
		if i % 2 == 0:
			var opening := _box(col, Vector3(0.10, 0.85, 0.62), center + radial * 0.31 + Vector3(0, 0.12, 0), shadow_stone)
			opening.look_at(center + tangent, Vector3.UP)
			var sill := _box(col, Vector3(0.18, 0.12, 0.82), center + radial * 0.36 + Vector3(0, -0.38, 0), trim)
			sill.look_at(center + tangent, Vector3.UP)
		var pilaster := _box(col, Vector3(0.68, 2.45, 0.20), center + radial * 0.34, trim)
		pilaster.look_at(center + tangent, Vector3.UP)
	_elliptical_ring(col, RX - 1.35, RZ - 1.0, 0.65, 23.25, trim, true)
	_elliptical_ring(col, RX - 1.15, RZ - 0.8, 0.32, 24.0, shadow_stone, true)
	# ceremonial SPQR standards and monumental approach stairs
	var banner_mat := _mat(Color("#7e2524"))
	var gold_mat := _mat(Color("#d7ad62"), 0.72, 0.08)
	for bx in [-18.0, -6.0, 6.0, 18.0]:
		_box(col, Vector3(0.18, 5.2, 0.18), Vector3(bx, 14.4, -25.2), gold_mat)
		_box(col, Vector3(1.75, 3.8, 0.14), Vector3(bx + 0.95, 13.3, -25.15), banner_mat)
		_box(col, Vector3(1.45, 0.12, 0.17), Vector3(bx + 0.95, 15.1, -25.04), gold_mat)
		_box(col, Vector3(1.25, 0.12, 0.17), Vector3(bx + 0.95, 11.45, -25.04), gold_mat)
		_box(col, Vector3(0.18, 5.2, 0.18), Vector3(bx, 14.4, 25.2), gold_mat)
		_box(col, Vector3(1.75, 3.8, 0.14), Vector3(bx + 0.95, 13.3, 25.15), banner_mat)
		_box(col, Vector3(1.45, 0.12, 0.17), Vector3(bx + 0.95, 15.1, 25.04), gold_mat)
		_box(col, Vector3(1.25, 0.12, 0.17), Vector3(bx + 0.95, 11.45, 25.04), gold_mat)
		var standard_text := Label3D.new()
		standard_text.text = "SPQR"
		standard_text.position = Vector3(bx + 0.95, 13.3, 25.25)
		standard_text.font_size = 48
		standard_text.pixel_size = 0.014
		standard_text.modulate = Color("#e4c078")
		standard_text.double_sided = true
		standard_text.no_depth_test = true
		col.add_child(standard_text)
	for step in range(8):
		_box(col, Vector3(18.0, 0.28, 1.1), Vector3(0, 0.14 + step * 0.28, -35.0 + step * 1.1), trim, true)
	# vomitoria stair aisles: radial stair flights between seating wedges
	for aisle in range(16):
		var a := TAU * float(aisle) / 16.0
		var radial := Vector3(cos(a), 0, sin(a))
		for step in range(10):
			var r := 21.5 + step * 0.82
			var pos := Vector3(radial.x * r, 1.75 + step * 0.29, radial.z * (15.0 + step * 0.58))
			var stair := _box(col, Vector3(1.45, 0.18, 0.95), pos, stone)
			stair.rotation.y = -a
	# radial vomitoria portals with deep reveals and lintels
	for aisle in range(16):
		var a := TAU * float(aisle) / 16.0
		var radial := Vector3(cos(a), 0, sin(a))
		var tangent := Vector3(-sin(a), 0, cos(a))
		var pos := Vector3(radial.x * 27.0, 5.0, radial.z * 19.0)
		for side in [-1.0, 1.0]:
			var jamb := _box(col, Vector3(0.38, 3.2, 0.48), pos + tangent * side * 1.05, trim, true)
			jamb.look_at(pos + tangent * side * 1.05 + tangent, Vector3.UP)
		var lintel := _box(col, Vector3(0.42, 0.34, 2.5), pos + Vector3(0, 1.72, 0), stone)
		lintel.look_at(pos + tangent, Vector3.UP)
	# arena, inner walls, tiered seating and hypogeum corridors
	_elliptical_ring(col, 19.5, 13.7, 0.35, 1.25, shadow_stone, true)
	_elliptical_ring(col, 18.4, 12.8, 0.3, 1.45, trim, true)
	for row in range(14):
		_elliptical_ring(col, 21.0 + row * 0.72, 14.6 + row * 0.52, 0.34, 1.55 + row * 0.31, trim if row % 3 else stone, true)
	# inner ambulatory: radial vault supports, continuous galleries and door openings
	for level in range(3):
		var yy := 4.2 + level * 4.0
		for i in range(48):
			var a := TAU * float(i) / 48
			var radial := Vector3(cos(a), 0, sin(a))
			var pos := Vector3(radial.x * (20.5 + level * 0.65), yy, radial.z * (14.8 + level * 0.45))
			var support := _box(col, Vector3(0.72, 3.5, 0.9), pos, trim, true)
			support.look_at(pos + Vector3(-radial.z, 0, radial.x), Vector3.UP)
			_box(col, Vector3(1.0, 0.18, 1.15), pos + Vector3(0, 1.8, 0), stone)
		# gallery floor bands visually separate the circulation levels
		_elliptical_ring(col, 21.0 + level * 0.7, 15.2 + level * 0.45, 0.26, yy + 1.95, trim, true)
	# radial service corridors beneath the arena and timber beam rhythm
	for x in range(-12, 13, 3):
		_box(col, Vector3(0.22, 1.7, 12.0), Vector3(x, 0.72, 0), trim)
		for z in range(-5, 6, 2):
			_box(col, Vector3(2.7, 0.16, 0.16), Vector3(x, 1.58, z), shadow_stone)
	# warm practical lights in the lower ambulatory and service corridors
	for i in range(24):
		var a := TAU * float(i) / 24.0
		var radial := Vector3(cos(a), 0, sin(a))
		var lamp_pos := Vector3(radial.x * 21.8, 3.3, radial.z * 15.6)
		var lamp := OmniLight3D.new()
		lamp.position = lamp_pos
		lamp.light_color = Color("#ffbd7a")
		lamp.light_energy = 0.45
		lamp.omni_range = 5.5
		lamp.shadow_enabled = false
		col.add_child(lamp)
		_cylinder(col, 0.12, 0.34, lamp_pos, trim, 10)
	# timber scaffolding, winches and maintenance platforms in the hypogeum
	var timber := _mat(Color("#63452f"), 0.92)
	for x in [-10.0, -5.0, 0.0, 5.0, 10.0]:
		for z in [-5.0, 0.0, 5.0]:
			_cylinder(col, 0.13, 2.4, Vector3(x, 1.05, z), timber, 8)
			_box(col, Vector3(4.8, 0.12, 0.65), Vector3(x, 2.1, z), timber)
	for z in [-6.0, 6.0]:
		_box(col, Vector3(27.0, 0.14, 0.24), Vector3(0, 2.25, z), timber)
	# stairwell handrails and posts for interior circulation
	for side in [-1.0, 1.0]:
		for step in range(10):
			var p := Vector3(side * (22.0 + step * 0.78), 2.0 + step * 0.28, -8.0 + step * 1.25)
			_cylinder(col, 0.055, 0.9, p, trim, 8)
			_box(col, Vector3(0.08, 0.08, 13.0), Vector3(side * 25.2, 3.1, -2.4), shadow_stone)
	# arena floor and hypogeum lanes
	_box(col, Vector3(29, 0.22, 19), Vector3(0, 1.55, 0), _mat(Color("#b99a70")))
	for x in range(-12, 13, 4):
		_box(col, Vector3(0.24, 0.08, 15), Vector3(x, 1.69, 0), shadow_stone)
	for x in range(-8, 9, 4):
		_box(col, Vector3(2.2, 1.0, 12), Vector3(x, 0.55, 0), shadow_stone)
	# upper attic story: alternating solid panels, pilasters and small square openings
	var attic_y := 1.15 + (FLOORS - 1) * 5.25 + 4.65
	for i in range(SEGMENTS):
		var a := TAU * float(i) / SEGMENTS
		var radial := Vector3(cos(a), 0, sin(a)).normalized()
		var tangent := Vector3(-sin(a), 0, cos(a))
		var p := Vector3(cos(a) * (RX - 2.1), attic_y + 1.45, sin(a) * (RZ - 1.7))
		var attic_pier := _box(col, Vector3(0.8, 2.9, 1.05), p, trim, true)
		attic_pier.look_at(p + tangent, Vector3.UP)
		if i % 2 == 0:
			var opening := _box(col, Vector3(0.14, 0.72, 0.48), p - radial * 0.28 + Vector3(0, 0.05, 0), shadow_stone)
			opening.look_at(p + tangent, Vector3.UP)
		_box(col, Vector3(1.12, 0.18, 1.38), p + Vector3(0, 1.5, 0), stone)
	_elliptical_ring(col, RX - 1.65, RZ - 1.25, 0.55, attic_y + 3.0, trim)
	# monumental entrance portals, travertine stairs and sculptural plinths
	for side in [-1.0, 1.0]:
		for x in [-8.0, -4.0, 0.0, 4.0, 8.0]:
			_box(col, Vector3(2.6, 0.22, 2.0), Vector3(x, 0.15, side * 26.0), trim)
			_box(col, Vector3(2.1, 0.22, 1.7), Vector3(x, 0.36, side * 26.0), stone)
		for x in [-14.0, 14.0]:
			_box(col, Vector3(1.5, 3.0, 1.5), Vector3(x, 1.7, side * 25.4), trim)
			_box(col, Vector3(2.1, 0.28, 2.1), Vector3(x, 3.25, side * 25.4), stone)

func _elliptical_ring(parent: Node3D, rx: float, rz: float, thickness: float, y: float, material: Material, collision := false) -> void:
	var count := 96
	for i in range(count):
		var a := TAU * float(i) / count
		var b := TAU * float(i + 1) / count
		var p := Vector3(cos(a) * rx, y, sin(a) * rz)
		var q := Vector3(cos(b) * rx, y, sin(b) * rz)
		var mid := (p + q) * 0.5
		var length := p.distance_to(q) + 0.08
		var n := _box(parent, Vector3(length, thickness, 0.65), mid, material, collision)
		n.rotation.y = -atan2(q.z - p.z, q.x - p.x)

func _make_neighbourhood() -> void:
	# Local Roman street grid between insulae, with raised travertine sidewalks.
	for street_z in [-69.5, -44.5, 55.5]:
		_box(self, Vector3(240, 0.14, 6.2), Vector3(0, -0.035, street_z), asphalt)
		for side in [-1.0, 1.0]:
			_box(self, Vector3(240, 0.18, 1.35), Vector3(0, 0.02, street_z + side * 3.75), stone)
		for lane_x in range(-110, 111, 12):
			_box(self, Vector3(2.3, 0.025, 0.12), Vector3(lane_x, 0.055, street_z), trim)
	for street_x in [-69.5, -44.5, 55.5]:
		_box(self, Vector3(6.2, 0.14, 240), Vector3(street_x, -0.035, 0), asphalt)
		for side in [-1.0, 1.0]:
			_box(self, Vector3(1.35, 0.18, 240), Vector3(street_x + side * 3.75, 0.02, 0), stone)
		for lane_z in range(-110, 111, 12):
			_box(self, Vector3(0.12, 0.025, 2.3), Vector3(street_x, 0.055, lane_z), trim)
	for row in range(5):
		for col in range(7):
			var x := -82.0 + col * 25.0
			var z := -82.0 + row * 25.0
			if abs(x) < 43 and abs(z) < 37:
				continue
			var h := 10.0 + float((row * 7 + col * 3) % 4) * 2.1
			var w := 12.0 + float((row + col) % 3) * 2.0
			var d := 10.0 + float((row * 2 + col) % 3) * 1.8
			var building := Node3D.new()
			building.position = Vector3(x, 0, z)
			add_child(building)
			var facade := terracotta if (row + col) % 3 == 0 else stone
			_box(building, Vector3(w, h, d), Vector3(0, h * 0.5, 0), facade, true)
			_box(building, Vector3(w + 0.7, 0.32, d + 0.7), Vector3(0, h + 0.1, 0), trim)
			_box(building, Vector3(w + 0.9, 0.45, d + 0.9), Vector3(0, h + 0.42, 0), _mat(Color("#713b2a")))
			if (row + col) % 2 == 0:
				var roof_left := _box(building, Vector3(w + 0.5, 0.20, d * 0.56), Vector3(0, h + 0.78, -d * 0.22), terracotta)
				roof_left.rotation.x = -0.28
				var roof_right := _box(building, Vector3(w + 0.5, 0.20, d * 0.56), Vector3(0, h + 0.78, d * 0.22), terracotta)
				roof_right.rotation.x = 0.28
				_box(building, Vector3(w + 0.6, 0.22, 0.28), Vector3(0, h + 1.02, 0), shadow_stone)
			if (row * 7 + col) % 3 == 0:
				var chimney := _box(building, Vector3(0.62, 1.05, 0.62), Vector3(w * 0.28, h + 1.05, -d * 0.22), terracotta)
				_box(building, Vector3(0.82, 0.14, 0.82), Vector3(w * 0.28, h + 1.62, -d * 0.22), trim)
			var floors := int(h / 2.8)
			for f in range(floors):
				var yy := 1.5 + f * 2.8
				_box(building, Vector3(w + 0.12, 0.16, d + 0.12), Vector3(0, yy, 0), trim)
				for side in [-1.0, 1.0]:
					for win in range(max(2, int(w / 2.7))):
						var wx: float = -w * 0.5 + 1.5 + win * (w - 3.0) / max(1, int(w / 2.7) - 1)
						_box(building, Vector3(0.82, 1.25, 0.12), Vector3(wx, yy + 0.6, side * (d * 0.5 + 0.08)), shadow_stone)
						_box(building, Vector3(1.04, 0.12, 0.18), Vector3(wx, yy + 1.28, side * (d * 0.5 + 0.12)), trim)
				# Side elevations also receive aligned openings and terracotta shutters.
				for side_x in [-1.0, 1.0]:
					for win_z in range(max(2, int(d / 2.8))):
						var wz: float = -d * 0.5 + 1.5 + win_z * (d - 3.0) / max(1, int(d / 2.8) - 1)
						_box(building, Vector3(0.12, 1.25, 0.82), Vector3(side_x * (w * 0.5 + 0.08), yy + 0.6, wz), shadow_stone)
						_box(building, Vector3(0.18, 0.12, 1.04), Vector3(side_x * (w * 0.5 + 0.12), yy + 1.28, wz), trim)
						for shutter_side in [-1.0, 1.0]:
							_box(building, Vector3(0.08, 1.25, 0.12), Vector3(side_x * (w * 0.5 + 0.17), yy + 0.6, wz + shutter_side * 0.49), terracotta)
				# window shutters, sills and lintels on the street-facing facade
				for win in range(max(2, int(w / 2.7))):
					var wx: float = -w * 0.5 + 1.5 + win * (w - 3.0) / max(1, int(w / 2.7) - 1)
					for side in [-1.0, 1.0]:
						_box(building, Vector3(0.12, 1.25, 0.08), Vector3(wx - 0.49, yy + 0.6, side * (d * 0.5 + 0.17)), terracotta)
						_box(building, Vector3(0.12, 1.25, 0.08), Vector3(wx + 0.49, yy + 0.6, side * (d * 0.5 + 0.17)), terracotta)
						_box(building, Vector3(1.12, 0.12, 0.20), Vector3(wx, yy - 0.08, side * (d * 0.5 + 0.17)), trim)
						if win % 2 == 0 and side > 0:
							_box(building, Vector3(1.7, 0.10, 0.78), Vector3(wx, yy + 0.04, d * 0.5 + 0.48), trim)
							_box(building, Vector3(1.7, 0.09, 0.08), Vector3(wx, yy + 0.52, d * 0.5 + 0.86), shadow_stone)
							for rail_x in [-0.68, -0.34, 0.0, 0.34, 0.68]:
								_box(building, Vector3(0.055, 0.42, 0.055), Vector3(wx + rail_x, yy + 0.30, d * 0.5 + 0.86), trim)
			# ground-level shopfronts, awnings and balconies
			_box(building, Vector3(w * 0.72, 2.1, 0.16), Vector3(0, 1.2, d * 0.5 + 0.1), shadow_stone)
			_box(building, Vector3(w * 0.8, 0.24, 1.1), Vector3(0, 2.45, d * 0.5 + 0.55), terracotta)
			# Alternating canvas stripes and carved door jambs make the tabernae legible at street level.
			for stripe in range(8):
				var stripe_x: float = -w * 0.38 + float(stripe) * (w * 0.76 / 7.0)
				_box(building, Vector3(0.12, 0.22, 1.08), Vector3(stripe_x, 2.45, d * 0.5 + 0.56), trim if stripe % 2 == 0 else terracotta)
			for jamb_x in [-w * 0.37, w * 0.37]:
				_box(building, Vector3(0.22, 2.45, 0.24), Vector3(jamb_x, 1.25, d * 0.5 + 0.19), trim)
			_box(building, Vector3(w * 0.76, 0.18, 0.24), Vector3(0, 2.53, d * 0.5 + 0.19), trim)
			for bx in [-w * 0.28, w * 0.28]:
				_box(building, Vector3(0.12, 1.0, 0.12), Vector3(bx, 2.0, d * 0.5 + 0.85), trim)
				_box(building, Vector3(1.7, 0.1, 1.0), Vector3(bx, 1.5, d * 0.5 + 0.85), trim)
				_box(building, Vector3(1.7, 0.10, 0.10), Vector3(bx, 1.95, d * 0.5 + 1.28), shadow_stone)
				for rail_x in [-0.68, -0.34, 0.0, 0.34, 0.68]:
					_box(building, Vector3(0.055, 0.42, 0.055), Vector3(bx + rail_x, 1.76, d * 0.5 + 1.28), trim)
			# roof parapet, terracotta coping and corner quoins
			for corner_x in [-1.0, 1.0]:
				for corner_z in [-1.0, 1.0]:
					_box(building, Vector3(0.38, h, 0.38), Vector3(corner_x * (w * 0.5 - 0.2), h * 0.5, corner_z * (d * 0.5 - 0.2)), trim)
			_box(building, Vector3(w + 0.4, 0.22, 0.42), Vector3(0, h + 0.62, -d * 0.5 + 0.2), terracotta)
			_box(building, Vector3(w + 0.4, 0.22, 0.42), Vector3(0, h + 0.62, d * 0.5 - 0.2), terracotta)

func _make_roman_skyline() -> void:
	# Distant campanili and rooflines frame the monument without competing with it.
	var masonry := _mat(Color("#b89a72"), 0.9)
	var pale_stone := _mat(Color("#d6bc91"), 0.88)
	var roof := _mat(Color("#98452f"), 0.9)
	for side in [-1.0, 1.0]:
		var tower := Node3D.new()
		tower.position = Vector3(side * 43.0, 0, -58.0)
		add_child(tower)
		_box(tower, Vector3(4.2, 17.0, 4.2), Vector3(0, 8.5, 0), masonry)
		_box(tower, Vector3(4.8, 0.65, 4.8), Vector3(0, 17.0, 0), pale_stone)
		_box(tower, Vector3(3.5, 4.2, 3.5), Vector3(0, 19.35, 0), pale_stone)
		for face in [-1.0, 1.0]:
			_box(tower, Vector3(0.12, 1.65, 1.05), Vector3(face * 1.81, 19.6, 0), shadow_stone)
			_box(tower, Vector3(1.05, 1.65, 0.12), Vector3(0, 19.6, face * 1.81), shadow_stone)
		_box(tower, Vector3(4.6, 0.35, 4.6), Vector3(0, 21.6, 0), trim)
		_cylinder(tower, 1.7, 1.0, Vector3(0, 22.2, 0), roof, 12)
		_cylinder(tower, 1.25, 1.2, Vector3(0, 23.2, 0), roof, 12)
		_cylinder(tower, 0.68, 1.2, Vector3(0, 24.25, 0), roof, 10)
		_cylinder(tower, 0.10, 2.2, Vector3(0, 25.8, 0), pale_stone, 8)

func _make_street_furniture() -> void:
	for x in range(-100, 101, 20):
		for z in [-42.0, 42.0]:
			_cylinder(self, 0.16, 3.4, Vector3(x, 1.7, z), shadow_stone, 10)
			_box(self, Vector3(0.85, 0.25, 0.85), Vector3(x, 3.45, z), trim)
			var light := OmniLight3D.new()
			light.position = Vector3(x, 3.4, z)
			light.light_color = Color("#ffbd73")
			light.light_energy = 1.2
			light.omni_range = 8
			add_child(light)
	for i in range(24):
		var a := TAU * float(i) / 24
		var x := cos(a) * 45.0
		var z := sin(a) * 37.0
		_box(self, Vector3(2.4, 0.8, 2.4), Vector3(x, 0.4, z), stone, true)
		_cylinder(self, 0.42, 1.2, Vector3(x, 1.3, z), shadow_stone, 10)
		var crown := _make_tree_crown(Vector3(x, 2.7, z), 1.1, 1.8, _mat(Color("#596c3b")))
		crown.rotation.y = a * 1.7
	# travertine benches, bollards and planter boxes along the main promenade
	for x in range(-36, 37, 12):
		_box(self, Vector3(4.4, 0.35, 1.15), Vector3(x, 0.48, -39.0), shadow_stone, true)
		_box(self, Vector3(4.1, 0.18, 0.92), Vector3(x, 0.73, -39.0), trim, true)
		for dx in [-1.65, 1.65]:
			_box(self, Vector3(0.28, 0.55, 1.0), Vector3(x + dx, 0.28, -39.0), stone, true)
	for x in [-38.0, 38.0]:
		for z in range(-24, 25, 12):
			_box(self, Vector3(0.7, 1.1, 0.7), Vector3(x, 0.55, z), trim, true)
	# archaeological perimeter, low bollards and sculpted travertine curb
	for x in range(-42, 43, 3):
		for z in [-34.0, 34.0]:
			_cylinder(self, 0.22, 0.82, Vector3(x, 0.41, z), trim, 12)
	for z in range(-32, 33, 3):
		for x in [-42.0, 42.0]:
			_cylinder(self, 0.22, 0.82, Vector3(x, 0.41, z), trim, 12)
	# ornamental bronze plaques on approach plinths
	var bronze := _mat(Color("#76532e"), 0.48, 0.62)
	for x in [-24.0, 24.0]:
		_box(self, Vector3(2.0, 1.3, 0.16), Vector3(x, 1.1, -32.8), shadow_stone, true)
		_box(self, Vector3(1.45, 0.78, 0.08), Vector3(x, 1.12, -32.68), bronze)
		for yy in [0.82, 1.42]:
			_box(self, Vector3(1.1, 0.045, 0.035), Vector3(x, yy, -32.61), trim)
	# Roman street signs and district markers, mounted on dark iron posts
	var iron := _mat(Color("#292b2a"), 0.56, 0.38)
	var sign_stone := _mat(Color("#e0c99f"), 0.84)
	for idx in range(6):
		var sx := -60.0 + idx * 24.0
		var sz := -46.0 if idx % 2 == 0 else 46.0
		_cylinder(self, 0.09, 3.2, Vector3(sx, 1.6, sz), iron, 10)
		_box(self, Vector3(3.6, 0.9, 0.12), Vector3(sx, 2.65, sz), sign_stone, true)
		_box(self, Vector3(3.25, 0.06, 0.05), Vector3(sx, 2.35, sz - 0.08), terracotta)
		var sign_text := Label3D.new()
		var destinations := ["COLOSSEO", "FORI IMPERIALI", "CENTRO STORICO", "ROMA ANTICA", "TERME", "TRASTEVERE"]
		sign_text.text = destinations[idx]
		sign_text.position = Vector3(sx, 2.65, sz + 0.10)
		sign_text.font_size = 48
		sign_text.pixel_size = 0.012
		sign_text.modulate = Color("#292b2a")
		sign_text.double_sided = true
		sign_text.no_depth_test = true
		add_child(sign_text)
	# painted zebra crossings and Roman paving insets
	for stripe in range(9):
		_box(self, Vector3(0.7, 0.035, 7.0), Vector3(-3.2 + stripe * 0.8, 0.08, -48.0), trim)
	# square paving seams, kept in shallow relief so the plaza reads at gameplay distance
	for x in range(-38, 39, 4):
		_box(self, Vector3(0.035, 0.012, 58.0), Vector3(x, 0.095, 0.0), _mat(Color("#a88b65")))
	for z in range(-28, 29, 4):
		_box(self, Vector3(78.0, 0.012, 0.035), Vector3(0.0, 0.095, z), _mat(Color("#a88b65")))

func _make_showcase_figures() -> void:
	# Low-poly Roman citizens provide human scale in the architectural showcase.
	var skin := _mat(Color("#b9825d"), 0.82)
	var tunic_a := _mat(Color("#8b3027"), 0.84)
	var tunic_b := _mat(Color("#d3b98c"), 0.9)
	var leather := _mat(Color("#49332b"), 0.92)
	var bronze := _mat(Color("#9b7845"), 0.65, 0.16)
	for idx in range(2):
		var person := Node3D.new()
		person.position = Vector3(11.0 + idx * 5.0, 0.0, 39.5)
		add_child(person)
		var tunic := _box(person, Vector3(0.78, 1.18, 0.42), Vector3(0, 1.18, 0), tunic_a if idx == 0 else tunic_b)
		var head := _cylinder(person, 0.22, 0.34, Vector3(0, 2.02, 0), skin, 12)
		var neck := _cylinder(person, 0.10, 0.18, Vector3(0, 1.79, 0), skin, 8)
		for side in [-1.0, 1.0]:
			var arm := _cylinder(person, 0.105, 0.72, Vector3(side * 0.52, 1.35, 0), skin, 8)
			arm.rotation.z = -side * 0.12
			var bracer := _cylinder(person, 0.12, 0.26, Vector3(side * 0.55, 1.12, 0), bronze, 8)
			bracer.rotation.z = -side * 0.12
			var leg := _cylinder(person, 0.13, 0.82, Vector3(side * 0.22, 0.42, 0), leather, 8)
			var sandal := _box(person, Vector3(0.26, 0.10, 0.40), Vector3(side * 0.22, 0.08, -0.06), leather)
		_box(person, Vector3(0.82, 0.12, 0.46), Vector3(0, 1.72, 0), bronze)
		# Simple crested bronze helmet silhouette.
		_cylinder(person, 0.27, 0.12, Vector3(0, 2.23, 0), bronze, 12)
		_box(person, Vector3(0.06, 0.30, 0.06), Vector3(0, 2.42, 0), tunic_a)
		_box(person, Vector3(0.14, 0.42, 0.12), Vector3(0, 2.22, 0.02), bronze)

func _make_vehicles() -> void:
	# Parked compact cars and scooters add scale and lived-in Roman street character.
	var tire := _mat(Color("#242321"), 0.96)
	var glass := _mat(Color("#263c47"), 0.38, 0.12)
	var chrome := _mat(Color("#c5bda9"), 0.42, 0.35)
	var car_colors := [_mat(Color("#a94332")), _mat(Color("#d4c5a2")), _mat(Color("#536b78"))]
	var car_positions := [Vector3(-59.0, 0, -69.5), Vector3(58.0, 0, 55.5), Vector3(-59.0, 0, -44.5)]
	for i in range(car_positions.size()):
		var car := Node3D.new()
		car.position = car_positions[i]
		add_child(car)
		_box(car, Vector3(3.5, 0.62, 1.65), Vector3(0, 0.66, 0), car_colors[i], true)
		_box(car, Vector3(1.95, 0.72, 1.32), Vector3(-0.18, 1.28, 0), car_colors[i])
		_box(car, Vector3(1.72, 0.48, 0.035), Vector3(-0.18, 1.32, -0.68), glass)
		_box(car, Vector3(1.72, 0.48, 0.035), Vector3(-0.18, 1.32, 0.68), glass)
		_box(car, Vector3(0.12, 0.16, 0.12), Vector3(1.7, 0.62, -0.53), chrome)
		_box(car, Vector3(0.12, 0.16, 0.12), Vector3(1.7, 0.62, 0.53), chrome)
		_box(car, Vector3(0.16, 0.16, 1.5), Vector3(-1.78, 0.53, 0), chrome)
		for wheel_x in [-1.12, 1.12]:
			for wheel_z in [-0.82, 0.82]:
				var wheel := _cylinder(car, 0.36, 0.22, Vector3(wheel_x, 0.38, wheel_z), tire, 12)
				wheel.rotation.z = PI * 0.5
				var hub := _cylinder(car, 0.16, 0.235, Vector3(wheel_x, 0.38, wheel_z), chrome, 10)
				hub.rotation.z = PI * 0.5
	_make_scooter(Vector3(-47.0, 0, -51.0), _mat(Color("#a94332")))
	_make_scooter(Vector3(48.0, 0, 51.0), _mat(Color("#4e5d63")))

func _make_scooter(origin: Vector3, paint: Material) -> void:
	var scooter := Node3D.new()
	scooter.position = origin
	add_child(scooter)
	var tire := _mat(Color("#252422"), 0.96)
	for wheel_z in [-0.48, 0.48]:
		var wheel := _cylinder(scooter, 0.19, 0.12, Vector3(0, 0.22, wheel_z), tire, 12)
		wheel.rotation.x = PI * 0.5
	_box(scooter, Vector3(0.30, 0.12, 0.68), Vector3(0, 0.42, 0.05), paint)
	_cylinder(scooter, 0.055, 0.78, Vector3(0, 0.80, -0.30), paint, 8)
	_box(scooter, Vector3(0.55, 0.055, 0.07), Vector3(0, 1.19, -0.30), paint)
	_box(scooter, Vector3(0.24, 0.10, 0.42), Vector3(0, 0.78, 0.12), _mat(Color("#242321")))

func _make_tree_crown(origin: Vector3, radius: float, height: float, material: Material) -> Node3D:
	var tree := Node3D.new()
	tree.position = origin
	add_child(tree)
	_cylinder(tree, 0.23, 2.2, Vector3(0, -0.3, 0), _mat(Color("#6a432d")), 9)
	var cluster_positions := [
		Vector3(0, 1.05, 0),
		Vector3(radius * 0.48, 1.18, radius * 0.10),
		Vector3(-radius * 0.42, 1.12, -radius * 0.18),
		Vector3(radius * 0.10, 1.30, -radius * 0.45),
		Vector3(-radius * 0.12, 1.26, radius * 0.42)
	]
	for i in range(cluster_positions.size()):
		var canopy := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = radius * (0.68 if i == 0 else 0.46)
		sphere.height = sphere.radius * 2.0
		canopy.mesh = sphere
		canopy.position = cluster_positions[i]
		canopy.scale = Vector3(1.0, height / maxf(radius * 2.0, 0.1), 1.0)
		canopy.material_override = material
		tree.add_child(canopy)
	return tree

func _make_player() -> void:
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.position = Vector3(0, 2.0, 57.0)
	add_child(p)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	p.add_child(collision)
	var pivot := Node3D.new()
	pivot.position.y = 1.55
	p.add_child(pivot)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 78
	camera.position = Vector3(0, 0.15, 0)
	pivot.add_child(camera)
	p.set_script(load("res://player.gd"))

func _make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# unobtrusive mobile touch zones and center reticle
	var reticle := Label.new()
	reticle.text = "+"
	reticle.position = Vector2(0, 0)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.add_theme_font_size_override("font_size", 22)
	reticle.add_theme_color_override("font_color", Color("#fff0d3"))
	layer.add_child(reticle)
	var move_hint := Label.new()
	move_hint.text = "MOVE"
	move_hint.position = Vector2(24, 150)
	move_hint.add_theme_font_size_override("font_size", 12)
	move_hint.add_theme_color_override("font_color", Color("#e6d2b0"))
	layer.add_child(move_hint)
	var look_hint := Label.new()
	look_hint.text = "LOOK"
	look_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	look_hint.position = Vector2(-90, 120)
	look_hint.add_theme_font_size_override("font_size", 12)
	look_hint.add_theme_color_override("font_color", Color("#e6d2b0"))
	layer.add_child(look_hint)
	var label := Label.new()
	label.text = "ROMA BATTLE ROYALE  •  COLOSSEO DISTRICT\nWASD / Frecce: movimento  •  SHIFT: corsa  •  Mouse: visuale\nTouch: sinistra muovi • destra ruota • RUN/JUMP in basso a destra"
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#fff0d3"))
	layer.add_child(label)
	if OS.has_feature("mobile"):
		var screen_size := get_viewport().get_visible_rect().size
		var ring_texture := _touch_ring_texture()
		var move_ring := TextureRect.new()
		move_ring.texture = ring_texture
		move_ring.position = Vector2(28, screen_size.y - 154)
		move_ring.size = Vector2(124, 124)
		move_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		move_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(move_ring)
		var look_ring := TextureRect.new()
		look_ring.texture = ring_texture
		look_ring.position = Vector2(screen_size.x - 152, screen_size.y - 390)
		look_ring.size = Vector2(124, 124)
		look_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		look_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(look_ring)
		for action in ["RUN", "JUMP"]:
			var action_ring := TextureRect.new()
			action_ring.texture = ring_texture
			action_ring.size = Vector2(86, 86)
			action_ring.position = Vector2(screen_size.x - 116, screen_size.y - (130 if action == "JUMP" else 250))
			action_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			action_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer.add_child(action_ring)
			var action_label := Label.new()
			action_label.text = action
			action_label.position = action_ring.position
			action_label.size = action_ring.size
			action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			action_label.add_theme_font_size_override("font_size", 12)
			action_label.add_theme_color_override("font_color", Color("#fff0d3"))
			action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer.add_child(action_label)

func _touch_ring_texture() -> Texture2D:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var distance := Vector2(x - 63.5, y - 63.5).length()
			if distance >= 51.0 and distance <= 58.0:
				img.set_pixel(x, y, Color(0.95, 0.82, 0.61, 0.72))
			elif distance <= 18.0:
				img.set_pixel(x, y, Color(0.95, 0.82, 0.61, 0.22))
	return ImageTexture.create_from_image(img)
