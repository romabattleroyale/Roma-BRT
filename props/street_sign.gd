extends Node3D
## Reusable Roman street-name sign.

@export var street_name: String = "VIA CAVOUR"

func _ready() -> void:
    var black := _mat(Color("#16181A"), 0.82)
    var white := _mat(Color("#F1EBDD"), 0.72)

    var pole := MeshInstance3D.new()
    var pole_mesh := CylinderMesh.new()
    pole_mesh.top_radius = 0.045
    pole_mesh.bottom_radius = 0.06
    pole_mesh.height = 3.0
    pole_mesh.radial_segments = 8
    pole.mesh = pole_mesh
    pole.material_override = black
    pole.position.y = 1.5
    add_child(pole)

    var plate := MeshInstance3D.new()
    var plate_mesh := BoxMesh.new()
    plate_mesh.size = Vector3(1.0, 0.3, 0.02)
    plate.mesh = plate_mesh
    plate.material_override = white
    plate.position = Vector3(0.0, 2.65, 0.0)
    add_child(plate)

    var label := Label3D.new()
    label.text = street_name
    label.font_size = 48
    label.modulate = Color("#17355A")
    label.outline_size = 4
    label.outline_modulate = Color("#F1EBDD")
    label.pixel_size = 0.0028
    label.position = Vector3(0.0, 2.65, -0.018)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(label)

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material
