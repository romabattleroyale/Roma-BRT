extends Node3D
## Replaces the primitive V37 building mesh pass with the approved V11 City Library.
## Terrain3D remains authoritative for placement height.

const ADAPTER_SCRIPT := "res://city_library/buildings/house_library_adapter.gd"

var adapter: RomaHouseLibraryAdapter
var built := false

func _ready() -> void:
    adapter = load(ADAPTER_SCRIPT).new() as RomaHouseLibraryAdapter
    call_deferred("_wait_for_v37")

func _wait_for_v37() -> void:
    for _i in range(600):
        var v37 := get_parent().get_node_or_null("V37Integration")
        if v37 != null and v37.get("city_root") != null and not (v37.get("map_data") as Dictionary).is_empty():
            _build_library(v37)
            return
        await get_tree().create_timer(0.1).timeout
    push_warning("V11 Building Bridge: V37 world non pronto entro 60 secondi")

func _build_library(v37: Node) -> void:
    if built or adapter == null:
        return
    if not adapter.initialize():
        push_warning("V11 Building Bridge: City Library V11 non inizializzabile")
        return
    var city_root := v37.get("city_root") as Node3D
    var map_data := v37.get("map_data") as Dictionary
    var buildings: Array = map_data.get("city", {}).get("buildings", [])
    var placed := 0
    for i in range(buildings.size()):
        var data: Dictionary = buildings[i]
        var pos: Dictionary = data.get("position", {})
        var px := float(pos.get("x", 0.0))
        var pz := float(pos.get("z", 0.0))
        if not is_finite(px) or not is_finite(pz):
            continue
        var size: Dictionary = data.get("size", {})
        var width := maxf(6.0, float(size.get("x", 10.0)))
        var depth := maxf(6.0, float(size.get("z", 10.0)))
        var height := 0.0
        if v37.has_method("sample_height"):
            height = float(v37.sample_height(px, pz))
        if not is_finite(height):
            height = 0.0
        var style := str(data.get("style", ""))
        var variant := i
        var building := adapter.build_for_footprint(width, depth, Vector3(px, 0.0, pz), height, style, variant, 0.0)
        if building == null:
            building = adapter.build_for_footprint(width, depth, Vector3(px, 0.0, pz), height, "", variant, 0.0)
        if building == null:
            continue
        building.name = str(data.get("id", "V11Building_%03d" % i))
        city_root.add_child(building)
        placed += 1
    built = true
    print("V11 City Library: edifici modulari piazzati = ", placed, " / ", buildings.size())
