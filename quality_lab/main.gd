extends Node3D

# Isolated Colosseo quality lab. Procedural architectural study, not a replacement for the main map.
const SEGMENTS := 96
const FLOORS := 4
const RX := 32.0
const RZ := 24.0
var stone: StandardMaterial3D
var trim: StandardMaterial3D
var shadow_stone: StandardMaterial3D
var terracotta: StandardMaterial3D
var asphalt: StandardMaterial3D

func _ready() -> void:
	_make_materials()
	_make_environment()
	_make_ground()
	_make_colosseum()
	_make_neighbourhood()
	_make_street_furniture()
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

func _procedural_stone_texture(base: Color, seed_value: int) -> Texture2D:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for y in range(256):
		for x in range(256):
			var cell_x := x % 64
			var cell_y := y % 32
			var mortar := cell_x < 2 or cell_y < 2
			var variation := rng.randf_range(-0.055, 0.055)
			var c := base.darkened(0.34) if mortar else Color(
				clampf(base.r + variation, 0.0, 1.0),
				clampf(base.g + variation, 0.0, 1.0),
				clampf(base.b + variation, 0.0, 1.0), 1.0)
			img.set_pixel(x, y, c)
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
	var n := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	n.mesh = m
	n.position = pos
	n.material_override = material
	parent.add_child(n)
	if bevel:
		var body := StaticBody3D.new()
		body.position = pos
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = size
		shape.shape = b
		body.add_child(shape)
		parent.add_child(body)
	return n

func _cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material, radial := 12) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = radial
	m.rings = 1
	n.mesh = m
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
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, -28, 0)
	sun.light_color = Color("#ffd4a0")
	sun.light_energy = 1.65
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

func _make_colosseum() -> void:
	var col := Node3D.new()
	col.name = "COLOSSEO_ARCHITECTURE"
	add_child(col)
	# elliptical stepped podium
	for layer in range(4):
		_elliptical_ring(col, RX + 2.2 - layer * 0.48, RZ + 2.2 - layer * 0.48, 0.55, -0.1 + layer * 0.48, trim if layer % 2 == 0 else stone)
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
			if i % 3 == 0:
				_cylinder(col, 0.24, 4.1, p + radial * 0.78, trim, 12)
				_cylinder(col, 0.38, 0.22, p + radial * 0.78 + Vector3(0, 2.08, 0), stone, 12)
				_cylinder(col, 0.36, 0.20, p + radial * 0.78 - Vector3(0, 2.08, 0), stone, 12)
			pier.look_at(p + tangent, Vector3.UP)
			_box(col, Vector3(1.25, 0.35, 1.65), p + Vector3(0, 2.2, 0), stone, true)
			_box(col, Vector3(1.18, 0.28, 1.58), p + Vector3(0, -2.18, 0), stone, true)
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
		_elliptical_ring(col, rx + 0.35, rz + 0.35, 0.45, y + 4.65, trim)
	# ceremonial SPQR standards and monumental approach stairs
	var banner_mat := _mat(Color("#7e2524"))
	var gold_mat := _mat(Color("#d7ad62"), 0.72, 0.08)
	for bx in [-18.0, -6.0, 6.0, 18.0]:
		_box(col, Vector3(0.18, 5.2, 0.18), Vector3(bx, 14.4, -25.2), gold_mat)
		_box(col, Vector3(1.75, 3.8, 0.14), Vector3(bx + 0.95, 13.3, -25.15), banner_mat)
		_box(col, Vector3(1.45, 0.12, 0.17), Vector3(bx + 0.95, 15.1, -25.04), gold_mat)
		_box(col, Vector3(1.25, 0.12, 0.17), Vector3(bx + 0.95, 11.45, -25.04), gold_mat)
	for step in range(8):
		_box(col, Vector3(18.0, 0.28, 1.1), Vector3(0, 0.14 + step * 0.28, -35.0 + step * 1.1), trim, true)
	# arena, inner walls, tiered seating and hypogeum corridors
	_elliptical_ring(col, 19.5, 13.7, 0.35, 1.25, shadow_stone)
	_elliptical_ring(col, 18.4, 12.8, 0.3, 1.45, trim)
	for row in range(14):
		_elliptical_ring(col, 21.0 + row * 0.72, 14.6 + row * 0.52, 0.34, 1.55 + row * 0.31, trim if row % 3 else stone)
	# arena floor and hypogeum lanes
	_box(col, Vector3(29, 0.22, 19), Vector3(0, 1.55, 0), _mat(Color("#b99a70")))
	for x in range(-12, 13, 4):
		_box(col, Vector3(0.24, 0.08, 15), Vector3(x, 1.69, 0), shadow_stone)
	for x in range(-8, 9, 4):
		_box(col, Vector3(2.2, 1.0, 12), Vector3(x, 0.55, 0), shadow_stone)
	# monumental entrance portals, travertine stairs and sculptural plinths
	for side in [-1.0, 1.0]:
		for x in [-8.0, -4.0, 0.0, 4.0, 8.0]:
			_box(col, Vector3(2.6, 0.22, 2.0), Vector3(x, 0.15, side * 26.0), trim)
			_box(col, Vector3(2.1, 0.22, 1.7), Vector3(x, 0.36, side * 26.0), stone)
		for x in [-14.0, 14.0]:
			_box(col, Vector3(1.5, 3.0, 1.5), Vector3(x, 1.7, side * 25.4), trim)
			_box(col, Vector3(2.1, 0.28, 2.1), Vector3(x, 3.25, side * 25.4), stone)

func _elliptical_ring(parent: Node3D, rx: float, rz: float, thickness: float, y: float, material: Material) -> void:
	var count := 128
	for i in range(count):
		var a := TAU * float(i) / count
		var b := TAU * float(i + 1) / count
		var p := Vector3(cos(a) * rx, y, sin(a) * rz)
		var q := Vector3(cos(b) * rx, y, sin(b) * rz)
		var mid := (p + q) * 0.5
		var length := p.distance_to(q) + 0.08
		var n := _box(parent, Vector3(length, thickness, 0.65), mid, material)
		n.rotation.y = -atan2(q.z - p.z, q.x - p.x)

func _make_neighbourhood() -> void:
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
			var floors := int(h / 2.8)
			for f in range(floors):
				var yy := 1.5 + f * 2.8
				_box(building, Vector3(w + 0.12, 0.16, d + 0.12), Vector3(0, yy, 0), trim)
				for side in [-1.0, 1.0]:
					for win in range(max(2, int(w / 2.7))):
						var wx := -w * 0.5 + 1.5 + win * (w - 3.0) / max(1, int(w / 2.7) - 1)
						_box(building, Vector3(0.82, 1.25, 0.12), Vector3(wx, yy + 0.6, side * (d * 0.5 + 0.08)), shadow_stone)
						_box(building, Vector3(1.04, 0.12, 0.18), Vector3(wx, yy + 1.28, side * (d * 0.5 + 0.12)), trim)
			# ground-level shopfronts, awnings and balconies
			_box(building, Vector3(w * 0.72, 2.1, 0.16), Vector3(0, 1.2, d * 0.5 + 0.1), shadow_stone)
			_box(building, Vector3(w * 0.8, 0.24, 1.1), Vector3(0, 2.45, d * 0.5 + 0.55), terracotta)
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
		_box(self, Vector3(2.4, 0.8, 2.4), Vector3(x, 0.4, z), stone)
		_cylinder(self, 0.42, 1.2, Vector3(x, 1.3, z), shadow_stone, 10)
		var crown := _cylinder(self, 1.1, 1.8, Vector3(x, 2.7, z), _mat(Color("#596c3b")), 10)
		crown.scale = Vector3(1.0, 1.15, 0.85)

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
	var label := Label.new()
	label.text = "ROMA BATTLE ROYALE  •  COLOSSEO DISTRICT\nWASD / Frecce: movimento  •  SHIFT: corsa  •  Mouse: visuale\nTouch: joystick sinistro per muoverti, trascina a destra per ruotare"
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("#fff0d3"))
	layer.add_child(label)
