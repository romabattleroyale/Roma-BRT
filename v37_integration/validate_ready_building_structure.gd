extends SceneTree
## Structural gate for all 587 ready assets: exactly one MeshInstance3D and
## exactly one BoxShape3D collision per baked building, with Roman facade colors.
## On failure, emit a compact tree/material diagnostic so CI exposes the exact asset issue.

const READY_DIR := "res://baked_city/ready_buildings"
const ROMAN_COLORS := ["b97845", "d3a63a", "b96f73", "c7aa83", "a9573b", "a99a7e"]

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    for i in range(587):
        var path := "%s/building_%03d.tscn" % [READY_DIR, i + 1]
        var packed := load(path) as PackedScene
        if packed == null:
            _fail(path, "cannot load")
            return
        var root := packed.instantiate() as Node3D
        if root == null:
            _fail(path, "cannot instantiate")
            return
        var meshes := _mesh_nodes(root)
        var boxes := _box_shapes(root)
        if meshes.size() != 1 or boxes.size() != 1:
            _diagnose(path, root, meshes, boxes)
            root.free()
            quit(1)
            return
        var mesh := meshes[0].mesh
        if mesh == null or mesh.get_surface_count() == 0:
            _diagnose(path, root, meshes, boxes)
            root.free()
            quit(1)
            return
        var facade_found := false
        for s in range(mesh.get_surface_count()):
            var material := mesh.surface_get_material(s) as StandardMaterial3D
            if material == null:
                continue
            var hex := material.albedo_color.to_html(false).to_lower()
            if ROMAN_COLORS.has(hex):
                facade_found = true
            if hex == "fff0c9":
                push_error("READY STRUCTURE: legacy #FFF0C9 found in %s surface=%d" % [path, s])
                _diagnose(path, root, meshes, boxes)
                root.free()
                quit(1)
                return
        if not facade_found:
            _diagnose(path, root, meshes, boxes)
            root.free()
            quit(1)
            return
        root.free()
        if (i + 1) % 50 == 0:
            print("READY STRUCTURE: ", i + 1, "/587")
    print("READY STRUCTURE OK: 587/587 one-mesh one-box Roman assets")
    quit(0)

func _fail(path: String, reason: String) -> void:
    push_error("READY STRUCTURE: %s %s" % [path, reason])

func _diagnose(path: String, root: Node3D, meshes: Array[MeshInstance3D], boxes: Array[CollisionShape3D]) -> void:
    push_error("READY STRUCTURE DIAG: %s meshes=%d boxes=%d root_children=%d" % [path, meshes.size(), boxes.size(), root.get_child_count()])
    for m in meshes:
        var surface_count := 0 if m.mesh == null else m.mesh.get_surface_count()
        print("READY STRUCTURE MESH: name=", m.get_path(), " surfaces=", surface_count, " meta_mobile=", m.get_meta("mobile_merged", false))
        if m.mesh != null:
            for s in range(m.mesh.get_surface_count()):
                var mat := m.mesh.surface_get_material(s) as StandardMaterial3D
                var hex := "null"
                if mat != null:
                    hex = mat.albedo_color.to_html(false).to_lower()
                print("READY STRUCTURE MATERIAL: surface=", s, " color=", hex)
    for b in boxes:
        var shape := b.shape as BoxShape3D
        print("READY STRUCTURE BOX: name=", b.get_path(), " size=", shape.size if shape != null else Vector3.ZERO)
    _dump_children(root, 0)

func _dump_children(node: Node, depth: int) -> void:
    if depth > 3:
        return
    for child in node.get_children():
        print("READY STRUCTURE NODE: depth=", depth, " type=", child.get_class(), " name=", child.name)
        _dump_children(child, depth + 1)

func _mesh_nodes(root: Node) -> Array[MeshInstance3D]:
    var result: Array[MeshInstance3D] = []
    _collect_meshes(root, result)
    return result

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, result)

func _box_shapes(root: Node) -> Array[CollisionShape3D]:
    var result: Array[CollisionShape3D] = []
    _collect_boxes(root, result)
    return result

func _collect_boxes(node: Node, result: Array[CollisionShape3D]) -> void:
    if node is CollisionShape3D and node.shape is BoxShape3D:
        result.append(node as CollisionShape3D)
    for child in node.get_children():
        _collect_boxes(child, result)
