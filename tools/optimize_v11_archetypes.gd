extends SceneTree
## Offline V11 optimizer.
## Goal: flatten each baked archetype to one visual MeshInstance3D and one
## StaticBody3D/ConcavePolygonShape3D, while preserving materials and transforms.

const ARCH_DIR: String = "res://baked_city/archetypes_587"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var optimized: int = 0
    for i in range(27):
        var path: String = "%s/archetype_%02d.tscn" % [ARCH_DIR, i]
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
    _collect_all_meshes(root, meshes)
    if meshes.is_empty():
        root.free()
        print("V11 OPTIMIZER: no meshes in %s" % path)
        return true

    var tools: Dictionary = {}
    var merged_count: int = 0
    var merged_faces: PackedVector3Array = PackedVector3Array()

    for mi in meshes:
        if not is_instance_valid(mi) or not mi.visible or mi.mesh == null:
            continue
        var mesh: Mesh = mi.mesh
        var local_to_root: Transform3D = _local_transform_to_root(mi, root)
        for surface in range(mesh.get_surface_count()):
            var material: Material = mi.get_surface_override_material(surface)
            if material == null:
                material = mesh.surface_get_material(surface)
            var key: String = _material_key(material)
            if not tools.has(key):
                var st: SurfaceTool = SurfaceTool.new()
                if material != null:
                    st.set_material(material)
                tools[key] = st
            var tool: SurfaceTool = tools[key]
            tool.append_from(mesh, surface, local_to_root)
            merged_count += 1

        _append_collision_faces(mesh, local_to_root, merged_faces)

    if merged_count == 0:
        root.free()
        return true

    var merged_mesh: ArrayMesh = ArrayMesh.new()
    for key in tools.keys():
        var tool: SurfaceTool = tools[key]
        tool.commit(merged_mesh)

    # Remove every visual mesh node, not only leaves. This is the important
    # flattening step that eliminates hundreds of intermediate MeshInstance3D nodes.
    for mi in meshes:
        if is_instance_valid(mi):
            mi.get_parent().remove_child(mi)
            mi.free()

    # Remove old collision trees. The merged visual geometry becomes one
    # ConcavePolygonShape3D under one StaticBody3D.
    _remove_collision_nodes(root)

    var merged_node: MeshInstance3D = MeshInstance3D.new()
    merged_node.name = "V11_MergedVisual"
    merged_node.mesh = merged_mesh
    merged_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    root.add_child(merged_node)

    if merged_faces.size() >= 3:
        var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
        shape.set_faces(merged_faces)
        var body: StaticBody3D = StaticBody3D.new()
        body.name = "V11_StaticCollision"
        var collision: CollisionShape3D = CollisionShape3D.new()
        collision.name = "V11_ConcaveCollision"
        collision.shape = shape
        body.add_child(collision)
        root.add_child(body)

    _prune_empty_nodes(root)
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

    print("V11 OPTIMIZER: %s mesh_nodes=%d surfaces=%d collision_vertices=%d" % [path, meshes.size(), merged_count, merged_faces.size()])
    return true

func _collect_all_meshes(current: Node, out: Array[MeshInstance3D]) -> void:
    for child in current.get_children():
        var node: Node = child
        if node is MeshInstance3D:
            var mi: MeshInstance3D = node as MeshInstance3D
            if mi.mesh != null:
                out.append(mi)
        _collect_all_meshes(node, out)

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

func _material_key(material: Material) -> String:
    if material == null:
        return "__NO_MATERIAL__"
    if not material.resource_path.is_empty():
        return "PATH:" + material.resource_path
    return "INSTANCE:" + str(material.get_instance_id())

func _append_collision_faces(mesh: Mesh, transform: Transform3D, out: PackedVector3Array) -> void:
    for surface in range(mesh.get_surface_count()):
        var arrays: Array = mesh.surface_get_arrays(surface)
        if arrays.is_empty():
            continue
        var vertices = arrays[Mesh.ARRAY_VERTEX]
        if not (vertices is PackedVector3Array):
            continue
        var indices = arrays[Mesh.ARRAY_INDEX]
        if indices is PackedInt32Array and indices.size() >= 3:
            for i in range(0, indices.size(), 3):
                out.append(transform * vertices[indices[i]])
                out.append(transform * vertices[indices[i + 1]])
                out.append(transform * vertices[indices[i + 2]])
        else:
            for i in range(0, vertices.size(), 3):
                if i + 2 >= vertices.size():
                    break
                out.append(transform * vertices[i])
                out.append(transform * vertices[i + 1])
                out.append(transform * vertices[i + 2])

func _remove_collision_nodes(root: Node) -> void:
    var remove_list: Array[Node] = []
    _collect_collision_nodes(root, remove_list)
    for node in remove_list:
        if is_instance_valid(node) and node != root:
            node.get_parent().remove_child(node)
            node.free()

func _collect_collision_nodes(current: Node, out: Array[Node]) -> void:
    for child in current.get_children():
        var node: Node = child
        if node is CollisionShape3D or node is CollisionPolygon3D or node is StaticBody3D:
            out.append(node)
            continue
        _collect_collision_nodes(node, out)

func _prune_empty_nodes(current: Node) -> void:
    var children: Array[Node] = []
    for child in current.get_children():
        children.append(child)
    for child in children:
        _prune_empty_nodes(child)
        if child == null or not is_instance_valid(child):
            continue
        if child.get_child_count() == 0 and child is Node3D and not (child is MeshInstance3D) and not (child is StaticBody3D):
            if child.get_script() == null:
                child.get_parent().remove_child(child)
                child.free()

func _set_owners(root: Node, current: Node) -> void:
    for child in current.get_children():
        child.owner = root
        _set_owners(root, child)
