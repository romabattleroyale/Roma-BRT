@tool
class_name MapPropField
extends RefCounted
## Positions and sizes of every instance that should be solid, in a uniform
## spatial grid so "what is near the player" is a cheap query rather than a
## linear scan over every tree on the map.

const CELL := 24.0

var positions := PackedVector3Array()
var radii := PackedFloat32Array()
var heights := PackedFloat32Array()
## Which species each prop came from, as an index into `kind_names`. Lets a
## caller ask "where are the boulders" rather than only "where is something
## solid" -- a search for the densest cluster of *anything* just finds forest.
var kinds := PackedInt32Array()
var kind_names := PackedStringArray()

var _grid: Dictionary = {}


func kind_id(name: String) -> int:
	var i := kind_names.find(name)
	if i >= 0:
		return i
	kind_names.append(name)
	return kind_names.size() - 1


func add(pos: Vector3, radius: float, height: float, kind: int = -1) -> void:
	positions.append(pos)
	radii.append(radius)
	heights.append(height)
	kinds.append(kind)


## Indices of props of a given species, nearest first.
func query_near_kind(center: Vector3, radius: float, kind: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in query_near(center, radius):
		if kinds[i] == kind:
			out.append(i)
	return out


func size() -> int:
	return positions.size()


func build_index() -> void:
	_grid.clear()
	for i in positions.size():
		var key := _key(positions[i])
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		var bucket: PackedInt32Array = _grid[key]
		bucket.append(i)
		_grid[key] = bucket


func _key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


## Indices of every prop whose centre is within `radius` of `center` on the XZ
## plane, nearest first.
func query_near(center: Vector3, radius: float) -> PackedInt32Array:
	var found: Array = []
	var span: int = int(ceil(radius / CELL))
	var base := _key(center)
	var r2 := radius * radius
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var bucket = _grid.get(Vector2i(base.x + dx, base.y + dz))
			if bucket == null:
				continue
			for i in bucket:
				var p: Vector3 = positions[i]
				var d2 := (p.x - center.x) * (p.x - center.x) + (p.z - center.z) * (p.z - center.z)
				if d2 <= r2:
					found.append([d2, i])
	found.sort_custom(func(a, b): return a[0] < b[0])
	var out := PackedInt32Array()
	for entry in found:
		out.append(entry[1])
	return out
