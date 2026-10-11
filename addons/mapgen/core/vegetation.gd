@tool
class_name MapVegetation
extends RefCounted
## Ground flora: grass, ferns, reeds and flowers, all built from one primitive.
##
## Everything here is a tapered blade. A grass blade, a fern pinna, a reed leaf
## and a flower petal differ only in proportion, curvature and which channel
## they mark, so one emitter covers the lot and the shapes stay consistent.
##
## Vertex colours carry data rather than colour, matching flora.gdshader:
##   r = wind weight, 0 at the root and 1 at the tip
##   g = exposure, dark at the base of a clump and light at the tips
##   b = petal mask, 0 for stem and leaf, 1 for a bloom
##
## Trees live in MapTreeBuilder and rocks in MapRockBuilder: branching geometry
## with alpha leaf cards, and fractured convex solids, are each a different
## problem from a tuft of grass.


static func _finish(st: SurfaceTool) -> ArrayMesh:
	st.index()
	return st.commit()


## The one primitive: a blade running from `base` along `up_dir`, `width` wide
## at the root and tapering to a point, leaning by `lean` on the way up.
##
## `mid_scale` is what turns a grass blade into a petal -- below 1 it narrows
## steadily like a leaf, above 1 it bulges in the middle like a bloom.
static func _add_blade(st: SurfaceTool, base: Vector3, up_dir: Vector3, side: Vector3,
		lean: Vector3, height: float, width: float,
		wind_base: float, wind_tip: float, exp_base: float, exp_tip: float,
		petal: float = 0.0, mid_scale: float = 0.62) -> void:
	var half := side * width * 0.5
	var p0l := base - half
	var p0r := base + half
	var mid := base + up_dir * height * 0.55 + lean * 0.3
	var p1l := mid - half * mid_scale
	var p1r := mid + half * mid_scale
	var tip := base + up_dir * height + lean

	# Bias the normal toward the plant's own up so a clump shades as a mass
	# rather than flashing bright on whichever side faces the sun.
	var facing := side.cross(up_dir).normalized()
	if facing.length_squared() < 1e-6:
		facing = Vector3.BACK
	var nrm := (facing * 0.4 + up_dir * 0.6).normalized()

	var c0 := Color(wind_base, exp_base, petal)
	var c1 := Color(lerpf(wind_base, wind_tip, 0.55), lerpf(exp_base, exp_tip, 0.55), petal)
	var c2 := Color(wind_tip, exp_tip, petal)

	var pts: Array[Vector3] = [p0l, p1r, p0r, p0l, p1l, p1r, p1l, tip, p1r]
	var cols: Array[Color] = [c0, c1, c0, c0, c1, c1, c1, c2, c1]
	for i in pts.size():
		st.set_color(cols[i])
		st.set_normal(nrm)
		st.set_uv(Vector2(0.5, 1.0 - float(i) / 8.0))
		st.add_vertex(pts[i])


## Flat disc, for the centre of a daisy-shaped bloom.
static func _add_disc(st: SurfaceTool, centre: Vector3, radius: float, up_dir: Vector3,
		segs: int, wind: float, exposure: float, petal: float) -> void:
	var side := up_dir.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = up_dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var other := up_dir.cross(side).normalized()
	var col := Color(wind, exposure, petal)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := centre + (side * cos(a0) + other * sin(a0)) * radius
		var p1 := centre + (side * cos(a1) + other * sin(a1)) * radius
		for p in [centre, p1, p0]:
			st.set_color(col)
			st.set_normal(up_dir)
			st.set_uv(Vector2(0.5, 0.5))
			st.add_vertex(p)


static func _perp(dir: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = dir.cross(Vector3.RIGHT)
	return side.normalized().rotated(dir, rng.randf_range(0.0, TAU))


# ---------------------------------------------------------------------------
# grass and reeds
# ---------------------------------------------------------------------------

## A tuft of tapered blades rather than crossed quads.
##
## Crossed quads only work with an alpha-masked blade texture; untextured they
## read as painted cardboard, which is exactly what they look like. Real tapered
## geometry costs a few more vertices, needs no texture, stays in the opaque
## pass with no alpha test or sorting, and actually looks like grass.
static func grass_tuft(rng: RandomNumberGenerator, height: float = 0.44,
		width: float = 0.058, blades: int = 7) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in blades:
		var yaw := TAU * (float(i) / float(blades)) + rng.randf_range(-0.5, 0.5)
		var side := Vector3(cos(yaw), 0.0, sin(yaw))
		var lean_dir := Vector3(cos(yaw + PI * 0.5), 0.0, sin(yaw + PI * 0.5))
		var h := height * rng.randf_range(0.65, 1.0)
		var w := width * rng.randf_range(0.8, 1.2)
		_add_blade(st, side * rng.randf_range(0.0, width * 1.6), Vector3.UP, side,
				lean_dir * h * rng.randf_range(0.18, 0.45), h, w,
				0.15, 1.0, 0.25, 1.0)
	return _finish(st)


## Waterside reeds: tall, near-vertical, with a few seed heads. Much less lean
## than grass, because reeds hold themselves up.
static func reed(rng: RandomNumberGenerator, height: float = 1.5,
		blades: int = 11) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in blades:
		var yaw := TAU * (float(i) / float(blades)) + rng.randf_range(-0.4, 0.4)
		var side := Vector3(cos(yaw), 0.0, sin(yaw))
		var h := height * rng.randf_range(0.55, 1.0)
		var lean := side * h * rng.randf_range(0.05, 0.22)
		_add_blade(st, side * rng.randf_range(0.0, height * 0.05), Vector3.UP, side,
				lean, h, height * rng.randf_range(0.018, 0.030),
				0.1, 1.0, 0.3, 1.0)
		# A couple of the tallest stems carry a brown seed head.
		if i % 4 == 0 and h > height * 0.8:
			var top := side * 0.0 + Vector3.UP * h + lean
			_add_blade(st, top - Vector3.UP * height * 0.22, Vector3.UP, side,
					Vector3.ZERO, height * 0.26, height * 0.032,
					0.9, 1.0, 0.9, 1.0, 1.0, 1.45)
	return _finish(st)


## Forest-floor fern: fronds that leave the crown steeply, arch over, and fall
## away at the tip.
##
## The arch has to be integrated as a direction that rotates from up toward out
## and then down. Interpolating a height curve over a straight horizontal spoke
## instead -- which is the obvious way to write it -- produces fronds that lie
## almost flat on the ground and read as a puddle of leaves.
static func fern(rng: RandomNumberGenerator, size: float = 0.7,
		fronds: int = 6) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in fronds:
		var yaw := TAU * (float(f) / float(fronds)) + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var length := size * rng.randf_range(0.85, 1.15)
		var droop := rng.randf_range(0.35, 0.70)
		var steps := 8
		var step_len := length / float(steps)

		var start_dir := (Vector3.UP * 1.0 + out * 0.30).normalized()
		var end_dir := (out * 1.0 + Vector3.DOWN * droop).normalized()
		var node := Vector3.ZERO
		var prev := Vector3.ZERO

		for i in range(1, steps + 1):
			var t := float(i) / float(steps)
			# Hold the climb, then fall away late. A symmetric ease turns over
			# by the halfway point and the frond never gets off the ground.
			var k: float = pow(t, 1.7)
			var dir := start_dir.lerp(end_dir, k).normalized()
			prev = node
			node += dir * step_len
			if node.y < 0.02:
				break

			var pinna_len: float = length * 0.30 * (1.0 - t * 0.7)
			if pinna_len < 0.012:
				continue
			var tangent := (node - prev).normalized()
			var side := tangent.cross(Vector3.UP).normalized()
			if side.length_squared() < 1e-6:
				side = out
			var sides: PackedFloat32Array = [1.0, -1.0]
			for d in sides:
				var pinna_dir: Vector3 = (side * d * 0.92 + tangent * 0.30
						+ Vector3.UP * 0.22).normalized()
				_add_blade(st, node, pinna_dir, tangent,
						Vector3.DOWN * pinna_len * 0.22, pinna_len, pinna_len * 0.34,
						0.25 + t * 0.6, 0.4 + t * 0.6, 0.35 + t * 0.4, 0.6 + t * 0.4)
	return _finish(st)


# ---------------------------------------------------------------------------
# flowers
# ---------------------------------------------------------------------------

## Daisy shape: a slim stem, a couple of basal leaves, a ring of petals and a
## disc centre. The most recognisable "wildflower" silhouette there is.
static func flower_daisy(rng: RandomNumberGenerator, height: float = 0.30,
		petals: int = 9) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0.0,
			rng.randf_range(-0.12, 0.12)) * height
	var side := _perp(Vector3.UP, rng)

	_add_blade(st, Vector3.ZERO, Vector3.UP, side, lean, height, height * 0.035,
			0.1, 0.85, 0.3, 0.8)
	for i in 2:
		var lf := _perp(Vector3.UP, rng)
		_add_blade(st, Vector3.UP * height * 0.15, (lf * 0.8 + Vector3.UP * 0.5).normalized(),
				lf.cross(Vector3.UP).normalized(), Vector3.DOWN * height * 0.05,
				height * 0.30, height * 0.10, 0.2, 0.5, 0.2, 0.6)

	var head := Vector3.UP * height + lean
	var up := (Vector3.UP + lean.normalized() * 0.2).normalized()
	var pw := height * 0.085
	var ph := height * 0.26
	for i in petals:
		var a := TAU * float(i) / float(petals) + rng.randf_range(-0.08, 0.08)
		var radial := side.rotated(up, a)
		var petal_dir := (radial * 0.86 + up * 0.32).normalized()
		_add_blade(st, head + radial * height * 0.03, petal_dir,
				radial.cross(up).normalized(), Vector3.ZERO,
				ph * rng.randf_range(0.85, 1.15), pw, 0.9, 1.0, 0.85, 1.0, 1.0, 1.25)
	_add_disc(st, head + up * height * 0.012, height * 0.055, up, 8, 0.9, 1.0, 1.0)
	return _finish(st)


## Spike shape: a tall stem carrying many small blooms up its top half. Reads as
## lupine or foxglove and gives a meadow vertical accents.
static func flower_spike(rng: RandomNumberGenerator, height: float = 0.55,
		blooms: int = 16) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lean := Vector3(rng.randf_range(-0.10, 0.10), 0.0,
			rng.randf_range(-0.10, 0.10)) * height
	var side := _perp(Vector3.UP, rng)
	_add_blade(st, Vector3.ZERO, Vector3.UP, side, lean, height, height * 0.030,
			0.1, 0.9, 0.3, 0.9)
	for i in 3:
		var lf := _perp(Vector3.UP, rng)
		_add_blade(st, Vector3.UP * height * rng.randf_range(0.05, 0.28),
				(lf * 0.5 + Vector3.UP * 0.85).normalized(),
				lf.cross(Vector3.UP).normalized(), Vector3.ZERO,
				height * 0.34, height * 0.045, 0.2, 0.6, 0.2, 0.7)

	for i in blooms:
		var t: float = 0.52 + 0.46 * float(i) / float(blooms - 1)
		var a := TAU * 0.618 * float(i)   # golden angle, as on a real raceme
		var radial := side.rotated(Vector3.UP, a)
		var at := Vector3.UP * height * t + lean * t
		var w: float = height * 0.055 * (1.0 - t * 0.45)
		_add_blade(st, at + radial * height * 0.012,
				(radial * 0.75 + Vector3.UP * 0.35).normalized(),
				radial.cross(Vector3.UP).normalized(), Vector3.ZERO,
				height * 0.115 * (1.0 - t * 0.35), w,
				t, 1.0, 0.85, 1.0, 1.0, 1.2)
	return _finish(st)


## Cup shape: one big bloom of four or five broad petals on a bare stem. Poppy,
## buttercup, anemone -- the flower that reads from furthest away.
static func flower_poppy(rng: RandomNumberGenerator, height: float = 0.34,
		petals: int = 5) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lean := Vector3(rng.randf_range(-0.18, 0.18), 0.0,
			rng.randf_range(-0.18, 0.18)) * height
	var side := _perp(Vector3.UP, rng)
	_add_blade(st, Vector3.ZERO, Vector3.UP, side, lean, height, height * 0.040,
			0.1, 0.85, 0.3, 0.75)

	var head := Vector3.UP * height + lean
	var up := (Vector3.UP * 0.9 + lean.normalized() * 0.3).normalized()
	for i in petals:
		var a := TAU * float(i) / float(petals) + rng.randf_range(-0.12, 0.12)
		var radial := side.rotated(up, a)
		# Cupped: petals lean outward but keep a strong upward component.
		var petal_dir := (radial * 0.62 + up * 0.72).normalized()
		_add_blade(st, head, petal_dir, radial.cross(up).normalized(), Vector3.ZERO,
				height * 0.40 * rng.randf_range(0.85, 1.15), height * 0.30,
				0.85, 1.0, 0.8, 1.0, 1.0, 1.35)
	_add_disc(st, head + up * height * 0.02, height * 0.055, up, 8, 0.9, 0.35, 0.0)
	return _finish(st)
