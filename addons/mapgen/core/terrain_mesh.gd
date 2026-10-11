@tool
class_name MapTerrainMesh
extends RefCounted
## Turns a MapHeightfield into renderable chunks plus one collision body.
##
## Normals and the cheap cavity-AO term are sampled from the heightfield rather
## than from each chunk's own vertices, so chunk borders match exactly and you
## get no lighting seams.

const CHUNK_MARGIN := 0.001


static func build_chunks(hf: MapHeightfield, chunks_per_side: int, material: Material) -> Array:
	var out: Array = []
	var cps: int = clampi(chunks_per_side, 1, 32)
	# Every chunk must land on whole heightfield cells, otherwise its edge
	# vertices interpolate and the seams crack open.
	while cps > 1 and hf.res % cps != 0:
		cps -= 1

	var per := hf.res / cps
	var half := hf.size_m * 0.5

	for cz in cps:
		for cx in cps:
			var x0 := cx * per
			var z0 := cz * per
			var mesh := _build_chunk_mesh(hf, x0, z0, per)
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.mesh = mesh
			mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			# Chunks are built in world space, so the node itself sits at origin.
			mi.position = Vector3.ZERO
			out.append(mi)
	return out


static func _build_chunk_mesh(hf: MapHeightfield, x0: int, z0: int, per: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := hf.size_m * 0.5
	var stride := per + 1

	for lz in stride:
		var zi := z0 + lz
		var wz := -half + float(zi) * hf.cell
		for lx in stride:
			var xi := x0 + lx
			var wx := -half + float(xi) * hf.cell
			var h := hf.height_at_index(xi, zi)
			var n := hf.normal_at_index(xi, zi)

			st.set_normal(n)
			# UV is a plain world-space projection. The shader does its own
			# multi-scale tiling on top; this exists so tangents are well
			# defined for normal mapping.
			st.set_uv(Vector2(wx, wz) / 32.0)
			# r = canyon mask (strata tinting), g = cavity AO, b = free, a = free
			st.set_color(Color(
				hf.canyon[clampi(zi, 0, hf.dim - 1) * hf.dim + clampi(xi, 0, hf.dim - 1)],
				_cavity_ao(hf, xi, zi),
				0.0, 1.0))
			st.add_vertex(Vector3(wx, h, wz))

	for lz in per:
		for lx in per:
			var a := lz * stride + lx
			var b := a + 1
			var c := a + stride
			var d := c + 1
			# Flip the quad's diagonal on alternate cells so the triangulation
			# does not print a visible directional grain across the landscape.
			#
			# Winding note: Godot's front faces have (v1-v0) x (v2-v0) pointing
			# AWAY from the shading normal -- check PlaneMesh, whose up-facing
			# quad cross-products to -Y. Get this backwards and the terrain is
			# entirely backface-culled while still passing every vertex-count
			# and normal check, which looks like holes in the mesh.
			if (lx + lz) % 2 == 0:
				st.add_index(a); st.add_index(b); st.add_index(c)
				st.add_index(b); st.add_index(d); st.add_index(c)
			else:
				st.add_index(a); st.add_index(d); st.add_index(c)
				st.add_index(a); st.add_index(b); st.add_index(d)

	st.generate_tangents()
	return st.commit()


## Very cheap ambient occlusion: how far this vertex sits below the average of
## its wider neighbourhood. Darkens gullies, canyon floors and the base of
## cliffs. Costs nothing and reads as contact shadowing even without SSAO.
static func _cavity_ao(hf: MapHeightfield, xi: int, zi: int) -> float:
	var h := hf.height_at_index(xi, zi)
	var r := 4
	var avg := 0.0
	avg += hf.height_at_index(xi - r, zi)
	avg += hf.height_at_index(xi + r, zi)
	avg += hf.height_at_index(xi, zi - r)
	avg += hf.height_at_index(xi, zi + r)
	avg += hf.height_at_index(xi - r, zi - r)
	avg += hf.height_at_index(xi + r, zi + r)
	avg += hf.height_at_index(xi - r, zi + r)
	avg += hf.height_at_index(xi + r, zi - r)
	avg /= 8.0
	var rel := (h - avg) / maxf(hf.cell * float(r), 0.001)
	return clampf(0.5 + rel * 0.6, 0.0, 1.0)


static func build_collision(hf: MapHeightfield) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"

	var shape := HeightMapShape3D.new()
	shape.map_width = hf.dim
	shape.map_depth = hf.dim
	shape.map_data = hf.height

	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	# HeightMapShape3D uses one unit per sample, so stretch it out to the real
	# cell size. Y stays at 1 because map_data is already in metres.
	cs.scale = Vector3(hf.cell, 1.0, hf.cell)
	body.add_child(cs)
	return body
