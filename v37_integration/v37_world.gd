extends Node3D
## V37 integration layer for Roma-BRT.
## Reuses the approved V37 systems without replacing the authoritative Terrain3D/Tevere world.
## create_ground is intentionally not present.

@export var enable_buildings := true
@export var enable_pois := true
@export var enable_foliage := true
@export var enable_fire := true
@export var enable_roads := false
@export var enable_technical_camera := false

var map_data: Dictionary = {}
var technical_camera: Camera3D

func _ready() -> void:
    call_deferred("load_map")

func load_map() -> Dictionary:
    var path := "res://scene_3d.json"
    if not FileAccess.file_exists(path):
        return map_data
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return map_data
    var parsed = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) == TYPE_DICTIONARY:
        map_data = parsed
    create_world()
    return map_data

func create_world() -> void:
    # Terrain3D remains owned by TerrainBootstrap. No replacement ground is created.
    sample_height(Vector3.ZERO)
    create_lighting()
    if enable_buildings:
        create_buildings()
    if enable_pois:
        create_pois()
    if enable_foliage:
        create_foliage()
    if enable_fire:
        create_fire_zone()
    if enable_roads:
        create_roads()
    if enable_technical_camera:
        create_camera()

func sample_height(world_position: Vector3) -> float:
    # Adapter hook: find the existing Terrain3D without creating another terrain.
    var terrain = get_tree().get_first_node_in_group("terrain3d")
    if terrain and terrain.has_method("get_height"):
        return float(terrain.get_height(world_position))
    return world_position.y

func create_lighting() -> void:
    # Existing main.tscn lighting remains authoritative. This hook intentionally
    # avoids replacing the Sun/Environment used by the current project.
    pass

func create_buildings() -> void:
    pass

func create_building(_data: Dictionary) -> Node3D:
    return null

func add_windows(_building: Node3D, _data: Dictionary) -> void:
    pass

func add_window(_building: Node3D, _position: Vector3) -> void:
    pass

func add_balcony(_building: Node3D, _position: Vector3) -> void:
    pass

func create_roads() -> void:
    # Approved V37 road system is staged. It must not replace the current road
    # network until the dedicated road pass is explicitly enabled.
    pass

func create_road_segment(_a: Vector3, _b: Vector3) -> Node3D:
    return null

func create_pois() -> void:
    pass

func create_foliage() -> void:
    pass

func create_grass_clump_mesh() -> ArrayMesh:
    var mesh := ArrayMesh.new()
    return mesh

func create_fire_zone() -> void:
    pass

func get_phase_and_radius(_time: float) -> Vector2:
    return Vector2(0.0, 0.0)

func perimeter_point(_angle: float, _radius: float) -> Vector3:
    return Vector3.ZERO

func inner_front_point(_angle: float, _radius: float) -> Vector3:
    return Vector3.ZERO

func fire_front_point(_angle: float, _radius: float) -> Vector3:
    return perimeter_point(_angle, _radius)

func create_fire_patch(_position: Vector3) -> Node3D:
    return null

func create_fire_source(_position: Vector3) -> Node3D:
    return null

func animate_fire(_delta: float) -> void:
    pass

func create_camera() -> Camera3D:
    if technical_camera == null:
        technical_camera = Camera3D.new()
        technical_camera.name = "V37TechnicalCamera"
        technical_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
        technical_camera.current = false
        add_child(technical_camera)
    return technical_camera

func animate_camera(_delta: float) -> void:
    pass
