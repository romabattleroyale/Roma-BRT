@tool
class_name MapGenerator
extends Node3D
## Drop this node into a scene, tick the features you want, press Generate.
##
## Generated nodes are deliberately NOT owned by the edited scene unless you
## turn on settings.bake_into_scene, so a 100k-instance map never ends up
## serialised into your .tscn. Regenerate at load time instead: it is
## deterministic from the seed.

signal generation_started()
signal generation_finished(heightfield: MapHeightfield, seconds: float)

@export var settings: MapGenSettings:
	set(value):
		settings = value
		update_configuration_warnings()

@export_tool_button("Generate", "Reload") var _act_generate := generate
@export_tool_button("New seed + Generate", "RandomNumberGenerator") var _act_reseed := reseed_and_generate
@export_tool_button("Clear", "Remove") var _act_clear := clear_generated

@export_group("Mesh overrides")
## Assign real CC0 models here to replace the built-in placeholder geometry.
@export var conifer_mesh_override: Mesh
@export var broadleaf_mesh_override: Mesh
@export var bush_mesh_override: Mesh
@export var grass_mesh_override: Mesh
@export var boulder_mesh_override: Mesh

@export_group("Runtime")
## Generate on _ready() in the running game as well as in the editor.
@export var generate_on_ready: bool = false

var heightfield: MapHeightfield
## Solid instances (tree trunks, boulders) from the last generate(), indexed
## spatially. Hand this to a MapPropColliders node to make them walk-into-able.
var prop_field: MapPropField
## Instances actually placed on the last generate(), per species name.
var scatter_counts: Dictionary = {}
## The sky built for the last generate(). Ask it for the time of day, the
## daylight level, the eclipse state or the moons.
var sky: MapSky
## Drainage from the last generate(), or null when waterfalls are off: it is
## only computed when something asks for it. Useful on its own for anything
## that wants to know where the water goes.
var flow: MapFlow
## MapWaterfalls.Fall for each fall placed on the last generate().
var waterfalls: Array = []

const _GENERATED_META := "mapgen_generated"


func _ready() -> void:
	if generate_on_ready and not Engine.is_editor_hint():
		generate()


func _get_configuration_warnings() -> PackedStringArray:
	if settings == null:
		return PackedStringArray(["Assign a MapGenSettings resource to generate a map."])
	return PackedStringArray()


# ---------------------------------------------------------------------------
# public API
# ---------------------------------------------------------------------------

func reseed_and_generate() -> void:
	if settings == null:
		settings = MapGenSettings.new()
	settings.seed = randi()
	generate()


func clear_generated() -> void:
	for child in get_children():
		if child.has_meta(_GENERATED_META):
			remove_child(child)
			child.queue_free()
	heightfield = null


func generate() -> void:
	if settings == null:
		settings = MapGenSettings.new()
	generation_started.emit()
	var t0 := Time.get_ticks_msec()

	clear_generated()
	sky = null
	flow = null
	prop_field = null
	scatter_counts.clear()
	waterfalls.clear()

	var hf := MapHeightfield.new()
	hf.generate(settings)
	heightfield = hf

	_build_terrain(hf)
	if settings.lake_enabled:
		_build_water(hf)
	if settings.waterfall_enabled and settings.waterfall_count > 0:
		_build_waterfalls(hf)
	if settings.vegetation_enabled:
		_build_vegetation(hf)
	_build_atmosphere(hf)

	if settings.bake_into_scene:
		_claim_ownership()

	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	generation_finished.emit(hf, secs)


## Ground height in metres at a world XZ. Cheaper and more reliable than a
## raycast for placing units, props or a spawn point.
func sample_height(world_x: float, world_z: float) -> float:
	return heightfield.height_at(world_x, world_z) if heightfield else 0.0


func sample_normal(world_x: float, world_z: float) -> Vector3:
	return heightfield.normal_at(world_x, world_z) if heightfield else Vector3.UP


func sample_slope_degrees(world_x: float, world_z: float) -> float:
	return heightfield.slope_at(world_x, world_z) if heightfield else 0.0


## Total instances placed on the last generate(), across all species.
func total_instances() -> int:
	var n := 0
	for k in scatter_counts:
		n += int(scatter_counts[k])
	return n


## Falls placed on the last generate(). Fewer than settings.waterfall_count
## when the terrain had fewer places that qualified.
func waterfall_count() -> int:
	return waterfalls.size()


func get_water_level() -> float:
	return heightfield.water_level if heightfield else 0.0


func is_underwater(world_pos: Vector3) -> bool:
	return heightfield != null and world_pos.y < heightfield.water_level


## A random point that satisfies the usual "can something stand here" rules.
## Returns Vector3.INF if it could not find one, so callers can fail loudly.
##
## `clearance` keeps the point away from solid props. Without it a spawn lands
## inside a tree trunk about as often as the forest is dense, which is both a
## bad camera and a stuck player.
func find_spawn_point(max_slope_deg: float = 20.0, margin_above_water: float = 2.0,
		attempts: int = 200, rng_seed: int = 0, clearance: float = 3.0) -> Vector3:
	if heightfield == null:
		return Vector3.INF
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed if rng_seed != 0 else settings.seed
	var half := heightfield.size_m * 0.48
	var relaxed := Vector3.INF
	for _i in attempts:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var h := heightfield.height_at(x, z)
		if h < heightfield.water_level + margin_above_water:
			continue
		if heightfield.slope_at(x, z) > max_slope_deg:
			continue
		var here := Vector3(x, h, z)
		if clearance > 0.0 and prop_field != null and prop_field.size() > 0:
			if not prop_field.query_near(here, clearance).is_empty():
				# Remember it in case nothing clear turns up at all.
				if relaxed == Vector3.INF:
					relaxed = here
				continue
		return here
	return relaxed


# ---------------------------------------------------------------------------
# build steps
# ---------------------------------------------------------------------------

func _new_container(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.set_meta(_GENERATED_META, true)
	add_child(n)
	return n


func _build_terrain(hf: MapHeightfield) -> void:
	var root := _new_container("Terrain")
	var mat := MapMaterials.build_terrain_material(settings, hf)
	for chunk in MapTerrainMesh.build_chunks(hf, settings.chunks_per_side, mat):
		root.add_child(chunk)
	if settings.generate_collision:
		root.add_child(MapTerrainMesh.build_collision(hf))


func _build_water(hf: MapHeightfield) -> void:
	var root := _new_container("WaterBody")
	root.add_child(MapWater.build(hf, settings, MapMaterials.build_water_material(settings)))


## Waterfalls come after the water plane and before the planting, so the
## drainage is available to anything later that wants it.
func _build_waterfalls(hf: MapHeightfield) -> void:
	flow = MapFlow.build(hf)
	waterfalls = MapWaterfalls.find_sites(hf, settings, flow)
	if waterfalls.is_empty():
		return
	var root := _new_container("Waterfalls")
	var mat := MapMaterials.build_waterfall_material(settings)
	for node in MapWaterfalls.build(hf, settings, flow, waterfalls, mat):
		root.add_child(node)


func _build_vegetation(hf: MapHeightfield) -> void:
	var root := _new_container("Vegetation")
	var species := MapScatter.default_species(settings, hf)
	var overrides := {
		"Conifer": conifer_mesh_override,
		"Broadleaf": broadleaf_mesh_override,
		"Bush": bush_mesh_override,
		"Grass": grass_mesh_override,
		"Boulder": boulder_mesh_override,
	}
	for sp in species:
		if overrides.has(sp.name) and overrides[sp.name] != null:
			sp.mesh = overrides[sp.name]
			# A supplied model brings its own materials and replaces every grown
			# variant, so clear those or the override would only apply to a third
			# of the instances.
			sp.variants = []
			sp.variants_lod1 = []
			sp.material = null
	var result := MapScatter.scatter(hf, settings, species, settings.chunks_per_side)
	scatter_counts.clear()
	for mmi in result.instances:
		root.add_child(mmi)
		var base: String = String(mmi.name).get_slice("_", 0)
		scatter_counts[base] = int(scatter_counts.get(base, 0)) + mmi.multimesh.instance_count
	prop_field = result.props


func _build_atmosphere(hf: MapHeightfield) -> void:
	var root := _new_container("Sky")
	sky = MapSky.new()
	root.add_child(sky)
	sky.setup(settings, hf)
	# An animating sky in the editor forces a redraw every frame for something
	# nobody is watching, so the clock only runs in a running game.
	if Engine.is_editor_hint():
		sky.paused = true


## Only called when bake_into_scene is on: makes generated nodes part of the
## saved scene file.
func _claim_ownership() -> void:
	var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	if scene_root == null:
		scene_root = self
	for child in get_children():
		if child.has_meta(_GENERATED_META):
			_set_owner_recursive(child, scene_root)


func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	node.owner = new_owner
	for c in node.get_children():
		_set_owner_recursive(c, new_owner)
