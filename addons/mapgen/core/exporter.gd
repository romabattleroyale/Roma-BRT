@tool
class_name MapExporter
extends RefCounted
## Writes a generated map out for other tools, or back into Godot.
##
## Two very different jobs, and it is worth being clear about which is which:
##
##   glTF is for taking the map somewhere else -- Blender, Unreal, a DCC tool.
##   It carries geometry and simple PBR materials and nothing else, so the
##   custom shaders cannot come with it. Instead the terrain's colour is *baked*
##   to a texture, and the scatter is exported as prototype meshes plus a
##   transform manifest rather than as a few hundred thousand nodes.
##
##   A Godot scene is for using the map in a Godot project. It keeps the real
##   shaders and the MultiMesh instancing intact, and therefore depends on this
##   addon being present in the target project.


class Options extends RefCounted:
	var terrain := true
	var water := true
	var vegetation := true
	## Emit every scattered instance as its own node. Off by default: a map
	## carries six figures of instances and no DCC tool wants that as nodes.
	var bake_instances := false
	var max_baked_instances := 40000
	## Bake the terrain's shaded colour to a texture, since the splat shader
	## cannot travel with the glTF.
	var bake_terrain_texture := true
	var texture_size := 2048
	## Float heightmap in metres. The most portable thing this can produce --
	## every terrain tool in existence can read one.
	var write_heightmap := true
	var heightmap_size := 1024
	var write_manifest := true


class Report extends RefCounted:
	var files: PackedStringArray = []
	var warnings: PackedStringArray = []
	var meshes := 0
	var instances := 0
	var seconds := 0.0
	var ok := true

	func note(path: String) -> void:
		files.append(path)

	func warn(msg: String) -> void:
		warnings.append(msg)
		push_warning("[MapGen export] " + msg)

	func summary() -> String:
		var lines: Array[String] = []
		lines.append("%s in %.1f s" % ["Exported" if ok else "Export failed", seconds])
		lines.append("%d meshes, %d instances" % [meshes, instances])
		for f in files:
			lines.append("  " + f.get_file())
		for w in warnings:
			lines.append("  ! " + w)
		return "\n".join(lines)


# ---------------------------------------------------------------------------
# glTF
# ---------------------------------------------------------------------------

## Coroutine: the terrain colour bake has to wait on rendered frames, so callers
## must `await` this even when the bake is switched off.
static func export_gltf(gen: MapGenerator, dir_path: String, base_name: String,
		opts: Options = null) -> Report:
	var rep := Report.new()
	var t0 := Time.get_ticks_msec()
	if opts == null:
		opts = Options.new()
	if gen == null or gen.heightfield == null:
		rep.ok = false
		rep.warn("nothing generated yet")
		return rep
	if not _ensure_dir(dir_path):
		rep.ok = false
		rep.warn("could not create " + dir_path)
		return rep

	var hf: MapHeightfield = gen.heightfield
	var root := Node3D.new()
	root.name = base_name

	# --- terrain ---------------------------------------------------------
	var baked: Image = null
	if opts.terrain:
		if opts.bake_terrain_texture:
			baked = await bake_terrain_albedo(gen, opts.texture_size)
			if baked == null:
				rep.warn("terrain colour bake needs a rendering context; "
						+ "exporting terrain with a plain material instead")
		var tex_path := dir_path.path_join(base_name + "_terrain_albedo.png")
		var mat := StandardMaterial3D.new()
		if baked:
			baked.save_png(tex_path)
			rep.note(tex_path)
			var t := ImageTexture.create_from_image(baked)
			mat.albedo_texture = t
			# Terrain UVs are a world projection at 1/32 metres. Remap them so
			# the baked map covers the whole terrain exactly once.
			var k := 32.0 / hf.size_m
			mat.uv1_scale = Vector3(k, k, 1.0)
			mat.uv1_offset = Vector3(0.5, 0.5, 0.0)
		else:
			mat.albedo_color = Color(0.38, 0.40, 0.30)
		mat.roughness = 1.0

		var terrain_root := Node3D.new()
		terrain_root.name = "Terrain"
		root.add_child(terrain_root)
		for chunk in gen.find_children("Chunk_*", "MeshInstance3D", true, false):
			var mi := MeshInstance3D.new()
			mi.name = String(chunk.name)
			mi.mesh = (chunk as MeshInstance3D).mesh
			mi.material_override = mat
			terrain_root.add_child(mi)
			rep.meshes += 1

	# --- water -----------------------------------------------------------
	if opts.water and gen.settings.lake_enabled:
		var plane := PlaneMesh.new()
		plane.size = Vector2(hf.size_m, hf.size_m)
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(gen.settings.water_color_shallow.r,
				gen.settings.water_color_shallow.g, gen.settings.water_color_shallow.b, 0.72)
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.roughness = 0.06
		var wmi := MeshInstance3D.new()
		wmi.name = "Water"
		wmi.mesh = plane
		wmi.material_override = wm
		wmi.position = Vector3(0.0, hf.water_level, 0.0)
		root.add_child(wmi)
		rep.meshes += 1

		# Waterfall sheets are real geometry, so unlike the lake's shading they
		# survive the trip. They go out with a plain translucent material: the
		# flow is in a custom shader, and glTF has nowhere to put it.
		var falls := gen.find_children("Waterfall_*", "MeshInstance3D", true, false)
		if not falls.is_empty():
			var fm := StandardMaterial3D.new()
			fm.albedo_color = Color(0.93, 0.96, 0.98, 0.85)
			fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fm.cull_mode = BaseMaterial3D.CULL_DISABLED
			fm.roughness = 0.2
			var froot := Node3D.new()
			froot.name = "Waterfalls"
			root.add_child(froot)
			for fall_node in falls:
				var fmi := MeshInstance3D.new()
				fmi.name = String(fall_node.name)
				fmi.mesh = (fall_node as MeshInstance3D).mesh
				fmi.material_override = fm
				froot.add_child(fmi)
				rep.meshes += 1

	# --- scatter ---------------------------------------------------------
	var placements := read_placements(gen)
	if opts.vegetation:
		var protos := Node3D.new()
		protos.name = "Prototypes"
		root.add_child(protos)
		# Prototypes are parked clear of the terrain so they are easy to find
		# and easy to delete once the transforms have been used.
		var x := hf.size_m * 0.6
		for entry in _prototype_meshes(gen):
			var mi := MeshInstance3D.new()
			mi.name = entry.name
			mi.mesh = entry.mesh
			mi.position = Vector3(x, hf.max_h + 4.0, 0.0)
			protos.add_child(mi)
			rep.meshes += 1
			x += 6.0

		if opts.bake_instances:
			var baked_root := Node3D.new()
			baked_root.name = "Instances"
			root.add_child(baked_root)
			var budget := opts.max_baked_instances
			for species in placements:
				for item in placements[species]:
					if budget <= 0:
						break
					var mi := MeshInstance3D.new()
					mi.name = "%s_%d" % [species, budget]
					mi.mesh = item.mesh
					mi.transform = item.transform
					baked_root.add_child(mi)
					budget -= 1
					rep.instances += 1
			if budget <= 0:
				rep.warn("instance bake hit the %d cap; the rest are in the manifest"
						% opts.max_baked_instances)

	_own_all(root, root)

	# --- write -----------------------------------------------------------
	var glb := dir_path.path_join(base_name + ".glb")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, glb)
	if err == OK:
		rep.note(glb)
	else:
		rep.ok = false
		rep.warn("glTF write failed: " + error_string(err))

	if opts.write_heightmap:
		var exr := dir_path.path_join(base_name + "_height.exr")
		if write_heightmap_exr(hf, exr, opts.heightmap_size) == OK:
			rep.note(exr)
		else:
			rep.warn("heightmap write failed")

	if opts.write_manifest:
		var mf := dir_path.path_join(base_name + "_manifest.json")
		if write_manifest(gen, placements, mf) == OK:
			rep.note(mf)

	root.queue_free()
	rep.seconds = float(Time.get_ticks_msec() - t0) / 1000.0
	return rep


# ---------------------------------------------------------------------------
# Godot scene
# ---------------------------------------------------------------------------

## Packs the generated map as a Godot scene. The result keeps the real shaders
## and the MultiMesh instancing, so the target project needs this addon; that is
## the trade for not flattening 300k instances into nodes.
static func export_godot_scene(gen: MapGenerator, path: String) -> Report:
	var rep := Report.new()
	var t0 := Time.get_ticks_msec()
	if gen == null or gen.heightfield == null:
		rep.ok = false
		rep.warn("nothing generated yet")
		return rep
	if not _ensure_dir(path.get_base_dir()):
		rep.ok = false
		rep.warn("could not create " + path.get_base_dir())
		return rep

	var root := Node3D.new()
	root.name = "GeneratedMap"
	for child in gen.get_children():
		var copy := (child as Node).duplicate(
				Node.DUPLICATE_USE_INSTANTIATION | Node.DUPLICATE_SIGNALS)
		root.add_child(copy)
		if copy is MultiMeshInstance3D:
			rep.instances += (copy as MultiMeshInstance3D).multimesh.instance_count
		for mmi in copy.find_children("*", "MultiMeshInstance3D", true, false):
			rep.instances += (mmi as MultiMeshInstance3D).multimesh.instance_count
		rep.meshes += copy.find_children("*", "MeshInstance3D", true, false).size()

	# Everything must be owned by the root or PackedScene drops it silently.
	_own_all(root, root)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	if err == OK:
		rep.note(path)
	else:
		rep.ok = false
		rep.warn("scene save failed: " + error_string(err))

	root.queue_free()
	rep.seconds = float(Time.get_ticks_msec() - t0) / 1000.0
	return rep


# ---------------------------------------------------------------------------
# pieces
# ---------------------------------------------------------------------------

## Renders the terrain straight down with its shader in unlit-albedo mode, which
## gives a flat colour map with no lighting baked into it. Needs a rendering
## context, so it returns null under --headless.
static func bake_terrain_albedo(gen: MapGenerator, size: int) -> Image:
	var tree := gen.get_tree()
	if tree == null or RenderingServer.get_rendering_device() == null:
		return null
	var hf: MapHeightfield = gen.heightfield
	var chunks := gen.find_children("Chunk_*", "MeshInstance3D", true, false)
	if chunks.is_empty():
		return null

	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	# Linear tonemap and no post: EMISSION has to reach the buffer untouched or
	# the "flat colour" map comes out with a filmic curve baked into it.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	env.fog_enabled = false
	env.ssao_enabled = false
	env.sdfgi_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	for chunk in chunks:
		var src := chunk as MeshInstance3D
		var mi := MeshInstance3D.new()
		mi.mesh = src.mesh
		var mat := (src.material_override as ShaderMaterial).duplicate() as ShaderMaterial
		mat.set_shader_parameter("debug_view", 7)
		mi.material_override = mat
		vp.add_child(mi)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = hf.size_m
	cam.near = 0.5
	cam.far = (hf.max_h - hf.min_h) + 400.0
	cam.position = Vector3(0.0, hf.max_h + 200.0, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	vp.add_child(cam)

	gen.add_child(vp)
	for i in 4:
		await tree.process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()

	# The ortho camera looks down -Y with its up along -Z, so the capture comes
	# out mirrored in Z relative to world space.
	img.flip_y()
	img.convert(Image.FORMAT_RGB8)
	return img


## Float heightmap in metres. EXR because it is lossless, floating point, and
## every terrain tool reads it; a PNG would quantise a 250 m relief into steps.
static func write_heightmap_exr(hf: MapHeightfield, path: String, size: int) -> Error:
	var n: int = clampi(size, 32, 4096)
	var img := Image.create(n, n, false, Image.FORMAT_RF)
	var half := hf.size_m * 0.5
	for y in n:
		var wz := -half + hf.size_m * (float(y) + 0.5) / float(n)
		for x in n:
			var wx := -half + hf.size_m * (float(x) + 0.5) / float(n)
			var h := hf.height_at(wx, wz)
			img.set_pixel(x, y, Color(h, h, h))
	return img.save_exr(path, true)


## Every scattered instance, read back from the MultiMeshes.
## Returns { species_name: [ { transform, mesh } ] }.
static func read_placements(gen: MapGenerator) -> Dictionary:
	var out: Dictionary = {}
	for node in gen.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null or mm.instance_count == 0:
			continue
		# Node names are "<Species>_<chunk>_<variant>", optionally "_far".
		var species := String(mmi.name).get_slice("_", 0)
		if String(mmi.name).ends_with("_far"):
			continue    # the far LOD duplicates the near one's transforms
		if not out.has(species):
			out[species] = []
		for i in mm.instance_count:
			out[species].append({
				"transform": mmi.transform * mm.get_instance_transform(i),
				"mesh": mm.mesh,
			})
	return out


static func write_manifest(gen: MapGenerator, placements: Dictionary, path: String) -> Error:
	var hf: MapHeightfield = gen.heightfield
	var species: Dictionary = {}
	for name in placements:
		var rows: Array = []
		for item in placements[name]:
			var t: Transform3D = item.transform
			var sc := t.basis.get_scale()
			var e := t.basis.get_euler()
			rows.append({
				"pos": [snappedf(t.origin.x, 0.001), snappedf(t.origin.y, 0.001),
						snappedf(t.origin.z, 0.001)],
				"rot": [snappedf(e.x, 0.0001), snappedf(e.y, 0.0001), snappedf(e.z, 0.0001)],
				"scale": snappedf((sc.x + sc.y + sc.z) / 3.0, 0.001),
			})
		species[name] = rows

	# Where the water falls, for anything rebuilding the map elsewhere: the
	# ribbons are in the .glb, but the sites are what you need to place your
	# own spray, sound or particle system.
	var waterfalls: Array = []
	for f in gen.waterfalls:
		waterfalls.append({
			"lip": [snappedf(f.lip.x, 0.01), snappedf(f.lip.y, 0.01), snappedf(f.lip.z, 0.01)],
			"base": [snappedf(f.base.x, 0.01), snappedf(f.base.y, 0.01), snappedf(f.base.z, 0.01)],
			"drop": snappedf(f.drop, 0.01),
			"width": snappedf(f.width, 0.01),
		})

	var doc := {
		"format": "mapgen-manifest/1",
		"units": "metres",
		"axis": "Godot: +Y up, right-handed, -Z forward",
		"seed": gen.settings.seed,
		"map_size": hf.size_m,
		"height_range": [snappedf(hf.min_h, 0.01), snappedf(hf.max_h, 0.01)],
		"water_level": snappedf(hf.water_level, 0.01),
		"heightmap": {
			"file": path.get_file().replace("_manifest.json", "_height.exr"),
			"encoding": "float32 metres, red channel; pixel (0,0) is world "
					+ "(-size/2, -size/2), +x east, +y south",
		},
		"prototypes": "meshes named proto_<species>_<variant> in the .glb, parked "
				+ "clear of the terrain",
		"waterfalls": waterfalls,
		"species": species,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	return OK


static func _prototype_meshes(gen: MapGenerator) -> Array:
	var out: Array = []
	var seen: Array = []
	for node in gen.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		if String(mmi.name).ends_with("_far"):
			continue
		var mesh := mmi.multimesh.mesh
		if seen.has(mesh):
			continue
		seen.append(mesh)
		var parts := String(mmi.name).split("_")
		out.append({
			"name": "proto_%s_%s" % [parts[0], parts[parts.size() - 1]],
			"mesh": mesh,
		})
	return out


static func _own_all(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		_own_all(c, owner_node)


static func _ensure_dir(path: String) -> bool:
	if path.is_empty() or DirAccess.dir_exists_absolute(path):
		return true
	return DirAccess.make_dir_recursive_absolute(path) == OK
