extends Node3D
## Reusable low-poly Roman nasone fountain.

func _ready() -> void:
    var iron := _mat(Color("#202224"), 0.78)
    var water := _mat(Color("#6FB7D8"), 0.25, true)

    var body := MeshInstance3D.new()
    var body_mesh := CylinderMesh.new()
    body_mesh.top_radius = 0.11
    body_mesh.bottom_radius = 0.15
    body_mesh.height = 1.0
    body_mesh.radial_segments = 8
    body.mesh = body_mesh
    body.material_override = iron
    body.position.y = 0.5
    add_child(body)

    var head := MeshInstance3D.new()
    var head_mesh := SphereMesh.new()
    head_mesh.radius = 0.16
    head_mesh.height = 0.28
    head.mesh = head_mesh
    head.material_override = iron
    head.position.y = 1.05
    add_child(head)

    var spout := MeshInstance3D.new()
    var spout_mesh := CylinderMesh.new()
    spout_mesh.top_radius = 0.035
    spout_mesh.bottom_radius = 0.045
    spout_mesh.height = 0.25
    spout_mesh.radial_segments = 6
    spout.mesh = spout_mesh
    spout.material_override = iron
    spout.rotation.z = PI * 0.5
    spout.position = Vector3(0.0, 0.72, 0.13)
    add_child(spout)

    var stream := MeshInstance3D.new()
    var stream_mesh := CylinderMesh.new()
    stream_mesh.top_radius = 0.018
    stream_mesh.bottom_radius = 0.018
    stream_mesh.height = 0.18
    stream_mesh.radial_segments = 6
    stream.mesh = stream_mesh
    stream.material_override = water
    stream.position = Vector3(0.0, 0.60, 0.25)
    stream.rotation.x = PI * 0.5
    add_child(stream)

func _mat(color: Color, roughness: float, emission: bool = false) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    if emission:
        material.emission_enabled = true
        material.emission = color
        material.emission_energy_multiplier = 0.5
    return material
