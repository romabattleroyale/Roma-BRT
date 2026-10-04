extends RefCounted
class_name RomaModularHouseFactory

const LIB_ROOT := "res://city_library/buildings/houses/roma_architecture_library_v11/"
const CATALOG_PATH := LIB_ROOT + "data/building_catalog.json"
const SYSTEM_SCRIPT := LIB_ROOT + "scripts/editor_library_building_system.gd"
const VISUAL_VARIATION_SCRIPT := "res://v37_integration/mobile_visual_variation.gd"

var catalog: Array[Dictionary] = []
var by_id: Dictionary = {}
var system: RomaLibraryBuildingSystem
var visual_variation = null
# Geometry is built once per real archetype/floor/roof combination, then duplicated
# shallowly so ArrayMesh/Material resources remain shared between mobile instances.
var mobile_prototypes: Dictionary = {}

func initialize() -> bool:
    if system == null:
        system = load(SYSTEM_SCRIPT).new() as RomaLibraryBuildingSystem
        if system == null:
            return false
        system.setup_materials()
    if visual_variation == null:
        var visual_script: Script = load(VISUAL_VARIATION_SCRIPT) as Script
        if visual_script != null:
            visual_variation = visual_script.new()
    if not catalog.is_empty():
        return true
    if not FileAccess.file_exists(CATALOG_PATH):
        return false
    var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
    if file == null:
        return false
    var parsed = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        return false
    for item in parsed:
        if item is Dictionary and item.has("id"):
            var entry: Dictionary = item.duplicate(true)
            catalog.append(entry)
            by_id[str(entry["id"])] = entry
    return not catalog.is_empty()

func get_catalog() -> Array[Dictionary]:
    initialize()
    return catalog.duplicate(true)

func get_building(id: String) -> Dictionary:
    initialize()
    return (by_id.get(id, {}) as Dictionary).duplicate(true)

func build_by_id(id: String, variant: int = 0) -> Node3D:
    if not initialize() or not by_id.has(id):
        return null
    return system.build(by_id[id], variant)

func build_mobile_by_id(id: String, variant: int = 0) -> Node3D:
    if not initialize() or not by_id.has(id):
        return null

    var source: Dictionary = by_id[id]
    var height_pattern: Array[int] = [3, 4, 5, 4, 3, 5]
    var floors: int = height_pattern[posmod(variant, height_pattern.size())]
    var roof_variant: int = int(variant / 10) * 10
    if posmod(variant, 2) == 1:
        roof_variant += 7

    var cache_key := "%s|f%d|r%d" % [id, floors, roof_variant]
    var prototype: Node3D = mobile_prototypes.get(cache_key) as Node3D
    if prototype == null:
        var entry: Dictionary = source.duplicate(true)
        entry["floors"] = floors
        entry["id"] = "__mobile_shared_%s_f%d_r%d" % [id, floors, roof_variant]
        prototype = system.build(entry, roof_variant)
        if prototype == null:
            return null
        var merged := _merge_mobile_geometry(prototype, floors)
        if merged == null:
            prototype.free()
            return null
        prototype = merged
        mobile_prototypes[cache_key] = prototype
        print("V11 MOBILE GEOMETRY CACHE: new prototype ", cache_key)
    else:
        print("V11 MOBILE GEOMETRY CACHE: reuse prototype ", cache_key)

    var root: Node3D = prototype.duplicate() as Node3D
    if root == null:
        return null
    if visual_variation != null:
        visual_variation.apply(root, variant, floors)
    return root

func build_and_place(id: String, terrain_position: Vector3, terrain_height: float, rotation_y: float = 0.0, variant: int = 0) -> Node3D:
    if not terrain_position.is_finite() or not is_finite(terrain_height):
        return null
    var root := build_by_id(id, variant)
    if root == null:
        return null
    root.position = Vector3(terrain_position.x, terrain_height, terrain_position.z)
    root.rotation.y = rotation_y
    if not root.position.is_finite():
        root.free()
        return null
    return root

func build_mobile_and_place(id: String, terrain_position: Vector3, terrain_height: float, rotation_y: float = 0.0, variant: int = 0) -> Node3D:
    if not terrain_position.is_finite() or not is_finite(terrain_height):
        return null
    var root := build_mobile_by_id(id, variant)
    if root == null:
        return null
    root.position = Vector3(terrain_position.x, terrain_height, terrain_position.z)
    root.rotation.y = rotation_y
    if not root.position.is_finite():
        root.free()
        return null
    return root

func _merge_mobile_geometry(root: Node3D, floors: int) -> Node3D:
    var mesh_nodes: Array[MeshInstance3D] = []
    _collect_mesh_nodes(root, mesh_nodes)
    if mesh_nodes.is_empty():
        return root

    var top_y: float = float(floors) * 3.2
    var max_mesh_y: float = -INF
    for node in mesh_nodes:
        max_mesh_y = maxf(max_mesh_y, node.position.y)

    var tools: Dictionary = {}
    var roles: Array[String] = []
    var merged_nodes: Array[MeshInstance3D] = []

    for node in mesh_nodes:
        var mesh: Mesh = node.mesh
        if mesh == null or not node.skeleton.is_empty():
            continue

        # Godot 4.7 Mesh does not expose surface_get_primitive_type().
        # The V11 procedural library emits triangle surfaces; SurfaceTool.commit()
        # is therefore the authoritative validation path for the merge.
        var node_role := _mesh_role(node, mesh, top_y, max_mesh_y)
        var local_transform: Transform3D = _transform_relative_to_root(node, root)
        for surface in range(mesh.get_surface_count()):
            var material: Material = node.get_active_material(surface)
            var format_key: int = -1
            if mesh is ArrayMesh:
                format_key = int((mesh as ArrayMesh).surface_get_format(surface))
            var material_key: int = 0 if material == null else material.get_instance_id()
            var key := "%s|m%d|f%d" % [node_role, material_key, format_key]
            var st: SurfaceTool = tools.get(key) as SurfaceTool
            if st == null:
                st = SurfaceTool.new()
                st.begin(Mesh.PRIMITIVE_TRIANGLES)
                st.set_material(material)
                tools[key] = st
            st.append_from(mesh, surface, local_transform)

        merged_nodes.append(node)

    if tools.is_empty():
        return root

    var merged_mesh := ArrayMesh.new()
    for key in tools.keys():
        var st: SurfaceTool = tools[key] as SurfaceTool
        var before := merged_mesh.get_surface_count()
        var committed: ArrayMesh = st.commit(merged_mesh)
        if committed != null:
            merged_mesh = committed
        var role := str(key).split("|", false, 1)[0]
        for _i in range(merged_mesh.get_surface_count() - before):
            roles.append(role)

    if merged_mesh.get_surface_count() == 0:
        return root

    var merged_instance := MeshInstance3D.new()
    merged_instance.name = "MobileMergedMesh"
    merged_instance.mesh = merged_mesh
    merged_instance.set_meta("mobile_merged", true)
    merged_instance.set_meta("mobile_surface_roles", roles)
    root.add_child(merged_instance)

    for node in merged_nodes:
        node.free()
    return root

func _transform_relative_to_root(node: Node3D, root: Node3D) -> Transform3D:
    var transform := Transform3D.IDENTITY
    var current: Node3D = node
    while current != null and current != root:
        transform = current.transform * transform
        current = current.get_parent() as Node3D
    if current != root:
        return Transform3D.IDENTITY
    return transform

func _mesh_role(node: MeshInstance3D, mesh: Mesh, top_y: float, max_mesh_y: float) -> String:
    var is_facade := false
    if mesh is BoxMesh:
        var size: Vector3 = (mesh as BoxMesh).size
        var horizontal: float = maxf(size.x, size.z)
        var thin: float = minf(size.x, size.z)
        is_facade = node.position.y < top_y - 0.20 and size.y >= 2.70 and size.y <= 3.30 and horizontal >= 5.0 and thin <= 0.50
    if is_facade:
        return "facade"
    if node.position.y >= max_mesh_y - 0.80 and node.position.y >= top_y - 0.15:
        return "roof"
    return "other"

func _collect_mesh_nodes(node: Node, result: Array[MeshInstance3D]) -> void:
    for child in node.get_children():
        if child is MeshInstance3D:
            result.append(child as MeshInstance3D)
        _collect_mesh_nodes(child, result)

func choose_id(min_w: float, max_w: float, min_d: float, max_d: float, function_filter: String = "", variant: int = 0) -> String:
    if not initialize():
        return ""
    var filter := function_filter.to_lower().strip_edges()
    var candidates: Array[Dictionary] = []
    for item in catalog:
        var w := float(item.get("w", item.get("width", 0.0)))
        var d := float(item.get("d", item.get("depth", 0.0)))
        if w < min_w or w > max_w or d < min_d or d > max_d:
            continue
        if not filter.is_empty() and not str(item.get("function", "")).to_lower().contains(filter):
            continue
        candidates.append(item)
    if candidates.is_empty() and not filter.is_empty():
        return choose_id(min_w, max_w, min_d, max_d, "", variant)
    if candidates.is_empty():
        return ""
    var index := posmod(variant, candidates.size())
    return str(candidates[index].get("id", ""))
