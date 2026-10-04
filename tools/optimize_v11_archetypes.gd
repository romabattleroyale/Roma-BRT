extends SceneTree
## Offline V11 visual optimizer.
## Merges leaf MeshInstance3D nodes in each baked archetype into one ArrayMesh,
## preserving materials and local transforms. Collision/gameplay nodes are kept.

const ARCH_DIR: String = "res://baked_city/archetypes_587"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var files: Array[String] = []
    for i in range(27):
        files.append("%s/archetype_%02d.tscn" % [ARCH_DIR, i])

    var optimized: int = 0
    for path in files:
        if not FileAccess.file_exists(path):
            push_error("V11 OPTIMIZER: missing %s" % path)
            continue
        if _optimize_one(path):
            optimized += 1

    print("V11 OPTIMIZER: optimized=%d/27" % optimized)
    quit(0 if optimized == 27 else 1)

func _optimize_one(path: String) -> bool:
    var packed: PackedScene = load(path) as PackedScene
    if packed == null:
        push_error("V11 OPTIMIZER: cannot load %s" % path)
        return false

    var root: Node3D = packed.instantiate() as Node3D
    if root == null:
        push_error("V11 OPTIMIZER: root is not Node3D: %s" % path)
        return false

    var meshes: Array[MeshInstance3D] = []
    _collect_leaf_meshes(root, root, meshes)
    if meshes.is_empty():
        root.free()
        print("V11 OPTIMIZER: no leaf meshes in %s" % path)
        return true

    var tools: Dictionary = {}
    var merged_count: int = 0

    for mi in meshes:
        if not is_instance_valid(mi) or not mi.visible or mi.mesh == null:
            continue
        var mesh: Mesh = mi.mesh
        var local_to_root: Transform3D = _local_transform_to_root(mi, root)
        for surface in range(mesh.get_surface_count()):
            var material: Material = mi.get_surface_override_material(surface)
            if material == null:
                material = mesh.surface_get_material(surface)
            var key: int = 0
            if material != null:
                key = material.get_instance_id()
            if not tools.has(key):
                var st: SurfaceTool = SurfaceTool.new()
                if material != null:
                    st.set_material(material)
                tools[key] = st
            var tool: SurfaceTool = tools[key]
            tool.append_from(mesh, surface, local_to_root)
            merged_count += 1

    if merged_count == 0:
        root.free()
        return true

    var merged_mesh: ArrayMesh = ArrayMesh.new()
    for key in tools.keys():
        var tool: SurfaceTool = tools[key]
        tool.commit(merged_mesh)

    for mi in meshes:
        if is_instance_valid(mi) and mi.get_parent() != null:
            mi.get_parent().remove_child(mi)
            mi.free()

    var merged_node: MeshInstance3D = MeshInstance3D.new()
    merged_node.name = "V11_MergedVisual"
    merged_node.mesh = merged_mesh
    merged_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    root.add_child(merged_node)

    _set_owners(root, root)
    var output: PackedScene = PackedScene.new()
    var pack_error: Error = output.pack(root)
    if pack_error != OK:
        push_error("V11 OPTIMIZER: pack failed for %s: %s" % [path, pack_error])
        root.free()
        return false

    var save_error: Error = ResourceSaver.save(output, path)
    root.free()
    if save_error != OK:
        push_error("V11 OPTIMIZER: save failed for %s: %s" % [path, save_error])
        return false

    print("V11 OPTIMIZER: %s meshes=%d surfaces=%d" % [path, meshes.size(), merged_count])
    return true

func _collect_leaf_meshes(root: Node, current: Node, out: Array[MeshInstance3D]) -> void:
    for child in current.get_children():
        var node: Node = child
        if node is MeshInstance3D:
            var mi: MeshInstance3D = node as MeshInstance3D
            if mi.get_child_count() == 0 and mi.mesh != null and mi != root:
                out.append(mi)
                continue
        _collect_leaf_meshes(root, node, out)

func _local_transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
    var result: Transform3D = Transform3D.IDENTITY
    var current: Node = node
    while current != root:
        var current_3d: Node3D = current as Node3D
        if current_3d == null:
            break
        result = current_3d.transform * result
        current = current.get_parent()
    return result

func _set_owners(root: Node, current: Node) -> void:
    for child in current.get_children():
        child.owner = root
        _set_owners(root, child)
