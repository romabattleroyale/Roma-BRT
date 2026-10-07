extends Node3D
## Reusable low-poly Roman wrought-iron street lamp.

@export var warm_energy: float = 1.2
@export var light_range: float = 8.0

func _ready() -> void:
    var black := _mat(Color("#17181A"), 0.82)
    var warm := _mat(Color("#FFB366"), 0.55, true)

    var pole := MeshInstance3D.new()
    var pole_mesh := CylinderMesh.new()
    pole_mesh.top_radius = 0.08
    pole_mesh.bottom_radius = 0.10
    pole_mesh.height = 4.0
    pole_mesh.radial_segments = 8
    pole.mesh = pole_mesh
    pole.material_override = black
    pole.position.y = 2.0
    add_child(pole)

    var lantern := CSGBox3D.new()
    lantern.size = Vector3(0.4, 0.4, 0.4)
    lantern.material = black
    lantern.position = Vector3(0.0, 4.0, 0.0)
    add_child(lantern)

    # Simple cage bars around the warm core.
    for x in [-0.17, 0.17]:
        var bar := MeshInstance3D.new()
        var bar_mesh := BoxMesh.new()
        bar_mesh.size = Vector3(0.035, 0.42, 0.035)
        bar.mesh = bar_mesh
        bar.material_override = black
        bar.position = Vector3(x, 4.0, 0.17)
        add_child(bar)
    for z in [-0.17, 0.17]:
        var bar := MeshInstance3D.new()
        var bar_mesh := BoxMesh.new()
        bar_mesh.size = Vector3(0.035, 0.42, 0.035)
        bar.mesh = bar_mesh
        bar.material_override = black
        bar.position = Vector3(0.17, 4.0, z)
        add_child(bar)

    var glow := MeshInstance3D.new()
    var glow_mesh := SphereMesh.new()
    glow_mesh.radius = 0.11
    glow_mesh.height = 0.22
    glow.mesh = glow_mesh
    glow.material_override = warm
    glow.position.y = 4.0
    add_child(glow)

    var light := OmniLight3D.new()
    light.light_color = Color("#FFB366")
    light.light_energy = warm_energy
    light.omni_range = light_range
    light.shadow_enabled = false
    light.position.y = 4.0
    add_child(light)

func _mat(color: Color, roughness: float, emission: bool = false) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    if emission:
        material.emission_enabled = true
        material.emission = color
        material.emission_energy_multiplier = 1.4
    return material
