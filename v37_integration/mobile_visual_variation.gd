extends RefCounted
class_name RomaMobileVisualVariation

const FACADE_COLORS = [
    Color("#B97845"),
    Color("#D3A63A"),
    Color("#B96F73"),
    Color("#C7AA83"),
    Color("#A9573B"),
    Color("#A99A7E")
]

const ROOF_COLORS = [
    Color("#B84D32"),
    Color("#C9783F"),
    Color("#8F6B4E")
]

func apply(root: Node3D, variant: int, floors: int) -> void:
    var facade_color: Color = FACADE_COLORS[posmod(variant * 7 + 1, FACADE_COLORS.size())]
    var roof_color: Color = ROOF_COLORS[posmod(variant * 5 + 2, ROOF_COLORS.size())]
    var facade_mat := StandardMaterial3D.new()
    facade_mat.albedo_color = facade_color
    facade_mat.roughness = 0.88
    var roof_mat := StandardMaterial3D.new()
    roof_mat.albedo_color = roof_color
    roof_mat.roughness = 0.90
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
        if node.position.y >= max_mesh_y - 0.80 and node.position.y >= top_y - 0.15:
            node.material_override = roof_mat

func _mesh_nodes(root: Node3D) -> Array[MeshInstance3D]:
    var result: Array[MeshInstance3D] = []
    _collect_meshes(root, result)
    return result

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, result)
