extends SceneTree
## Conservative V11 collision simplifier.
## Replaces the baked ConcavePolygonShape3D with a small set of BoxShape3D.
## Visual meshes/materials are not modified.

const ARCH_DIR := "res://baked_city/archetypes_587"
const WALL_THICKNESS := 0.20
const FLOOR_THICKNESS := 0.25
const ROOF_THICKNESS := 0.25
const DOOR_GAP_FRACTION := 0.22
const MIN_DOOR_GAP := 1.6
const MAX_DOOR_GAP := 3.0

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var ok := 0
    for i in range(27):
        var path := "%s/archetype_%02d.tscn" % [ARCH_DIR, i]
        if not FileAccess.file_exists(path):
            push_error("V11 COLLISION: missing %s" % path)
            continue
        if _simplify_one(path):
            ok += 1
    print("V11 COLLISION: simplified=%d/27" % ok)
    quit(0 if ok == 27 else 1)

func _simplify_one(path: String) -> bool:
    var packed := load(path) as PackedScene
    if packed == null:
        push_error("V11 COLLISION: cannot load %s" % path)
        return false
    var root := packed.instantiate() as Node3D
    if root == null:
        push_error("V11 COLLISION: root is not Node3D %s" % path)
        return false

    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    if meshes.is_empty():
        root.free()
        push_error("V11 COLLISION: no visual mesh %s" % path)
        return false

    var aabb := _visual_aabb(root, meshes)
    if aabb.size.x <= 0.01 or aabb.size.y <= 0.01 or aabb.size.z <= 0.01:
        root.free()
        push_error("V11 COLLISION: invalid visual AABB %s" % path)
        return false

    var collision_info := _inspect_collision(root)
    print("[V11 COLLISION BEFORE] %s visual_triangles=%d concave_faces=%d collision_shapes=%d static_bodies=%d" % [path, _visual_triangles(meshes), collision_info["faces"], collision_info["shapes"], collision_info["bodies"]])

    var preferred_side := _find_door_side(root, aabb)
    var side_name := ["-X", "+X", "-Z", "+Z"][preferred_side]

    _remove_collision_nodes(root)

    var body := StaticBody3D.new()
    body.name = "V11_StaticCollision"
    root.add_child(body)

    var added := 0
    added += _add_box(body, "Floor", Vector3(aabb.size.x, FLOOR_THICKNESS, aabb.size.z), Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.position.y + FLOOR_THICKNESS * 0.5, aabb.position.z + aabb.size.z * 0.5))
    added += _add_box(body, "Roof", Vector3(aabb.size.x, ROOF_THICKNESS, aabb.size.z), Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.end.y - ROOF_THICKNESS * 0.5, aabb.position.z + aabb.size.z * 0.5))

    var door_gap := clampf(max(MIN_DOOR_GAP, min(MAX_DOOR_GAP, _side_span(aabb, preferred_side) * DOOR_GAP_FRACTION)), 1.2, 3.0)
    added += _add_wall_set(body, aabb, preferred_side, door_gap)

    print("[V11 COLLISION AFTER] %s side=%s box_shapes=%d collision_triangles=%d" % [path, side_name, added, added * 12])

    _set_owners(root, root)
    var output := PackedScene.new()
    var pack_error := output.pack(root)
    if pack_error != OK:
        root.free()
        push_error("V11 COLLISION: pack failed %s" % path)
        return false
    var save_error := ResourceSaver.save(output, path)
    root.free()
    if save_error != OK:
        push_error("V11 COLLISION: save failed %s" % path)
        return false
    return true

func _side_span(aabb: AABB, side: int) -> float:
    return aabb.size.z if side == 0 or side == 1 else aabb.size.x

func _add_wall_set(body: StaticBody3D, aabb: AABB, door_side: int, door_gap: float) -> int:
    var count := 0
    var cx := aabb.position.x + aabb.size.x * 0.5
    var cz := aabb.position.z + aabb.size.z * 0.5
    var cy := aabb.position.y + aabb.size.y * 0.5
    var h := aabb.size.y

    if door_side != 0:
        count += _add_box(body, "WallNegX", Vector3(WALL_THICKNESS, h, aabb.size.z), Vector3(aabb.position.x + WALL_THICKNESS * 0.5, cy, cz))
    if door_side != 1:
        count += _add_box(body, "WallPosX", Vector3(WALL_THICKNESS, h, aabb.size.z), Vector3(aabb.end.x - WALL_THICKNESS * 0.5, cy, cz))
    if door_side != 2:
        count += _add_box(body, "WallNegZ", Vector3(aabb.size.x, h, WALL_THICKNESS), Vector3(cx, cy, aabb.position.z + WALL_THICKNESS * 0.5))
    if door_side != 3:
        count += _add_box(body, "WallPosZ", Vector3(aabb.size.x, h, WALL_THICKNESS), Vector3(cx, cy, aabb.end.z - WALL_THICKNESS * 0.5))

    if door_side == 0 or door_side == 1:
        var span := aabb.size.z
        var gap := min(door_gap, span * 0.45)
        var left := max(0.05, (span - gap) * 0.5)
        var right := left
        var x := aabb.position.x + (WALL_THICKNESS * 0.5 if door_side == 0 else aabb.size.x - WALL_THICKNESS * 0.5)
        if left > 0.05:
            count += _add_box(body, "DoorSideA", Vector3(WALL_THICKNESS, h, left), Vector3(x, cy, aabb.position.z + left * 0.5))
        if right > 0.05:
            count += _add_box(body, "DoorSideB", Vector3(WALL_THICKNESS, h, right), Vector3(x, cy, aabb.end.z - right * 0.5))
    else:
        var span := aabb.size.x
        var gap := min(door_gap, span * 0.45)
        var left := max(0.05, (span - gap) * 0.5)
        var right := left
        var z := aabb.position.z + (WALL_THICKNESS * 0.5 if door_side == 2 else aabb.size.z - WALL_THICKNESS * 0.5)
        if left > 0.05:
            count += _add_box(body, "DoorSideA", Vector3(left, h, WALL_THICKNESS), Vector3(aabb.position.x + left * 0.5, cy, z))
        if right > 0.05:
            count += _add_box(body, "DoorSideB", Vector3(right, h, WALL_THICKNESS), Vector3(aabb.end.x - right * 0.5, cy, z))
    return count

func _add_box(body: StaticBody3D, name: String, size: Vector3, position: Vector3) -> int:
    var shape := BoxShape3D.new()
    shape.size = size
    var cs := CollisionShape3D.new()
    cs.name = name
    cs.shape = shape
    cs.position = position
    body.add_child(cs)
    return 1

func _find_door_side(root: Node3D, aabb: AABB) -> int:
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    var scores := [0, 0, 0, 0]
    var y_cut := aabb.position.y + aabb.size.y * 0.35
    var tol_x := max(0.08, aabb.size.x * 0.04)
    var tol_z := max(0.08, aabb.size.z * 0.04)
    for mi in meshes:
        var mesh := mi.mesh
        if mesh == null:
            continue
        var tr := _local_transform_to_root(mi, root)
        for s in range(mesh.get_surface_count()):
            var arrays := mesh.surface_get_arrays(s)
            if arrays.is_empty():
                continue
            var vertices = arrays[Mesh.ARRAY_VERTEX]
            if not vertices is PackedVector3Array:
                continue
            var indices = arrays[Mesh.ARRAY_INDEX]
            if indices is PackedInt32Array and indices.size() >= 3:
                for i in range(0, indices.size(), 3):
                    _score_face(tr * vertices[indices[i]], tr * vertices[indices[i + 1]], tr * vertices[indices[i + 2]], aabb, y_cut, tol_x, tol_z, scores)
            else:
                for i in range(0, vertices.size(), 3):
                    if i + 2 >= vertices.size():
                        break
                    _score_face(tr * vertices[i], tr * vertices[i + 1], tr * vertices[i + 2], aabb, y_cut, tol_x, tol_z, scores)
    var best := 0
    for i in range(1, 4):
        if scores[i] < scores[best]:
            best = i
    return best

func _score_face(a: Vector3, b: Vector3, c: Vector3, box: AABB, y_cut: float, tx: float, tz: float, scores: Array) -> void:
    var center := (a + b + c) / 3.0
    if center.y > y_cut:
        return
    if abs(center.x - box.position.x) <= tx:
        scores[0] += 1
    if abs(center.x - box.end.x) <= tx:
        scores[1] += 1
    if abs(center.z - box.position.z) <= tz:
        scores[2] += 1
    if abs(center.z - box.end.z) <= tz:
        scores[3] += 1

func _visual_aabb(root: Node3D, meshes: Array[MeshInstance3D]) -> AABB:
    var first := true
    var out := AABB()
    for mi in meshes:
        var mesh := mi.mesh
        if mesh == null:
            continue
        var tr := _local_transform_to_root(mi, root)
        for s in range(mesh.get_surface_count()):
            var arrays := mesh.surface_get_arrays(s)
            if arrays.is_empty():
                continue
            var vertices = arrays[Mesh.ARRAY_VERTEX]
            if not vertices is PackedVector3Array:
                continue
            for v in vertices:
                var p := tr * v
                if first:
                    out = AABB(p, Vector3.ZERO)
                    first = false
                else:
                    out = out.expand(p)
    return out

func _inspect_collision(root: Node) -> Dictionary:
    var faces := 0
    var shapes := 0
    var bodies := 0
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        if current is StaticBody3D:
            bodies += 1
        if current is CollisionShape3D:
            shapes += 1
            var cs := current as CollisionShape3D
            if cs.shape is ConcavePolygonShape3D:
                var cp := cs.shape as ConcavePolygonShape3D
                faces += int(cp.get_faces().size() / 3)
        for child in current.get_children():
            stack.append(child)
    return {"faces": faces, "shapes": shapes, "bodies": bodies}

func _visual_triangles(meshes: Array[MeshInstance3D]) -> int:
    var total := 0
    for mi in meshes:
        var mesh := mi.mesh
        if mesh == null:
            continue
        for s in range(mesh.get_surface_count()):
            var arrays := mesh.surface_get_arrays(s)
            if arrays.is_empty():
                continue
            var idx = arrays[Mesh.ARRAY_INDEX]
            if idx is PackedInt32Array:
                total += idx.size() / 3
            else:
                var verts = arrays[Mesh.ARRAY_VERTEX]
                if verts is PackedVector3Array:
                    total += verts.size() / 3
    return total

func _collect_meshes(current: Node, out: Array[MeshInstance3D]) -> void:
    for child in current.get_children():
        if child is MeshInstance3D:
            var mi := child as MeshInstance3D
            if mi.mesh != null:
                out.append(mi)
        _collect_meshes(child, out)

func _local_transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
    var result := Transform3D.IDENTITY
    var current: Node = node
    while current != root:
        var n := current as Node3D
        if n == null:
            break
        result = n.transform * result
        current = current.get_parent()
    return result

func _remove_collision_nodes(root: Node) -> void:
    var remove_list: Array[Node] = []
    _collect_collision_nodes(root, remove_list)
    for node in remove_list:
        if is_instance_valid(node) and node != root:
            node.get_parent().remove_child(node)
            node.free()

func _collect_collision_nodes(current: Node, out: Array[Node]) -> void:
    for child in current.get_children():
        if child is CollisionShape3D or child is CollisionPolygon3D or child is StaticBody3D:
            out.append(child)
            continue
        _collect_collision_nodes(child, out)

func _set_owners(root: Node, current: Node) -> void:
    for child in current.get_children():
        child.owner = root
        _set_owners(root, child)
