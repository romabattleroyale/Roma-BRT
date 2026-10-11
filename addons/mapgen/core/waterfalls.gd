@tool
class_name MapWaterfalls
extends RefCounted
## Finds the places where a stream runs off a cliff, and builds the water that
## goes down it.
##
## Two halves, and the first one is the one that matters:
##
##   1. Siting. A fall is a *channel* crossing a *steep step*: take the drainage
##      network from MapFlow, keep the cells with a real catchment above them,
##      and walk downstream looking for a run steeper than the angle of repose.
##      Placing falls on slope alone gives water pouring out of dry hillsides;
##      placing them on the drainage gives water arriving along a valley, going
##      over an edge, and carrying on downhill afterwards.
##
##   2. The ribbon. One strip of quads following the channel from a little way
##      above the lip to a little way below the plunge, hugging the rock but
##      bowing off it through the middle of the drop, spreading as it falls.
##      Vertex colours carry steepness, foam and the end fades, so the shader
##      can tell falling water from the stream that feeds it.
##
## Nothing here touches the heightfield: waterfalls are added to the terrain,
## not carved into it, so turning them on cannot change the map underneath.

## Stream shown above the lip and below the plunge. Enough to read as "this
## water came from somewhere and went somewhere", short enough to stay cheap.
const APPROACH_M := 14.0
const RUNOUT_M := 20.0
## Hard cap on one fall's ribbon, so a pathological channel cannot build a
## 10,000-vertex mesh.
const MAX_POINTS := 400
## A run longer than this stops being a waterfall and starts being a river.
const MAX_RUN_STEPS := 40
## Vertices across the sheet. Two would do for a flat ribbon, but a flat ribbon
## disappears when you walk round to the side of it. Five lets the cross
## section bow outwards, which gives the fall a silhouette from any angle for
## the price of a few hundred vertices.
const ACROSS := 5
## How far the middle of the sheet stands proud of its edges, as a fraction of
## the fall's width.
const BOW := 0.22


class Fall:
	var lip := Vector3.ZERO        ## where the water leaves the top
	var base := Vector3.ZERO       ## where it lands
	var drop := 0.0                ## metres, lip to base
	var width := 1.0               ## metres across, from the catchment
	var catchment := 0.0           ## cells draining through the lip
	var lip_cell := -1
	var base_cell := -1
	var cells := PackedInt32Array()  ## the steep run itself, lip -> base

	func describe() -> String:
		return "%.0f m fall, %.1f m wide, at (%.0f, %.0f, %.0f)" % [
			drop, width, lip.x, lip.y, lip.z]


# ---------------------------------------------------------------------------
# siting
# ---------------------------------------------------------------------------

## Every fall the settings ask for, best first. Deterministic: same seed and
## same settings, same falls, because nothing in here rolls a die.
static func find_sites(hf: MapHeightfield, s: MapGenSettings, flow: MapFlow) -> Array:
	var cells_total := float(hf.dim * hf.dim)
	# A catchment threshold in *cells* rather than in metres, so the same
	# setting means the same stream at any resolution.
	var min_catchment: float = maxf(8.0, s.waterfall_catchment * cells_total)
	var min_grad := tan(deg_to_rad(s.waterfall_min_slope))
	# Hysteresis: a run has to *start* steeper than min_slope but only has to
	# stay above this to continue, so one gentler step partway down does not
	# chop a 60 m fall into two short ones.
	var end_grad := tan(deg_to_rad(maxf(s.waterfall_min_slope - 14.0, 18.0)))

	var candidates: Array = []
	var claimed := {}

	# Highest first, so the first steep cell reached on any stream is that
	# stream's brink. Anything lower down the same drop is part of this run and
	# gets claimed, rather than being reported again as its own little fall.
	for i in flow.order:
		if flow.accum[i] < min_catchment or claimed.has(i):
			continue
		var d := flow.down[i]
		if d < 0:
			continue
		if hf.height[i] <= hf.water_level + 1.0:
			continue
		if flow.gradient(hf, i, d) < min_grad:
			continue

		var run := PackedInt32Array()
		var cur := i
		var total := 0.0
		while run.size() < MAX_RUN_STEPS:
			var nxt := flow.down[cur]
			if nxt < 0 or flow.gradient(hf, cur, nxt) < end_grad:
				break
			run.append(cur)
			claimed[cur] = true
			total += hf.height[cur] - hf.height[nxt]
			cur = nxt
			# Below the waterline it is a lake, not a fall.
			if hf.height[cur] <= hf.water_level:
				break
		if run.is_empty():
			continue
		run.append(cur)

		if total < s.waterfall_min_drop:
			continue

		var f := Fall.new()
		f.lip_cell = i
		f.base_cell = cur
		f.cells = run
		f.drop = total
		f.catchment = flow.accum[i]
		f.lip = Vector3(flow.cell_x(i), hf.height[i], flow.cell_z(i))
		f.base = Vector3(flow.cell_x(cur), hf.height[cur], flow.cell_z(cur))
		# Discharge, not drainage area: width goes as roughly the square root
		# of the catchment, which is why a stream twice as long is nothing like
		# twice as wide.
		f.width = s.waterfall_width * clampf(sqrt(f.catchment / min_catchment), 0.7, 2.6)
		candidates.append(f)

	# Tallest and biggest first, then thin out anything sharing a cliff with a
	# better fall: six falls in a row down one face reads as a bug, not as a
	# feature of the terrain.
	candidates.sort_custom(func(a: Fall, b: Fall) -> bool:
		return a.drop * sqrt(a.catchment) > b.drop * sqrt(b.catchment))

	var kept: Array = []
	for f in candidates:
		if kept.size() >= s.waterfall_count:
			break
		var clear := true
		for other in kept:
			var sep: float = maxf(hf.size_m * 0.04, maxf(f.drop, other.drop) * 0.9)
			if Vector2(f.lip.x - other.lip.x, f.lip.z - other.lip.z).length() < sep:
				clear = false
				break
		if clear:
			kept.append(f)
	return kept


# ---------------------------------------------------------------------------
# geometry
# ---------------------------------------------------------------------------

## Nodes for one generated map: a ribbon per fall, each with its own mist.
static func build(hf: MapHeightfield, s: MapGenSettings, flow: MapFlow,
		falls: Array, material: Material) -> Array:
	var out: Array = []
	var idx := 0
	for f in falls:
		var mesh := build_ribbon(hf, s, flow, f)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Waterfall_%d" % idx
		mi.mesh = mesh
		mi.material_override = material
		# A sheet of water has no business darkening the cliff behind it, and
		# it is transparent, so it stays out of both shadow and GI.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if s.waterfall_mist and f.drop >= 6.0:
			mi.add_child(_build_mist(s, f))
		out.append(mi)
		idx += 1
	return out


## One fall's water, in world space. Null if the channel came out degenerate.
static func build_ribbon(hf: MapHeightfield, s: MapGenSettings, flow: MapFlow,
		f: Fall) -> ArrayMesh:
	var line := _channel_line(hf, flow, f)
	if line.size() < 3:
		return null

	var detach_max: float = clampf(f.drop * 0.06, 0.3, 2.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var dist := 0.0
	var count := line.size()
	var total_len := 0.0
	for k in range(1, count):
		total_len += line[k].distance_to(line[k - 1])

	for k in count:
		var p: Vector3 = line[k]
		var prev: Vector3 = line[maxi(k - 1, 0)]
		var next: Vector3 = line[mini(k + 1, count - 1)]
		if k > 0:
			dist += p.distance_to(prev)

		var tangent := (next - prev)
		if tangent.length_squared() < 0.000001:
			tangent = Vector3(0.0, -1.0, 0.0)
		tangent = tangent.normalized()

		var n := hf.normal_at(p.x, p.z)
		# Across the flow. Falling water is nearly vertical, so cross it with
		# the surface normal rather than with up, which degenerates on a cliff.
		var side := tangent.cross(n)
		if side.length_squared() < 0.0001:
			side = tangent.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()

		# How steeply the water is moving here, 0 = pooling, 1 = falling.
		var steep: float = clampf((-tangent.y - 0.34) / 0.62, 0.0, 1.0)
		var fallen: float = clampf(f.lip.y - p.y, 0.0, maxf(f.drop, 0.001))
		var progress: float = fallen / maxf(f.drop, 0.001)

		# Water leaves the brink on a ballistic curve and lands back in its own
		# pool, so bow the sheet off the rock through the middle of the drop.
		# Hugging the face all the way down is the tell-tale "painted-on
		# waterfall" look; leaving it hanging in the air is worse.
		var detach := steep * sin(PI * clampf(progress, 0.0, 1.0)) * detach_max
		var pos := p + n * (0.12 + detach)

		# Spreads as it falls: narrow in the channel above, widest in the
		# plunge below.
		var half_w := f.width * 0.5 * lerpf(0.8, 1.45, progress)

		# Water that is already broken before the shader adds any: the lip,
		# where the stream trips over the edge, and the plunge, where it hits.
		# The white *between* those two is aeration, and that belongs to the
		# shader, which knows how fast the sheet is moving at each pixel.
		var foam: float = 0.5 * (1.0 - smoothstep(0.0, 3.0, absf(p.y - f.lip.y)))
		foam = maxf(foam, 0.9 * smoothstep(f.drop - 1.0, f.drop + 4.0, fallen))
		foam = clampf(foam, 0.0, 1.0)

		# Fade both ends into the terrain: the ribbon is a fragment of a river
		# that carries on past it, and a hard rectangular end says so loudly.
		var fade: float = smoothstep(0.0, 5.0, dist) * smoothstep(0.0, 5.0, total_len - dist)
		# Under the lake, dissolve instead: the water plane is transparent, so
		# a sheet cut off flat below the surface shows through it as a white
		# slab standing on the lake bed.
		if p.y < hf.water_level:
			fade = clampf((p.y - hf.water_level + 2.0) * 0.5, 0.0, 1.0)

		# Alpha carries how far the water has fallen. Water leaves a lip
		# clear and glassy and is white by the time it lands, and the shader
		# needs to know which end of that it is shading.
		var vcol := Color(steep, foam, fade, progress)

		for j in ACROSS:
			var u := float(j) / float(ACROSS - 1)
			var lateral := u * 2.0 - 1.0
			var bow := (1.0 - lateral * lateral) * half_w * BOW
			st.set_normal((n + side * (-lateral * 0.5)).normalized())
			st.set_color(vcol)
			st.set_uv(Vector2(u, dist))
			st.add_vertex(pos + side * (lateral * half_w) + n * bow)

	for k in range(count - 1):
		for j in range(ACROSS - 1):
			var a := k * ACROSS + j
			var b := a + 1
			var c := a + ACROSS
			var d := c + 1
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)

	st.generate_tangents()
	return st.commit()


## The channel as a smooth line of world points: approach, drop, runout.
##
## The raw D8 path is unusable as geometry -- it is a staircase of 45-degree
## cell steps, and on a cliff two of its points can be 60 m apart vertically
## and 2 m apart horizontally. So: smooth the plan view, then resample against
## the heightfield, which is what makes the sheet follow the actual rock face
## rather than cutting a straight chord through it.
static func _channel_line(hf: MapHeightfield, flow: MapFlow, f: Fall) -> PackedVector3Array:
	var xz := PackedVector2Array()

	var approach := flow.trace_upstream(f.lip_cell, int(APPROACH_M / hf.cell) + 2)
	var run := 0.0
	# Backwards from the lip so the approach is trimmed at its far end.
	var start := 0
	for k in range(approach.size() - 1, 0, -1):
		run += flow.step_length(approach[k], approach[k - 1])
		if run > APPROACH_M:
			start = k
			break
	for k in range(start, approach.size() - 1):
		xz.append(Vector2(flow.cell_x(approach[k]), flow.cell_z(approach[k])))

	for c in f.cells:
		xz.append(Vector2(flow.cell_x(c), flow.cell_z(c)))

	var runout := flow.trace_downstream(f.base_cell, int(RUNOUT_M / hf.cell) + 2)
	run = 0.0
	for k in range(1, runout.size()):
		run += flow.step_length(runout[k], runout[k - 1])
		xz.append(Vector2(flow.cell_x(runout[k]), flow.cell_z(runout[k])))
		if run > RUNOUT_M:
			break
		# One cell into the lake is enough; the water surface covers the rest.
		if hf.height[runout[k]] < hf.water_level:
			break

	if xz.size() < 3:
		return PackedVector3Array()

	xz = _smooth(xz, 4)

	# Resample: horizontally where the channel is gentle, vertically where it
	# is not, so a sheer drop gets enough segments to bend around the face.
	var out := PackedVector3Array()
	for k in range(xz.size() - 1):
		var a: Vector2 = xz[k]
		var b: Vector2 = xz[k + 1]
		var ha := hf.height_at(a.x, a.y)
		var hb := hf.height_at(b.x, b.y)
		var steps: int = maxi(1, int(ceil(a.distance_to(b) / maxf(hf.cell * 0.5, 0.5))))
		steps = maxi(steps, int(ceil(absf(hb - ha) / 2.0)))
		steps = mini(steps, 64)
		for j in steps:
			var t := float(j) / float(steps)
			var p := a.lerp(b, t)
			var y := hf.height_at(p.x, p.y)
			out.append(Vector3(p.x, y, p.y))
			# Far enough under the surface to hide the cut end. Following the
			# channel all the way down a deepened basin draws a white column
			# standing on the lake bed, visible through the water.
			if y < hf.water_level - 1.5:
				return out
			if out.size() >= MAX_POINTS:
				return out
	var last: Vector2 = xz[xz.size() - 1]
	out.append(Vector3(last.x, hf.height_at(last.x, last.y), last.y))
	return out


## Plan-view smoothing with the ends pinned. Four passes takes the D8 zigzag
## out without letting the channel wander off its own gully.
static func _smooth(pts: PackedVector2Array, passes: int) -> PackedVector2Array:
	var cur := pts
	for _p in passes:
		var next := cur.duplicate()
		for k in range(1, cur.size() - 1):
			next[k] = cur[k - 1] * 0.25 + cur[k] * 0.5 + cur[k + 1] * 0.25
		cur = next
	return cur


# ---------------------------------------------------------------------------
# mist
# ---------------------------------------------------------------------------

## Spray at the plunge. Cheap and small on purpose: this is the cue that the
## water is hitting something, not a weather system.
static func _build_mist(s: MapGenSettings, f: Fall) -> GPUParticles3D:
	var spread: float = clampf(f.width * 0.9, 1.5, 8.0)
	var rise: float = clampf(f.drop * 0.22, 2.0, 9.0)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	# Wider than the fall itself, or the cloud hides behind the water it is
	# supposed to be coming off.
	pm.emission_sphere_radius = spread * 0.85
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 55.0
	pm.initial_velocity_min = rise * 0.25
	pm.initial_velocity_max = rise * 0.6
	# Just buoyant enough to drift up and hang: spray that falls looks like
	# rain, spray that rises looks like a waterfall.
	pm.gravity = Vector3(0.0, 0.35, 0.0)
	pm.damping_min = 0.6
	pm.damping_max = 1.4
	pm.scale_min = spread * 0.5
	pm.scale_max = spread * 1.3
	pm.color = Color(1.0, 1.0, 1.0, 0.22)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.25, Color(1, 1, 1, 1.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _puff_texture()
	# Lit, not unshaded: spray that glows at 3 a.m. gives the whole map away.
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.disable_receive_shadows = true
	quad.material = mat

	var p := GPUParticles3D.new()
	p.name = "Mist"
	p.amount = clampi(int(f.drop * 1.2) + 12, 12, 64)
	p.lifetime = 2.4
	p.preprocess = 2.0
	p.randomness = 0.6
	p.process_material = pm
	p.draw_pass_1 = quad
	# The ribbon's vertices are in world space and its node sits at the origin,
	# so this is a world position too. Offsetting it by anything -- the lip, the
	# node's own transform -- parks the spray in mid-air somewhere else, which
	# is invisible from the fall and therefore easy to miss.
	p.position = f.base + Vector3(0.0, spread * 0.35, 0.0)
	# The AABB has to be generous or the whole cloud pops out at grazing angles.
	var r: float = spread * 2.0 + rise
	p.visibility_aabb = AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2.0)
	return p


static var _puff: ImageTexture


## Soft round blob. Generated rather than shipped: one more PNG in the addon
## for something this simple is not worth the download.
static func _puff_texture() -> ImageTexture:
	if _puff != null:
		return _puff
	var n := 64
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var c := float(n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			# Squared falloff: a linear edge on a billboard reads as a disc.
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	img.generate_mipmaps()
	_puff = ImageTexture.create_from_image(img)
	return _puff
