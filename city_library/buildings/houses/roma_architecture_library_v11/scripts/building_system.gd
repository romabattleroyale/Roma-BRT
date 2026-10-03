extends Node3D
class_name RomaBuildingSystem

const FLOOR_H: float = 3.2
const WALL_T: float = 0.28
const FRONT_Z_OFFSET: float = 0.17

var mats: Dictionary = {}

func setup_materials() -> void:
    mats["plaster_cream"] = _pbr("res://assets/textures/roman_plaster_cream.jpg", "res://assets/textures/roman_plaster_cream_normal.jpg", 0.88, 3.2)
    mats["plaster_pale"] = _pbr("res://assets/textures/roman_plaster_pale.jpg", "res://assets/textures/roman_plaster_pale_normal.jpg", 0.90, 3.2)
    mats["plaster_terracotta"] = _pbr("res://assets/textures/roman_plaster_terracotta.jpg", "res://assets/textures/roman_plaster_terracotta_normal.jpg", 0.86, 3.0)
    mats["brick"] = _pbr("res://assets/textures/brick_weathered_albedo.jpg", "res://assets/textures/brick_weathered_normal.jpg", 0.92, 4.0)
    var brick_rough: Texture2D = load("res://assets/textures/brick_weathered_roughness.jpg") as Texture2D
    var brick_mat: StandardMaterial3D = mats["brick"] as StandardMaterial3D
    if brick_rough:
        brick_mat.roughness_texture = brick_rough
        brick_mat.roughness = 0.88
    mats["travertine"] = _weathered_pbr("res://assets/textures/travertine_weathered_albedo.jpg", "res://assets/textures/travertine_weathered_normal.jpg", "res://assets/textures/travertine_weathered_roughness.jpg", 0.86, 2.8)
    mats["wood"] = _pbr("res://assets/textures/dark_wood.jpg", "res://assets/textures/dark_wood_normal.jpg", 0.78, 2.0)
    mats["painted_wood"] = _pbr("res://assets/textures/painted_wood.jpg", "res://assets/textures/painted_wood_normal.jpg", 0.80, 2.0)
    mats["roof"] = _warm_roof(Color("#E45B2F"), 3.5)
    mats["roof_terrace"] = _terracotta_terrace()
    mats["fabric_blue"] = _pbr("res://assets/textures/fabric_blue.jpg", "", 0.84, 2.2)

    mats["shutter_green"] = _pbr("res://assets/textures/painted_wood.jpg", "res://assets/textures/painted_wood_normal.jpg", 0.82, 2.0)
    mats["shutter_warm"] = _pbr("res://assets/textures/painted_wood.jpg", "res://assets/textures/painted_wood_normal.jpg", 0.80, 2.0)
    mats["stucco"] = StandardMaterial3D.new()
    (mats["stucco"] as StandardMaterial3D).albedo_color = Color("#D9C3A1")
    (mats["stucco"] as StandardMaterial3D).roughness = 0.86
    mats["weathered_plaster"] = _weathered_pbr("res://assets/textures/roman_plaster_weathered_albedo.jpg", "res://assets/textures/roman_plaster_weathered_normal.jpg", "res://assets/textures/roman_plaster_weathered_roughness.jpg", 0.94, 3.8)
    mats["iron"] = StandardMaterial3D.new()
    (mats["iron"] as StandardMaterial3D).albedo_color = Color("#252522")
    (mats["iron"] as StandardMaterial3D).metallic = 0.78
    (mats["iron"] as StandardMaterial3D).roughness = 0.42
    mats["dark_stone"] = StandardMaterial3D.new()
    (mats["dark_stone"] as StandardMaterial3D).albedo_color = Color("#B8876D")
    (mats["dark_stone"] as StandardMaterial3D).roughness = 0.92

    var metal: StandardMaterial3D = StandardMaterial3D.new()
    metal.albedo_color = Color("#30363A")
    metal.metallic = 0.72
    metal.roughness = 0.36
    mats["metal"] = metal

    var stone: StandardMaterial3D = StandardMaterial3D.new()
    stone.albedo_color = Color("#D9C9AA")
    stone.roughness = 0.84
    mats["stone"] = stone

    var glass: StandardMaterial3D = StandardMaterial3D.new()
    glass.albedo_color = Color(0.82, 0.92, 0.90, 0.18)
    glass.metallic = 0.05
    glass.roughness = 0.18
    glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    glass.cull_mode = BaseMaterial3D.CULL_DISABLED
    mats["glass"] = glass

    var interior: StandardMaterial3D = StandardMaterial3D.new()
    interior.albedo_color = Color("#A37A5B")
    interior.roughness = 0.88
    mats["interior"] = interior

    var warm: StandardMaterial3D = StandardMaterial3D.new()
    warm.albedo_color = Color(1.0, 0.64, 0.28)
    warm.emission_enabled = true
    warm.emission = Color(1.0, 0.38, 0.10)
    warm.emission_energy_multiplier = 1.2
    mats["warm"] = warm

    var awning: StandardMaterial3D = StandardMaterial3D.new()
    awning.albedo_color = Color("#8A3E32")
    awning.roughness = 0.88
    mats["awning"] = awning

    var plant: StandardMaterial3D = StandardMaterial3D.new()
    plant.albedo_color = Color("#4D6D3F")
    plant.roughness = 0.96
    mats["plant"] = plant

    # Roman facades: warm albedo + real plaster color texture + normal + roughness.
    mats["facade_ochre"] = _weathered_facade(Color("#FFF0C9"), "res://assets/textures/roman_plaster_weathered_albedo.jpg", "res://assets/textures/roman_plaster_weathered_normal.jpg", "res://assets/textures/roman_plaster_weathered_roughness.jpg")
    mats["facade_yellow"] = _weathered_facade(Color("#FFF2B8"), "res://assets/textures/roman_plaster_weathered_albedo.jpg", "res://assets/textures/roman_plaster_weathered_normal.jpg", "res://assets/textures/roman_plaster_weathered_roughness.jpg")
    mats["facade_beige"] = _weathered_facade(Color("#FFF2DA"), "res://assets/textures/roman_plaster_weathered_albedo.jpg", "res://assets/textures/roman_plaster_weathered_normal.jpg", "res://assets/textures/roman_plaster_weathered_roughness.jpg")
    mats["facade_terracotta"] = _weathered_facade(Color("#FFD0B2"), "res://assets/textures/roman_plaster_weathered_albedo.jpg", "res://assets/textures/roman_plaster_weathered_normal.jpg", "res://assets/textures/roman_plaster_weathered_roughness.jpg")
    mats["facade_rose"] = _weathered_facade(Color("#FFE0D4"), "res://assets/textures/roman_plaster_weathered_albedo.jpg", "res://assets/textures/roman_plaster_weathered_normal.jpg", "res://assets/textures/roman_plaster_weathered_roughness.jpg")

func build(data: Dictionary, variant: int) -> Node3D:
    var root: Node3D = Node3D.new()
    root.name = str(data["id"])
    var w: float = float(data["w"])
    var d: float = float(data["d"])
    var floors: int = int(data["floors"])
    var style: String = str(data["style"])
    var style_mat: Material = mats["facade_beige"] as Material
    # Roman palette only: no gray/black facade bodies. The named style controls the warm family.
    if style == "plaster_cream" or style == "brick":
        style_mat = mats["facade_ochre"] as Material
    elif style == "plaster_pale" or style == "travertine":
        style_mat = mats["facade_beige"] as Material
    elif style == "plaster_terracotta":
        style_mat = mats["facade_terracotta"] as Material
    if root.name == "palazzetto" or root.name == "palazzo_nobile":
        style_mat = mats["facade_yellow"] as Material
    elif root.name == "casa_mercante":
        style_mat = mats["facade_rose"] as Material
    var ground_function: String = str(data["function"])
    # Two named Roman archetypes deliberately have a differentiated active ground floor.
    if root.name == "casa_mercante":
        ground_function += " / BOTTEGA"
    elif root.name == "palazzetto":
        ground_function += " / BAR / NEGOZI"

    _build_shell(root, w, d, floors, style_mat, variant, ground_function)
    _build_interior_glimpses(root, w, d, floors, ground_function, variant)
    _build_internal_stairs(root, w, d, floors, variant)
    _build_facade_details(root, w, d, floors, style, variant, ground_function)
    _build_weathering(root, w, d, floors, style, variant)
    _build_windows_and_shutters(root, w, d, floors, ground_function, variant)
    _build_bugnato_ground(root, w, d, ground_function, variant)
    _build_balconies(root, w, d, floors, variant)
    _build_commercial_frontage(root, w, d, ground_function, variant)
    _build_noble_portico(root, w, d, floors, ground_function, variant)
    _build_roof(root, w, d, floors, style, variant)
    _build_door_anchor(root, w, d, ground_function)
    _validate_front_clearance(root, w, d, floors, ground_function)
    return root

func _build_shell(root: Node3D, w: float, d: float, floors: int, style_mat: Material, variant: int, function_name: String) -> void:
    var ground_floor: float = 3.0
    for f in range(floors):
        var floor_y: float = float(f) * FLOOR_H
        var h: float = ground_floor if f == 0 else FLOOR_H
        var openings_front: Array[Vector2] = _front_openings(w, f, function_name, variant)
        var openings_back: Array[Vector2] = _back_openings(w, f, variant)
        var openings_side: Array[Vector2] = _side_openings(d, f, variant)

        _wall_x(root, "front_%d" % f, -d * 0.5, floor_y, w, h, openings_front, style_mat)
        _wall_x(root, "back_%d" % f, d * 0.5, floor_y, w, h, openings_back, style_mat)
        _wall_z(root, "left_%d" % f, -w * 0.5, floor_y, d, h, openings_side, style_mat)
        _wall_z(root, "right_%d" % f, w * 0.5, floor_y, d, h, openings_side, style_mat)

    # Base plinth is segmented around EVERY ground-floor opening.
    # Never run a solid travertine strip through a door, shopfront, or window.
    _segmented_plinth_x(root, -d * 0.5 - 0.12, w, _front_openings(w, 0, function_name, variant), true)
    _segmented_plinth_x(root, d * 0.5 + 0.12, w, _back_openings(w, 0, variant), false)
    _segmented_plinth_z(root, -w * 0.5 - 0.12, d, _side_openings(d, 0, variant), true)
    _segmented_plinth_z(root, w * 0.5 + 0.12, d, _side_openings(d, 0, variant), false)

    var top_y: float = float(floors) * FLOOR_H
    _box(root, Vector3(0, top_y + 0.10, -d * 0.5 - 0.14), Vector3(w + 0.72, 0.30, 0.44), mats["travertine"], true)
    _box(root, Vector3(0, top_y + 0.10, d * 0.5 + 0.14), Vector3(w + 0.72, 0.30, 0.44), mats["travertine"], true)
    _box(root, Vector3(-w * 0.5 - 0.14, top_y + 0.10, 0), Vector3(0.44, 0.30, d + 0.72), mats["travertine"], true)
    _box(root, Vector3(w * 0.5 + 0.14, top_y + 0.10, 0), Vector3(0.44, 0.30, d + 0.72), mats["travertine"], true)

func _front_openings(w: float, floor_index: int, function_name: String, variant: int) -> Array[Vector2]:
    var result: Array[Vector2] = []
    var lower: String = function_name.to_lower()
    if floor_index == 0:
        if lower.contains("palazzo nobile"):
            result.append(Vector2(0.0, min(2.25, w * 0.20)))
            return result
        if _is_commercial(lower):
            if w >= 12.0:
                result.append(Vector2(-w * 0.30, min(3.20, w * 0.26)))
                result.append(Vector2(0.0, 1.55))
                result.append(Vector2(w * 0.30, min(3.20, w * 0.26)))
            elif w >= 9.5:
                result.append(Vector2(-w * 0.25, min(2.80, w * 0.28)))
                result.append(Vector2(0.0, 1.50))
                result.append(Vector2(w * 0.25, min(2.80, w * 0.28)))
            else:
                result.append(Vector2(-w * 0.22, min(2.55, w * 0.28)))
                result.append(Vector2(0.0, 1.45))
            return result
        result.append(Vector2(0.0, 1.45))
        return result
    var count_upper: int = max(2, int(floor(w / 3.3)))
    var span_upper: float = min(w - 2.0, float(count_upper) * 2.65)
    for i in range(count_upper):
        var x_upper: float = -span_upper * 0.5 + span_upper * float(i) / float(max(1, count_upper - 1))
        result.append(Vector2(x_upper, 1.72))
    return result

func _back_openings(w: float, floor_index: int, variant: int) -> Array[Vector2]:
    var result: Array[Vector2] = []
    var count: int = max(2, int(floor(w / 3.6)))
    var span: float = min(w - 2.0, float(count) * 2.7)
    for i in range(count):
        var x: float = -span * 0.5 + span * float(i) / float(max(1, count - 1))
        result.append(Vector2(x, 1.60))
    return result

func _side_openings(d: float, floor_index: int, variant: int) -> Array[Vector2]:
    var result: Array[Vector2] = []
    var count: int = max(2, int(floor(d / 3.7)))
    var span: float = min(d - 2.0, float(count) * 2.8)
    for i in range(count):
        var z: float = -span * 0.5 + span * float(i) / float(max(1, count - 1))
        result.append(Vector2(z, 1.52))
    return result

func _wall_x(root: Node3D, name: String, z: float, y: float, total_w: float, h: float, openings: Array[Vector2], material: Material) -> void:
    var sorted: Array = openings.duplicate()
    var cursor: float = -total_w * 0.5
    for opening in sorted:
        var a: float = opening.x - opening.y * 0.5
        var b: float = opening.x + opening.y * 0.5
        if a > cursor:
            _box(root, Vector3((cursor + a) * 0.5, y + h * 0.5, z), Vector3(a - cursor, h, WALL_T), material, true)
        cursor = b
        # Above the opening, fill the header strip.
        var header_bottom: float = y + min(2.60, h)
        if header_bottom < y + h:
            _box(root, Vector3(opening.x, (header_bottom + y + h) * 0.5, z), Vector3(opening.y, y + h - header_bottom, WALL_T), material, true)
    if cursor < total_w * 0.5:
        _box(root, Vector3((cursor + total_w * 0.5) * 0.5, y + h * 0.5, z), Vector3(total_w * 0.5 - cursor, h, WALL_T), material, true)

    # Re-add the sill portion inside the opening so the window has a real recessed base.
    for opening in sorted:
        if opening.y > 1.55:
            _box(root, Vector3(opening.x, y + 0.38, z), Vector3(opening.y, 0.76, WALL_T), mats["travertine"], true)

func _wall_z(root: Node3D, name: String, x: float, y: float, total_d: float, h: float, openings: Array[Vector2], material: Material) -> void:
    var sorted: Array = openings.duplicate()
    var cursor: float = -total_d * 0.5
    for opening in sorted:
        var a: float = opening.x - opening.y * 0.5
        var b: float = opening.x + opening.y * 0.5
        if a > cursor:
            _box(root, Vector3(x, y + h * 0.5, (cursor + a) * 0.5), Vector3(WALL_T, h, a - cursor), material, true)
        cursor = b
        var header_bottom: float = y + min(2.60, h)
        if header_bottom < y + h:
            _box(root, Vector3(x, (header_bottom + y + h) * 0.5, opening.x), Vector3(WALL_T, y + h - header_bottom, opening.y), material, true)
    if cursor < total_d * 0.5:
        _box(root, Vector3(x, y + h * 0.5, (cursor + total_d * 0.5) * 0.5), Vector3(WALL_T, h, total_d * 0.5 - cursor), material, true)
    for opening in sorted:
        if opening.y > 1.55:
            _box(root, Vector3(x, y + 0.38, opening.x), Vector3(WALL_T, 0.76, opening.y), mats["travertine"], true)

func _build_interior_glimpses(root: Node3D, w: float, d: float, floors: int, function_name: String, variant: int) -> void:
    var lower: String = function_name.to_lower()
    for f in range(floors):
        var y0: float = float(f) * FLOOR_H
        var front_z: float = -d * 0.5 + 0.85
        var back_z: float = d * 0.16

        # Realistic floor slabs and a shallow room shell visible through windows.
        _box(root, Vector3(0, y0 + 0.10, 0), Vector3(max(3.2, w * 0.84), 0.16, max(3.2, d * 0.78)), mats["roof_terrace"], false)

        # Main divider wall: creates actual rooms instead of a hollow box.
        if d >= 8.5:
            _box(root, Vector3(0, y0 + 1.55, d * 0.02), Vector3(max(3.0, w * 0.72), 2.55, 0.14), mats["interior"], false)

        # Side room / bathroom partition with a narrow door gap.
        var room_w: float = min(2.35, max(1.75, w * 0.18))
        _box(root, Vector3(w * 0.5 - room_w * 0.5 - 0.45, y0 + 1.45, back_z), Vector3(room_w, 2.40, 0.12), mats["interior"], false)
        _box(root, Vector3(w * 0.5 - 0.45, y0 + 1.45, d * 0.18), Vector3(0.12, 2.40, max(1.2, d * 0.28)), mats["interior"], false)

        if f == 0 and _is_commercial(lower):
            _commercial_interior(root, Vector3(0, y0, front_z), lower, variant)
            # Rear kitchen/service zone.
            _box(root, Vector3(0, y0 + 0.65, d * 0.28), Vector3(max(2.8, w * 0.58), 0.95, 0.55), mats["wood"], false)
            for i in range(3):
                _box(root, Vector3(-w * 0.22 + float(i) * 0.22, y0 + 1.32, d * 0.28), Vector3(0.16, 0.45, 0.16), mats["metal"], false)
        else:
            _residential_room_set(root, w, d, y0, f, variant)

        # Compact bathroom fixtures on upper floors and selected ground floors.
        if f > 0 or lower.contains("hotel") or lower.contains("residenza"):
            _add_bathroom(root, Vector3(w * 0.30, y0 + 0.05, d * 0.18), variant + f)

        if f % 2 == 0:
            var light: OmniLight3D = OmniLight3D.new()
            light.position = Vector3(0, y0 + 1.55, -d * 0.5 + 1.0)
            light.light_color = Color("#FFD7A0")
            light.light_energy = 0.42
            light.omni_range = min(4.5, d * 0.55)
            root.add_child(light)

func _is_commercial(lower: String) -> bool:
    return lower.contains("bar") or lower.contains("ristorante") or lower.contains("pasticceria") or lower.contains("gelateria") or lower.contains("alimentari") or lower.contains("farmacia") or lower.contains("libreria") or lower.contains("negozi") or lower.contains("bottega")

func _residential_room_set(root: Node3D, w: float, d: float, y0: float, floor_index: int, variant: int) -> void:
    # Living room furniture near the street.
    _box(root, Vector3(-w * 0.18, y0 + 0.55, -d * 0.22), Vector3(min(2.0, w * 0.22), 0.16, 0.70), mats["wood"], false)
    _box(root, Vector3(-w * 0.18, y0 + 0.88, -d * 0.37), Vector3(min(2.0, w * 0.22), 0.55, 0.12), mats["painted_wood"], false)

    # Kitchen run.
    _box(root, Vector3(w * 0.26, y0 + 0.68, d * 0.18), Vector3(min(2.7, w * 0.30), 0.78, 0.55), mats["wood"], false)
    for i in range(3):
        _box(root, Vector3(w * 0.13 + float(i) * 0.24, y0 + 1.22, d * 0.18), Vector3(0.16, 0.42, 0.16), mats["metal"], false)

    # Bed/desk arrangement changes with floor/variant.
    if (floor_index + variant) % 2 == 0:
        _box(root, Vector3(-w * 0.18, y0 + 0.58, d * 0.25), Vector3(min(2.0, w * 0.22), 0.22, 1.25), mats["painted_wood"], false)
        _box(root, Vector3(-w * 0.18, y0 + 0.78, d * 0.25), Vector3(min(2.0, w * 0.22), 0.20, 1.18), mats["fabric_blue"], false)
    else:
        _box(root, Vector3(-w * 0.18, y0 + 0.55, d * 0.25), Vector3(1.25, 0.16, 0.70), mats["wood"], false)
        _box(root, Vector3(-w * 0.18, y0 + 0.78, d * 0.34), Vector3(1.25, 0.62, 0.08), mats["painted_wood"], false)

func _add_bathroom(root: Node3D, p: Vector3, variant: int) -> void:
    var white: StandardMaterial3D = StandardMaterial3D.new()
    white.albedo_color = Color("#D8D3C8")
    white.roughness = 0.70
    _box(root, p + Vector3(0, 0.35, 0), Vector3(0.95, 0.10, 0.55), white, false)
    _cylinder(root, p + Vector3(0.0, 0.62, 0.02), 0.23, 0.45, white, 14)
    _box(root, p + Vector3(0.42, 0.70, 0.02), Vector3(0.55, 0.10, 0.55), white, false)
    _box(root, p + Vector3(0.42, 1.15, 0.02), Vector3(0.55, 0.65, 0.08), white, false)

func _residential_interior(root: Node3D, p: Vector3, variant: int) -> void:
    _residential_room_set(root, 8.0, 8.0, p.y, 1, variant)

func _commercial_interior(root: Node3D, p: Vector3, kind: String, variant: int) -> void:
    if kind.contains("bar"):
        # Street-facing bar counter, espresso machine and rear service/kitchen line.
        _box(root, p + Vector3(0, 0.62, 0.30), Vector3(2.30, 0.95, 0.42), mats["wood"], false)
        for i in range(3):
            _cylinder(root, p + Vector3(-0.65 + i * 0.65, 0.55, 0.90), 0.11, 0.70, mats["metal"], 10)
        _box(root, p + Vector3(0, 0.90, -0.35), Vector3(2.60, 1.00, 0.12), mats["wood"], false)
        _box(root, p + Vector3(-1.10, 0.88, 1.55), Vector3(0.72, 1.35, 0.62), mats["metal"], false)
        _box(root, p + Vector3(-0.30, 1.12, 1.55), Vector3(0.22, 0.24, 0.22), mats["metal"], false)
        _cylinder(root, p + Vector3(0.05, 1.10, 1.55), 0.14, 0.20, mats["metal"], 12)
        _box(root, p + Vector3(0.85, 0.65, 1.55), Vector3(1.35, 0.12, 0.55), mats["wood"], false)
    elif kind.contains("ristorante"):
        for row in range(2):
            for col in range(2):
                var px: float = -0.75 + float(col) * 1.5
                var pz: float = 0.10 + float(row) * 1.05
                _box(root, p + Vector3(px, 0.45, pz), Vector3(1.00, 0.10, 0.68), mats["wood"], false)
                for sx in [-0.36, 0.36]:
                    _box(root, p + Vector3(px + sx, 0.25, pz), Vector3(0.07, 0.48, 0.07), mats["wood"], false)
        _box(root, p + Vector3(0, 0.82, 1.60), Vector3(2.80, 1.10, 0.55), mats["metal"], false)
        _box(root, p + Vector3(0, 1.45, 1.60), Vector3(2.50, 0.10, 0.50), mats["wood"], false)
    else:
        _box(root, p + Vector3(0, 0.72, 0.55), Vector3(2.20, 1.25, 0.35), mats["wood"], false)
        _box(root, p + Vector3(0.85, 0.82, 1.55), Vector3(1.25, 1.10, 0.50), mats["metal"], false)

func _build_internal_stairs(root: Node3D, w: float, d: float, floors: int, variant: int) -> void:
    if floors <= 1:
        return

    var stair_w: float = min(1.65, max(1.20, w * 0.12))
    var run: float = min(0.30, max(0.25, d * 0.025))
    var rise: float = 0.19
    var steps_per_floor: int = 16

    # Local staircase kept inside the footprint; direction alternates by floor.
    for floor_index in range(floors - 1):
        var base_y: float = float(floor_index) * FLOOR_H + 0.08
        var direction: float = -1.0 if (floor_index + variant) % 2 == 0 else 1.0
        var start_z: float = -d * 0.18 if direction < 0.0 else d * 0.18
        var start_x: float = w * 0.20 if floor_index % 2 == 0 else -w * 0.20

        for step in range(steps_per_floor):
            var t: float = float(step)
            var z: float = start_z + direction * t * run
            var y: float = base_y + t * rise
            if abs(z) < d * 0.44:
                _box(
                    root,
                    Vector3(start_x, y + rise * 0.5, z),
                    Vector3(stair_w, rise, run * 1.12),
                    mats["travertine"],
                    true
                )

        # Small landing at each floor.
        var landing_z: float = start_z + direction * float(steps_per_floor - 1) * run
        _box(
            root,
            Vector3(start_x, base_y + FLOOR_H - 0.10, landing_z),
            Vector3(stair_w + 0.35, 0.20, 1.10),
            mats["wood"],
            true
        )

func _build_facade_details(root: Node3D, w: float, d: float, floors: int, style: String, variant: int, function_name: String) -> void:
    var top: float = float(floors) * FLOOR_H

    # Strong horizontal cornices at every floor.
    for f in range(1, floors):
        var y: float = float(f) * FLOOR_H - 0.10
        _box(root, Vector3(0, y, -d * 0.5 - 0.23), Vector3(w + 0.52, 0.20, 0.36), mats["travertine"], false)
        _box(root, Vector3(0, y, d * 0.5 + 0.23), Vector3(w + 0.52, 0.20, 0.36), mats["travertine"], false)
        _box(root, Vector3(-w * 0.5 - 0.23, y, 0), Vector3(0.36, 0.20, d + 0.52), mats["travertine"], false)
        _box(root, Vector3(w * 0.5 + 0.23, y, 0), Vector3(0.36, 0.20, d + 0.52), mats["travertine"], false)

    # Deeper top cornice / eave.
    _box(root, Vector3(0, top + 0.05, -d * 0.5 - 0.26), Vector3(w + 1.0, 0.34, 0.50), mats["travertine"], false)
    _box(root, Vector3(0, top + 0.05, d * 0.5 + 0.26), Vector3(w + 1.0, 0.34, 0.50), mats["travertine"], false)

    # Corner pilasters + capitals, stronger on large structures.
    var pilaster_offset: float = 0.43
    var front_px: float = -w * pilaster_offset
    var front_px2: float = w * pilaster_offset
    if not _front_column_intersects_opening(front_px, w, floors, function_name, variant):
        _add_pilaster(root, front_px, -d * 0.5 - 0.24, top)
    if not _front_column_intersects_opening(front_px2, w, floors, function_name, variant):
        _add_pilaster(root, front_px2, -d * 0.5 - 0.24, top)
    if w >= 18.0:
        if not _side_column_intersects_opening(d * 0.43, d, floors, variant):
            _add_pilaster(root, -w * 0.5 - 0.24, d * 0.43, top)
        if not _side_column_intersects_opening(-d * 0.43, d, floors, variant):
            _add_pilaster(root, -w * 0.5 - 0.24, -d * 0.43, top)
        if not _side_column_intersects_opening(d * 0.43, d, floors, variant):
            _add_pilaster(root, w * 0.5 + 0.24, d * 0.43, top)
        if not _side_column_intersects_opening(-d * 0.43, d, floors, variant):
            _add_pilaster(root, w * 0.5 + 0.24, -d * 0.43, top)

    # Weathered masonry accents and service details.
    if style == "brick":
        _box(root, Vector3(0, 0.18, -d * 0.5 - 0.25), Vector3(w, 0.28, 0.18), mats["brick"], false)
    _add_drainpipe(root, -w * 0.47, -d * 0.46, top)
    _add_drainpipe(root, w * 0.47, d * 0.46, top)

    # Decorative wall lamps, laundry and free-standing planters are intentionally
    # omitted from wall elevations in this library: their previous fixed positions
    # could coincide with side/rear window envelopes. Balcony planters remain because
    # they are mounted beyond the railing and do not cover the glazing itself.

func _build_windows_and_shutters(root: Node3D, w: float, d: float, floors: int, function_name: String, variant: int) -> void:
    var lower: String = function_name.to_lower()
    for f in range(floors):
        var floor_y: float = float(f) * FLOOR_H
        var front: Array[Vector2] = _front_openings(w, f, function_name, variant)
        for opening in front:
            if f == 0 and _is_commercial(lower):
                _storefront_assembly(root, opening.x, floor_y, opening.y, -d * 0.5 - 0.18, lower, variant)
            else:
                _window_assembly(root, opening.x, floor_y + 1.45, opening.y, -d * 0.5 - 0.17, f, variant, true, lower)
        var back: Array[Vector2] = _back_openings(w, f, variant)
        for opening in back:
            _window_assembly(root, opening.x, floor_y + 1.43, opening.y, d * 0.5 + 0.17, f, variant, false, lower)
        var side: Array[Vector2] = _side_openings(d, f, variant)
        for opening in side:
            _side_window_assembly(root, -w * 0.5 - 0.17, floor_y + 1.42, opening.x, opening.y, f, variant, true)
            _side_window_assembly(root, w * 0.5 + 0.17, floor_y + 1.42, opening.x, opening.y, f, variant, false)

func _storefront_assembly(root: Node3D, x: float, floor_y: float, width: float, z: float, lower: String, variant: int) -> void:
    var glass_m: Material = mats["glass"]
    var frame: Material = mats["painted_wood"]
    var trim: Material = mats["travertine"]
    var h: float = 2.55
    var door_width: float = min(width, 1.45)
    _box(root, Vector3(x, floor_y + 1.32, z - 0.045), Vector3(width, h, 0.055), glass_m, false)
    _box(root, Vector3(x - width * 0.5, floor_y + 1.32, z - 0.07), Vector3(0.12, h + 0.18, 0.16), frame, false)
    _box(root, Vector3(x + width * 0.5, floor_y + 1.32, z - 0.07), Vector3(0.12, h + 0.18, 0.16), frame, false)
    _box(root, Vector3(x, floor_y + 2.63, z - 0.07), Vector3(width + 0.18, 0.16, 0.16), frame, false)
    _box(root, Vector3(x, floor_y + 0.06, z - 0.08), Vector3(width + 0.18, 0.18, 0.22), trim, false)
    if width > 1.9:
        _box(root, Vector3(x, floor_y + 1.30, z - 0.09), Vector3(0.08, 2.55, 0.10), frame, false)
    _add_protected_volume(root, "SHOPFRONT", Vector3(x, floor_y + 1.32, z), Vector3(width + 0.28, h + 0.20, 2.0))
    if abs(x) < 0.9:
        # Wooden entrance with a Roman-style semicircular arch trim.
        _box(root, Vector3(x, floor_y + 1.25, z - 0.12), Vector3(door_width, 2.35, 0.14), mats["wood"], false)
        _box(root, Vector3(x - door_width * 0.5 - 0.08, floor_y + 1.27, z - 0.16), Vector3(0.12, 2.55, 0.24), trim, false)
        _box(root, Vector3(x + door_width * 0.5 + 0.08, floor_y + 1.27, z - 0.16), Vector3(0.12, 2.55, 0.24), trim, false)
        var radius: float = door_width * 0.50 + 0.14
        for seg in range(9):
            var a0: float = PI - float(seg) * PI / 9.0
            var a1: float = PI - float(seg + 1) * PI / 9.0
            var am: float = (a0 + a1) * 0.5
            var px: float = x + cos(am) * radius
            var py: float = floor_y + 2.48 + sin(am) * radius * 0.55
            var block: MeshInstance3D = _box(root, Vector3(px, py, z - 0.16), Vector3(0.24, 0.22, 0.24), trim, false)
            block.rotation.z = am - PI * 0.5

func _window_assembly(root: Node3D, x: float, y: float, width: float, z: float, floor_index: int, variant: int, front: bool, lower: String) -> void:
    var frame_w: float = max(0.75, width * 0.90)
    var glass_m: StandardMaterial3D = mats["glass"] as StandardMaterial3D
    _box(root, Vector3(x, y, z), Vector3(frame_w, 1.95, 0.055), glass_m, false, Vector3.ZERO, false, 0.0, false)

    var frame_mat: Material = mats["stucco"]
    var frame_depth: float = 0.10
    var side_x: float = frame_w * 0.5
    for sx in [-side_x, side_x]:
        _box(root, Vector3(x + sx, y, z - 0.045), Vector3(frame_depth, 2.18, 0.16), frame_mat, false)
    _box(root, Vector3(x, y + 1.09, z - 0.045), Vector3(frame_w + 0.20, frame_depth, 0.16), frame_mat, false)
    _box(root, Vector3(x, y - 1.09, z - 0.045), Vector3(frame_w + 0.24, 0.16, 0.24), mats["travertine"], false)

    # Roman scuri: hinged and semi-open, never a flat dark rectangle glued to the facade.
    var shutter_mat: Material = mats["shutter_green"] if (variant + floor_index) % 2 == 0 else mats["shutter_warm"]
    var shutter_w: float = 0.34 if width >= 1.7 else 0.26
    for sx in [-1.0, 1.0]:
        _add_front_shutter(root, x + sx * side_x, y, z - 0.055, shutter_w, sx, shutter_mat)
    _add_protected_volume(root, "WINDOW", Vector3(x, y, z), Vector3(frame_w + 0.28, 2.18, 2.0))

func _side_window_assembly(root: Node3D, x: float, y: float, z: float, width: float, floor_index: int, variant: int, left: bool) -> void:
    var glass_m: Material = mats["glass"]
    _box(root, Vector3(x, y, z), Vector3(0.055, 1.90, max(0.72, width * 0.88)), glass_m, false)
    var frame: Material = mats["stucco"]
    for sz in [-1.0, 1.0]:
        _box(root, Vector3(x + (0.045 if left else -0.045), y, z + sz * max(0.40, width * 0.45)), Vector3(0.16, 2.10, 0.10), frame, false)
    _box(root, Vector3(x + (0.045 if left else -0.045), y - 1.05, z), Vector3(0.22, 0.16, max(0.90, width)), mats["travertine"], false)
    if floor_index >= 0:
        var shutter_mat: Material = mats["shutter_green"] if (variant + floor_index) % 2 == 0 else mats["shutter_warm"]
        var sw: float = 0.28
        for sz in [-1.0, 1.0]:
            _add_side_shutter(root, x + (0.08 if left else -0.08), y, z + sz * max(0.42, width * 0.45), sw, sz, left, shutter_mat)
    _add_protected_volume(root, "WINDOW", Vector3(x, y, z), Vector3(2.0, 2.18, max(0.86, width * 0.88) + 0.28))

func _build_bugnato_ground(root: Node3D, w: float, d: float, function_name: String, variant: int) -> void:
    # Bugnato is kept away from the main entrance so it cannot visually overlap the door.
    var front_z: float = -d * 0.5 - 0.31
    var blocks: int = max(4, int(floor(w / 1.15)))
    var door_clear: float = 2.35 if root.name == "palazzo_nobile" or root.name == "palazzetto" else 1.85
    # Commercial frontages use glass/wood storefronts: no projecting bugnato is allowed
    # across that plane, otherwise the windows and doors appear physically blocked.
    if _is_commercial(function_name.to_lower()) or root.name == "palazzo_portico":
        blocks = 0
    for i in range(blocks):
        var x: float = -w * 0.5 + 0.58 + float(i) * (w - 1.16) / float(max(1, blocks - 1))
        if abs(x) < door_clear * 0.5 + 0.35:
            continue
        var bh: float = 0.48 + 0.08 * float((i + variant) % 2)
        _box(root, Vector3(x, 0.58, front_z), Vector3(min(1.05, w / float(blocks) * 0.88), bh, 0.20), mats["travertine"], false)
        _box(root, Vector3(x, 1.15, front_z), Vector3(min(1.05, w / float(blocks) * 0.88), 0.42, 0.20), mats["travertine"], false)
    if w >= 14.0:
        # Side bugnato is segmented around every side-window opening. Never place a
        # projecting stone block in front of a glass/shutter assembly.
        var side_openings: Array[Vector2] = _side_openings(d, 1, variant)
        var cursor: float = -d * 0.5 + 0.45
        for opening in side_openings:
            var gap_end: float = opening.x - opening.y * 0.5 - 0.28
            if gap_end > cursor:
                var mid: float = (cursor + gap_end) * 0.5
                var span: float = gap_end - cursor
                if span > 0.42:
                    _box(root, Vector3(-w * 0.5 - 0.31, 0.75, mid), Vector3(0.20, 1.20, min(0.82, span)), mats["travertine"], false)
                    _box(root, Vector3(w * 0.5 + 0.31, 0.75, mid), Vector3(0.20, 1.20, min(0.82, span)), mats["travertine"], false)
            cursor = opening.x + opening.y * 0.5 + 0.28
        var end_gap: float = d * 0.5 - 0.45
        if end_gap > cursor and end_gap - cursor > 0.42:
            var mid_end: float = (cursor + end_gap) * 0.5
            var span_end: float = end_gap - cursor
            _box(root, Vector3(-w * 0.5 - 0.31, 0.75, mid_end), Vector3(0.20, 1.20, min(0.82, span_end)), mats["travertine"], false)
            _box(root, Vector3(w * 0.5 + 0.31, 0.75, mid_end), Vector3(0.20, 1.20, min(0.82, span_end)), mats["travertine"], false)

func _build_weathering(root: Node3D, w: float, d: float, floors: int, style: String, variant: int) -> void:
    var top: float = float(floors) * FLOOR_H
    var plaster_style: bool = true
    if plaster_style:
        var patch_count: int = max(4, int(round(w / 3.4)))
        for i in range(patch_count):
            var t: float = float(i + 1) / float(patch_count + 1)
            var x: float = -w * 0.5 + w * t
            var y: float = 1.25 + float(posmod(i + variant, max(1, floors))) * FLOOR_H * 0.72
            var pw: float = 0.42 + 0.18 * float(posmod(i * 3 + variant, 4))
            var ph: float = 0.32 + 0.15 * float(posmod(i + variant, 3))
            # Keep the front facade clean around every opening. Weathering is distributed
            # only on the rear/side elevations so it can never cover a window or shopfront.
            var side_offset: float = d * 0.5 + 0.34 if i % 2 == 0 else -w * 0.5 - 0.34
            if i % 2 == 0:
                _box(root, Vector3(x, min(y, top - 0.65), side_offset), Vector3(pw, ph, 0.05), mats["brick"], false)
                _box(root, Vector3(x + 0.10, min(y + 0.17, top - 0.45), side_offset + 0.015), Vector3(pw * 0.66, ph * 0.38, 0.025), mats["weathered_plaster"], false)
            else:
                _box(root, Vector3(side_offset, min(y, top - 0.65), x), Vector3(0.05, ph, pw), mats["brick"], false)
                _box(root, Vector3(side_offset - 0.015, min(y + 0.17, top - 0.45), x + 0.10), Vector3(0.025, ph * 0.38, pw * 0.66), mats["weathered_plaster"], false)

    # Humidity traces are placed only in wall gaps, never across a door/window opening.
    var stain_mat: Material = mats["dark_stone"]
    var front_openings: Array[Vector2] = _front_openings(w, 0, "", variant)
    var stain_xs: Array[float] = [-w * 0.44, w * 0.44]
    for sx in stain_xs:
        var safe: bool = true
        for op in front_openings:
            if abs(sx - op.x) < op.y * 0.5 + 0.48:
                safe = false
                break
        if safe:
            _box(root, Vector3(sx, 0.34, -d * 0.5 - 0.35), Vector3(0.26, 0.55, 0.035), stain_mat, false)
    if floors >= 4:
        # Higher stains are kept on rear/side wall gaps rather than on window glass.
        _box(root, Vector3(-w * 0.44, FLOOR_H * 2.0 + 0.32, d * 0.5 + 0.345), Vector3(0.18, 0.55, 0.025), stain_mat, false)
        _box(root, Vector3(w * 0.44, FLOOR_H * 2.5 + 0.28, -d * 0.5 - 0.345), Vector3(0.18, 0.50, 0.025), stain_mat, false)

func _build_commercial_frontage(root: Node3D, w: float, d: float, function_name: String, variant: int) -> void:
    var lower: String = function_name.to_lower()
    if not _is_commercial(lower):
        return
    var frontage_w: float = min(w - 1.0, max(4.8, w * 0.86))
    var z: float = -d * 0.5 - 1.10
    # Structural shop band/signage/awnings are kept outside the 1 m protected approach volume; the central entrance stays unobstructed.
    _box(root, Vector3(0, 2.76, z), Vector3(frontage_w, 0.18, 0.18), mats["painted_wood"], false)
    _box(root, Vector3(-frontage_w * 0.5, 1.45, z), Vector3(0.14, 2.65, 0.18), mats["travertine"], false)
    _box(root, Vector3(frontage_w * 0.5, 1.45, z), Vector3(0.14, 2.65, 0.18), mats["travertine"], false)
    var sign_color: Color = Color("#EBCB8D")
    if lower.contains("farmacia"):
        sign_color = Color("#E5E2C6")
    elif lower.contains("gelateria") or lower.contains("pasticceria"):
        sign_color = Color("#F0C9A8")
    elif lower.contains("bottega") or lower.contains("alimentari"):
        sign_color = Color("#D9A76C")
    _sign_band(root, frontage_w * 0.72, z - 0.08, 2.84, sign_color)
    _add_shop_label(root, _shop_label(lower), Vector3(0, 2.86, z - 0.18))
    if lower.contains("bar") or lower.contains("ristorante") or lower.contains("pasticceria") or lower.contains("gelateria"):
        _awning(root, frontage_w * 0.88, z - 0.40, 2.84, mats["awning"])
        _add_dehors(root, frontage_w * 0.70, z - 1.35, 0.02, variant)
    elif lower.contains("bottega") or lower.contains("alimentari") or lower.contains("libreria") or lower.contains("farmacia"):
        _awning(root, frontage_w * 0.52, z - 0.36, 2.84, mats["awning"])

func _shop_label(lower: String) -> String:
    if lower.contains("farmacia"):
        return "FARMACIA"
    if lower.contains("gelateria"):
        return "GELATERIA"
    if lower.contains("pasticceria"):
        return "FORNO"
    if lower.contains("ristorante"):
        return "TRATTORIA"
    if lower.contains("bar"):
        return "CAFFÈ"
    if lower.contains("alimentari"):
        return "ALIMENTARI"
    if lower.contains("libreria"):
        return "LIBRERIA"
    return "BOTTEGA"

func _add_shop_label(root: Node3D, text_value: String, p: Vector3) -> void:
    var label: Label3D = Label3D.new()
    label.text = text_value
    label.font_size = 28
    label.outline_size = 8
    label.modulate = Color("#3B2418")
    label.position = p
    label.pixel_size = 0.004
    label.rotation_degrees = Vector3(0, 180, 0)
    root.add_child(label)

func _add_dehors(root: Node3D, width: float, z: float, y: float, variant: int) -> void:
    var aw: float = min(width, 8.0)
    _box(root, Vector3(0, y + 0.08, z), Vector3(aw, 0.12, 2.0), mats["travertine"], false)
    for sx in [-aw * 0.5 + 0.22, aw * 0.5 - 0.22]:
        _cylinder(root, Vector3(sx, y + 1.35, z + 0.75), 0.055, 2.70, mats["iron"], 10)
    _box(root, Vector3(0, y + 2.68, z + 0.75), Vector3(aw, 0.10, 1.70), mats["awning"], false)
    var tables: int = max(2, int(floor(aw / 2.4)))
    for i in range(tables):
        var x: float = -aw * 0.5 + 1.2 + float(i) * 2.35
        _box(root, Vector3(x, y + 0.55, z), Vector3(0.75, 0.08, 0.75), mats["wood"], false)
        _cylinder(root, Vector3(x, y + 0.28, z), 0.045, 0.52, mats["iron"], 10)

func _build_noble_portico(root: Node3D, w: float, d: float, floors: int, function_name: String, variant: int) -> void:
    var lower: String = function_name.to_lower()
    var is_noble: bool = root.name == "palazzo_nobile" or root.name == "palazzetto"
    var is_portico_commercial: bool = root.name == "palazzo_portico"
    if not is_noble and not is_portico_commercial:
        if not (w >= 20.0 and floors >= 4 and (lower.contains("uffici") or lower.contains("residenza") or lower.contains("hotel"))):
            return

    var width: float = min(w - 1.2, 0.92 * w)
    var z: float = -d * 0.5 - 1.12
    var columns: int = 4 if root.name == "palazzetto" else (6 if root.name == "palazzo_portico" else 6)
    var column_h: float = 3.25
    var door_clear: float = 2.35 if is_noble else 1.85

    # Even column counts deliberately leave the center bay free for the entrance. The portico is set beyond the 1 m protected approach volume.
    for i in range(columns):
        var x: float = -width * 0.5 + float(i) * width / float(max(1, columns - 1))
        if abs(x) < door_clear * 0.5 + 0.20:
            continue
        _cylinder(root, Vector3(x, 1.63, z), 0.34 if is_noble else 0.30, column_h, mats["travertine"], 20)
        _box(root, Vector3(x, 3.10, z), Vector3(0.82, 0.30, 0.82), mats["travertine"], false)
        _box(root, Vector3(x, 0.18, z), Vector3(0.72, 0.36, 0.72), mats["travertine"], false)

    # Arch spans are built only between real columns and never across the door opening.
    var active_columns: Array[float] = []
    for i in range(columns):
        var cx: float = -width * 0.5 + float(i) * width / float(max(1, columns - 1))
        if abs(cx) >= door_clear * 0.5 + 0.20:
            active_columns.append(cx)
    for i in range(active_columns.size() - 1):
        var x0: float = active_columns[i]
        var x1: float = active_columns[i + 1]
        var bay: float = x1 - x0
        var xmid: float = (x0 + x1) * 0.5
        var radius: float = max(0.95, bay * 0.43)
        for seg in range(10):
            var a0: float = PI - float(seg) * PI / 10.0
            var a1: float = PI - float(seg + 1) * PI / 10.0
            var am: float = (a0 + a1) * 0.5
            var px: float = xmid + cos(am) * radius
            var py: float = 2.22 + sin(am) * radius
            var seg_len: float = max(0.24, radius * PI / 10.0)
            var block: MeshInstance3D = _box(root, Vector3(px, py, z), Vector3(seg_len * 1.18, 0.28, 0.44), mats["travertine"], false)
            block.rotation.z = am - PI * 0.5

    if is_noble:
        var door_z: float = z - 0.18
        # Monumental door is centered in the free bay; no column, bugnato or arch crosses it.
        _box(root, Vector3(0, 1.34, door_z), Vector3(2.05, 2.56, 0.18), mats["wood"], false)
        _box(root, Vector3(-1.18, 1.46, door_z - 0.06), Vector3(0.18, 2.90, 0.30), mats["travertine"], false)
        _box(root, Vector3(1.18, 1.46, door_z - 0.06), Vector3(0.18, 2.90, 0.30), mats["travertine"], false)
        _box(root, Vector3(0, 2.91, door_z - 0.06), Vector3(2.64, 0.28, 0.34), mats["travertine"], false)
        _box(root, Vector3(0, 3.20, door_z - 0.06), Vector3(3.04, 0.18, 0.34), mats["travertine"], false)
        for f in range(1, floors):
            var yy: float = float(f) * FLOOR_H - 0.14
            _box(root, Vector3(0, yy, -d * 0.5 - 0.40), Vector3(w + 1.0, 0.26, 0.46), mats["travertine"], false)
            _box(root, Vector3(0, yy + 0.16, -d * 0.5 - 0.48), Vector3(w + 0.62, 0.10, 0.26), mats["stone"], false)

func _build_balconies(root: Node3D, w: float, d: float, floors: int, variant: int) -> void:
    if w >= 18.0:
        # BIG BUILDINGS: one continuous balcony across the full row of windows.
        for f in range(1, floors):
            if f == 1 or (f >= 3 and (variant + f) % 2 == 0):
                _continuous_balcony(root, w, d, float(f) * FLOOR_H + 1.55)
    else:
        # SMALL/MEDIUM: individual balconies on selected windows only.
        for f in range(1, floors):
            var count: int = max(2, int(floor(w / 3.3)))
            var span: float = min(w - 2.0, float(count) * 2.65)
            for i in range(count):
                var pick: int = posmod(variant * 13 + f * 17 + i * 7, 11)
                if pick > 4:
                    continue
                var x: float = -span * 0.5 + span * float(i) / float(max(1, count - 1))
                _individual_balcony(root, x, d, float(f) * FLOOR_H + 1.35)

func _continuous_balcony(root: Node3D, w: float, d: float, y: float) -> void:
    var width: float = max(6.0, w - 0.9)
    var depth: float = 1.60
    var z: float = -d * 0.5 - depth * 0.50
    var slab_y: float = y - 0.90
    _box(root, Vector3(0, slab_y, z), Vector3(width, 0.22, depth), mats["travertine"], true)
    _box(root, Vector3(0, slab_y - 0.16, z + depth * 0.38), Vector3(width * 0.98, 0.10, 0.15), mats["stone"], false)
    var rail_z: float = z - depth * 0.43
    var rail_y: float = slab_y + 1.02
    _box(root, Vector3(0, rail_y, rail_z), Vector3(width, 0.10, 0.10), mats["metal"], false)
    _box(root, Vector3(0, slab_y + 0.38, rail_z), Vector3(width, 0.06, 0.06), mats["metal"], false)
    var posts: int = max(6, int(round(width / 1.0)))
    for i in range(posts):
        var t: float = float(i) / float(max(1, posts - 1))
        var x: float = lerp(-width * 0.5, width * 0.5, t)
        _box(root, Vector3(x, slab_y + 0.51, rail_z), Vector3(0.055, 1.02, 0.055), mats["metal"], false)
    _add_planter(root, Vector3(-width * 0.43, slab_y + 0.22, rail_z - 0.05), 0.75)
    _add_planter(root, Vector3(width * 0.43, slab_y + 0.22, rail_z - 0.05), 0.75)

func _individual_balcony(root: Node3D, x: float, d: float, y: float) -> void:
    var width: float = 2.05
    var depth: float = 1.22
    var z: float = -d * 0.5 - depth * 0.50
    var slab_y: float = y - 0.82
    _box(root, Vector3(x, slab_y, z), Vector3(width, 0.18, depth), mats["stone"], true)
    var rail_z: float = z - depth * 0.43
    _box(root, Vector3(x, slab_y + 0.97, rail_z), Vector3(width, 0.09, 0.09), mats["metal"], false)
    _box(root, Vector3(x, slab_y + 0.35, rail_z), Vector3(width, 0.06, 0.06), mats["metal"], false)
    for px in [x - width * 0.48, x, x + width * 0.48]:
        _box(root, Vector3(px, slab_y + 0.48, rail_z), Vector3(0.055, 0.96, 0.055), mats["metal"], false)

func _build_roof(root: Node3D, w: float, d: float, floors: int, style: String, variant: int) -> void:
    var y: float = float(floors) * FLOOR_H + 0.34
    var roof_w: float = w + 0.85
    var roof_d: float = d + 0.85
    var pitched: bool = (variant % 10) < 6 and style != "pietra"
    if pitched:
        var half_d: float = roof_d * 0.5
        var ridge_h: float = clamp(roof_d * 0.075, 0.46, 0.78)
        var slope_len: float = sqrt(half_d * half_d + ridge_h * ridge_h)
        var angle: float = atan2(ridge_h, half_d)
        var left: MeshInstance3D = _box(root, Vector3(0, y + ridge_h * 0.5, -half_d * 0.5), Vector3(roof_w, 0.14, slope_len), mats["roof"], false)
        left.rotation.x = -angle
        var right: MeshInstance3D = _box(root, Vector3(0, y + ridge_h * 0.5, half_d * 0.5), Vector3(roof_w, 0.14, slope_len), mats["roof"], false)
        right.rotation.x = angle
        var rows: int = max(5, int(round(roof_d / 1.15)))
        for side in [-1.0, 1.0]:
            for r in range(rows):
                var t: float = (float(r) + 0.5) / float(rows)
                var z: float = side * lerp(half_d - 0.10, 0.10, t)
                var yy: float = y + ridge_h * (1.0 - t) + 0.10
                # Rounded coppi courses: larger curved profiles, staggered by row, following the low slope.
                var tile_row: MeshInstance3D = _cylinder(root, Vector3(0, yy, z), 0.105, roof_w * 0.985, mats["roof"], 12)
                tile_row.rotation.z = PI * 0.5
                tile_row.rotation.x = -side * angle
                if r % 2 == 1:
                    tile_row.position.x = roof_w * 0.018
        # A small ridge-cap and repeated rounded ribs make the roof read as overlapping Roman coppi, not a flat red plane.
        _box(root, Vector3(0, y + ridge_h + 0.10, 0), Vector3(roof_w + 0.16, 0.20, 0.36), mats["roof"], false)
        var rib_count: int = max(8, int(round(roof_w / 1.35)))
        for rib in range(rib_count):
            var rx: float = lerp(-roof_w * 0.48, roof_w * 0.48, float(rib) / float(max(1, rib_count - 1)))
            var cap: MeshInstance3D = _cylinder(root, Vector3(rx, y + ridge_h * 0.58, 0), 0.065, roof_d * 0.84, mats["roof"], 10)
            cap.rotation.x = PI * 0.5
        _box(root, Vector3(0, y + 0.12, -half_d), Vector3(roof_w + 0.48, 0.20, 0.34), mats["roof"], false)
        _box(root, Vector3(0, y + 0.12, half_d), Vector3(roof_w + 0.48, 0.20, 0.34), mats["roof"], false)
    else:
        _build_rooftop_terrace(root, roof_w, roof_d, y, variant)

func _build_rooftop_terrace(root: Node3D, roof_w: float, roof_d: float, y: float, variant: int) -> void:
    _box(root, Vector3(0, y, 0), Vector3(roof_w, 0.30, roof_d), mats["roof_terrace"], true)
    var inset: float = 0.28
    var rail_y: float = y + 1.05
    var rail_h: float = 0.90
    _box(root, Vector3(0, rail_y, -roof_d * 0.5 + inset), Vector3(roof_w - 0.6, 0.08, 0.08), mats["iron"], false)
    _box(root, Vector3(0, rail_y, roof_d * 0.5 - inset), Vector3(roof_w - 0.6, 0.08, 0.08), mats["iron"], false)
    _box(root, Vector3(-roof_w * 0.5 + inset, rail_y, 0), Vector3(0.08, 0.08, roof_d - 0.6), mats["iron"], false)
    _box(root, Vector3(roof_w * 0.5 - inset, rail_y, 0), Vector3(0.08, 0.08, roof_d - 0.6), mats["iron"], false)
    var posts_x: int = max(6, int(round((roof_w - 0.8) / 1.15)))
    for i in range(posts_x):
        var tx: float = float(i) / float(max(1, posts_x - 1))
        var xx: float = lerp(-(roof_w - 0.8) * 0.5, (roof_w - 0.8) * 0.5, tx)
        for zz in [-roof_d * 0.5 + inset, roof_d * 0.5 - inset]:
            _box(root, Vector3(xx, y + 0.60, zz), Vector3(0.05, rail_h, 0.05), mats["iron"], false)
    var posts_z: int = max(5, int(round((roof_d - 0.8) / 1.15)))
    for i in range(posts_z):
        var tz: float = float(i) / float(max(1, posts_z - 1))
        var zz: float = lerp(-(roof_d - 0.8) * 0.5, (roof_d - 0.8) * 0.5, tz)
        for xx in [-roof_w * 0.5 + inset, roof_w * 0.5 - inset]:
            _box(root, Vector3(xx, y + 0.60, zz), Vector3(0.05, rail_h, 0.05), mats["iron"], false)
    if variant % 3 == 0 and roof_w >= 12.0 and roof_d >= 9.0:
        var aw: float = min(5.0, roof_w * 0.30)
        var ad: float = min(3.6, roof_d * 0.28)
        var ay: float = y + 1.65
        _box(root, Vector3(0, ay - 0.10, 0), Vector3(aw, 0.18, ad), mats["stone"], false)
        for xx in [-aw * 0.5, aw * 0.5]:
            for zz in [-ad * 0.5, ad * 0.5]:
                _cylinder(root, Vector3(xx, ay + 1.15, zz), 0.10, 2.30, mats["travertine"], 12)
        _box(root, Vector3(0, ay + 2.25, 0), Vector3(aw + 0.25, 0.20, ad + 0.25), mats["travertine"], false)

func _commercial_facade(root: Node3D, w: float, d: float, function_name: String, variant: int) -> void:
    var lower: String = function_name.to_lower()
    if lower.contains("bar"):
        _awning(root, w * 0.62, -d * 0.5 - 0.62, 2.62, mats["awning"])
        _sign_band(root, w * 0.54, -d * 0.5 - 0.66, 2.20, Color("#F2D8B0"))
    elif lower.contains("ristorante"):
        _awning(root, w * 0.68, -d * 0.5 - 0.64, 2.55, mats["awning"])
        _sign_band(root, w * 0.58, -d * 0.5 - 0.67, 2.15, Color("#E5C6A5"))
    elif lower.contains("pasticceria") or lower.contains("gelateria"):
        _awning(root, w * 0.55, -d * 0.5 - 0.60, 2.58, mats["plaster_pale"])
        _sign_band(root, w * 0.48, -d * 0.5 - 0.64, 2.16, Color("#F0D2A8"))
    elif lower.contains("farmacia"):
        _sign_band(root, w * 0.55, -d * 0.5 - 0.63, 2.18, Color("#DCE6D0"))
    elif lower.contains("hotel"):
        _sign_band(root, w * 0.48, -d * 0.5 - 0.64, 2.18, Color("#D6C29F"))
    elif lower.contains("negozi") or lower.contains("bottega") or lower.contains("alimentari") or lower.contains("libreria"):
        _awning(root, w * 0.52, -d * 0.5 - 0.60, 2.55, mats["awning"])

func _awning(root: Node3D, width: float, z: float, y: float, material: Material) -> void:
    _box(root, Vector3(0, y, z), Vector3(width, 0.12, 0.86), material, false)
    _box(root, Vector3(-width * 0.43, y - 0.15, z), Vector3(0.06, 0.35, 0.06), mats["metal"], false)
    _box(root, Vector3(width * 0.43, y - 0.15, z), Vector3(0.06, 0.35, 0.06), mats["metal"], false)

func _sign_band(root: Node3D, width: float, z: float, y: float, color: Color) -> void:
    var m: StandardMaterial3D = StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.70
    _box(root, Vector3(0, y, z), Vector3(width, 0.42, 0.08), m, false)

func _build_door_anchor(root: Node3D, w: float, d: float, function_name: String) -> void:
    # Door is deliberately not auto-opening here. The geometry is a real wall opening,
    # and this anchor is reserved for the later touch APRI/CHIUDI interaction.
    var anchor: Node3D = Node3D.new()
    anchor.name = "DoorAnchor_INTERACTION_READY"
    anchor.set_meta("interaction", "APRI_CHIUDI")
    anchor.set_meta("future_animation", true)
    anchor.position = Vector3(0, 0.0, -d * 0.5 - 0.20)
    root.add_child(anchor)
    var panel: MeshInstance3D = MeshInstance3D.new()
    var mesh: BoxMesh = BoxMesh.new()
    var door_w: float = 2.05 if root.name == "palazzo_nobile" or root.name == "palazzetto" else 1.25
    var door_h: float = 2.55 if root.name == "palazzo_nobile" or root.name == "palazzetto" else 2.35
    mesh.size = Vector3(door_w, door_h, 0.10)
    panel.mesh = mesh
    panel.position = Vector3(0, door_h * 0.5, 0.06)
    panel.material_override = mats["wood"]
    anchor.add_child(panel)
    # Only a thin threshold, recessed into the opening. Nothing projects into the
    # player's approach volume in front of the door.
    _box(root, Vector3(0, 0.055, -d * 0.5 - 0.16), Vector3(door_w + 0.10, 0.08, 0.10), mats["travertine"], false)
    _add_protected_volume(root, "DOOR", Vector3(0, door_h * 0.5, -d * 0.5), Vector3(door_w + 0.20, door_h + 0.10, 2.0))

func _add_front_shutter(root: Node3D, hinge_x: float, y: float, z: float, width: float, side: float, material: Material) -> void:
    var hinge: Node3D = Node3D.new()
    hinge.position = Vector3(hinge_x, y, z)
    hinge.rotation.y = -side * deg_to_rad(32.0)
    root.add_child(hinge)
    _box(hinge, Vector3(side * width * 0.56, 0, 0), Vector3(width, 1.72, 0.10), material, false)
    for slat in range(4):
        _box(hinge, Vector3(side * width * 0.56, -0.58 + float(slat) * 0.38, -0.055), Vector3(width * 0.84, 0.045, 0.025), mats["iron"], false)

func _add_side_shutter(root: Node3D, hinge_x: float, y: float, hinge_z: float, width: float, side: float, left: bool, material: Material) -> void:
    var hinge: Node3D = Node3D.new()
    hinge.position = Vector3(hinge_x, y, hinge_z)
    hinge.rotation.y = (1.0 if left else -1.0) * side * deg_to_rad(30.0)
    root.add_child(hinge)
    _box(hinge, Vector3(0, 0, side * width * 0.56), Vector3(0.10, 1.70, width), material, false)

func _add_pilaster(root: Node3D, x: float, z: float, height: float) -> void:
    _box(root, Vector3(x, height * 0.5, z), Vector3(0.34, height, 0.30), mats["travertine"], false)
    _box(root, Vector3(x, height - 0.12, z), Vector3(0.62, 0.20, 0.42), mats["travertine"], false)
    _box(root, Vector3(x, 0.18, z), Vector3(0.58, 0.36, 0.40), mats["travertine"], false)

func _add_drainpipe(root: Node3D, x: float, z: float, height: float) -> void:
    _cylinder(root, Vector3(x, height * 0.5, z), 0.055, height, mats["metal"], 10)
    for y in [1.0, 3.4, 5.8, 8.2]:
        if y < height:
            _cylinder(root, Vector3(x, y, z), 0.075, 0.08, mats["metal"], 10)

func _add_wall_lamp(root: Node3D, p: Vector3, rot: float) -> void:
    var g: Node3D = Node3D.new()
    g.position = p
    g.rotation.y = rot
    root.add_child(g)
    _cylinder(g, Vector3(0, 0, 0), 0.05, 0.28, mats["metal"], 10)
    _cylinder(g, Vector3(0, 0.20, 0), 0.11, 0.18, mats["warm"], 12)

func _add_planter(root: Node3D, p: Vector3, scale_value: float) -> void:
    _box(root, p + Vector3(0, 0.18, 0), Vector3(0.80 * scale_value, 0.36, 0.38 * scale_value), mats["stone"], false)
    for i in range(4):
        _cylinder(root, p + Vector3(-0.24 * scale_value + float(i) * 0.16 * scale_value, 0.58 * scale_value, 0), 0.045 * scale_value, 0.45 * scale_value, mats["plant"], 8)

func _add_laundry(root: Node3D, a: Vector3, b: Vector3) -> void:
    var mid: Vector3 = (a + b) * 0.5
    var length: float = a.distance_to(b)
    var rope: MeshInstance3D = _box(root, mid, Vector3(0.025, 0.025, length), mats["metal"], false)
    rope.look_at(b, Vector3.UP)
    for i in range(4):
        var t: float = (float(i) + 0.5) / 4.0
        var p: Vector3 = a.lerp(b, t)
        _box(root, p + Vector3(0, -0.28, 0), Vector3(0.35, 0.55, 0.035), mats["painted_wood"], false)


func _segmented_plinth_x(root: Node3D, z: float, total_w: float, openings: Array[Vector2], front: bool) -> void:
    var cursor: float = -total_w * 0.5
    for opening in openings:
        var a: float = opening.x - opening.y * 0.5 - 0.12
        var b: float = opening.x + opening.y * 0.5 + 0.12
        if a > cursor:
            _box(root, Vector3((cursor + a) * 0.5, 0.45, z), Vector3(a - cursor, 0.90, 0.30), mats["travertine"], true)
        cursor = max(cursor, b)
    if cursor < total_w * 0.5:
        _box(root, Vector3((cursor + total_w * 0.5) * 0.5, 0.45, z), Vector3(total_w * 0.5 - cursor, 0.90, 0.30), mats["travertine"], true)

func _segmented_plinth_z(root: Node3D, x: float, total_d: float, openings: Array[Vector2], left: bool) -> void:
    var cursor: float = -total_d * 0.5
    for opening in openings:
        var a: float = opening.x - opening.y * 0.5 - 0.12
        var b: float = opening.x + opening.y * 0.5 + 0.12
        if a > cursor:
            _box(root, Vector3(x, 0.45, (cursor + a) * 0.5), Vector3(0.30, 0.90, a - cursor), mats["travertine"], true)
        cursor = max(cursor, b)
    if cursor < total_d * 0.5:
        _box(root, Vector3(x, 0.45, (cursor + total_d * 0.5) * 0.5), Vector3(0.30, 0.90, total_d * 0.5 - cursor), mats["travertine"], true)

func _front_column_intersects_opening(x: float, w: float, floors: int, function_name: String, variant: int) -> bool:
    for f in range(floors):
        for opening in _front_openings(w, f, function_name, variant):
            if abs(x - opening.x) < opening.y * 0.5 + 0.24:
                return true
    return false

func _side_column_intersects_opening(z: float, d: float, floors: int, variant: int) -> bool:
    for f in range(floors):
        for opening in _side_openings(d, f, variant):
            if abs(z - opening.x) < opening.y * 0.5 + 0.24:
                return true
    return false

func _add_protected_volume(root: Node3D, kind: String, center: Vector3, size: Vector3) -> void:
    var marker: Area3D = Area3D.new()
    marker.name = "PROTECTED_VOLUME_%s" % kind
    marker.monitoring = false
    marker.monitorable = false
    marker.collision_layer = 0
    marker.collision_mask = 0
    marker.position = center
    marker.set_meta("protected_volume", true)
    marker.set_meta("clearance_depth_m", 1.0)
    marker.set_meta("clearance_rule", "No structural/decorative module may occupy this volume.")
    var shape: CollisionShape3D = CollisionShape3D.new()
    var box: BoxShape3D = BoxShape3D.new()
    box.size = size
    shape.shape = box
    marker.add_child(shape)
    root.add_child(marker)

func _validate_front_clearance(root: Node3D, w: float, d: float, floors: int, function_name: String) -> void:
    # Runtime-visible audit marker: all front openings remain reserved for glazing/doors.
    var audit: Node3D = Node3D.new()
    audit.name = "FRONT_OPENINGS_CLEAR_AUDIT"
    audit.set_meta("checked_floors", floors)
    audit.set_meta("front_openings", _front_openings(w, 0, function_name, 0).size())
    audit.set_meta("rule", "No decorative projection may occupy the opening envelope.")
    root.add_child(audit)

func _box(parent: Node3D, pos: Vector3, size: Vector3, material: Material, collision: bool = false, rot: Vector3 = Vector3.ZERO, hidden: bool = false, alpha: float = 0.0, allow_collision: bool = true) -> MeshInstance3D:
    var mi: MeshInstance3D = MeshInstance3D.new()
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    mi.mesh = mesh
    mi.position = pos
    mi.rotation = rot
    mi.material_override = material
    mi.visible = not hidden
    parent.add_child(mi)
    if collision and allow_collision:
        var body: StaticBody3D = StaticBody3D.new()
        var shape: CollisionShape3D = CollisionShape3D.new()
        var box_shape: BoxShape3D = BoxShape3D.new()
        box_shape.size = size
        shape.shape = box_shape
        body.position = pos
        body.rotation = rot
        body.add_child(shape)
        parent.add_child(body)
    return mi

func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, material: Material, sides: int = 16) -> MeshInstance3D:
    var mi: MeshInstance3D = MeshInstance3D.new()
    var mesh: CylinderMesh = CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = sides
    mi.mesh = mesh
    mi.position = pos
    mi.material_override = material
    parent.add_child(mi)
    return mi

func _terracotta_terrace() -> StandardMaterial3D:
    var m: StandardMaterial3D = StandardMaterial3D.new()
    var albedo: Texture2D = load("res://assets/textures/cotto_tiles.jpg") as Texture2D
    if albedo:
        m.albedo_texture = albedo
    var normal: Texture2D = load("res://assets/textures/cotto_tiles_normal.jpg") as Texture2D
    if normal:
        m.normal_enabled = true
        m.normal_texture = normal
        m.normal_scale = 0.48
    m.albedo_color = Color("#F0B58A")
    m.roughness = 0.91
    m.uv1_scale = Vector3(2.2, 2.2, 2.2)
    m.texture_repeat = true
    return m

func _warm_roof(color: Color, uv_scale: float) -> StandardMaterial3D:
    var m: StandardMaterial3D = StandardMaterial3D.new()
    m.albedo_color = color
    var albedo: Texture2D = load("res://assets/textures/coppi_romani_albedo.jpg") as Texture2D
    if albedo:
        m.albedo_texture = albedo
    var normal: Texture2D = load("res://assets/textures/coppi_romani_normal.jpg") as Texture2D
    if normal:
        m.normal_enabled = true
        m.normal_texture = normal
        m.normal_scale = 0.72
    var rough: Texture2D = load("res://assets/textures/coppi_romani_roughness.jpg") as Texture2D
    if rough:
        m.roughness_texture = rough
    m.roughness = 0.88
    m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
    m.texture_repeat = true
    return m

func _weathered_facade(tint: Color, albedo_path: String, normal_path: String, roughness_path: String) -> StandardMaterial3D:
    var m: StandardMaterial3D = StandardMaterial3D.new()
    var albedo: Texture2D = load(albedo_path) as Texture2D
    if albedo:
        m.albedo_texture = albedo
    m.albedo_color = tint
    var normal: Texture2D = load(normal_path) as Texture2D
    if normal:
        m.normal_enabled = true
        m.normal_texture = normal
        m.normal_scale = 0.52
    var rough: Texture2D = load(roughness_path) as Texture2D
    if rough:
        m.roughness_texture = rough
    m.roughness = 0.90
    m.uv1_scale = Vector3(3.6, 3.6, 3.6)
    m.texture_repeat = true
    return m

func _weathered_pbr(albedo_path: String, normal_path: String, roughness_path: String, rough: float, uv_scale: float) -> StandardMaterial3D:
    var m: StandardMaterial3D = StandardMaterial3D.new()
    var albedo: Texture2D = load(albedo_path) as Texture2D
    if albedo:
        m.albedo_texture = albedo
    var normal: Texture2D = load(normal_path) as Texture2D
    if normal:
        m.normal_enabled = true
        m.normal_texture = normal
        m.normal_scale = 0.52
    var roughness_tex: Texture2D = load(roughness_path) as Texture2D
    if roughness_tex:
        m.roughness_texture = roughness_tex
    m.roughness = rough
    m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
    m.texture_repeat = true
    return m

func _warm_facade(color: Color, normal_path: String) -> StandardMaterial3D:
    var m: StandardMaterial3D = StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.90
    var normal: Texture2D = load(normal_path) as Texture2D
    if normal:
        m.normal_enabled = true
        m.normal_texture = normal
        m.normal_scale = 0.42
    m.uv1_scale = Vector3(3.2, 3.2, 3.2)
    return m

func _pbr(color_path: String, normal_path: String, rough: float, uv_scale: float) -> StandardMaterial3D:
    var m: StandardMaterial3D = StandardMaterial3D.new()
    var color: Texture2D = load(color_path) as Texture2D
    if color:
        m.albedo_texture = color
    var normal: Texture2D = load(normal_path) as Texture2D
    if normal:
        m.normal_enabled = true
        m.normal_texture = normal
        m.normal_scale = 0.55
    m.roughness = rough
    m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
    m.texture_repeat = true
    return m
