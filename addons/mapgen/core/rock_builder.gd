@tool
class_name MapRockBuilder
extends RefCounted
## Procedural rocks built as a rounded convex polytope.
##
## A noise-displaced sphere always reads as a potato, because the thing that
## makes stone look like stone is not bumpiness -- it is *planar fracture*. Rock
## breaks along flat planes that meet at sharp arrises, and weathering then
## rounds those arrises without flattening the faces.
##
## So the radius function here is the intersection of a set of random half-
## spaces (which gives flat faces and sharp edges), smooth-min'd against a lumpy
## sphere (which rounds the arrises by a controllable amount), with fine noise on
## top for surface texture. `edge_round` walks the whole range from a freshly
## split angular chunk to a river-worn cobble.
##
## Vertex colours:
##   r = cavity occlusion, darker in the crevices between faces
##   g = large-scale colour variation across the rock
##   b = height up the rock, 0 at the buried base -- used to blend into soil


class RockProfile extends RefCounted:
	var name := "boulder"
	## Longest axis, in metres, before per-instance scaling.
	var size := 1.8
	## Squash per axis. Rocks are rarely spherical and almost never taller than
	## they are wide once they have come to rest.
	var axes := Vector3(1.0, 0.70, 0.92)

	## Number of fracture planes. Few and large = an angular broken chunk; many
	## and small = a rounded cobble.
	## Number of fracture planes, and how far out they sit as a fraction of the
	## base radius. These have to be close enough in that their cut caps overlap
	## -- otherwise the planes only clip shallow lids off a sphere and the
	## result is a potato with a few flat spots. For N planes spread over a
	## sphere, distances around 0.5-0.8 give a fully faceted solid whose corners
	## reach roughly the base radius.
	var facets := 11
	var facet_min := 0.50
	var facet_max := 0.80
	## Blend radius where faces meet. 0 gives razor arrises, higher gives
	## weathered ones. This one dial does most of the character.
	var edge_round := 0.045
	## Fracture planes avoid pointing straight down, so the underside stays
	## broad and the rock sits rather than balances.
	var upward_bias := 0.35

	var lumpiness := 0.15
	var lump_scale := 1.4
	var detail := 0.012
	var detail_scale := 13.0

	## Fraction of the rock's height sliced off the bottom. Real rocks are
	## partly buried; a full ellipsoid resting on terrain always looks dropped.
	var bury := 0.22

	var rings := 18
	var segs := 26


static func build(p: RockProfile, rng: RandomNumberGenerator, material: Material) -> ArrayMesh:
	# Jitter the proportions per rock. Without this every boulder grown from one
	# profile has the same footprint, and a scatter of them reads as copies
	# however much the facets differ.
	var axes := Vector3(
			p.axes.x * rng.randf_range(0.82, 1.18),
			p.axes.y * rng.randf_range(0.80, 1.22),
			p.axes.z * rng.randf_range(0.82, 1.18))

	# --- fracture planes -------------------------------------------------
	var pn: Array[Vector3] = []
	var pd := PackedFloat32Array()
	for i in p.facets:
		var n := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0))
		if n.length_squared() < 1e-6:
			n = Vector3.UP
		n = n.normalized()
		# Lift planes away from pointing straight down.
		n.y = lerpf(n.y, absf(n.y), p.upward_bias)
		pn.append(n.normalized())
		pd.append(rng.randf_range(p.facet_min, p.facet_max))

	var lump := FastNoiseLite.new()
	lump.seed = rng.randi()
	lump.noise_type = FastNoiseLite.TYPE_SIMPLEX
	lump.frequency = 1.0
	var fine := FastNoiseLite.new()
	fine.seed = rng.randi()
	fine.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fine.frequency = 1.0
	var tint := FastNoiseLite.new()
	tint.seed = rng.randi()
	tint.noise_type = FastNoiseLite.TYPE_SIMPLEX
	tint.frequency = 0.7

	# --- sample the surface ----------------------------------------------
	var rows: Array = []
	var norm_rows: Array = []
	var ao_rows: Array = []
	var min_y := INF
	var max_y := -INF

	for r in p.rings + 1:
		var row: Array[Vector3] = []
		var nrow: Array[Vector3] = []
		var arow := PackedFloat32Array()
		var phi := PI * float(r) / float(p.rings)
		for s in p.segs + 1:
			var theta := TAU * float(s) / float(p.segs)
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var pos := _surface(dir, p, pn, pd, lump, fine, axes)
			row.append(pos)
			nrow.append(_normal_at(dir, p, pn, pd, lump, fine, axes))
			arow.append(_cavity(dir, p, pn, pd, lump, fine))
			min_y = minf(min_y, pos.y)
			max_y = maxf(max_y, pos.y)
		rows.append(row)
		norm_rows.append(nrow)
		ao_rows.append(arow)

	# --- bury the base ----------------------------------------------------
	var cut := min_y + (max_y - min_y) * p.bury
	var height: float = maxf(max_y - cut, 0.001)
	for r in rows.size():
		var row: Array[Vector3] = rows[r]
		for s in row.size():
			var v: Vector3 = row[s]
			row[s] = Vector3(v.x, maxf(v.y, cut) - cut, v.z)

	# --- emit -------------------------------------------------------------
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in p.rings:
		for s in p.segs:
			var quad := [
				[rows[r][s], norm_rows[r][s], ao_rows[r][s], _uv(r, s, p)],
				[rows[r + 1][s], norm_rows[r + 1][s], ao_rows[r + 1][s], _uv(r + 1, s, p)],
				[rows[r][s + 1], norm_rows[r][s + 1], ao_rows[r][s + 1], _uv(r, s + 1, p)],
				[rows[r + 1][s + 1], norm_rows[r + 1][s + 1], ao_rows[r + 1][s + 1],
						_uv(r + 1, s + 1, p)],
			]
			# Same winding convention as everything else here: the geometric
			# cross product points opposite the shading normal.
			for order in [[0, 1, 2], [2, 1, 3]]:
				for k in order:
					var v: Vector3 = quad[k][0]
					var variation: float = tint.get_noise_3d(v.x, v.y, v.z) * 0.5 + 0.5
					st.set_normal(quad[k][1])
					st.set_uv(quad[k][3])
					st.set_color(Color(quad[k][2], variation,
							clampf(v.y / height, 0.0, 1.0), 1.0))
					st.add_vertex(v)

	st.generate_tangents()
	st.index()
	var mesh := st.commit()
	if material:
		mesh.surface_set_material(0, material)
	return mesh


static func _uv(r: int, s: int, p: RockProfile) -> Vector2:
	return Vector2(float(s) / float(p.segs), float(r) / float(p.rings))


## Radius along `dir`: a lumpy sphere carved by the fracture planes.
static func _radius(dir: Vector3, p: RockProfile, pn: Array[Vector3], pd: PackedFloat32Array,
		lump: FastNoiseLite, fine: FastNoiseLite) -> float:
	var r := 1.0 + lump.get_noise_3d(dir.x * p.lump_scale, dir.y * p.lump_scale,
			dir.z * p.lump_scale) * p.lumpiness

	var poly := 1.0e9
	for i in pn.size():
		var dp := dir.dot(pn[i])
		if dp > 0.001:
			poly = minf(poly, pd[i] / dp)

	r = _smin(r, poly, p.edge_round)
	r += fine.get_noise_3d(dir.x * p.detail_scale, dir.y * p.detail_scale,
			dir.z * p.detail_scale) * p.detail
	return maxf(r, 0.05)


static func _surface(dir: Vector3, p: RockProfile, pn: Array[Vector3], pd: PackedFloat32Array,
		lump: FastNoiseLite, fine: FastNoiseLite, ax: Vector3) -> Vector3:
	var r := _radius(dir, p, pn, pd, lump, fine)
	return Vector3(dir.x * ax.x, dir.y * ax.y, dir.z * ax.z) * r * p.size * 0.5


## Normals by finite difference on the surface itself, not from the sphere
## direction: the polytope carving means the true normal turns hard at an arris
## and a radial normal would smooth every edge away.
static func _normal_at(dir: Vector3, p: RockProfile, pn: Array[Vector3], pd: PackedFloat32Array,
		lump: FastNoiseLite, fine: FastNoiseLite, ax: Vector3) -> Vector3:
	var t1 := dir.cross(Vector3.UP)
	if t1.length_squared() < 1e-6:
		t1 = dir.cross(Vector3.RIGHT)
	t1 = t1.normalized()
	var t2 := dir.cross(t1).normalized()
	var eps := 0.012

	var o := _surface(dir, p, pn, pd, lump, fine, ax)
	var a := _surface((dir + t1 * eps).normalized(), p, pn, pd, lump, fine, ax)
	var b := _surface((dir + t2 * eps).normalized(), p, pn, pd, lump, fine, ax)
	var n := (a - o).cross(b - o)
	if n.length_squared() < 1e-12:
		return dir
	n = n.normalized()
	return n if n.dot(dir) > 0.0 else -n


## How far this point sits below its wider neighbourhood: 1 on an exposed face,
## lower down in the crevice where two faces meet.
static func _cavity(dir: Vector3, p: RockProfile, pn: Array[Vector3], pd: PackedFloat32Array,
		lump: FastNoiseLite, fine: FastNoiseLite) -> float:
	var t1 := dir.cross(Vector3.UP)
	if t1.length_squared() < 1e-6:
		t1 = dir.cross(Vector3.RIGHT)
	t1 = t1.normalized()
	var t2 := dir.cross(t1).normalized()
	var wide := 0.16

	var r := _radius(dir, p, pn, pd, lump, fine)
	var avg := 0.0
	for d in [t1, -t1, t2, -t2]:
		avg += _radius((dir + d * wide).normalized(), p, pn, pd, lump, fine)
	avg *= 0.25
	# Unoccluded is 1.0, and a flat face has r == avg, so the curve has to be
	# centred on 1 and only fall in concavities. Centring it on 0.5 instead
	# darkens the entire rock by half and reads as a badly exposed texture
	# rather than as occlusion.
	return clampf(1.0 + (r - avg) * 4.0, 0.35, 1.0)


static func _smin(a: float, b: float, k: float) -> float:
	if k <= 0.0001:
		return minf(a, b)
	var h: float = clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


# ---------------------------------------------------------------------------
# stock profiles
# ---------------------------------------------------------------------------

## Weathered boulder: many small facets, well-rounded arrises.
static func boulder_profile(size: float = 1.8) -> RockProfile:
	var p := RockProfile.new()
	p.name = "Boulder"
	p.size = size
	p.axes = Vector3(1.0, 0.68, 0.94)
	p.facets = 13
	p.facet_min = 0.54
	p.facet_max = 0.82
	p.edge_round = 0.045
	p.lumpiness = 0.16
	p.detail = 0.013
	p.bury = 0.24
	return p


## Freshly broken chunk: few large faces, sharp arrises. Reads as scree.
static func angular_profile(size: float = 0.8) -> RockProfile:
	var p := RockProfile.new()
	p.name = "Angular"
	p.size = size
	p.axes = Vector3(1.0, 0.62, 0.78)
	p.facets = 8
	p.facet_min = 0.44
	p.facet_max = 0.74
	p.edge_round = 0.012
	p.upward_bias = 0.15
	p.lumpiness = 0.09
	p.detail = 0.010
	p.bury = 0.30
	p.rings = 14
	p.segs = 20
	return p


## Bedded slab: heavily squashed, planar top and bottom. Outcrop material.
static func slab_profile(size: float = 3.2) -> RockProfile:
	var p := RockProfile.new()
	p.name = "Slab"
	p.size = size
	p.axes = Vector3(1.0, 0.32, 0.85)
	p.facets = 10
	p.facet_min = 0.50
	p.facet_max = 0.80
	p.edge_round = 0.022
	p.upward_bias = 0.55
	p.lumpiness = 0.12
	p.detail = 0.011
	p.bury = 0.30
	return p


## Blocky outcrop: large, tall, still angular. Breaks up steep ground.
static func outcrop_profile(size: float = 4.5) -> RockProfile:
	var p := RockProfile.new()
	p.name = "Outcrop"
	p.size = size
	p.axes = Vector3(1.0, 1.05, 0.86)
	p.facets = 10
	p.facet_min = 0.48
	p.facet_max = 0.80
	p.edge_round = 0.020
	p.upward_bias = 0.30
	p.lumpiness = 0.20
	p.lump_scale = 1.1
	p.detail = 0.014
	p.bury = 0.34
	p.rings = 20
	p.segs = 28
	return p


## Small water-worn cobble: many facets, heavily rounded.
static func pebble_profile(size: float = 0.35) -> RockProfile:
	var p := RockProfile.new()
	p.name = "Pebble"
	p.size = size
	p.axes = Vector3(1.0, 0.55, 0.85)
	p.facets = 16
	p.facet_min = 0.62
	p.facet_max = 0.88
	p.edge_round = 0.12
	p.lumpiness = 0.10
	p.detail = 0.009
	p.bury = 0.34
	p.rings = 10
	p.segs = 14
	return p
