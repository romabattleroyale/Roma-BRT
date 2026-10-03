extends RefCounted
class_name RomaHouseLibrary

const ROOT := "res://city_library/buildings/houses/roma_architecture_library_v11/"
const CATALOG_PATH := ROOT + "data/building_catalog.json"

var catalog: Array[Dictionary] = []
var by_id: Dictionary = {}

func load_catalog() -> bool:
    if not FileAccess.file_exists(CATALOG_PATH):
        return false
    var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
    if file == null:
        return false
    var parsed = JSON.parse_string(file.get_as_text())
    if not (parsed is Array):
        return false
    catalog.clear()
    by_id.clear()
    for item in parsed:
        if item is Dictionary and item.has("id"):
            var entry: Dictionary = item.duplicate(true)
            catalog.append(entry)
            by_id[str(entry["id"])] = entry
    return not catalog.is_empty()

func get_building(id: String) -> Dictionary:
    return (by_id.get(id, {}) as Dictionary).duplicate(true)

func get_all() -> Array[Dictionary]:
    return catalog.duplicate(true)

func has(id: String) -> bool:
    return by_id.has(id)
