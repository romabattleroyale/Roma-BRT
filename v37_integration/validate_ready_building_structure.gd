extends SceneTree
## Structural gate for all 587 ready assets: exactly one MeshInstance3D and
## exactly one BoxShape3D collision per baked building, with Roman facade colors.

const READY_DIR := "res://baked_city/ready_buildings"
const ROMAN_COLORS := ["b97845", "d3a63a", "b96f73", "c7aa83", "a9573b", "a99a7e"]

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    for i in range(587):
        var path := "%s/building_%03d.tscn" % [READY_DIR, i + 1]
        var packed := load(path) as PackedScene
        if packed == null:
            push_error("READY STRUCTURE: cannot load %s" % path)
            quit(1)
            return
        var root := packed.instantiate() as Node3D
        if root == null:
            push_error("READY STRUCTURE: cannot instantiate %s" % path)
            quit(1)
            return
        var meshes := _mesh_nodes(root)
        if meshes.size() != 1:
            push_error("READY STRUCTURE: %s has %d mesh nodes, expected 1" % [path, meshes.size()])
            root.free()
            quit(1)
            return
        var boxes := _box_shapes(root)
        if boxes.size() != 1:
            push_error("READY STRUCTURE: %s has %d BoxShape3D nodes, expected 1" % [path, boxes.size()])
            root.free()
            quit(1)
            return
        var mesh := meshes[0].mesh
        if mesh == null or mesh.get_surface_count() == 0:
            push_error("READY STRUCTURE: %s has no mesh surfaces" % path)
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
                root.free()
                quit(1)
                return
        if not facade_found:
            push_error("READY STRUCTURE: no Roman facade material found in %s" % path)
            root.free()
            quit(1)
            return
        root.free()
        if (i + 1) % 50 == 0:
            print("READY STRUCTURE: ", i + 1, "/587")
    print("READY STRUCTURE OK: 587/587 one-mesh one-box Roman assets")
    quit(0)

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
