extends SceneTree
## Deterministic V11 gameplay collision probe for 40 archetype instances.
## It checks that a capsule can cross the centered doorway opening, then walk
## inside the shell without immediately colliding with the wall volume.

const BAKED_SCENE := "res://baked_city/roma_city_587.tscn"
const BUILDINGS := 40
const PLAYER_RADIUS := 0.42
const PLAYER_HEIGHT := 1.80
const DOOR_Y := 1.05
const OUTSIDE_OFFSET := 2.0
const INSIDE_TRAVEL := 2.0
const STEP := 0.20

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var entries := _read_entries()
    if entries.size() < BUILDINGS:
        push_error("V11 GAMEPLAY FAIL: only %d entries available, need %d" % [entries.size(), BUILDINGS])
        quit(2)
        return

    var root := Node3D.new()
    root.name = "V11GameplayValidation"
    get_root().add_child(root)

    var passed := 0
    for i in range(BUILDINGS):
        var packed := load(str(entries[i]["archetype"])) as PackedScene
        if packed == null:
            push_error("V11 GAMEPLAY FAIL: cannot load %s" % str(entries[i]["archetype"]))
            quit(3)
            return
        var building := packed.instantiate() as Node3D
        if building == null:
            push_error("V11 GAMEPLAY FAIL: instantiate %d" % (i + 1))
            quit(4)
            return
        building.transform = entries[i]["transform"]
        root.add_child(building)
        var result := _probe_building(building)
        print("[V11 GAMEPLAY] edificio=%d door=%s enter=%s walk=%s" % [i + 1, str(result["door"]), str(result["enter"]), str(result["walk"])])
        if bool(result["enter"]) and bool(result["walk"]):
            passed += 1
        else:
            push_error("V11 GAMEPLAY FAIL: building %d entry/walk probe failed" % (i + 1))
        building.queue_free()
        await process_frame

    print("=== V11 GAMEPLAY 40 ===")
    print("Edifici testati: %d" % BUILDINGS)
    print("Edifici PASS: %d" % passed)
    if passed != BUILDINGS:
        quit(5)
        return
    print("V11 GAMEPLAY 40 PASS: doorway entry and interior walking probes passed for all 40 buildings")
    quit(0)

func _probe_building(root: Node3D) -> Dictionary:
    var aabb := _visual_aabb(root)
    if aabb.size.x <= 0.1 or aabb.size.z <= 0.1:
        return {"door": "invalid", "enter": false, "walk": false}
    var side := _find_door_side(root, aabb)
    var door_point := _door_point(aabb, side)
    var inward := _inward(side)
    var player := CharacterBody3D.new()
    player.name = "ProbePlayer"
    var capsule := CapsuleShape3D.new()
    capsule.radius = PLAYER_RADIUS
    capsule.height = PLAYER_HEIGHT
    var cs := CollisionShape3D.new()
    cs.shape = capsule
    player.add_child(cs)
    get_root().add_child(player)

    var start := door_point - inward * OUTSIDE_OFFSET
    start.y = DOOR_Y
    player.global_position = start
    var entered := true
    var steps := int(ceil((OUTSIDE_OFFSET + INSIDE_TRAVEL) / STEP))
    for _j in range(steps):
        var collision := player.move_and_collide(inward * STEP, true, true, true)
        if collision != null:
            entered = false
            break
        await process_frame

    var walked := entered
    if entered:
        var side_move := _side_vector(side) * 1.2
        var collision2 := player.move_and_collide(side_move, true, true, true)
        walked = collision2 == null
    player.queue_free()
    return {"door": side, "enter": entered, "walk": walked}

func _inward(side: int) -> Vector3:
    if side == 0:
        return Vector3(0, 0, 1)
    if side == 1:
        return Vector3(0, 0, -1)
    if side == 2:
        return Vector3(1, 0, 0)
    return Vector3(-1, 0, 0)

func _side_vector(side: int) -> Vector3:
    if side == 0 or side == 1:
        return Vector3(1, 0, 0)
    return Vector3(0, 0, 1)

func _door_point(aabb: AABB, side: int) -> Vector3:
    var p := aabb.position + aabb.size * 0.5
    if side == 0:
        p.z = aabb.position.z - 0.35
    elif side == 1:
        p.z = aabb.end.z + 0.35
    elif side == 2:
        p.x = aabb.position.x - 0.35
    else:
        p.x = aabb.end.x + 0.35
    return p

func _visual_aabb(root: Node3D) -> AABB:
    var first := true
    var out := AABB()
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        if current is MeshInstance3D:
            var mi := current as MeshInstance3D
            if mi.mesh != null:
                var tr := _local_transform_to_root(mi, root)
                for s in range(mi.mesh.get_surface_count()):
                    var arrays := mi.mesh.surface_get_arrays(s)
                    if arrays.is_empty():
                        continue
                    var vertices = arrays[Mesh.ARRAY_VERTEX]
                    if vertices is PackedVector3Array:
                        for v in vertices:
                            var p := tr * v
                            if first:
                                out = AABB(p, Vector3.ZERO)
                                first = false
                            else:
                                out = out.expand(p)
        for child in current.get_children():
            stack.append(child)
    return out

func _find_door_side(root: Node3D, aabb: AABB) -> int:
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    var scores := [0, 0, 0, 0]
    var y_cut := aabb.position.y + aabb.size.y * 0.35
    var tol_x := maxf(0.08, aabb.size.x * 0.04)
    var tol_z := maxf(0.08, aabb.size.z * 0.04)
    for mi in meshes:
        if mi.mesh == null:
            continue
        var tr := _local_transform_to_root(mi, root)
        for s in range(mi.mesh.get_surface_count()):
            var arrays := mi.mesh.surface_get_arrays(s)
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
    if absf(center.x - box.position.x) <= tx:
        scores[0] += 1
    if absf(center.x - box.end.x) <= tx:
        scores[1] += 1
    if absf(center.z - box.position.z) <= tz:
        scores[2] += 1
    if absf(center.z - box.end.z) <= tz:
        scores[3] += 1

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
        current = n.get_parent()
    return result

func _read_entries() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var f := FileAccess.open(BAKED_SCENE, FileAccess.READ)
    if f == null:
        return out
    var lines := f.get_as_text().split("\n")
    f.close()
    var ext_paths: Dictionary = {}
    for raw in lines:
        var line: String = raw.strip_edges()
        if line.begins_with("[ext_resource") and line.contains("type=\"PackedScene\""):
            var path := _between(line, "path=\"", "\" id=\"")
            var id := _between(line, "id=\"", "\"]")
            if not path.is_empty() and not id.is_empty():
                ext_paths[id] = path
    for i in range(lines.size() - 1):
        var line: String = lines[i].strip_edges()
        if not line.begins_with("[node name=\"building_") or not line.contains("instance=ExtResource(\""):
            continue
        var id := _between(line, "instance=ExtResource(\"", "\")")
        var path := str(ext_paths.get(id, ""))
        if path.is_empty():
            continue
        var transform_line: String = lines[i + 1].strip_edges()
        if not transform_line.begins_with("transform = Transform3D("):
            continue
        out.append({"archetype": path, "transform": _parse_transform(transform_line)})
    return out

func _between(line: String, left: String, right: String) -> String:
    var a := line.find(left)
    if a < 0:
        return ""
    a += left.length()
    var b := line.find(right, a)
    if b < 0:
        return ""
    return line.substr(a, b - a)

func _parse_transform(line: String) -> Transform3D:
    var body := line.trim_prefix("transform = Transform3D(").trim_suffix(")")
    var parts := body.split(",")
    if parts.size() < 12:
        return Transform3D.IDENTITY
    var v: Array[float] = []
    for i in range(12):
        v.append(float(parts[i].strip_edges()))
    var basis := Basis(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]), Vector3(v[6], v[7], v[8]))
    return Transform3D(basis, Vector3(v[9], v[10], v[11]))
