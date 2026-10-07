extends RefCounted
## Reusable Roman travertine sidewalk builder.
## Keeps geometry low-poly and samples Terrain3D only for Y placement.

static var _travertine_mat: StandardMaterial3D
static var _curb_mat: StandardMaterial3D
static var _gutter_mat: StandardMaterial3D
static var _joint_mat: StandardMaterial3D

static func _ensure_materials() -> void:
    if _travertine_mat != null:
        return
    _travertine_mat = _make_material(Color("#D4C8B0"), 0.90)
    _curb_mat = _make_material(Color("#C7BDA9"), 0.92)
    _gutter_mat = _make_material(Color("#514F4A"), 0.98)
    _joint_mat = _make_material(Color("#8E846F"), 0.98)

static func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material

static func add_pair(parent: Node3D, terrain_data: Object, p0: Vector3, p1: Vector3, road_width: float = 8.0, sidewalk_width: float = 1.5) -> void:
    _ensure_materials()
    var flat_a: Vector3 = Vector3(p0.x, 0.0, p0.z)
    var flat_b: Vector3 = Vector3(p1.x, 0.0, p1.z)
    var direction: Vector3 = (flat_b - flat_a).normalized()
    var side: Vector3 = Vector3(-direction.z, 0.0, direction.x)
    var length: float = flat_a.distance_to(flat_b) + 0.18
    var center: Vector3 = (flat_a + flat_b) * 0.5

    for side_sign in [-1.0, 1.0]:
        var sidewalk_center: Vector3 = center + side * side_sign * 5.0
        _add_box(parent, terrain_data, sidewalk_center, direction, sidewalk_width, 0.15, length, 0.08, _travertine_mat)
        var curb_center: Vector3 = center + side * side_sign * 4.10
        _add_box(parent, terrain_data, curb_center, direction, 0.22, 0.16, length, 0.16, _curb_mat)
        var gutter_center: Vector3 = center + side * side_sign * 4.22
        _add_box(parent, terrain_data, gutter_center, direction, 0.20, 0.06, length, 0.06, _gutter_mat)

        # Visible travertine slab joints, kept sparse for Android.
        for joint in range(1, int(length / 4.0)):
            var t: float = float(joint * 4.0) / length
            var joint_center: Vector3 = flat_a.lerp(flat_b, t) + side * side_sign * 5.0
            _add_box(parent, terrain_data, joint_center, direction, 0.025, 0.156, 0.012, 0.16, _joint_mat)

static func _surface(terrain_data: Object, x: float, z: float, extra: float) -> Vector3:
    var y: float = 0.0
    if terrain_data != null:
        y = float(terrain_data.call("get_height", Vector3(x, 0.0, z)))
    if is_nan(y) or is_inf(y):
        y = 0.0
    return Vector3(x, y + 0.07 + extra, z)

static func _add_box(parent: Node3D, terrain_data: Object, center: Vector3, direction: Vector3, width: float, height: float, length: float, extra: float, material: Material) -> void:
    var a: Vector3 = _surface(terrain_data, center.x - direction.x * length * 0.5, center.z - direction.z * length * 0.5, extra + height * 0.5)
    var b: Vector3 = _surface(terrain_data, center.x + direction.x * length * 0.5, center.z + direction.z * length * 0.5, extra + height * 0.5)
    var mesh := BoxMesh.new()
    mesh.size = Vector3(width, height, maxf(0.10, a.distance_to(b) + 0.18))
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = material
    parent.add_child(instance)
    instance.look_at_from_position((a + b) * 0.5, (a + b) * 0.5 + direction, Vector3.UP)

static func _travertine() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#D4C8B0")
    material.roughness = 0.90
    return material

static func _curb() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#C7BDA9")
    material.roughness = 0.92
    return material

static func _gutter() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#514F4A")
    material.roughness = 0.98
    return material

static func _joint() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#8E846F")
    material.roughness = 0.98
    return material
