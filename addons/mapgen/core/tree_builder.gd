@tool
class_name MapTreeBuilder
extends RefCounted
## Procedural trees: a recursive branch skeleton skinned with tapered tubes,
## plus alpha-cut leaf cards.
##
## The mesh has two surfaces -- 0 bark, 1 foliage -- so each can carry its own
## material and shader. Materials are baked onto the ArrayMesh rather than set
## as a MultiMeshInstance material_override, because an override replaces every
## surface at once.
##
## Vertex colours carry shading and animation data, not colour:
##   r = wind weight   0 at the root, 1 at the leaf tips
##   g = ambient occlusion, darker deep inside the canopy
##   b = per-element random, for wind phase and colour variation
##
## The three things that decide whether a tree reads as real:
##   1. alpha-cut leaves. A solid canopy is the single biggest tell there is --
##      you have to be able to see sky through it.
##   2. canopy normals. Leaf cards shaded by their own quad normal look like
##      flat cardboard; pointing the normal away from the canopy centre instead
##      makes the whole crown shade as one soft volume.
##   3. silhouette. Real branches taper, curve toward the light, and are spaced
##      by phyllotaxis rather than evenly.


class TreeProfile extends RefCounted:
	var name := "tree"
	var height := 9.0
	var trunk_radius := 0.20
	## Fraction of the parent's radius a child branch starts at.
	var radius_ratio := 0.55
	## Fraction of the parent's length a child branch runs for.
	var length_ratio := 0.62
	var levels := 3
	## Children spawned per branch, indexed by the parent's level.
	var children: PackedInt32Array = PackedInt32Array([5, 4, 3])
	## Where along the parent children are allowed, as fractions of its length.
	var child_start := 0.32
	var child_end := 0.94
	## Angle away from the parent's direction, in degrees.
	var child_angle := 55.0
	var child_angle_var := 14.0
	## Added to child_angle at the top of the parent. Negative makes upper
	## branches sweep upward, which is what most broadleaf trees do.
	var angle_by_height := -20.0
	## Per-segment bend toward vertical. Positive lifts tips (phototropism),
	## negative makes them droop, which is the conifer silhouette.
	var curve_up := 0.30
	## Random wobble per segment. Straight branches look manufactured.
	var gnarl := 0.13
	## Length multiplier for a child spawned at the very top of its parent.
	## Driving this low is what turns a bush into a cone.
	var child_shrink_top := 0.55
	var trunk_lean := 0.06
	## Whorls of branches at discrete heights instead of a continuous spiral.
	## 0 = spiral (broadleaf), >0 = whorled (conifer).
	var whorls := 0
	var sides_by_level: PackedInt32Array = PackedInt32Array([9, 6, 5, 4])
	var segs_by_level: PackedInt32Array = PackedInt32Array([6, 4, 3, 2])
	## Foliage
	var conifer := false
	var leaf_w := 0.17
	var leaf_h := 0.29
	var leaves_per_tip := 12
	var leaf_spread := 0.30
	## Foliage only appears on branches at or past this level.
	var foliage_from_level := 2
	## Fraction along a branch where foliage starts. Bare inner twigs, leafy
	## outer ones -- the same reason a hedge is green outside and brown inside.
	var foliage_along := 0.45
	var bark_tile := 0.85


const GOLDEN_ANGLE := 2.39996323   # radians; the phyllotaxis spacing


class _Sprout extends RefCounted:
	var path: PackedVector3Array
	var wind0: float
	var wind1: float


static func build(profile: TreeProfile, rng: RandomNumberGenerator,
		bark_material: Material, leaf_material: Material) -> ArrayMesh:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tips: Array[_Sprout] = []

	var canopy_y: float = profile.height * 0.62
	var canopy_r: float = profile.height * 0.34

	var start_dir := Vector3(
			rng.randf_range(-profile.trunk_lean, profile.trunk_lean), 1.0,
			rng.randf_range(-profile.trunk_lean, profile.trunk_lean)).normalized()

	_grow(bark, tips, profile, rng, 0, Vector3.ZERO, start_dir,
			profile.height, profile.trunk_radius, canopy_y, canopy_r)

	var mesh := ArrayMesh.new()
	bark.generate_tangents()
	bark.index()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bark.commit_to_arrays())
	if bark_material:
		mesh.surface_set_material(0, bark_material)

	if not tips.is_empty():
		var foliage := SurfaceTool.new()
		foliage.begin(Mesh.PRIMITIVE_TRIANGLES)
		for tip in tips:
			if profile.conifer:
				_emit_needle_spray(foliage, profile, rng, tip, canopy_y, canopy_r)
			else:
				_emit_leaf_cluster(foliage, profile, rng, tip, canopy_y, canopy_r)
		foliage.generate_tangents()
		foliage.index()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, foliage.commit_to_arrays())
		if leaf_material:
			mesh.surface_set_material(1, leaf_material)

	return mesh


# ---------------------------------------------------------------------------
# skeleton
# ---------------------------------------------------------------------------

static func _grow(st: SurfaceTool, tips: Array[_Sprout], p: TreeProfile,
		rng: RandomNumberGenerator, level: int, start: Vector3, dir: Vector3,
		length: float, radius: float, canopy_y: float, canopy_r: float) -> void:
	var segs: int = p.segs_by_level[mini(level, p.segs_by_level.size() - 1)]
	var sides: int = p.sides_by_level[mini(level, p.sides_by_level.size() - 1)]

	# Wind weight rises with depth: the trunk barely moves, tips move a lot.
	var wind_base := float(level) / float(maxi(p.levels, 1))
	var wind_tip := float(level + 1) / float(maxi(p.levels, 1))

	var path := _branch_path(start, dir, length, segs, p.curve_up, p.gnarl, rng)
	_emit_tube(st, path, radius, radius * p.radius_ratio * 0.85, sides,
			wind_base, wind_tip, p.bark_tile, canopy_y, canopy_r, rng)

	# Foliage rides the whole outer stretch of a branch, not just its tip.
	# Bunching leaves at the endpoint produces pom-poms on sticks; real leaves
	# run along the outer half of every twig, and that is most of what makes a
	# canopy read as full rather than sparse.
	if level >= p.foliage_from_level or level == p.levels:
		var sprout := _Sprout.new()
		sprout.path = path
		sprout.wind0 = wind_base
		sprout.wind1 = wind_tip
		tips.append(sprout)

	if level >= p.levels:
		return

	var count: int = p.children[mini(level, p.children.size() - 1)]
	if count <= 0:
		return

	if p.whorls > 0 and level == 0:
		_spawn_whorled(st, tips, p, rng, level, path, length, radius, count,
				canopy_y, canopy_r)
	else:
		_spawn_spiral(st, tips, p, rng, level, path, length, radius, count,
				canopy_y, canopy_r)


static func _spawn_spiral(st: SurfaceTool, tips: Array[_Sprout], p: TreeProfile,
		rng: RandomNumberGenerator, level: int, path: PackedVector3Array,
		length: float, radius: float, count: int, canopy_y: float, canopy_r: float) -> void:
	var phase := rng.randf_range(0.0, TAU)
	for i in count:
		var f: float = lerpf(p.child_start, p.child_end,
				(float(i) + rng.randf_range(0.1, 0.9)) / float(count))
		# Golden angle between successive branches: this is how real plants
		# space them, and evenly divided angles read as manufactured.
		var azimuth := phase + GOLDEN_ANGLE * float(i)
		_spawn_child(st, tips, p, rng, level, path, f, azimuth, length, radius,
				canopy_y, canopy_r)


static func _spawn_whorled(st: SurfaceTool, tips: Array[_Sprout], p: TreeProfile,
		rng: RandomNumberGenerator, level: int, path: PackedVector3Array,
		length: float, radius: float, count: int, canopy_y: float, canopy_r: float) -> void:
	for w in p.whorls:
		var f: float = lerpf(p.child_start, p.child_end,
				float(w) / float(maxi(p.whorls - 1, 1)))
		var phase := rng.randf_range(0.0, TAU)
		# Fewer, longer branches at the bottom; more, shorter ones at the top.
		var n: int = maxi(2, count - int(float(w) / float(maxi(p.whorls, 1)) * 2.0))
		for i in n:
			var azimuth := phase + TAU * float(i) / float(n) + rng.randf_range(-0.25, 0.25)
			_spawn_child(st, tips, p, rng, level, path, f, azimuth, length, radius,
					canopy_y, canopy_r)


static func _spawn_child(st: SurfaceTool, tips: Array[_Sprout], p: TreeProfile,
		rng: RandomNumberGenerator, level: int, path: PackedVector3Array,
		f: float, azimuth: float, length: float, radius: float,
		canopy_y: float, canopy_r: float) -> void:
	var attach := _sample_path(path, f)
	var parent_dir := _path_dir(path, f)

	var angle: float = p.child_angle + p.angle_by_height * f \
			+ rng.randf_range(-p.child_angle_var, p.child_angle_var)

	var side := Vector3.UP.cross(parent_dir)
	if side.length_squared() < 1e-5:
		side = Vector3.RIGHT
	side = side.normalized()
	var out := side.rotated(parent_dir, azimuth)
	var child_dir := parent_dir.rotated(out.cross(parent_dir).normalized(),
			deg_to_rad(angle)).normalized()

	# Branches shorten toward the top of the parent, which is what gives a tree
	# its taper instead of a cylinder of foliage.
	var shrink: float = lerpf(1.0, p.child_shrink_top, f)
	var child_len: float = length * p.length_ratio * shrink * rng.randf_range(0.85, 1.15)
	var child_rad: float = radius * p.radius_ratio * shrink

	if child_len < 0.05 or child_rad < 0.004:
		return
	_grow(st, tips, p, rng, level + 1, attach, child_dir, child_len, child_rad,
			canopy_y, canopy_r)


static func _branch_path(start: Vector3, dir: Vector3, length: float, segs: int,
		curve_up: float, gnarl: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.append(start)
	var d := dir.normalized()
	var step := length / float(maxi(segs, 1))
	var pos := start
	for i in segs:
		var t := float(i) / float(maxi(segs, 1))
		# Bend toward (or away from) vertical, strengthening along the branch.
		d = d.lerp(Vector3.UP, curve_up * step * (0.35 + t)).normalized()
		d = (d + Vector3(rng.randf_range(-gnarl, gnarl), rng.randf_range(-gnarl, gnarl) * 0.4,
				rng.randf_range(-gnarl, gnarl)) * step).normalized()
		pos += d * step
		pts.append(pos)
	return pts


static func _sample_path(path: PackedVector3Array, f: float) -> Vector3:
	var x: float = clampf(f, 0.0, 1.0) * float(path.size() - 1)
	var i: int = clampi(int(x), 0, path.size() - 2)
	return path[i].lerp(path[i + 1], x - float(i))


static func _path_dir(path: PackedVector3Array, f: float) -> Vector3:
	var x: float = clampf(f, 0.0, 1.0) * float(path.size() - 1)
	var i: int = clampi(int(x), 0, path.size() - 2)
	return (path[i + 1] - path[i]).normalized()


# ---------------------------------------------------------------------------
# skinning
# ---------------------------------------------------------------------------

static func _emit_tube(st: SurfaceTool, path: PackedVector3Array, r0: float, r1: float,
		sides: int, wind0: float, wind1: float, tile: float,
		canopy_y: float, canopy_r: float, rng: RandomNumberGenerator) -> void:
	var n := path.size()
	if n < 2:
		return

	# Parallel transport keeps the ring orientation continuous along a curving
	# branch; recomputing a frame per ring makes the bark texture spin.
	var dir0 := (path[1] - path[0]).normalized()
	var side := Vector3.UP.cross(dir0)
	if side.length_squared() < 1e-5:
		side = Vector3.RIGHT.cross(dir0)
	side = side.normalized()

	var rings: Array[PackedVector3Array] = []
	var ring_v: PackedFloat32Array = PackedFloat32Array()
	var ring_w: PackedFloat32Array = PackedFloat32Array()
	var run := 0.0
	var prev_dir := dir0

	for i in n:
		var d: Vector3 = (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		if d.length_squared() < 1e-6:
			d = prev_dir
		side = (Quaternion(prev_dir, d) * side).normalized()
		prev_dir = d
		var up := d.cross(side).normalized()

		var t := float(i) / float(n - 1)
		var r: float = lerpf(r0, r1, t * t * 0.7 + t * 0.3)
		if i > 0:
			run += path[i].distance_to(path[i - 1])

		var ring := PackedVector3Array()
		for s in sides:
			var a := TAU * float(s) / float(sides)
			ring.append(path[i] + (side * cos(a) + up * sin(a)) * r)
		rings.append(ring)
		# Texel density stays square by measuring v in the same units as u.
		ring_v.append(run / maxf(tile, 0.01))
		ring_w.append(lerpf(wind0, wind1, t))

	var circumference := TAU * maxf(r0, 0.01)
	for i in n - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			var u0 := float(s) / float(sides) * circumference / maxf(tile, 0.01)
			var u1 := float(s + 1) / float(sides) * circumference / maxf(tile, 0.01)
			var quad := [
				[rings[i][s], Vector2(u0, ring_v[i]), ring_w[i]],
				[rings[i][s2], Vector2(u1, ring_v[i]), ring_w[i]],
				[rings[i + 1][s2], Vector2(u1, ring_v[i + 1]), ring_w[i + 1]],
				[rings[i + 1][s], Vector2(u0, ring_v[i + 1]), ring_w[i + 1]],
			]
			# Winding matches the terrain's: cross product opposite the normal.
			for order in [[0, 2, 1], [0, 3, 2]]:
				for k in order:
					var v: Vector3 = quad[k][0]
					var nrm := (v - _axis_point(path, i, k >= 2)).normalized()
					st.set_normal(nrm)
					st.set_uv(quad[k][1])
					st.set_color(Color(quad[k][2], _bark_ao(v, canopy_y, canopy_r), 0.5, 1.0))
					st.add_vertex(v)


static func _axis_point(path: PackedVector3Array, i: int, next: bool) -> Vector3:
	return path[mini(i + (1 if next else 0), path.size() - 1)]


## Bark darkens low down and deep inside the crown, where little sky reaches.
static func _bark_ao(v: Vector3, canopy_y: float, canopy_r: float) -> float:
	var radial: float = Vector2(v.x, v.z).length() / maxf(canopy_r, 0.01)
	var inside: float = 1.0 - clampf(radial, 0.0, 1.0)
	var low: float = 1.0 - clampf(v.y / maxf(canopy_y, 0.01), 0.0, 1.0)
	return clampf(1.0 - 0.45 * inside * (0.4 + 0.6 * low), 0.25, 1.0)


# ---------------------------------------------------------------------------
# foliage
# ---------------------------------------------------------------------------

## The leaf texture holds two photoscanned leaves side by side, front and back.
## Picking between them per leaf gives free variation and, more importantly,
## real leaf undersides -- which is most of what you actually see from below.
## Four cluster cells in a 2x2 atlas, inset slightly so mipmaps cannot bleed
## one bunch into its neighbour.
const LEAF_UV := [
	Rect2(0.005, 0.005, 0.49, 0.49),
	Rect2(0.505, 0.005, 0.49, 0.49),
	Rect2(0.005, 0.505, 0.49, 0.49),
	Rect2(0.505, 0.505, 0.49, 0.49),
]


static func _emit_leaf_cluster(st: SurfaceTool, p: TreeProfile, rng: RandomNumberGenerator,
		sprout: _Sprout, canopy_y: float, canopy_r: float) -> void:
	for i in p.leaves_per_tip:
		var t := rng.randf_range(p.foliage_along, 1.0)
		var stem := _path_dir(sprout.path, t)
		var side := _perp(stem).rotated(stem, rng.randf_range(0.0, TAU))
		var base: Vector3 = _sample_path(sprout.path, t) \
				+ side * rng.randf_range(0.0, p.leaf_spread)

		# Leaves reach outward and upward for light, with enough jitter that no
		# two sit in the same plane.
		var outward := (base - Vector3(0.0, canopy_y, 0.0))
		if outward.length_squared() < 1e-5:
			outward = stem
		outward = outward.normalized()
		var up_dir := (outward * 0.40 + Vector3.UP * 0.40 + stem * 0.30
				+ Vector3(rng.randf_range(-0.55, 0.55), rng.randf_range(-0.4, 0.3),
						rng.randf_range(-0.55, 0.55))).normalized()

		var w: float = p.leaf_w * rng.randf_range(0.75, 1.25)
		var h: float = p.leaf_h * rng.randf_range(0.8, 1.2)
		var uv: Rect2 = LEAF_UV[rng.randi() % LEAF_UV.size()]
		_emit_card(st, base, up_dir, w, h, uv, lerpf(sprout.wind0, sprout.wind1, t),
				rng, canopy_y, canopy_r, rng.randf())


static func _emit_needle_spray(st: SurfaceTool, p: TreeProfile, rng: RandomNumberGenerator,
		sprout: _Sprout, canopy_y: float, canopy_r: float) -> void:
	for i in p.leaves_per_tip:
		var t := rng.randf_range(p.foliage_along, 1.0)
		var stem := _path_dir(sprout.path, t)
		var side := _perp(stem).rotated(stem, rng.randf_range(0.0, TAU))
		var base: Vector3 = _sample_path(sprout.path, t) \
				+ side * rng.randf_range(0.0, p.leaf_spread)
		# Needle sprays are broad flat branchlets that follow the shoot and sag
		# under their own weight, rather than reaching upward like a leaf.
		var up_dir := (stem * 1.0 + Vector3.DOWN * rng.randf_range(0.05, 0.35)
				+ side * rng.randf_range(-0.35, 0.35)).normalized()
		var w: float = p.leaf_w * rng.randf_range(0.8, 1.3)
		var h: float = p.leaf_h * rng.randf_range(0.85, 1.3)
		_emit_card(st, base, up_dir, w, h, Rect2(0.0, 0.0, 1.0, 1.0),
				lerpf(sprout.wind0, sprout.wind1, t), rng, canopy_y, canopy_r, rng.randf())


static func _perp(dir: Vector3) -> Vector3:
	var side := Vector3.UP.cross(dir)
	if side.length_squared() < 1e-5:
		side = Vector3.RIGHT.cross(dir)
	return side.normalized()


static func _emit_card(st: SurfaceTool, base: Vector3, up_dir: Vector3, w: float, h: float,
		uv: Rect2, wind: float, rng: RandomNumberGenerator,
		canopy_y: float, canopy_r: float, variation: float) -> void:
	var side := up_dir.cross(Vector3.UP)
	if side.length_squared() < 1e-5:
		side = up_dir.cross(Vector3.RIGHT)
	side = side.normalized().rotated(up_dir, rng.randf_range(-0.9, 0.9))
	var half := side * w * 0.5

	var a := base - half
	var b := base + half
	var c := base + half + up_dir * h
	var d := base - half + up_dir * h
	var centre := base + up_dir * h * 0.5

	# Canopy normal: point away from the crown's centre, not along the card.
	# This is what stops a canopy reading as a pile of flat cards.
	var outward := (centre - Vector3(0.0, canopy_y, 0.0))
	if outward.length_squared() < 1e-5:
		outward = Vector3.UP
	outward = outward.normalized()
	var quad_n := (b - a).cross(d - a).normalized()
	var nrm := (outward * 0.75 + quad_n * 0.25).normalized()

	var radial: float = Vector2(centre.x, centre.z).length() / maxf(canopy_r, 0.01)
	var exposure: float = clampf(0.40 + 0.60 * clampf(radial, 0.0, 1.0), 0.0, 1.0)
	# Leaves under the crown see less sky than leaves on top.
	exposure *= lerpf(0.72, 1.0, clampf((centre.y - canopy_y) / maxf(canopy_r, 0.01) * 0.5 + 0.5, 0.0, 1.0))
	var col := Color(wind, exposure, variation, 1.0)

	var pts: Array[Vector3] = [a, b, c, a, c, d]
	var uvs: Array[Vector2] = [
		Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.end.y),
		Vector2(uv.end.x, uv.position.y),
		Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.position.y),
		Vector2(uv.position.x, uv.position.y),
	]
	for i in 6:
		st.set_normal(nrm)
		st.set_uv(uvs[i])
		st.set_color(col)
		st.add_vertex(pts[i])


# ---------------------------------------------------------------------------
# stock profiles
# ---------------------------------------------------------------------------

static func broadleaf_profile(height: float = 9.0) -> TreeProfile:
	var p := TreeProfile.new()
	p.name = "Broadleaf"
	p.height = height
	p.trunk_radius = height * 0.026
	p.levels = 3
	p.children = PackedInt32Array([6, 5, 4])
	p.child_start = 0.30
	p.child_end = 0.94
	p.child_angle = 62.0
	p.angle_by_height = -16.0
	p.length_ratio = 0.62
	p.radius_ratio = 0.52
	p.child_shrink_top = 0.55
	p.curve_up = 0.50
	p.gnarl = 0.15
	p.trunk_lean = 0.07
	# Cluster cards, not single leaves: each quad carries a bunch, so they are
	# large and roughly square and there are far fewer of them.
	p.leaf_w = height * 0.085
	p.leaf_h = height * 0.085
	p.leaves_per_tip = 9
	p.leaf_spread = height * 0.030
	# Leaves on the outer two branch orders, not just the last: one order of
	# leafy twigs makes a crown that reads as a wireframe with confetti on it.
	p.foliage_from_level = 2
	p.foliage_along = 0.32
	p.bark_tile = 0.75
	return p


static func conifer_profile(height: float = 12.0) -> TreeProfile:
	var p := TreeProfile.new()
	p.name = "Conifer"
	p.height = height
	p.trunk_radius = height * 0.021
	p.levels = 2
	p.children = PackedInt32Array([6, 3])
	p.child_start = 0.12
	p.child_end = 0.98
	# Lower whorls sit out near horizontal and sag; upper ones sweep up. That
	# spread from ~95 to ~40 degrees is the whole fir silhouette.
	p.child_angle = 95.0
	p.angle_by_height = -55.0
	p.length_ratio = 0.34
	p.radius_ratio = 0.32
	# Hard shrink toward the leader: this is what makes the cone.
	p.child_shrink_top = 0.13
	p.curve_up = -0.22
	p.gnarl = 0.07
	p.trunk_lean = 0.02
	p.whorls = 12
	p.sides_by_level = PackedInt32Array([8, 5, 4])
	p.segs_by_level = PackedInt32Array([8, 3, 2])
	# Needle sprays are branchlets, not leaves: much larger cards, far fewer.
	p.leaf_w = height * 0.055
	p.leaf_h = height * 0.075
	p.leaves_per_tip = 14
	p.leaf_spread = height * 0.006
	p.foliage_from_level = 2
	p.foliage_along = 0.10
	p.bark_tile = 0.6
	return p


## A shrub is a tree with no trunk: branches straight from the ground, and a
## crown that starts at ankle height. Same builder, different proportions.
static func shrub_profile(height: float = 1.7) -> TreeProfile:
	var p := TreeProfile.new()
	p.name = "Shrub"
	p.height = height
	p.trunk_radius = height * 0.035
	p.levels = 2
	p.children = PackedInt32Array([6, 3])
	p.child_start = 0.04
	p.child_end = 0.85
	p.child_angle = 48.0
	p.angle_by_height = -22.0
	p.length_ratio = 0.72
	p.radius_ratio = 0.55
	p.child_shrink_top = 0.60
	p.curve_up = 0.55
	p.gnarl = 0.22
	p.trunk_lean = 0.20
	p.sides_by_level = PackedInt32Array([5, 4, 3])
	p.segs_by_level = PackedInt32Array([3, 2, 2])
	p.leaf_w = height * 0.42
	p.leaf_h = height * 0.42
	p.leaves_per_tip = 7
	p.leaf_spread = height * 0.13
	p.foliage_from_level = 1
	p.foliage_along = 0.20
	p.bark_tile = 0.25
	return p
