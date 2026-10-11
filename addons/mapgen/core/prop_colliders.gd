@tool
class_name MapPropColliders
extends Node3D
## Gives trees and boulders collision without creating a StaticBody per instance.
##
## A map has thousands of solid props and a player can only touch a handful at
## once, so this keeps a small pool of collider bodies and re-parks them onto
## whichever props are currently nearest. Cost is constant in the size of the
## map: 24 bodies whether the forest has 2,000 trees or 200,000.

## Number of colliders kept alive. Anything the player can plausibly touch
## between two updates has to fit in here.
@export var pool_size: int = 24:
	set(value):
		pool_size = maxi(value, 1)
		if is_inside_tree():
			_rebuild_pool()

## Props further than this from the target are not given collision.
@export var active_radius: float = 16.0
## Seconds between refreshes. The player cannot outrun active_radius in this
## time at any sane speed, so there is no reason to do it every frame.
@export var update_interval: float = 0.15
@export var collision_layer_mask: int = 1

var field: MapPropField
var target: Node3D

var _bodies: Array[StaticBody3D] = []
var _shapes: Array[CollisionShape3D] = []
var _timer := 0.0


func _ready() -> void:
	_rebuild_pool()
	set_physics_process(true)


func _rebuild_pool() -> void:
	for b in _bodies:
		b.queue_free()
	_bodies.clear()
	_shapes.clear()
	for i in pool_size:
		var body := StaticBody3D.new()
		body.name = "PropCollider%d" % i
		body.collision_layer = collision_layer_mask
		var cs := CollisionShape3D.new()
		cs.shape = CylinderShape3D.new()
		cs.disabled = true
		body.add_child(cs)
		add_child(body)
		_bodies.append(body)
		_shapes.append(cs)


## Point the pool at a freshly generated map.
func bind(prop_field: MapPropField, follow: Node3D) -> void:
	field = prop_field
	target = follow
	_timer = 0.0
	refresh()


func _physics_process(delta: float) -> void:
	if field == null or target == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = update_interval
		refresh()


func refresh() -> void:
	if field == null or target == null or _bodies.is_empty():
		return
	var near := field.query_near(target.global_position, active_radius)
	var used: int = mini(near.size(), _bodies.size())

	for slot in used:
		var idx := near[slot]
		var pos := field.positions[idx]
		var r: float = maxf(field.radii[idx], 0.05)
		var h: float = maxf(field.heights[idx], 0.2)
		var cyl: CylinderShape3D = _shapes[slot].shape
		cyl.radius = r
		cyl.height = h
		# CylinderShape3D is centred on its origin; lift it so the base sits on
		# the ground the prop was placed on.
		_bodies[slot].global_position = pos + Vector3(0.0, h * 0.5, 0.0)
		_shapes[slot].disabled = false

	for slot in range(used, _bodies.size()):
		_shapes[slot].disabled = true


## How many colliders are live right now. Useful for a debug HUD.
func active_count() -> int:
	var n := 0
	for cs in _shapes:
		if not cs.disabled:
			n += 1
	return n
