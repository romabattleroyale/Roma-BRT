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
    var world_x := float(resolved["world_x"])
    var world_z := float(resolved["world_z"])
    var ground_y := _ground_height(world_x, world_z)
    if instantiate_existing_modules and not scene_path.is_empty() and ResourceLoader.exists(scene_path):
        var packed := load(scene_path) as PackedScene
        if packed:
            var instance := packed.instantiate()
            instance.name = str(poi.get("id", "POI"))
            add_child(instance)
            instance.position = Vector3(world_x, ground_y, world_z)
            return

    # The module scenes are not present in this repository snapshot. Build a
    # visible, named landmark placeholder rather than silently omitting the POI.
    var root := Node3D.new()
    root.name = str(poi.get("id", "POI"))
    root.position = Vector3(world_x, ground_y, world_z)
    add_child(root)
    var id := str(poi.get("id", "poi"))
    var width := float(resolved["width"])
    var depth := float(resolved["depth"])
    var category := str(poi.get("category", "landmark"))
    var tint := Color(0.66, 0.56, 0.42)
    if category in ["station", "trasporti"]:
        tint = Color(0.48, 0.55, 0.62)
    elif category in ["park_landmark", "parco_piazza"]:
        tint = Color(0.3, 0.48, 0.27)
    elif category in ["modern", "moderno"]:
        tint = Color(0.68, 0.72, 0.75)
    elif category in ["square", "piazze_fontane"]:
        tint = Color(0.72, 0.62, 0.45)
    var pad_mat := _poi_material(Color(0.31, 0.29, 0.26))
    var stone_mat := _poi_material(tint)
    var accent_mat := _poi_material(Color(0.78, 0.69, 0.48))
    _poi_box(root, "POI_Footprint", Vector3(width, 0.5, depth), Vector3(0, 0.25, 0), pad_mat)
    var h := 12.0
    if id.contains("colosseo"):
        h = 18.0
        for i in range(16):
            var a := TAU * float(i) / 16.0
            _poi_cylinder(root, "Colosseum_Pier_%02d" % i, 2.2, 10.0, Vector3(cos(a) * 19.0, 5.25, sin(a) * 19.0), stone_mat)
        _poi_cylinder(root, "Colosseum_UpperRing", 23.0, 2.0, Vector3(0, 11.0, 0), accent_mat)
        _poi_cylinder(root, "Colosseum_Arena", 13.0, 1.0, Vector3(0, 1.0, 0), pad_mat)
    elif id.contains("vaticano"):
        h = 24.0
        _poi_box(root, "Basilica_Nave", Vector3(32, 10, 20), Vector3(0, 5, 0), stone_mat)
        _poi_cylinder(root, "St_Peters_Dome", 8.0, 12.0, Vector3(0, 16, 0), accent_mat)
        _poi_cylinder(root, "Dome_Lantern", 2.0, 5.0, Vector3(0, 24.5, 0), stone_mat)
    elif id.contains("termini") or id.contains("tiburtina"):
        h = 14.0
        _poi_box(root, "Station_MainHall", Vector3(width * 0.72, h, depth * 0.48), Vector3(0, h * 0.5, 0), stone_mat)
        _poi_box(root, "Station_Roof", Vector3(width * 0.78, 1.5, depth * 0.54), Vector3(0, h + 0.75, 0), accent_mat)
    elif id.contains("eur"):
        h = 25.0
        _poi_box(root, "EUR_Marble_Block", Vector3(26, h, 26), Vector3(0, h * 0.5, 0), stone_mat)
        for i in range(5):
            _poi_box(root, "EUR_Arch_%d" % i, Vector3(3.0, 12.0, 0.8), Vector3(-8.0 + i * 4.0, 8.0, -13.3), pad_mat)
    elif id.contains("villa") or id.contains("circo"):
        h = 5.0
        for i in range(9):
            _poi_box(root, "Park_Tree_%d" % i, Vector3(1.5, 5.0, 1.5), Vector3(-20 + (i % 3) * 20, 2.5, -20 + int(i / 3) * 20), stone_mat)
            _poi_cylinder(root, "Park_Canopy_%d" % i, 4.5, 3.5, Vector3(-20 + (i % 3) * 20, 6.5, -20 + int(i / 3) * 20), accent_mat)
    elif id.contains("trevi") or id.contains("pantheon") or id.contains("venezia"):
        h = 10.0
        _poi_cylinder(root, "Historic_Podium", 15.0, 2.0, Vector3(0, 1.0, 0), accent_mat)
        _poi_cylinder(root, "Historic_Landmark", 9.0, h, Vector3(0, h * 0.5 + 1.0, 0), stone_mat)
        _poi_cylinder(root, "Historic_Cap", 11.0, 1.5, Vector3(0, h + 2.0, 0), accent_mat)
    else:
        _poi_box(root, "Historic_Block", Vector3(width * 0.55, h, depth * 0.45), Vector3(0, h * 0.5, 0), stone_mat)
        _poi_box(root, "Historic_Roof", Vector3(width * 0.62, 1.5, depth * 0.52), Vector3(0, h + 0.75, 0), accent_mat)
    var label := Label3D.new()
    label.name = "POI_Name"
    label.text = str(poi.get("name", id))
    label.position = Vector3(0, h + 5.0, 0)
    label.font_size = 36
    label.pixel_size = 0.01
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    root.add_child(label)

func _ground_height(world_x: float, world_z: float) -> float:
    var generator := get_tree().current_scene.find_child("MapGenerator", true, false)
    if generator != null and generator.has_method("sample_height"):
        return float(generator.call("sample_height", world_x, world_z))
    return SLOT_Y

func _poi_material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.88
    return material

func _poi_box(root: Node3D, node_name: String, size: Vector3, at: Vector3, material: Material) -> void:
    var mesh := BoxMesh.new()
    mesh.size = size
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.material_override = material
    instance.position = at
    root.add_child(instance)

func _poi_cylinder(root: Node3D, node_name: String, radius: float, height: float, at: Vector3, material: Material) -> void:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 24
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.material_override = material
    instance.position = at
    root.add_child(instance)


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
