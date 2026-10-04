extends RefCounted
class_name RomaMobileVisualVariation

const FACADE_COLORS = [
    Color("#B97845"), # ocra
    Color("#D3A63A"), # giallo romano
    Color("#B96F73"), # rosa antico
    Color("#C7AA83"), # beige
    Color("#A9573B"), # terracotta
    Color("#A99A7E")  # travertino
]

const ROOF_COLORS = [
    Color("#B84D32"),
    Color("#C9783F"),
    Color("#8F6B4E")
]

const FACADE_ALBEDO_PATH := "res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures/roman_plaster_weathered_albedo.jpg"
const FACADE_NORMAL_PATH := "res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures/roman_plaster_weathered_normal.jpg"
const FACADE_ROUGHNESS_PATH := "res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures/roman_plaster_weathered_roughness.jpg"

var _facade_materials: Dictionary = {}
var _roof_materials: Dictionary = {}
var _facade_albedo: Texture2D
var _facade_normal: Texture2D
var _facade_roughness: Texture2D
var _building_counter: int = 0

func _load_facade_textures() -> void:
    if _facade_albedo == null:
        _facade_albedo = load(FACADE_ALBEDO_PATH) as Texture2D
    if _facade_normal == null:
        _facade_normal = load(FACADE_NORMAL_PATH) as Texture2D
    if _facade_roughness == null:
        _facade_roughness = load(FACADE_ROUGHNESS_PATH) as Texture2D

func _facade_material(color: Color) -> StandardMaterial3D:
    var key := color.to_html(true)
    var cached := _facade_materials.get(key) as StandardMaterial3D
    if cached != null:
        return cached

    _load_facade_textures()
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    if _facade_albedo != null:
        material.albedo_texture = _facade_albedo
    if _facade_normal != null:
        material.normal_enabled = true
        material.normal_texture = _facade_normal
        material.normal_scale = 0.58
    if _facade_roughness != null:
        material.roughness_texture = _facade_roughness
    material.roughness = 0.88
    material.uv1_scale = Vector3(3.6, 3.6, 3.6)
    material.texture_repeat = true
    _facade_materials[key] = material
    return material

func _roof_material(color: Color) -> StandardMaterial3D:
    var key := color.to_html(true)
    var cached := _roof_materials.get(key) as StandardMaterial3D
    if cached != null:
        return cached
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.90
    _roof_materials[key] = material
    return material

func apply(root: Node3D, variant: int, floors: int) -> void:
    _building_counter += 1
    var facade_color: Color = FACADE_COLORS[posmod(variant * 7 + 1, FACADE_COLORS.size())]
    var roof_color: Color = ROOF_COLORS[posmod(variant * 5 + 2, ROOF_COLORS.size())]
    var facade_mat := _facade_material(facade_color)
    var roof_mat := _roof_material(roof_color)

    var merged_applied := false
    var facade_surface_count: int = 0
    var roof_surface_count: int = 0
    for node in _mesh_nodes(root):
        if bool(node.get_meta("mobile_merged", false)) and node.mesh != null:
            var roles: Array = node.mesh.get_meta("surface_roles", []) as Array
            if roles.is_empty():
                roles = node.get_meta("mobile_surface_roles", []) as Array
            var surface_count: int = node.mesh.get_surface_count()
            for surface in range(surface_count):
                var role := str(roles[surface]) if surface < roles.size() else "other"
                if role == "facade":
                    node.set_surface_override_material(surface, facade_mat)
                    var effective := node.get_surface_override_material(surface) as StandardMaterial3D
                    print("[MAT-ROLE] surface=%d role=facade override=%s" % [surface, effective.albedo_color.to_html(false) if effective != null else "NULL"])
                    facade_surface_count += 1
                elif role == "roof":
                    node.set_surface_override_material(surface, roof_mat)
                    roof_surface_count += 1
            merged_applied = true

    if merged_applied:
        print("[MAT] Edificio #%d - Colore facciata: %s, Texture: %s, superfici facciata: %d, tetto: %d" % [
            _building_counter,
            facade_color.to_html(false),
            FACADE_ALBEDO_PATH if _facade_albedo != null else "MANCANTE",
            facade_surface_count,
            roof_surface_count
        ])
        return

    var top_y: float = float(floors) * 3.2
    var max_mesh_y: float = -INF
    for node in _mesh_nodes(root):
        max_mesh_y = maxf(max_mesh_y, node.position.y)
    for node in _mesh_nodes(root):
        var mesh = node.mesh
        if mesh is BoxMesh:
            var size: Vector3 = mesh.size
            var horizontal: float = maxf(size.x, size.z)
            var thin: float = minf(size.x, size.z)
            if node.position.y < top_y - 0.20 and size.y >= 2.70 and size.y <= 3.30 and horizontal >= 5.0 and thin <= 0.50:
                node.material_override = facade_mat
                facade_surface_count += 1
        if node.position.y >= max_mesh_y - 0.80 and node.position.y >= top_y - 0.15:
            node.material_override = roof_mat
            roof_surface_count += 1

    print("[MAT] Edificio #%d - Colore facciata: %s, Texture: %s, superfici facciata: %d, tetto: %d" % [
        _building_counter,
        facade_color.to_html(false),
        FACADE_ALBEDO_PATH if _facade_albedo != null else "MANCANTE",
        facade_surface_count,
        roof_surface_count
    ])

func _mesh_nodes(root: Node3D) -> Array[MeshInstance3D]:
    var result: Array[MeshInstance3D] = []
    _collect_meshes(root, result)
    return result

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, result)
