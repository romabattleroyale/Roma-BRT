extends Node3D
## Roma Battle Royale — measured modular POI placer.
## It reserves POI footprints in local map space, avoids existing building centers
## from baked_city/ready_templates/manifest.json, and converts to world space once.
## No terrain, road, river, or existing building transform is modified.

const POI_MANIFEST := "res://city_library/poi/poi_manifest.json"
const BUILDING_MANIFEST := "res://baked_city/ready_templates/manifest.json"
const WORLD_OFFSET := Vector3(1000.0, 0.0, 1000.0)
const LOCAL_MIN := -1000.0
const LOCAL_MAX := 1000.0
const SLOT_Y := 0.0
const MARKER_HEIGHT := 0.20

@export var show_reservation_markers := false
@export var instantiate_existing_modules := true

var _config: Dictionary = {}
var _buildings: Array[Vector2] = []
var _resolved: Array[Dictionary] = []

func _ready() -> void:
    call_deferred("_build_poi_layout")

func _build_poi_layout() -> void:
    # Give the building bridge / terrain one frame to finish its initial spawn.
    await get_tree().process_frame
    await get_tree().process_frame
    _load_config()
    _load_building_centers()

    if _config.is_empty():
        push_error("POI: manifest not available; no POIs placed")
        return

    var pois: Array = _config.get("pois", [])
    var placed_positions: Array[Vector2] = []
    for poi in pois:
        var resolved := _resolve_poi(poi, placed_positions)
        if resolved.is_empty():
            push_warning("POI: no safe slot found for %s" % str(poi.get("name", poi.get("id", "unknown"))))
            continue
        placed_positions.append(Vector2(resolved["local_x"], resolved["local_z"]))
        _resolved.append(resolved)
        _spawn_poi(poi, resolved)

    print("ROMA POI PLACER: PASS slots=%d/%d buildings=%d map=2000x2000m modular=true" % [_resolved.size(), pois.size(), _buildings.size()])
    for item in _resolved:
        print("ROMA POI SLOT: %s local=(%.1f, %.1f) world=(%.1f, %.1f) footprint=%.1fx%.1f" % [
            item["id"], item["local_x"], item["local_z"], item["world_x"], item["world_z"], item["width"], item["depth"]
        ])

func _load_config() -> void:
    if not FileAccess.file_exists(POI_MANIFEST):
        return
    var text := FileAccess.get_file_as_string(POI_MANIFEST)
    var parsed = JSON.parse_string(text)
    if parsed is Dictionary:
        _config = parsed

func _load_building_centers() -> void:
    if not FileAccess.file_exists(BUILDING_MANIFEST):
        push_warning("POI: building manifest missing; safe placement cannot be certified")
        return
    var text := FileAccess.get_file_as_string(BUILDING_MANIFEST)
    var parsed = JSON.parse_string(text)
    if not (parsed is Dictionary):
        return
    for placement in parsed.get("placements", []):
        if placement is Dictionary and placement.has("x") and placement.has("z"):
            _buildings.append(Vector2(float(placement["x"]), float(placement["z"])))

func _resolve_poi(poi: Dictionary, placed: Array[Vector2]) -> Dictionary:
    var footprint: Array = poi.get("footprint", [56.0, 56.0])
    var width := float(footprint[0])
    var depth := float(footprint[1])
    var half_diag := sqrt(width * width + depth * depth) * 0.5
    var building_clearance := float(_config.get("placement", {}).get("building_clearance_m", 48.0))
    var min_slot_sep := float(_config.get("placement", {}).get("min_slot_separation_m", 95.0))
    var search_radius := float(_config.get("placement", {}).get("search_radius_m", 140.0))
    var step := float(_config.get("placement", {}).get("search_step_m", 10.0))

    var cell: Array = poi.get("target_cell", [0, 0])
    var ix := int(cell[0])
    var iz := int(cell[1])
    var target_x := lerp(-850.0, 850.0, float(ix) / 6.0)
    var target_z := lerp(-700.0, 700.0, float(iz) / 2.0)
    var target := Vector2(target_x, target_z)

    var best := Vector2.ZERO
    var best_distance := INF
    var radius_steps := int(ceil(search_radius / step))
    for ring in range(radius_steps + 1):
        for sx in range(-ring, ring + 1):
            for sz in range(-ring, ring + 1):
                if max(abs(sx), abs(sz)) != ring:
                    continue
                var candidate := target + Vector2(float(sx) * step, float(sz) * step)
                if not _inside_map(candidate, width, depth):
                    continue
                if not _safe_from_buildings(candidate, half_diag + building_clearance):
                    continue
                if not _safe_from_pois(candidate, min_slot_sep, placed):
                    continue
                var d := candidate.distance_to(target)
                if d < best_distance:
                    best = candidate
                    best_distance = d
        if best_distance < INF:
            break

    if best_distance == INF:
        return {}

    return {
        "id": str(poi.get("id", "poi")),
        "local_x": best.x,
        "local_z": best.y,
        "world_x": best.x + WORLD_OFFSET.x,
        "world_z": best.y + WORLD_OFFSET.z,
        "width": width,
        "depth": depth,
        "target_error_m": best_distance
    }

func _inside_map(candidate: Vector2, width: float, depth: float) -> bool:
    return candidate.x - width * 0.5 >= LOCAL_MIN and candidate.x + width * 0.5 <= LOCAL_MAX and candidate.y - depth * 0.5 >= LOCAL_MIN and candidate.y + depth * 0.5 <= LOCAL_MAX

func _safe_from_buildings(candidate: Vector2, clearance_radius: float) -> bool:
    for building in _buildings:
        if candidate.distance_to(building) < clearance_radius:
            return false
    return true

func _safe_from_pois(candidate: Vector2, min_distance: float, placed: Array[Vector2]) -> bool:
    for other in placed:
        if candidate.distance_to(other) < min_distance:
            return false
    return true

func _spawn_poi(poi: Dictionary, resolved: Dictionary) -> void:
    var scene_path := str(poi.get("scene", ""))
    if instantiate_existing_modules and not scene_path.is_empty() and ResourceLoader.exists(scene_path):
        var packed := load(scene_path) as PackedScene
        if packed:
            var instance := packed.instantiate()
            instance.name = str(poi.get("id", "POI"))
            add_child(instance)
            instance.position = Vector3(resolved["world_x"], SLOT_Y, resolved["world_z"])
            return

    if show_reservation_markers:
        var marker := MeshInstance3D.new()
        marker.name = str(poi.get("id", "POI")) + "_Reservation"
        var box := BoxMesh.new()
        box.size = Vector3(float(resolved["width"]), MARKER_HEIGHT, float(resolved["depth"]))
        marker.mesh = box
        marker.position = Vector3(resolved["world_x"], SLOT_Y, resolved["world_z"])
        add_child(marker)
