extends RefCounted
class_name RomaHouseLibraryAdapter

const FACTORY_SCRIPT := "res://city_library/buildings/houses/roma_architecture_library_v11/scripts/modular_house_factory.gd"

var factory: RomaModularHouseFactory
var initialized := false

func initialize() -> bool:
    if initialized:
        return true
    factory = RomaModularHouseFactory.new()
    initialized = factory.initialize()
    return initialized

func catalog_size() -> int:
    if not initialize():
        return 0
    return factory.get_catalog().size()

func choose_for_footprint(width: float, depth: float, function_filter: String = "", variant: int = 0) -> String:
    if not initialize():
        return ""
    if not width.is_finite() or not depth.is_finite() or width <= 0.0 or depth <= 0.0:
        return ""
    # Prefer an archetype that fits the requested footprint without changing the
    # source footprint. A later placement pass can rotate the selected module.
    var tolerance_w := maxf(2.0, width * 0.30)
    var tolerance_d := maxf(2.0, depth * 0.30)
    return factory.choose_id(maxf(1.0, width - tolerance_w), width + tolerance_w, maxf(1.0, depth - tolerance_d), depth + tolerance_d, function_filter, variant)

func build_for_footprint(width: float, depth: float, terrain_position: Vector3, terrain_height: float, function_filter: String = "", variant: int = 0, rotation_y: float = 0.0) -> Node3D:
    if not initialize():
        return null
    var id := choose_for_footprint(width, depth, function_filter, variant)
    if id.is_empty():
        return null
    return factory.build_and_place(id, terrain_position, terrain_height, rotation_y, variant)

func build_by_id(id: String, terrain_position: Vector3, terrain_height: float, rotation_y: float = 0.0, variant: int = 0) -> Node3D:
    if not initialize() or id.is_empty():
        return null
    return factory.build_and_place(id, terrain_position, terrain_height, rotation_y, variant)
