extends Node3D
## Storm circle for Roma BRT: visible boundary, shrinking radius and safe-zone query.
@export var center_x: float = 1000.0
@export var center_z: float = 1000.0
@export var start_radius: float = 900.0
@export var final_radius: float = 35.0
@export var delay_seconds: float = 15.0
@export var shrink_seconds: float = 900.0
@export var ring_height: float = 3.0
@export var ring_thickness: float = 2.0
var elapsed: float = 0.0
var current_radius: float = 900.0
var ring: MeshInstance3D
var material: StandardMaterial3D

func _ready() -> void:
	current_radius = start_radius
	var torus := TorusMesh.new()
	torus.inner_radius = 0.985
	torus.outer_radius = 1.0
	torus.rings = 96
	torus.ring_segments = 8
	ring = MeshInstance3D.new()
	ring.name = "StormBoundary"
	ring.mesh = torus
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.1, 0.65, 1.0, 0.9)
	material.emission_enabled = true
	material.emission = Color(0.05, 0.35, 1.0, 1.0)
	material.emission_energy_multiplier = 1.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = material
	add_child(ring)
	_update_ring()

func _process(delta: float) -> void:
	elapsed += delta
	var t := clampf((elapsed - delay_seconds) / maxf(shrink_seconds, 0.001), 0.0, 1.0)
	current_radius = lerpf(start_radius, final_radius, t)
	_update_ring()

func _update_ring() -> void:
	if ring == null:
		return
	ring.position = Vector3(center_x, ring_height, center_z)
	ring.scale = Vector3(current_radius, 1.0, current_radius)

func is_inside_safe_zone(world_position: Vector3) -> bool:
	return Vector2(world_position.x - center_x, world_position.z - center_z).length() <= current_radius

func get_current_radius() -> float:
	return current_radius
