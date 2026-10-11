extends Node3D
## Cerchio della tempesta: anello visivo che si restringe nel tempo.
@export var initial_radius: float = 900.0
@export var final_radius: float = 35.0
@export var shrink_duration: float = 900.0
@export var start_delay: float = 15.0
@export var ring_height: float = 2.5
var elapsed := 0.0
var ring: MeshInstance3D
var map: Node3D

func _ready() -> void:
	map = get_parent().get_node_or_null("MapGenerator")
	var torus := TorusMesh.new()
	torus.inner_radius = initial_radius - 2.0
	torus.outer_radius = initial_radius + 2.0
	torus.rings = 96
	torus.ring_segments = 8
	ring = MeshInstance3D.new()
	ring.name = "StormBoundaryVisual"
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.15, 0.75, 1.0, 0.9)
	material.emission_enabled = true
	material.emission = Color(0.05, 0.35, 1.0)
	material.emission_energy_multiplier = 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = material
	add_child(ring)
	global_position = Vector3(1000.0, ring_height, 1000.0)

func _process(delta: float) -> void:
	elapsed += delta
	var progress := clampf((elapsed - start_delay) / maxf(shrink_duration, 1.0), 0.0, 1.0)
	var radius := lerpf(initial_radius, final_radius, progress)
	if ring and ring.mesh is TorusMesh:
		var torus := ring.mesh as TorusMesh
		torus.inner_radius = maxf(1.0, radius - 2.0)
		torus.outer_radius = radius + 2.0
	if map and map.has_method("sample_height"):
		global_position.y = float(map.call("sample_height", 1000.0, 1000.0)) + ring_height
