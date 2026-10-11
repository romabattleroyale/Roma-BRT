@tool
class_name MapMaterials
extends RefCounted
## Builds the terrain / water / foliage materials and wires the CC0 texture
## sets into them. Everything degrades gracefully: with no textures on disk
## the shaders fall back to their tint colours and the map still reads.

const TEX_DIR := "res://addons/mapgen/assets/textures/"
const LAYERS := ["ground", "cliff", "shore", "snow"]

static var _needle_albedo: ImageTexture
static var _needle_opacity: ImageTexture
static var _cluster_albedo: ImageTexture
static var _cluster_opacity: ImageTexture

## Near-neutral multipliers used when a real PBR albedo is present.
const TINT_WITH_TEXTURE := {
	"ground": Color(0.92, 1.02, 0.80),
	"cliff": Color(1.02, 1.00, 0.96),
	"shore": Color(1.06, 1.00, 0.90),
	"snow": Color(1.00, 1.01, 1.06),
}

## Full colours used when the texture set has not been downloaded.
const TINT_FALLBACK := {
	"ground": Color(0.31, 0.36, 0.19),
	"cliff": Color(0.42, 0.40, 0.37),
	"shore": Color(0.62, 0.55, 0.44),
	"snow": Color(0.92, 0.94, 0.99),
}

static var _flat_normal: ImageTexture


## 1x1 flat tangent-space normal, used wherever a real normal map is missing.
static func flat_normal() -> ImageTexture:
	if _flat_normal == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
		img.set_pixel(0, 0, Color(0.5, 0.5, 1.0))
		_flat_normal = ImageTexture.create_from_image(img)
	return _flat_normal


## Loads a texture whether or not the project has imported it yet. The direct
## Image path matters for headless runs and for the first launch straight after
## the asset fetcher has downloaded the files.
##
## Colour space is deliberately left alone in both paths: the shader's
## source_color / hint_normal hints tell the renderer how to decode each
## sampler, so converting here as well would double-apply the transfer curve.
static func load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			return res
	var abs := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs):
		return null
	var img := Image.new()
	if img.load(abs) != OK:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _layer_texture(layer: String, kind: String) -> Texture2D:
	for ext in [".jpg", ".png", ".webp"]:
		var t := load_texture(TEX_DIR + layer + "_" + kind + ext)
		if t != null:
			return t
	return null


static func noise_image_texture(p_seed: int, period: float, octaves: int, size: int) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = p_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.0 / maxf(period, 1.0)
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	var img := n.get_seamless_image(size, size, false, false, 0.15, true)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func build_terrain_material(s: MapGenSettings, hf: MapHeightfield) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://addons/mapgen/shaders/terrain.gdshader")

	var flat := flat_normal()
	var found := 0
	for layer in LAYERS:
		var albedo := _layer_texture(layer, "color")
		var normal := _layer_texture(layer, "normal")
		var rough := _layer_texture(layer, "rough")
		if albedo:
			mat.set_shader_parameter(layer + "_albedo", albedo)
			# The texture already carries the colour. The tint is only a gentle
			# art-direction nudge here -- multiplying a photographic albedo by a
			# saturated colour is what turns terrain into dark mud.
			mat.set_shader_parameter(layer + "_tint", TINT_WITH_TEXTURE[layer])
			found += 1
		else:
			# No texture: the tint has to carry the whole layer colour.
			mat.set_shader_parameter(layer + "_tint", TINT_FALLBACK[layer])
		mat.set_shader_parameter(layer + "_normal", normal if normal else flat)
		if rough:
			mat.set_shader_parameter(layer + "_rough", rough)

	# Tiling is expressed in the shader as "UV units per world metre".
	mat.set_shader_parameter("ground_tiling", 0.13)
	mat.set_shader_parameter("cliff_tiling", 0.055)
	mat.set_shader_parameter("shore_tiling", 0.18)
	mat.set_shader_parameter("snow_tiling", 0.12)

	mat.set_shader_parameter("blend_noise", noise_image_texture(s.seed + 501, 90.0, 4, 512))
	mat.set_shader_parameter("macro_noise", noise_image_texture(s.seed + 907, 700.0, 4, 512))
	mat.set_shader_parameter("macro_tiling", 0.0012)
	mat.set_shader_parameter("macro_strength", 0.35)

	mat.set_shader_parameter("terrain_min_y", hf.min_h)
	mat.set_shader_parameter("terrain_max_y", hf.max_h)
	mat.set_shader_parameter("water_level", hf.water_level)
	mat.set_shader_parameter("shore_width", s.shore_width)

	mat.set_shader_parameter("snow_enabled", s.snow_enabled)
	mat.set_shader_parameter("snow_line", s.snow_line)
	mat.set_shader_parameter("snow_blend", s.snow_blend)
	mat.set_shader_parameter("snow_max_slope", s.snow_max_slope)
	mat.set_shader_parameter("snow_noise_amount", s.snow_noise)

	mat.set_shader_parameter("strata_strength", s.canyon_terrace_strength if s.canyon_enabled else 0.0)
	mat.set_shader_parameter("strata_scale", maxf(float(s.canyon_terraces), 1.0) / maxf(s.height_scale, 1.0) * 2.0)

	# Without any texture set on disk, lean harder on tints and macro noise so
	# the terrain still has variation instead of reading as flat gouraud.
	if found == 0:
		mat.set_shader_parameter("macro_strength", 0.55)
		mat.set_shader_parameter("normal_strength", 0.0)
	return mat


static func build_water_material(s: MapGenSettings) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://addons/mapgen/shaders/water.gdshader")
	mat.set_shader_parameter("shallow_color", s.water_color_shallow)
	mat.set_shader_parameter("deep_color", s.water_color_deep)
	mat.set_shader_parameter("wave_noise", noise_image_texture(s.seed + 313, 30.0, 3, 256))
	mat.set_shader_parameter("wave_height", s.wave_height)
	mat.set_shader_parameter("depth_fade", maxf(s.height_scale * 0.05, 3.0))
	mat.set_shader_parameter("foam_width", 0.35)
	return mat


## Falling water. Shares the lake's palette so a fall does not change colour
## when it lands in one, but pulled towards white: aerated water is pale, and a
## waterfall the same shade as the lake it feeds reads as a wet stripe.
static func build_waterfall_material(s: MapGenSettings) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://addons/mapgen/shaders/waterfall.gdshader")
	mat.set_shader_parameter("water_color",
			s.water_color_shallow.lerp(Color(0.88, 0.94, 0.96), 0.55))
	mat.set_shader_parameter("flow_noise", noise_image_texture(s.seed + 617, 26.0, 4, 256))
	mat.set_shader_parameter("flow_speed", s.waterfall_flow_speed)
	return mat


## Ground flora: grass, ferns, reeds, flowers. Colour lives in uniforms rather
## than in the mesh, so one flower mesh covers a whole meadow of shades.
static func build_flora_material(s: MapGenSettings, hf: MapHeightfield,
		dark: Color, light: Color, bend_height: float, wind_scale: float = 1.0,
		fade_end: float = 0.0, petal_a: Color = Color.WHITE,
		petal_b: Color = Color.WHITE) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://addons/mapgen/shaders/flora.gdshader")
	mat.set_shader_parameter("foliage_dark", dark)
	mat.set_shader_parameter("foliage_light", light)
	mat.set_shader_parameter("petal_a", petal_a)
	mat.set_shader_parameter("petal_b", petal_b)
	mat.set_shader_parameter("bend_height", bend_height)
	mat.set_shader_parameter("wind_strength", s.wind_strength * wind_scale)
	mat.set_shader_parameter("fade_start", fade_end * 0.65)
	mat.set_shader_parameter("fade_end", fade_end)
	_apply_snow(mat, s, hf)
	return mat


# ---------------------------------------------------------------------------
# rock
# ---------------------------------------------------------------------------

## Rock surfacing: triplanar stone with a moss overlay on upward faces and a
## soil blend at the buried base. Falls back to flat tints with no textures.
static func build_rock_material(s: MapGenSettings, hf: MapHeightfield,
		tiling: float = 0.85, moss: float = 0.32) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://addons/mapgen/shaders/rock.gdshader")
	var flat := flat_normal()

	var albedo := _layer_texture("rock", "color")
	if albedo:
		mat.set_shader_parameter("rock_albedo", albedo)
		# Rock026 is a light limestone-ish stone. Straight it reads as chalk in
		# full sun, so bring it down to a mid grey granite.
		mat.set_shader_parameter("rock_tint", Color(0.80, 0.79, 0.76))
	else:
		mat.set_shader_parameter("rock_tint", Color(0.46, 0.45, 0.43))
	mat.set_shader_parameter("rock_normal", _layer_texture("rock", "normal")
			if _layer_texture("rock", "normal") else flat)
	var rr := _layer_texture("rock", "rough")
	if rr:
		mat.set_shader_parameter("rock_rough", rr)

	var moss_tex := _layer_texture("moss", "color")
	if moss_tex:
		mat.set_shader_parameter("moss_albedo", moss_tex)
		mat.set_shader_parameter("moss_tint", Color(1.20, 1.30, 0.95))
	else:
		# No moss set on disk: tint instead of texture, and back it off so a
		# flat green wash does not sit on top of every rock.
		mat.set_shader_parameter("moss_tint", Color(0.24, 0.32, 0.16))
		moss *= 0.6
	mat.set_shader_parameter("moss_normal", _layer_texture("moss", "normal")
			if _layer_texture("moss", "normal") else flat)

	mat.set_shader_parameter("rock_tiling", tiling)
	mat.set_shader_parameter("moss_tiling", tiling * 0.65)
	mat.set_shader_parameter("moss_strength", moss)
	mat.set_shader_parameter("macro_noise", noise_image_texture(s.seed + 733, 40.0, 4, 256))
	mat.set_shader_parameter("soil_color", Color(0.20, 0.18, 0.13))
	_apply_snow(mat, s, hf)
	return mat


# ---------------------------------------------------------------------------
# trees
# ---------------------------------------------------------------------------

static func build_bark_material(s: MapGenSettings, hf: MapHeightfield,
		kind: String, wind_scale: float = 1.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://addons/mapgen/shaders/bark.gdshader")
	var flat := flat_normal()
	var layer := "bark_" + kind
	var albedo := _layer_texture(layer, "color")
	if albedo:
		mat.set_shader_parameter("bark_albedo", albedo)
		# The photo already carries the colour; the tint is a nudge, not a paint.
		mat.set_shader_parameter("bark_tint", Color(0.98, 0.95, 0.92))
	else:
		mat.set_shader_parameter("bark_tint", Color(0.34, 0.26, 0.19))
	mat.set_shader_parameter("bark_normal", _layer_texture(layer, "normal")
			if _layer_texture(layer, "normal") else flat)
	var rough := _layer_texture(layer, "rough")
	if rough:
		mat.set_shader_parameter("bark_rough", rough)
	_apply_wind(mat, s, wind_scale, 0.0)
	_apply_snow(mat, s, hf)
	return mat


static func build_leaf_material(s: MapGenSettings, hf: MapHeightfield,
		young: Color, mature: Color, fade_end: float, wind_scale: float = 1.0,
		flutter: float = 0.035) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://addons/mapgen/shaders/leaf.gdshader")
	mat.set_shader_parameter("leaf_albedo", leaf_cluster_albedo())
	mat.set_shader_parameter("leaf_opacity", leaf_cluster_opacity())
	# The cluster atlas scatters leaves at every angle, so a single-leaf normal
	# map would be wrong for most of them. Flat is the honest choice; the canopy
	# normal in the mesh is doing the shaping anyway.
	mat.set_shader_parameter("leaf_normal", flat_normal())
	mat.set_shader_parameter("tint_young", young)
	mat.set_shader_parameter("tint_mature", mature)
	mat.set_shader_parameter("fade_start", fade_end * 0.72)
	mat.set_shader_parameter("fade_end", fade_end)
	_apply_wind(mat, s, wind_scale, flutter)
	_apply_snow(mat, s, hf)
	return mat


static func build_needle_material(s: MapGenSettings, hf: MapHeightfield,
		young: Color, mature: Color, fade_end: float, wind_scale: float = 1.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://addons/mapgen/shaders/leaf.gdshader")
	mat.set_shader_parameter("leaf_albedo", needle_albedo())
	mat.set_shader_parameter("leaf_opacity", needle_opacity())
	mat.set_shader_parameter("leaf_normal", flat_normal())
	mat.set_shader_parameter("tint_young", young)
	mat.set_shader_parameter("tint_mature", mature)
	mat.set_shader_parameter("alpha_cut", 0.35)
	mat.set_shader_parameter("roughness_value", 0.78)
	mat.set_shader_parameter("translucency", 0.32)
	mat.set_shader_parameter("fade_start", fade_end * 0.72)
	mat.set_shader_parameter("fade_end", fade_end)
	_apply_wind(mat, s, wind_scale, 0.012)
	_apply_snow(mat, s, hf)
	return mat


static func _apply_wind(mat: ShaderMaterial, s: MapGenSettings, scale: float,
		flutter: float) -> void:
	mat.set_shader_parameter("wind_strength", s.wind_strength * scale)
	mat.set_shader_parameter("wind_speed", 1.0)
	mat.set_shader_parameter("wind_flutter", flutter * s.wind_strength)


static func _apply_snow(mat: ShaderMaterial, s: MapGenSettings, hf: MapHeightfield) -> void:
	mat.set_shader_parameter("snow_enabled", s.snow_enabled)
	if s.snow_enabled:
		var relief: float = maxf(hf.max_h - hf.min_h, 1.0)
		mat.set_shader_parameter("snow_line_y", hf.min_h + s.snow_line * relief)
		mat.set_shader_parameter("snow_blend_y", s.snow_blend * relief)
	else:
		mat.set_shader_parameter("snow_line_y", 1e9)


# ---------------------------------------------------------------------------
# procedural needle spray
# ---------------------------------------------------------------------------

static func needle_albedo() -> ImageTexture:
	if _needle_albedo == null:
		_build_needle_textures()
	return _needle_albedo


static func needle_opacity() -> ImageTexture:
	if _needle_opacity == null:
		_build_needle_textures()
	return _needle_opacity


## There is no CC0 conifer-needle atlas worth using, so draw one: a central
## shoot with needles fanning off it, which is what a fir spray actually looks
## like. Rasterised analytically so rotation is free -- Godot's Image has no
## arbitrary-angle rotate.
static func _build_needle_textures() -> void:
	var size := 256
	# Draw at 2x and downsample: free antialiasing, and thin needles stop
	# breaking up into dotted lines.
	var ss := size * 2
	var img := Image.create(ss, ss, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260830

	var base := Vector2(ss * 0.5, ss * 0.98)
	var apex := Vector2(ss * 0.5, ss * 0.03)
	var dark := Color(0.17, 0.31, 0.13)
	var light := Color(0.52, 0.68, 0.31)

	# Woody shoot up the middle.
	_draw_taper(img, base, apex, ss * 0.011, ss * 0.003,
			Color(0.24, 0.18, 0.10), Color(0.31, 0.25, 0.14))

	var count := 360
	for i in count:
		var t := float(i) / float(count - 1)
		var along: float = pow(t, 0.8)
		var origin := base.lerp(apex, along)
		var side := 1.0 if (i % 2 == 0) else -1.0
		# A fir branchlet is a broad flat spray, not a narrow feather.
		var angle: float = deg_to_rad(rng.randf_range(38.0, 72.0)) * side
		var length: float = ss * lerpf(0.40, 0.10, along) * rng.randf_range(0.70, 1.20)
		var dir := Vector2(sin(angle), -cos(angle))
		var tip := origin + dir * length
		var shade: float = rng.randf_range(0.0, 1.0)
		_draw_taper(img, origin, tip, ss * 0.0068, ss * 0.0018,
				dark.lerp(light, shade * 0.45), dark.lerp(light, 0.55 + shade * 0.45))

	img.resize(size, size, Image.INTERPOLATE_BILINEAR)
	# Anything the alpha mask leaves opaque at the texture border becomes a hard
	# straight line along the card's edge -- instantly readable as a quad, and
	# very obvious on a branch the camera is standing next to.
	_fade_border(img, 0.06)
	img.generate_mipmaps()
	_needle_albedo = ImageTexture.create_from_image(img)

	# Opacity as its own single-channel texture, matching how the ambientCG leaf
	# sets are laid out so the shader has one code path.
	var mask := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var a := img.get_pixel(x, y).a
			mask.set_pixel(x, y, Color(a, a, a))
	mask.generate_mipmaps()
	_needle_opacity = ImageTexture.create_from_image(mask)


## Ramps alpha to zero across the outer `margin` fraction of an image.
static func _fade_border(img: Image, margin: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var mx: float = maxf(float(w) * margin, 1.0)
	var my: float = maxf(float(h) * margin, 1.0)
	for y in h:
		var fy: float = clampf(minf(float(y), float(h - 1 - y)) / my, 0.0, 1.0)
		for x in w:
			var fx: float = clampf(minf(float(x), float(w - 1 - x)) / mx, 0.0, 1.0)
			var f: float = minf(fx, fy)
			if f >= 1.0:
				continue
			var c := img.get_pixel(x, y)
			c.a *= f
			img.set_pixel(x, y, c)


## Same idea, applied to each cell of a packed atlas working on raw bytes.
static func _fade_cell_borders(buf: PackedByteArray, n: int, cells: int, margin: float) -> void:
	var cell := n / cells
	var m: float = maxf(float(cell) * margin, 1.0)
	for y in n:
		var ly := y % cell
		var fy: float = clampf(minf(float(ly), float(cell - 1 - ly)) / m, 0.0, 1.0)
		for x in n:
			var lx := x % cell
			var fx: float = clampf(minf(float(lx), float(cell - 1 - lx)) / m, 0.0, 1.0)
			var f: float = minf(fx, fy)
			if f >= 1.0:
				continue
			var i := (y * n + x) * 4 + 3
			buf[i] = int(float(buf[i]) * f)


static func _draw_taper(img: Image, a: Vector2, b: Vector2, w0: float, w1: float,
		c0: Color, c1: Color) -> void:
	var size := img.get_width()
	var delta := b - a
	var length: float = maxf(delta.length(), 1.0)
	var dir := delta / length
	var perp := Vector2(-dir.y, dir.x)
	var steps: int = int(ceil(length))

	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := a + delta * t
		var w: float = maxf(lerpf(w0, w1, t), 0.6)
		var col := c0.lerp(c1, t)
		var span: int = int(ceil(w)) + 1
		for o in range(-span, span + 1):
			var q := p + perp * float(o)
			var px := int(round(q.x))
			var py := int(round(q.y))
			if px < 0 or py < 0 or px >= size or py >= size:
				continue
			# Soft edge so needles do not alias into dotted lines.
			var alpha: float = clampf(1.0 - (absf(float(o)) - w + 1.0), 0.0, 1.0)
			if alpha <= 0.0:
				continue
			var prev := img.get_pixel(px, py)
			if alpha > prev.a:
				img.set_pixel(px, py, Color(col.r, col.g, col.b, alpha))


# ---------------------------------------------------------------------------
# leaf cluster atlas
# ---------------------------------------------------------------------------

## A crown cannot be filled with single-leaf cards. A 10 m tree carries tens of
## thousands of leaves; at one quad each that is a six-figure triangle count per
## tree. Every real-time tree since the early 2000s solves this the same way:
## one quad shows a whole bunch of leaves, cut out together.
##
## There is no CC0 cluster atlas worth using, so this composites one from the
## single photoscanned leaf -- scattered, rotated and scaled into a 2x2 grid of
## four distinct bunches. Built once per session and held in a static.
static func leaf_cluster_albedo() -> ImageTexture:
	if _cluster_albedo == null:
		_build_leaf_clusters()
	return _cluster_albedo


static func leaf_cluster_opacity() -> ImageTexture:
	if _cluster_opacity == null:
		_build_leaf_clusters()
	return _cluster_opacity


## Sub-rects of the source texture, which holds two leaves side by side --
## a front and a back. Using both gives real leaf undersides for free.
const SRC_LEAVES := [
	Rect2(0.045, 0.10, 0.445, 0.77),
	Rect2(0.505, 0.10, 0.455, 0.77),
]
const CLUSTER_SIZE := 512      ## whole atlas, 2x2 cells
const CLUSTER_CELLS := 2
const LEAVES_PER_CLUSTER := 22


static func _build_leaf_clusters() -> void:
	var col := _layer_texture("leaf", "color")
	var opa := _layer_texture("leaf", "opacity")
	if col == null or opa == null:
		# No source leaf on disk: fall back to the needle card so the tree at
		# least has cut-out foliage rather than solid rectangles.
		_cluster_albedo = needle_albedo()
		_cluster_opacity = needle_opacity()
		return

	# Pre-scale the source so stamping is roughly 1:1. Sampling is
	# nearest-neighbour for speed, and nearest-neighbour *minification* of a
	# photographic leaf aliases its veins and highlights into isolated bright
	# pixels -- which show up in the canopy as a fine speckle that survives
	# mipmapping. Matching the sizes removes the cause instead of blurring it.
	var src := col.get_image().duplicate() as Image
	var sop := opa.get_image().duplicate() as Image
	var src_px := int(float(CLUSTER_SIZE / CLUSTER_CELLS) * 0.55 / SRC_LEAVES[0].size.y)
	src.resize(src_px, src_px, Image.INTERPOLATE_LANCZOS)
	sop.resize(src_px, src_px, Image.INTERPOLATE_LANCZOS)
	src.convert(Image.FORMAT_RGBA8)
	sop.convert(Image.FORMAT_RGBA8)
	var sw := src.get_width()
	var sh := src.get_height()
	var sdata := src.get_data()
	var odata := sop.get_data()

	var n := CLUSTER_SIZE
	var out := PackedByteArray()
	out.resize(n * n * 4)
	out.fill(0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var cell := n / CLUSTER_CELLS

	for cy in CLUSTER_CELLS:
		for cx in CLUSTER_CELLS:
			var ox := cx * cell
			var oy := cy * cell
			for i in LEAVES_PER_CLUSTER:
				var rect: Rect2 = SRC_LEAVES[rng.randi() % SRC_LEAVES.size()]
				var h: float = float(cell) * rng.randf_range(0.34, 0.56)
				var w: float = h * (rect.size.x / rect.size.y)
				var angle := rng.randf_range(0.0, TAU)
				# Pull toward the middle of the cell so the bunch has a centre
				# and does not clip its own edges into hard straight cuts.
				var centre := Vector2(
					float(ox) + float(cell) * 0.5 + rng.randf_range(-0.30, 0.30) * float(cell),
					float(oy) + float(cell) * 0.5 + rng.randf_range(-0.30, 0.30) * float(cell))
				var shade: float = rng.randf_range(0.72, 1.12)
				_stamp_leaf(out, n, sdata, odata, sw, sh, rect, centre, w, h, angle, shade)

	_clean_mask(out, n)
	# Per cell, not per atlas: a leaf that runs off the edge of its own cell
	# would otherwise be sliced by the UV rect and show a straight cut.
	_fade_cell_borders(out, n, CLUSTER_CELLS, 0.06)

	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, out)
	img.generate_mipmaps()
	_cluster_albedo = ImageTexture.create_from_image(img)

	var mask := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var a := float(out[(y * n + x) * 4 + 3]) / 255.0
			mask.set_pixel(x, y, Color(a, a, a))
	mask.generate_mipmaps()
	_cluster_opacity = ImageTexture.create_from_image(mask)


## Conditions the alpha mask for alpha testing.
##
## Two problems, both of which show up in a canopy as a fine sparkle rather than
## as anything obviously wrong with the texture:
##
##   Isolated texels that clear the threshold with no opaque neighbours survive
##   as single lit pixels floating in front of the leaves behind them.
##
##   Texels sitting right at the cut flip in and out as the mip chain averages
##   them, so pushing alpha away from the threshold in both directions makes the
##   cut stable across mip levels.
static func _clean_mask(buf: PackedByteArray, n: int) -> void:
	var alpha := PackedFloat32Array()
	alpha.resize(n * n)
	for i in n * n:
		alpha[i] = float(buf[i * 4 + 3]) / 255.0

	for y in range(1, n - 1):
		for x in range(1, n - 1):
			var i := y * n + x
			if alpha[i] < 0.35:
				continue
			var neighbours := 0
			if alpha[i - 1] >= 0.35: neighbours += 1
			if alpha[i + 1] >= 0.35: neighbours += 1
			if alpha[i - n] >= 0.35: neighbours += 1
			if alpha[i + n] >= 0.35: neighbours += 1
			if neighbours <= 1:
				buf[i * 4 + 3] = 0

	for i in n * n:
		var a := float(buf[i * 4 + 3]) / 255.0
		buf[i * 4 + 3] = int(clampf(smoothstep(0.28, 0.72, a) * 255.0, 0.0, 255.0))


## Alpha-composites one rotated, scaled leaf into the output buffer. Iterates
## the leaf's own bounding box rather than the whole atlas, and works on raw
## bytes because get_pixel/set_pixel per sample is far too slow here.
static func _stamp_leaf(out: PackedByteArray, n: int, sdata: PackedByteArray,
		odata: PackedByteArray, sw: int, sh: int, rect: Rect2, centre: Vector2,
		w: float, h: float, angle: float, shade: float) -> void:
	var ca := cos(angle)
	var sa := sin(angle)
	var reach: float = (absf(w * ca) + absf(h * sa) + absf(w * sa) + absf(h * ca)) * 0.5
	var x0: int = maxi(int(centre.x - reach) - 1, 0)
	var x1: int = mini(int(centre.x + reach) + 1, n - 1)
	var y0: int = maxi(int(centre.y - reach) - 1, 0)
	var y1: int = mini(int(centre.y + reach) + 1, n - 1)

	var sx0: int = int(rect.position.x * float(sw))
	var sy0: int = int(rect.position.y * float(sh))
	var sw_px: float = rect.size.x * float(sw)
	var sh_px: float = rect.size.y * float(sh)

	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) - centre.x
			var dy := float(y) - centre.y
			# Inverse-rotate into the leaf's own frame.
			var lx := dx * ca + dy * sa
			var ly := -dx * sa + dy * ca
			var u := lx / w + 0.5
			var v := ly / h + 0.5
			if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
				continue
			var si: int = ((sy0 + int(v * sh_px)) * sw + (sx0 + int(u * sw_px))) * 4
			if si < 0 or si + 3 >= sdata.size():
				continue
			var a := float(odata[si]) / 255.0
			if a < 0.02:
				continue
			var di := (y * n + x) * 4
			# Straight-alpha "over", not premultiplied. Compositing RGB against
			# the empty black buffer would darken every leaf edge, and those
			# dark fringes then bleed inward through the mip chain.
			var dst_a := float(out[di + 3]) / 255.0
			var out_a: float = a + dst_a * (1.0 - a)
			if out_a <= 0.001:
				continue
			for c in 3:
				var s_val: float = float(sdata[si + c]) * shade
				var d_val: float = float(out[di + c])
				out[di + c] = int(clampf(
						(s_val * a + d_val * dst_a * (1.0 - a)) / out_a, 0.0, 255.0))
			out[di + 3] = int(clampf(out_a * 255.0, 0.0, 255.0))
