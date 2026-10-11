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

    _save_resolved_layout(pois)
    print("ROMA POI PLACER: PASS slots=%d/%d buildings=%d map=2000x2000m modular=true" % [_resolved.size(), pois.size(), _buildings.size()])
    for item in _resolved:
        print("ROMA POI SLOT: %s local=(%.1f, %.1f) world=(%.1f, %.1f) footprint=%.1fx%.1f" % [
            item["id"], item["local_x"], item["local_z"], item["world_x"], item["world_z"], item["width"], item["depth"]
        ])

func _load_config() -> void:
    if not FileAccess.file_exists(POI_MANIFEST):
        return
    var text: String = FileAccess.get_file_as_string(POI_MANIFEST)
    var parsed: Variant = JSON.parse_string(text)
    if parsed is Dictionary:
        _config = parsed

func _load_building_centers() -> void:
    if not FileAccess.file_exists(BUILDING_MANIFEST):
        push_warning("POI: building manifest missing; safe placement cannot be certified")
        return
    var text: String = FileAccess.get_file_as_string(BUILDING_MANIFEST)
    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Dictionary):
        return
    for placement in parsed.get("placements", []):
        if placement is Dictionary and placement.has("x") and placement.has("z"):
            _buildings.append(Vector2(float(placement["x"]), float(placement["z"])))

func _resolve_poi(poi: Dictionary, placed: Array[Vector2]) -> Dictionary:
    var footprint: Array = poi.get("footprint", [56.0, 56.0])
    var width: float = float(footprint[0])
    var depth: float = float(footprint[1])
    var half_diag: float = sqrt(width * width + depth * depth) * 0.5
    var building_clearance: float = float(_config.get("placement", {}).get("building_clearance_m", 48.0))
    var min_slot_sep: float = float(_config.get("placement", {}).get("min_slot_separation_m", 95.0))
    var search_radius: float = float(_config.get("placement", {}).get("search_radius_m", 140.0))
    var step: float = float(_config.get("placement", {}).get("search_step_m", 10.0))

    # poi_layout.json stores intended positions in Godot world coordinates.
    # Convert to the manager's local slot space before searching; older target_cell
    # layouts remain supported only as a compatibility fallback.
    var target := Vector2.ZERO
    var configured_position: Variant = poi.get("position", null)
    if configured_position is Dictionary and configured_position.has("x") and configured_position.has("z"):
        target = Vector2(
            float(configured_position.get("x", WORLD_OFFSET.x)) - WORLD_OFFSET.x,
            float(configured_position.get("z", WORLD_OFFSET.z)) - WORLD_OFFSET.z
        )
    elif configured_position is Array and configured_position.size() >= 3:
        target = Vector2(float(configured_position[0]) - WORLD_OFFSET.x, float(configured_position[2]) - WORLD_OFFSET.z)
    else:
        var cell: Array = poi.get("target_cell", [3, 1])
        var ix: int = int(cell[0])
        var iz: int = int(cell[1])
        target = Vector2(lerp(-850.0, 850.0, float(ix) / 6.0), lerp(-700.0, 700.0, float(iz) / 2.0))

    var best: Vector2 = Vector2.ZERO
    var best_distance: float = INF
    var radius_steps: int = int(ceil(search_radius / step))
    for ring in range(radius_steps + 1):
        for sx in range(-ring, ring + 1):
            for sz in range(-ring, ring + 1):
                if max(abs(sx), abs(sz)) != ring:
                    continue
                var candidate: Vector2 = target + Vector2(float(sx) * step, float(sz) * step)
                if not _inside_map(candidate, width, depth):
                    continue
                if not _safe_from_buildings(candidate, half_diag + building_clearance):
                    continue
                if not _safe_from_pois(candidate, min_slot_sep, placed):
                    continue
                var d: float = candidate.distance_to(target)
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


func _save_resolved_layout(pois: Array) -> void:
    var source_by_id: Dictionary = {}
    for poi in pois:
        if poi is Dictionary:
            source_by_id[str(poi.get("id", ""))] = poi

    var output: Array[Dictionary] = []
    for item in _resolved:
        var source: Dictionary = source_by_id.get(str(item.get("id", "")), {})
        var poi_name := str(source.get("name", item.get("id", "POI")))
        var zone := _zone_settings_for_poi(poi_name)
        output.append({
            "id": str(item.get("id", "")),
            "name": poi_name,
            "x": float(item.get("world_x", 0.0)),
            "z": float(item.get("world_z", 0.0)),
            "local_x": float(item.get("local_x", 0.0)),
            "local_z": float(item.get("local_z", 0.0)),
            "radius": float(zone.get("radius", 220.0)),
            "falloff": float(zone.get("falloff", 90.0)),
            "texture_id": _texture_id_for_poi(poi_name),
            "target_error_m": float(item.get("target_error_m", 0.0))
        })

    var json_text := JSON.stringify(output, "\t")
    var resource_path := "res://city_library/poi/poi_layout_resolved.json"
    var file := FileAccess.open(resource_path, FileAccess.WRITE)
    if file:
        file.store_string(json_text + "\n")
        file.close()
        print("ROMA POI RESOLVED: saved ", resource_path, " count=", output.size())
    else:
        push_warning("ROMA POI RESOLVED: res:// non scrivibile, salvo in user://")
    var user_file := FileAccess.open("user://poi_layout_resolved.json", FileAccess.WRITE)
    if user_file:
        user_file.store_string(json_text + "\n")
        user_file.close()

    # Attach the painter only after the manager has finalized all real POI slots.
    var painter_script := load("res://city_library/poi/terrain_zone_painter.gd")
    if painter_script:
        var painter := Node.new()
        painter.name = "TerrainZonePainter"
        painter.set_script(painter_script)
        add_child(painter)

func _texture_id_for_poi(poi_name: String) -> int:
    var name := poi_name.to_lower()
    if "eur" in name or "civiltà" in name or "civilta" in name:
        return 4
    if "villa borghese" in name or "circo massimo" in name or "caracalla" in name:
        return 2
    if "termini" in name or "tiburtina" in name or "ostiense" in name or "piramide" in name:
        return 0
    return 1

func _zone_settings_for_poi(poi_name: String) -> Dictionary:
    var name := poi_name.to_lower()
    if "colosseo" in name or "foro romano" in name or "palatino" in name:
        return {"radius": 250.0, "falloff": 100.0}
    if "termini" in name or "tiburtina" in name:
        return {"radius": 200.0, "falloff": 80.0}
    if "vaticano" in name or "san pietro" in name:
        return {"radius": 300.0, "falloff": 120.0}
    if "pantheon" in name or "navona" in name:
        return {"radius": 220.0, "falloff": 90.0}
    if "trevi" in name or "spagna" in name:
        return {"radius": 220.0, "falloff": 90.0}
    if "venezia" in name or "campidoglio" in name:
        return {"radius": 220.0, "falloff": 90.0}
    if "circo massimo" in name or "caracalla" in name:
        return {"radius": 250.0, "falloff": 120.0}
    if "villa borghese" in name or "popolo" in name:
        return {"radius": 350.0, "falloff": 150.0}
    if "trastevere" in name or "isola tiberina" in name:
        return {"radius": 280.0, "falloff": 120.0}
    if "ostiense" in name or "piramide" in name:
        return {"radius": 220.0, "falloff": 90.0}
    if "eur" in name or "civiltà" in name or "civilta" in name:
        return {"radius": 300.0, "falloff": 120.0}
    return {"radius": 220.0, "falloff": 90.0}
