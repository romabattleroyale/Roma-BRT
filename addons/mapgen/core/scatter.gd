@tool
class_name MapScatter
extends RefCounted
## Rule-based instancing onto the heightfield.
##
## The rules matter more than the meshes. Real vegetation is decided by slope,
## altitude, distance to water and clumping; an even random sprinkle is the
## single most recognisable "procedural" tell there is, so every species goes
## through a clump mask with real clearings.

const MAX_TOTAL_INSTANCES := 800000
## Distinct grown meshes per tree species.
const TREE_VARIANTS := 3
## Distinct grown meshes per rock species.
const ROCK_VARIANTS := 3


class Species extends RefCounted:
	var name := "species"
	var mesh: Mesh
	## Distinct meshes for the same species. A forest of one identical mesh is
	## obvious however much you jitter scale and rotation, so trees ship several
	## grown from different seeds and instances are split between them.
	var variants: Array[Mesh] = []
	## Optional cheaper meshes used past lod_distance. Must line up 1:1 with
	## `variants`.
	var variants_lod1: Array[Mesh] = []
	var lod_distance := 0.0
	var material: Material
	var density_per_km2 := 1000.0
	var min_slope := 0.0
	var max_slope := 30.0
	var min_alt := 0.0            ## normalised 0..1 over the map's relief
	var max_alt := 1.0
	var water_margin := 2.0       ## metres of dry ground kept above the waterline
	## Upper bound on height above the waterline. Reeds live in a band, not
	## everywhere that is merely "not underwater".
	var water_ceiling := INF
	## Only place within `shade_radius` of one of these species. Undergrowth
	## grows under a canopy, not in the middle of an open meadow.
	var shade_kinds: PackedStringArray = []
	var shade_radius := 7.0
	var scale_min := 0.85
	var scale_max := 1.35
	var align_to_normal := 0.0    ## 0 = grows straight up, 1 = lies on the slope
	var avoid_snow := 1.0
	var clump_bias := 1.0         ## 0 = ignores the clump mask entirely
	## Metres to sink the instance into the ground at scale 1. Rocks with a flat
	## base sit proud of uneven terrain and read as dropped; pushing them down a
	## little beds them in.
	var sink := 0.0
	var visibility_end := 0.0     ## 0 = always visible
	var cast_shadow := true
	## >0 makes this species solid: MapPropColliders will pool a cylinder
	## collider onto nearby instances so the player cannot walk through trunks.
	var collision_radius := 0.0
	var collision_height := 0.0


static func make_clump_noise(s: MapGenSettings) -> FastNoiseLite:
	var clump := FastNoiseLite.new()
	clump.seed = s.seed + 4001
	clump.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	clump.frequency = 1.0 / maxf(s.clump_scale, 1.0)
	clump.fractal_type = FastNoiseLite.FRACTAL_FBM
	clump.fractal_octaves = 3
	return clump


## Decides where one species goes and returns { chunk_index: Array[Transform3D] }.
##
## Placement walks a jittered grid rather than throwing darts at the whole map.
## Two reasons: the cost is exactly one rule evaluation per candidate instead of
## four-plus rejected throws, which is what makes ground-cover densities
## affordable at all; and a jittered grid is already blue-noise-ish, so you do
## not get the clumps-and-voids that uniform random sampling produces before the
## clump mask has even had a say.
##
## Kept separate from MultiMesh creation so the placement rules can be tested
## and so game code can reuse the same points -- to drop a collision capsule on
## every tree, or to spawn pickups only where the grass is.
static func place_species(hf: MapHeightfield, s: MapGenSettings, sp: Species,
		rng: RandomNumberGenerator, clump: FastNoiseLite, chunks_per_side: int,
		budget: int = MAX_TOTAL_INSTANCES, shade: MapPropField = null) -> Dictionary:
	var buckets: Dictionary = {}
	if sp.density_per_km2 <= 0.0:
		return buckets

	var half := hf.size_m * 0.5
	var cps: int = clampi(chunks_per_side, 1, 32)
	var chunk_m := hf.size_m / float(cps)

	# Grid spacing that yields the requested candidate density.
	var spacing: float = sqrt(1.0e6 / sp.density_per_km2)
	var cols: int = int(ceil(hf.size_m / maxf(spacing, 0.01)))
	# Never blow the instance budget, however extreme the density.
	while cols > 4 and cols * cols > budget:
		cols = int(float(cols) * 0.85)
	if cols < 1:
		return buckets
	spacing = hf.size_m / float(cols)

	var placed := 0
	for gz in cols:
		for gx in cols:
			if placed >= budget:
				break
			var wx := -half + (float(gx) + 0.5 + rng.randf_range(-0.5, 0.5)) * spacing
			var wz := -half + (float(gz) + 0.5 + rng.randf_range(-0.5, 0.5)) * spacing
			var h := hf.height_at(wx, wz)

			if h < hf.water_level + sp.water_margin:
				continue
			if h > hf.water_level + sp.water_ceiling:
				continue

			var alt := hf.normalised_height(h)
			if alt < sp.min_alt or alt > sp.max_alt:
				continue

			var nrm := hf.normal_at(wx, wz)
			var slope := rad_to_deg(acos(clampf(nrm.y, -1.0, 1.0)))
			if slope < sp.min_slope or slope > sp.max_slope:
				continue

			if sp.avoid_snow > 0.0:
				var snow := hf.snow_at(wx, wz, h, slope)
				if rng.randf() < snow * sp.avoid_snow:
					continue

			if not sp.shade_kinds.is_empty():
				if shade == null:
					continue
				var sheltered := false
				for idx in shade.query_near(Vector3(wx, h, wz), sp.shade_radius):
					if sp.shade_kinds.has(shade.kind_names[shade.kinds[idx]]):
						sheltered = true
						break
				if not sheltered:
					continue

			if sp.clump_bias > 0.0 and s.clump_contrast > 0.0:
				var c := clump.get_noise_2d(wx, wz) * 0.5 + 0.5
				# clump_contrast pushes the mask toward hard forest / hard clearing.
				var p := lerpf(1.0, smoothstep(0.35, 0.75, c), s.clump_contrast * sp.clump_bias)
				if rng.randf() > p:
					continue

			# --- accepted -------------------------------------------------
			var up := Vector3.UP.lerp(nrm, sp.align_to_normal).normalized()
			var sc := rng.randf_range(sp.scale_min, sp.scale_max)
			var basis := Basis(Quaternion(Vector3.UP, up)) \
					* Basis(Vector3.UP, rng.randf_range(0.0, TAU))
			basis = basis.scaled(Vector3.ONE * sc)
			h -= sp.sink * sc

			var cx: int = clampi(int((wx + half) / chunk_m), 0, cps - 1)
			var cz: int = clampi(int((wz + half) / chunk_m), 0, cps - 1)
			var key := cz * cps + cx
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(Transform3D(basis, Vector3(wx, h, wz)))
			placed += 1

	return buckets


## Builds the MultiMesh nodes and, alongside them, a MapPropField describing
## every instance that should be solid. Returns { instances: Array, props: MapPropField }.
static func scatter(hf: MapHeightfield, s: MapGenSettings, species_list: Array,
		chunks_per_side: int) -> Dictionary:
	var out: Array = []
	var props := MapPropField.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = s.seed * 7919 + 13
	var clump := make_clump_noise(s)
	var budget := MAX_TOTAL_INSTANCES

	# Two passes. Species that seek shade need to know where the canopy ended up,
	# and the canopy is itself part of the scatter, so everything that stands on
	# its own goes down first and the undergrowth follows.
	var ordered: Array = []
	var shaded: Array = []
	for sp in species_list:
		if (sp.mesh == null and sp.variants.is_empty()) or sp.density_per_km2 <= 0.0:
			continue
		if sp.shade_kinds.is_empty():
			ordered.append(sp)
		else:
			shaded.append(sp)

	for pass_index in 2:
		if pass_index == 1:
			if shaded.is_empty():
				break
			# The index has to exist before anything can query it.
			props.build_index()
			ordered = shaded

		for sp in ordered:
			var buckets := place_species(hf, s, sp, rng, clump, chunks_per_side,
					budget, props if pass_index == 1 else null)

			var meshes: Array = sp.variants if not sp.variants.is_empty() else [sp.mesh]
			var lods: Array = sp.variants_lod1 if sp.variants_lod1.size() == meshes.size() else []

			for key in buckets:
				var list: Array = buckets[key]
				budget -= list.size()

				# Split the bucket between mesh variants. Instancing efficiency drops
				# by the variant count, but a forest where every tree is the same
				# model is the thing people notice first.
				var per_variant: Array = []
				for v in meshes.size():
					per_variant.append([])
				for i in list.size():
					per_variant[i % meshes.size()].append(list[i])

				for v in meshes.size():
					var slice: Array = per_variant[v]
					if slice.is_empty():
						continue
					var custom := PackedColorArray()
					for i in slice.size():
						custom.append(Color(rng.randf(), rng.randf(), 0.0, 0.0))
					var mm := _make_multimesh(meshes[v], slice, custom)
					var kind := props.kind_id(sp.name)
					for xf in slice:
						if sp.collision_radius > 0.0:
							var scale: float = (xf as Transform3D).basis.get_scale().y
							props.add((xf as Transform3D).origin, sp.collision_radius * scale,
									sp.collision_height * scale, kind)

					var near := _make_instance(mm, sp, hf, "%s_%d_%d" % [sp.name, key, v], slice)
					if not lods.is_empty() and sp.lod_distance > 0.0:
						near.visibility_range_end = sp.lod_distance
						near.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
						var far_mm := _make_multimesh(lods[v], slice, custom)
						var far_mmi := _make_instance(far_mm, sp, hf,
								"%s_%d_%d_far" % [sp.name, key, v], slice)
						far_mmi.visibility_range_begin = sp.lod_distance
						far_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
						out.append(far_mmi)
					out.append(near)

	props.build_index()
	return {"instances": out, "props": props}


static func _make_multimesh(mesh: Mesh, list: Array, custom: PackedColorArray) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i])
		# r = wind phase, g = colour variation. Generated up front rather than
		# read back off the near LOD, so the far LOD gets identical values and
		# a tree does not change colour when it swaps.
		mm.set_instance_custom_data(i, custom[i])
	return mm


static func _make_instance(mm: MultiMesh, sp: Species, hf: MapHeightfield,
		node_name: String, list: Array) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	# Trees carry per-surface materials on the mesh itself: material_override
	# would replace bark and leaves with one shader.
	if sp.material:
		mmi.material_override = sp.material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sp.cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Bounds of THIS bucket, not of the whole map. visibility_range measures to
	# the instance's AABB, so a map-sized AABB culls every ranged species the
	# moment the camera leaves the map centre.
	mmi.custom_aabb = _bucket_bounds(list, mm.mesh)
	if sp.visibility_end > 0.0:
		# Cull just past where the shader has already shrunk the mesh to
		# nothing, so the hard cut is invisible. FADE_SELF is wrong here: it
		# needs a transparent material and these shaders are opaque.
		mmi.visibility_range_end = sp.visibility_end * 1.08
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	return mmi


static func _bucket_bounds(list: Array, mesh: Mesh) -> AABB:
	var mesh_aabb := mesh.get_aabb()
	var bounds := AABB()
	for i in list.size():
		var inst: AABB = (list[i] as Transform3D) * mesh_aabb
		bounds = inst if i == 0 else bounds.merge(inst)
	return bounds


## The default biome: conifers up high, broadleaf and bushes lower, grass in
## the flats, boulders on the scree. Tweak or replace wholesale from your own
## code -- this is just a sensible starting palette.
static func default_species(s: MapGenSettings, hf: MapHeightfield) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = s.seed + 991
	var list: Array = []

	# --- conifer -------------------------------------------------------
	var conifer := Species.new()
	conifer.name = "Conifer"
	var conifer_bark := MapMaterials.build_bark_material(s, hf, "conifer", 0.22)
	# fade_end 0: no distance shrink on tree foliage. Shrinking works for ground
	# cover, where the alternative is popping, but on a tree it strips the leaves
	# off and leaves a bare stick standing -- far worse than the full mesh. Cost
	# at distance is handled by the LOD swap instead.
	var conifer_needles := MapMaterials.build_needle_material(
			s, hf, Color(1.02, 1.06, 0.84), Color(0.74, 0.86, 0.66), 0.0, 0.45)
	for v in TREE_VARIANTS:
		var p := MapTreeBuilder.conifer_profile(rng.randf_range(9.0, 16.0))
		var seed_v := rng.randi()
		conifer.variants.append(_grow_tree(p, seed_v, conifer_bark, conifer_needles, false))
		conifer.variants_lod1.append(_grow_tree(p, seed_v, conifer_bark, conifer_needles, true))
	conifer.lod_distance = 60.0
	conifer.density_per_km2 = s.tree_density * 0.55
	conifer.max_slope = s.tree_max_slope
	conifer.min_alt = 0.18
	conifer.max_alt = s.tree_line
	conifer.water_margin = s.tree_water_margin
	conifer.scale_min = 0.7
	conifer.scale_max = 1.35
	conifer.align_to_normal = 0.10
	conifer.collision_radius = 0.45
	conifer.collision_height = 5.0
	list.append(conifer)

	# --- broadleaf -----------------------------------------------------
	var broad := Species.new()
	broad.name = "Broadleaf"
	var broad_bark := MapMaterials.build_bark_material(s, hf, "broadleaf", 0.30)
	var broad_leaves := MapMaterials.build_leaf_material(
			s, hf, Color(0.98, 1.02, 0.70), Color(0.70, 0.84, 0.60), 0.0, 0.55, 0.045)
	for v in TREE_VARIANTS:
		var p := MapTreeBuilder.broadleaf_profile(rng.randf_range(6.5, 11.0))
		var seed_v := rng.randi()
		broad.variants.append(_grow_tree(p, seed_v, broad_bark, broad_leaves, false))
		broad.variants_lod1.append(_grow_tree(p, seed_v, broad_bark, broad_leaves, true))
	broad.lod_distance = 55.0
	broad.density_per_km2 = s.tree_density * 0.45
	broad.max_slope = s.tree_max_slope * 0.85
	broad.min_alt = 0.05
	broad.max_alt = s.tree_line * 0.72
	broad.water_margin = s.tree_water_margin
	broad.scale_min = 0.75
	broad.scale_max = 1.45
	broad.align_to_normal = 0.13
	broad.collision_radius = 0.45
	broad.collision_height = 4.0
	list.append(broad)

	# --- undergrowth ---------------------------------------------------
	var bushes := Species.new()
	bushes.name = "Bush"
	var shrub_bark := MapMaterials.build_bark_material(s, hf, "broadleaf", 0.5)
	# Shrubs are small enough that a bare stem at distance is invisible, so they
	# keep the shrink -- it is what stops a hard pop at the cull distance.
	var shrub_leaves := MapMaterials.build_leaf_material(
			s, hf, Color(0.90, 0.98, 0.62), Color(0.58, 0.74, 0.50), 210.0, 0.9, 0.06)
	for v in TREE_VARIANTS:
		var sp_profile := MapTreeBuilder.shrub_profile(rng.randf_range(1.1, 2.2))
		bushes.variants.append(_grow_tree(sp_profile, rng.randi(), shrub_bark, shrub_leaves, false))
	bushes.density_per_km2 = s.tree_density * 1.1
	bushes.max_slope = s.tree_max_slope + 8.0
	bushes.max_alt = s.tree_line + 0.08
	bushes.water_margin = s.tree_water_margin * 0.4
	bushes.align_to_normal = 0.5
	bushes.visibility_end = 220.0
	bushes.cast_shadow = false
	list.append(bushes)

	# --- ground cover --------------------------------------------------
	var grass := Species.new()
	grass.name = "Grass"
	grass.mesh = MapVegetation.grass_tuft(rng, 0.44, 0.058, 7)
	grass.material = MapMaterials.build_flora_material(
			s, hf, Color(0.15, 0.23, 0.09), Color(0.46, 0.54, 0.22), 0.44, 1.0, 78.0)
	grass.density_per_km2 = s.grass_density
	grass.max_slope = 34.0
	grass.max_alt = s.tree_line + 0.05
	grass.water_margin = 0.4
	grass.scale_min = 0.7
	grass.scale_max = 1.55
	grass.align_to_normal = 0.85
	grass.clump_bias = 0.35
	grass.visibility_end = 78.0
	grass.cast_shadow = false
	list.append(grass)

	# Ferns only under a canopy. This is the payoff for placing undergrowth in a
	# second pass: it can see where the trees actually landed, so the forest
	# floor differs from the meadow instead of being the same scatter twice.
	var ferns := Species.new()
	ferns.name = "Fern"
	for v in 2:
		ferns.variants.append(MapVegetation.fern(rng, rng.randf_range(0.75, 1.20), 6))
	ferns.material = MapMaterials.build_flora_material(
			s, hf, Color(0.13, 0.24, 0.10), Color(0.38, 0.52, 0.22), 0.8, 0.8, 95.0)
	ferns.density_per_km2 = s.grass_density * 0.055
	ferns.max_slope = 31.0
	ferns.max_alt = s.tree_line
	ferns.water_margin = 1.0
	ferns.scale_min = 0.7
	ferns.scale_max = 1.6
	ferns.align_to_normal = 0.6
	ferns.clump_bias = 0.5
	ferns.shade_kinds = PackedStringArray(["Conifer", "Broadleaf"])
	ferns.shade_radius = 7.0
	ferns.visibility_end = 95.0
	ferns.cast_shadow = false
	list.append(ferns)

	# Reeds live in a band at the waterline: a negative margin lets them stand
	# in the shallows, and the ceiling keeps them off the bank.
	var reeds := Species.new()
	reeds.name = "Reed"
	for v in 2:
		reeds.variants.append(MapVegetation.reed(rng, rng.randf_range(1.1, 1.9), 11))
	reeds.material = MapMaterials.build_flora_material(
			s, hf, Color(0.20, 0.26, 0.10), Color(0.55, 0.58, 0.26), 1.5, 1.2, 130.0,
			Color(0.42, 0.30, 0.14), Color(0.55, 0.42, 0.20))
	reeds.density_per_km2 = s.grass_density * 0.10
	reeds.max_slope = 17.0
	reeds.water_margin = -0.7
	reeds.water_ceiling = 1.9
	reeds.scale_min = 0.7
	reeds.scale_max = 1.5
	reeds.align_to_normal = 0.25
	reeds.clump_bias = 1.0
	reeds.visibility_end = 130.0
	reeds.cast_shadow = false
	list.append(reeds)

	# Flowers: three shapes, each with its own colour range baked onto its mesh
	# so one species covers daisies, spikes and poppies. Clumped hard, because
	# wildflowers come in drifts.
	var flowers := Species.new()
	flowers.name = "Flower"
	var blooms := [
		[MapVegetation.flower_daisy(rng, rng.randf_range(0.24, 0.38), 9),
			Color(0.96, 0.95, 0.90), Color(0.97, 0.87, 0.35)],
		[MapVegetation.flower_spike(rng, rng.randf_range(0.45, 0.70), 16),
			Color(0.56, 0.36, 0.74), Color(0.38, 0.46, 0.82)],
		[MapVegetation.flower_poppy(rng, rng.randf_range(0.26, 0.42), 5),
			Color(0.62, 0.13, 0.10), Color(0.74, 0.38, 0.09)],
	]
	for entry in blooms:
		var mesh: ArrayMesh = entry[0]
		mesh.surface_set_material(0, MapMaterials.build_flora_material(
				s, hf, Color(0.16, 0.25, 0.10), Color(0.42, 0.52, 0.20), 0.4, 1.1, 85.0,
				entry[1], entry[2]))
		flowers.variants.append(mesh)
	flowers.density_per_km2 = s.grass_density * 0.14
	flowers.max_slope = 27.0
	flowers.min_alt = 0.02
	flowers.max_alt = s.tree_line * 0.9
	flowers.water_margin = 1.0
	flowers.scale_min = 0.75
	flowers.scale_max = 1.5
	flowers.align_to_normal = 0.5
	flowers.clump_bias = 1.0
	flowers.visibility_end = 85.0
	flowers.cast_shadow = false
	list.append(flowers)

	# --- rock ----------------------------------------------------------
	# One shared material: the shader varies colour per instance and per vertex,
	# so every rock on the map can come off the same shader without reading as
	# the same rock.
	var rock_mat := MapMaterials.build_rock_material(s, hf)
	var rock_rng := RandomNumberGenerator.new()
	rock_rng.seed = s.seed + 5501

	var boulders := Species.new()
	boulders.name = "Boulder"
	for v in ROCK_VARIANTS:
		boulders.variants.append(MapRockBuilder.build(
				MapRockBuilder.boulder_profile(rock_rng.randf_range(1.3, 2.6)),
				rock_rng, rock_mat))
	boulders.density_per_km2 = s.rock_density * 1.15
	boulders.max_slope = 48.0
	boulders.water_margin = -6.0    # boulders are happy half-submerged
	boulders.scale_min = 0.5
	boulders.scale_max = 1.7
	boulders.align_to_normal = 0.55
	boulders.sink = 0.18
	boulders.avoid_snow = 0.25
	# Boulders come in fields -- a glacial drop, the run-out below a crag --
	# not evenly spaced across a meadow, so cluster them hard.
	boulders.clump_bias = 0.95
	boulders.collision_radius = 0.55
	boulders.collision_height = 1.4
	list.append(boulders)

	# Talus: small angular debris that collects on steep ground. Heavily
	# clumped, because scree comes in fields below a crag, not sprinkled evenly.
	var scree := Species.new()
	scree.name = "Scree"
	for v in ROCK_VARIANTS:
		scree.variants.append(MapRockBuilder.build(
				MapRockBuilder.angular_profile(rock_rng.randf_range(0.55, 1.15)),
				rock_rng, rock_mat))
	scree.density_per_km2 = s.rock_density * 3.2
	scree.min_slope = 19.0
	scree.max_slope = 54.0
	scree.water_margin = 0.5
	scree.scale_min = 0.35
	scree.scale_max = 1.35
	scree.align_to_normal = 0.9
	scree.sink = 0.10
	scree.avoid_snow = 0.15
	scree.clump_bias = 1.0
	scree.visibility_end = 170.0
	list.append(scree)

	# Outcrops: big blocky stone breaking out of steep upper ground. Low
	# density, high impact -- they give a bare slope something to read against.
	var outcrop := Species.new()
	outcrop.name = "Outcrop"
	for v in ROCK_VARIANTS:
		var prof := MapRockBuilder.outcrop_profile(rock_rng.randf_range(3.0, 5.5)) if v != 1 \
				else MapRockBuilder.slab_profile(rock_rng.randf_range(3.5, 6.0))
		outcrop.variants.append(MapRockBuilder.build(prof, rock_rng, rock_mat))
	outcrop.density_per_km2 = s.rock_density * 0.22
	outcrop.min_slope = 7.0
	outcrop.max_slope = 56.0
	outcrop.min_alt = 0.22
	outcrop.water_margin = 1.0
	outcrop.scale_min = 0.7
	outcrop.scale_max = 1.8
	outcrop.align_to_normal = 0.35
	outcrop.sink = 0.45
	outcrop.avoid_snow = 0.1
	outcrop.clump_bias = 0.6
	outcrop.collision_radius = 1.5
	outcrop.collision_height = 3.0
	list.append(outcrop)

	return list


## Grows one tree. The LOD pair shares a seed so both meshes describe the same
## tree: same trunk, same limbs, only the tessellation and leaf count differ.
static func _grow_tree(p: MapTreeBuilder.TreeProfile, tree_seed: int,
		bark: Material, foliage: Material, low_detail: bool) -> ArrayMesh:
	var trng := RandomNumberGenerator.new()
	trng.seed = tree_seed
	if low_detail:
		p = _reduce(p)
	return MapTreeBuilder.build(p, trng, bark, foliage)


## Far-LOD profile. Segment counts are deliberately untouched: they drive the
## random walk that shapes each branch, so changing them would grow a visibly
## different tree and the LOD swap would pop.
static func _reduce(src: MapTreeBuilder.TreeProfile) -> MapTreeBuilder.TreeProfile:
	var p := MapTreeBuilder.TreeProfile.new()
	for prop in ["name", "height", "trunk_radius", "radius_ratio", "length_ratio",
			"levels", "children", "child_start", "child_end", "child_angle",
			"child_angle_var", "angle_by_height", "curve_up", "gnarl", "trunk_lean",
			"whorls", "sides_by_level", "segs_by_level", "conifer", "leaf_w", "leaf_h",
			"leaves_per_tip", "leaf_spread", "foliage_from_level", "bark_tile"]:
		p.set(prop, src.get(prop))
	var sides := PackedInt32Array()
	for n in src.sides_by_level:
		sides.append(maxi(3, int(n * 0.6)))
	p.sides_by_level = sides
	p.leaves_per_tip = maxi(3, int(src.leaves_per_tip * 0.45))
	# Fewer, larger cards keep roughly the same canopy density on screen.
	p.leaf_w = src.leaf_w * 1.5
	p.leaf_h = src.leaf_h * 1.5
	return p
