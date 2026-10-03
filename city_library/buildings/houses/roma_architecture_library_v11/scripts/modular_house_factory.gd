extends RefCounted
class_name RomaModularHouseFactory

const LIB_ROOT := "res://city_library/buildings/houses/roma_architecture_library_v11/"
const CATALOG_PATH := LIB_ROOT + "data/building_catalog.json"
const SYSTEM_SCRIPT := LIB_ROOT + "scripts/editor_library_building_system.gd"
const VISUAL_VARIATION_SCRIPT := "res://v37_integration/mobile_visual_variation.gd"

var catalog: Array[Dictionary] = []
var by_id: Dictionary = {}
var system: RomaLibraryBuildingSystem
var visual_variation = null

func initialize() -> bool:
    if system == null:
        system = load(SYSTEM_SCRIPT).new() as RomaLibraryBuildingSystem
        if system == null:
            return false
        system.setup_materials()
    if visual_variation == null:
        var visual_script: Script = load(VISUAL_VARIATION_SCRIPT) as Script
        if visual_script != null:
            visual_variation = visual_script.new()
    if not catalog.is_empty():
        return true
    if not FileAccess.file_exists(CATALOG_PATH):
        return false
    var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
    if file == null:
        return false
    var parsed = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        return false
    for item in parsed:
        if item is Dictionary and item.has("id"):
            var entry: Dictionary = item.duplicate(true)
            catalog.append(entry)
            by_id[str(entry["id"])] = entry
    return not catalog.is_empty()

func get_catalog() -> Array[Dictionary]:
    initialize()
    return catalog.duplicate(true)

func get_building(id: String) -> Dictionary:
    initialize()
    return (by_id.get(id, {}) as Dictionary).duplicate(true)

func build_by_id(id: String, variant: int = 0) -> Node3D:
    if not initialize() or not by_id.has(id):
        return null
    return system.build(by_id[id], variant)

func build_mobile_by_id(id: String, variant: int = 0) -> Node3D:
    if not initialize() or not by_id.has(id):
        return null
    var entry: Dictionary = by_id[id].duplicate(true)
    var height_pattern: Array[int] = [3, 4, 5, 4, 3, 5]
    var floors: int = height_pattern[posmod(variant, height_pattern.size())]
    entry["floors"] = floors
    entry["id"] = "__mobile_variant_%d" % variant
    var roof_variant: int = int(variant / 10) * 10
    if posmod(variant, 2) == 1:
        roof_variant += 7
    var root: Node3D = system.build(entry, roof_variant)
    if root == null:
        return null
    if visual_variation != null:
        visual_variation.apply(root, variant, floors)
    return root

func build_and_place(id: String, terrain_position: Vector3, terrain_height: float, rotation_y: float = 0.0, variant: int = 0) -> Node3D:
    if not terrain_position.is_finite() or not is_finite(terrain_height):
        return null
    var root := build_by_id(id, variant)
    if root == null:
        return null
    root.position = Vector3(terrain_position.x, terrain_height, terrain_position.z)
    root.rotation.y = rotation_y
    if not root.position.is_finite():
        root.queue_free()
        return null
    return root

func build_mobile_and_place(id: String, terrain_position: Vector3, terrain_height: float, rotation_y: float = 0.0, variant: int = 0) -> Node3D:
    if not terrain_position.is_finite() or not is_finite(terrain_height):
        return null
    var root := build_mobile_by_id(id, variant)
    if root == null:
        return null
    root.position = Vector3(terrain_position.x, terrain_height, terrain_position.z)
    root.rotation.y = rotation_y
    if not root.position.is_finite():
        root.queue_free()
        return null
    return root

func choose_id(min_w: float, max_w: float, min_d: float, max_d: float, function_filter: String = "", variant: int = 0) -> String:
    if not initialize():
        return ""
    var filter := function_filter.to_lower().strip_edges()
    var candidates: Array[Dictionary] = []
    for item in catalog:
        var w := float(item.get("w", item.get("width", 0.0)))
        var d := float(item.get("d", item.get("depth", 0.0)))
        if w < min_w or w > max_w or d < min_d or d > max_d:
            continue
        if not filter.is_empty() and not str(item.get("function", "")).to_lower().contains(filter):
            continue
        candidates.append(item)
    if candidates.is_empty() and not filter.is_empty():
        return choose_id(min_w, max_w, min_d, max_d, "", variant)
    if candidates.is_empty():
        return ""
    var index := posmod(variant, candidates.size())
    return str(candidates[index].get("id", ""))
