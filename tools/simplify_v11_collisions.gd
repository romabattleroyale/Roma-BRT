extends SceneTree
## Conservative V11 collision simplifier.
## Replaces baked ConcavePolygonShape3D with a small set of BoxShape3D.
## Visual meshes/materials are not modified.

const ARCH_DIR: String = "res://baked_city/archetypes_587"
const WALL_THICKNESS: float = 0.20
const FLOOR_THICKNESS: float = 0.25
const ROOF_THICKNESS: float = 0.25
const DOOR_GAP_FRACTION: float = 0.22
const MIN_DOOR_GAP: float = 1.6
const MAX_DOOR_GAP: float = 3.0

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var ok: int = 0
    for i: int in range(27):
        var path: String = "%s/archetype_%02d.tscn" % [ARCH_DIR, i]
        if not FileAccess.file_exists(path):
            push_error("V11 COLLISION: missing %s" % path)
            continue
        if _simplify_one(path):
            ok += 1
    print("V11 COLLISION: simplified=%d/27" % ok)
    quit(0 if ok == 27 else 1)

func _simplify_one(path: String) -> bool:
    var packed: PackedScene = load(path) as PackedScene
    if packed == null:
        push_error("V11 COLLISION: cannot load %s" % path)
        return false
    var root: Node3D = packed.instantiate() as Node3D
    if root == null:
        push_error("V11 COLLISION: root is not Node3D %s" % path)
        return false
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    if meshes.is_empty():
        root.free()
        push_error("V11 COLLISION: no visual mesh %s" % path)
        return false
    var aabb: AABB = _visual_aabb(root, meshes)
    if aabb.size.x <= 0.01 or aabb.size.y <= 0.01 or aabb.size.z <= 0.01:
        root.free()
        push_error("V11 COLLISION: invalid visual AABB %s" % path)
        return false

    var collision_info: Dictionary = _inspect_collision(root)
    print("[V11 COLLISION BEFORE] %s visual_triangles=%d concave_faces=%d collision_shapes=%d static_bodies=%d" % [path, _visual_triangles(meshes), collision_info["faces"], collision_info["shapes"], collision_info["bodies"]])
    var preferred_side: int = _find_door_side(root, aabb)
    var side_names: Array[String] = ["-X", "+X", "-Z", "+Z"]
    var side_name: String = side_names[preferred_side]

    _remove_collision_nodes(root)
    var body: StaticBody3D = StaticBody3D.new()
    body.name = "V11_StaticCollision"
    root.add_child(body)

    var added: int = 0
    added += _add_box(body, "Floor", Vector3(aabb.size.x, FLOOR_THICKNESS, aabb.size.z), Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.position.y + FLOOR_THICKNESS * 0.5, aabb.position.z + aabb.size.z * 0.5))
    added += _add_box(body, "Roof", Vector3(aabb.size.x, ROOF_THICKNESS, aabb.size.z), Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.end.y - ROOF_THICKNESS * 0.5, aabb.position.z + aabb.size.z * 0.5))
    var door_gap: float = clampf(maxf(MIN_DOOR_GAP, minf(MAX_DOOR_GAP, _side_span(aabb, preferred_side) * DOOR_GAP_FRACTION)), 1.2, 3.0)
    added += _add_wall_set(body, aabb, preferred_side, door_gap)
    print("[V11 COLLISION AFTER] %s side=%s box_shapes=%d collision_triangles=%d" % [path, side_name, added, added * 12])

    _set_owners(root, root)
    var output: PackedScene = PackedScene.new()
    var pack_error: Error = output.pack(root)
    if pack_error != OK:
        root.free()
        push_error("V11 COLLISION: pack failed %s" % path)
        return false
    var save_error: Error = ResourceSaver.save(output, path)
    root.free()
    if save_error != OK:
        push_error("V11 COLLISION: save failed %s" % path)
        return false
    return true

func _side_span(aabb: AABB, side: int) -> float:
    return aabb.size.z if side == 0 or side == 1 else aabb.size.x

func _add_wall_set(body: StaticBody3D, aabb: AABB, door_side: int, door_gap: float) -> int:
    var count: int = 0
    var cx: float = aabb.position.x + aabb.size.x * 0.5
    var cz: float = aabb.position.z + aabb.size.z * 0.5
    var cy: float = aabb.position.y + aabb.size.y * 0.5
    var h: float = aabb.size.y
    if door_side != 0:
        count += _add_box(body, "WallNegX", Vector3(WALL_THICKNESS, h, aabb.size.z), Vector3(aabb.position.x + WALL_THICKNESS * 0.5, cy, cz))
    if door_side != 1:
        count += _add_box(body, "WallPosX", Vector3(WALL_THICKNESS, h, aabb.size.z), Vector3(aabb.end.x - WALL_THICKNESS * 0.5, cy, cz))
    if door_side != 2:
        count += _add_box(body, "WallNegZ", Vector3(aabb.size.x, h, WALL_THICKNESS), Vector3(cx, cy, aabb.position.z + WALL_THICKNESS * 0.5))
    if door_side != 3:
        count += _add_box(body, "WallPosZ", Vector3(aabb.size.x, h, WALL_THICKNESS), Vector3(cx, cy, aabb.end.z - WALL_THICKNESS * 0.5))

    if door_side == 0 or door_side == 1:
        var span_x: float = aabb.size.z
        var gap_x: float = minf(door_gap, span_x * 0.45)
        var left_x: float = maxf(0.05, (span_x - gap_x) * 0.5)
        var right_x: float = left_x
        var x: float = aabb.position.x + (WALL_THICKNESS * 0.5 if door_side == 0 else aabb.size.x - WALL_THICKNESS * 0.5)
        if left_x > 0.05:
            count += _add_box(body, "DoorSideA", Vector3(WALL_THICKNESS, h, left_x), Vector3(x, cy, aabb.position.z + left_x * 0.5))
        if right_x > 0.05:
            count += _add_box(body, "DoorSideB", Vector3(WALL_THICKNESS, h, right_x), Vector3(x, cy, aabb.end.z - right_x * 0.5))
    else:
        var span_z: float = aabb.size.x
        var gap_z: float = minf(door_gap, span_z * 0.45)
        var left_z: float = maxf(0.05, (span_z - gap_z) * 0.5)
        var right_z: float = left_z
        var z: float = aabb.position.z + (WALL_THICKNESS * 0.5 if door_side == 2 else aabb.size.z - WALL_THICKNESS * 0.5)
        if left_z > 0.05:
            count += _add_box(body, "DoorSideA", Vector3(left_z, h, WALL_THICKNESS), Vector3(aabb.position.x + left_z * 0.5, cy, z))
        if right_z > 0.05:
            count += _add_box(body, "DoorSideB", Vector3(right_z, h, WALL_THICKNESS), Vector3(aabb.end.x - right_z * 0.5, cy, z))
    return count

func _add_box(body: StaticBody3D, name: String, size: Vector3, position: Vector3) -> int:
    var shape: BoxShape3D = BoxShape3D.new()
    shape.size = size
    var cs: CollisionShape3D = CollisionShape3D.new()
    cs.name = name
    cs.shape = shape
    cs.position = position
    body.add_child(cs)
    return 1

func _find_door_side(root: Node3D, aabb: AABB) -> int:
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    var scores: Array[int] = [0, 0, 0, 0]
    var y_cut: float = aabb.position.y + aabb.size.y * 0.35
    var tol_x: float = maxf(0.08, aabb.size.x * 0.04)
    var tol_z: float = maxf(0.08, aabb.size.z * 0.04)
    for mi: MeshInstance3D in meshes:
        var mesh: Mesh = mi.mesh
        if mesh == null:
            continue
        var tr: Transform3D = _local_transform_to_root(mi, root)
        for s: int in range(mesh.get_surface_count()):
            var arrays: Array = mesh.surface_get_arrays(s)
            if arrays.is_empty():
                continue
            var vertices_variant: Variant = arrays[Mesh.ARRAY_VERTEX]
            if not vertices_variant is PackedVector3Array:
                continue
            var vertices: PackedVector3Array = vertices_variant
            var indices: Variant = arrays[Mesh.ARRAY_INDEX]
            if indices is PackedInt32Array and (indices as PackedInt32Array).size() >= 3:
                var index_array: PackedInt32Array = indices
                for i: int in range(0, index_array.size(), 3):
                    _score_face(tr * vertices[index_array[i]], tr * vertices[index_array[i + 1]], tr * vertices[index_array[i + 2]], aabb, y_cut, tol_x, tol_z, scores)
            else:
                for i: int in range(0, vertices.size(), 3):
                    if i + 2 >= vertices.size():
                        break
                    _score_face(tr * vertices[i], tr * vertices[i + 1], tr * vertices[i + 2], aabb, y_cut, tol_x, tol_z, scores)
    var best: int = 0
    for i: int in range(1, 4):
        if scores[i] < scores[best]:
            best = i
    return best

func _score_face(a: Vector3, b: Vector3, c: Vector3, box: AABB, y_cut: float, tx: float, tz: float, scores: Array[int]) -> void:
    var center: Vector3 = (a + b + c) / 3.0
    if center.y > y_cut:
        return
    if absf(center.x - box.position.x) <= tx:
        scores[0] += 1
    if absf(center.x - box.end.x) <= tx:
        scores[1] += 1
    if absf(center.z - box.position.z) <= tz:
        scores[2] += 1
    if absf(center.z - box.end.z) <= tz:
        scores[3] += 1

func _visual_aabb(root: Node3D, meshes: Array[MeshInstance3D]) -> AABB:
    var first: bool = true
    var out: AABB = AABB()
    for mi: MeshInstance3D in meshes:
        var mesh: Mesh = mi.mesh
        if mesh == null:
            continue
        var tr: Transform3D = _local_transform_to_root(mi, root)
        for s: int in range(mesh.get_surface_count()):
            var arrays: Array = mesh.surface_get_arrays(s)
            if arrays.is_empty():
                continue
            var vertices_variant: Variant = arrays[Mesh.ARRAY_VERTEX]
            if not vertices_variant is PackedVector3Array:
                continue
            var vertices: PackedVector3Array = vertices_variant
            for v: Vector3 in vertices:
                var p: Vector3 = tr * v
                if first:
                    out = AABB(p, Vector3.ZERO)
                    first = false
                else:
                    out = out.expand(p)
    return out

func _inspect_collision(root: Node) -> Dictionary:
    var faces: int = 0
    var shapes: int = 0
    var bodies: int = 0
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        if current is StaticBody3D:
            bodies += 1
        if current is CollisionShape3D:
            shapes += 1
            var cs: CollisionShape3D = current as CollisionShape3D
            if cs.shape is ConcavePolygonShape3D:
                var cp: ConcavePolygonShape3D = cs.shape as ConcavePolygonShape3D
                faces += int(cp.get_faces().size() / 3)
        for child: Node in current.get_children():
            stack.append(child)
    return {"faces": faces, "shapes": shapes, "bodies": bodies}

func _visual_triangles(meshes: Array[MeshInstance3D]) -> int:
    var total: int = 0
    for mi: MeshInstance3D in meshes:
        var mesh: Mesh = mi.mesh
        if mesh == null:
            continue
        for s: int in range(mesh.get_surface_count()):
            var arrays: Array = mesh.surface_get_arrays(s)
            if arrays.is_empty():
                continue
            var idx: Variant = arrays[Mesh.ARRAY_INDEX]
            if idx is PackedInt32Array:
                total += (idx as PackedInt32Array).size() / 3
            else:
                var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
                if verts is PackedVector3Array:
                    total += (verts as PackedVector3Array).size() / 3
    return total

func _collect_meshes(current: Node, out: Array[MeshInstance3D]) -> void:
    for child: Node in current.get_children():
        if child is MeshInstance3D:
            var mi: MeshInstance3D = child as MeshInstance3D
            if mi.mesh != null:
                out.append(mi)
        _collect_meshes(child, out)

func _local_transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
    var result: Transform3D = Transform3D.IDENTITY
    var current: Node = node
    while current != root:
        var n: Node3D = current as Node3D
        if n == null:
            break
        result = n.transform * result
        current = n.get_parent()
    return result

func _remove_collision_nodes(root: Node) -> void:
    var remove_list: Array[Node] = []
    _collect_collision_nodes(root, remove_list)
    for node: Node in remove_list:
        if is_instance_valid(node) and node != root:
            var parent: Node = node.get_parent()
            if parent != null:
                parent.remove_child(node)
            node.free()

func _collect_collision_nodes(current: Node, out: Array[Node]) -> void:
    for child: Node in current.get_children():
        if child is CollisionShape3D or child is CollisionPolygon3D or child is StaticBody3D:
            out.append(child)
            continue
        _collect_collision_nodes(child, out)

func _set_owners(root: Node, current: Node) -> void:
    for child: Node in current.get_children():
        child.owner = root
        _set_owners(root, child)
