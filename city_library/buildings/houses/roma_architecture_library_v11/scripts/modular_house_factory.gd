extends RefCounted
class_name RomaModularHouseFactory

const ROOT := "res://city_library/buildings/houses/roma_architecture_library_v11/"
const SYSTEM_SCRIPT := ROOT + "scripts/library_building_system.gd"

var library := RomaHouseLibrary.new()
var system: RomaLibraryBuildingSystem
var loaded := false

func initialize() -> bool:
    if loaded:
        return true
    if not library.load_catalog():
        return false
    system = RomaLibraryBuildingSystem.new()
    system.name = "RomaLibraryBuildingSystem"
    system.setup_materials()
    loaded = true
    return true

func get_catalog() -> Array[Dictionary]:
    if not loaded:
        initialize()
    return library.get_all()

func build_by_id(id: String, variant: int = 0) -> Node3D:
    if not initialize():
        return null
    var data := library.get_building(id)
    if data.is_empty():
        return null
    return system.build(data, variant)

func build_matching(min_width: float, max_width: float, min_depth: float, max_depth: float, function_filter: String = "", variant: int = 0) -> Node3D:
    if not initialize():
        return null
    var candidates: Array[Dictionary] = []
    var filter := function_filter.to_lower().strip_edges()
    for data in library.get_all():
        var w := float(data.get("w", 0.0))
        var d := float(data.get("d", 0.0))
        var function_name := str(data.get("function", "")).to_lower()
        if w < min_width or w > max_width or d < min_depth or d > max_depth:
            continue
        if not filter.is_empty() and not function_name.contains(filter):
            continue
        candidates.append(data)
    if candidates.is_empty():
        return null
    var chosen: Dictionary = candidates[variant % candidates.size()]
    return system.build(chosen, variant)

func place_on_terrain(building: Node3D, world_position: Vector3, terrain_height: float, rotation_y: float = 0.0) -> Node3D:
    if building == null:
        return null
    if not terrain_height.is_finite():
        return null
    if not world_position.is_finite():
        return null
    building.position = Vector3(world_position.x, terrain_height, world_position.z)
    building.rotation.y = rotation_y
    return building

func build_and_place(id: String, world_position: Vector3, terrain_height: float, rotation_y: float = 0.0, variant: int = 0) -> Node3D:
    var building := build_by_id(id, variant)
    return place_on_terrain(building, world_position, terrain_height, rotation_y)

func choose_id(min_width: float, max_width: float, min_depth: float, max_depth: float, function_filter: String = "", variant: int = 0) -> String:
    if not initialize():
        return ""
    var candidates: Array[String] = []
    var filter := function_filter.to_lower().strip_edges()
    for data in library.get_all():
        var w := float(data.get("w", 0.0))
        var d := float(data.get("d", 0.0))
        var function_name := str(data.get("function", "")).to_lower()
        if w < min_width or w > max_width or d < min_depth or d > max_depth:
            continue
        if not filter.is_empty() and not function_name.contains(filter):
            continue
        candidates.append(str(data.get("id", "")))
    if candidates.is_empty():
        return ""
    return candidates[variant % candidates.size()]
