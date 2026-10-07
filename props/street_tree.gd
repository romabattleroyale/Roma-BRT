extends Node3D
## Low-poly Roman street tree: trunk + compact foliage, Android friendly.

func _ready() -> void:
    var trunk_mat := _mat(Color("#5A3B25"), 0.95)
    var leaf_mat := _mat(Color("#3D7A3A"), 0.90)

    var trunk := MeshInstance3D.new()
    var trunk_mesh := CylinderMesh.new()
    trunk_mesh.top_radius = 0.09
    trunk_mesh.bottom_radius = 0.14
    trunk_mesh.height = 2.4
    trunk_mesh.radial_segments = 7
    trunk.mesh = trunk_mesh
    trunk.material_override = trunk_mat
    trunk.position.y = 1.2
    add_child(trunk)

    var crown := MeshInstance3D.new()
    var crown_mesh := SphereMesh.new()
    crown_mesh.radius = 1.15
    crown_mesh.height = 2.1
    crown_mesh.radial_segments = 8
    crown_mesh.rings = 4
    crown.mesh = crown_mesh
    crown.material_override = leaf_mat
    crown.position.y = 3.0
    add_child(crown)

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material
