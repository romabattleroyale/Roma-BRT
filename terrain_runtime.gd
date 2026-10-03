extends Node3D
## Terrain3D RAW importer for the Roma heightmap beta.
## The RAW file is selected at runtime. Because RAW has no metadata,
## dimensions are inferred from the byte count when it is a square 16-bit file.
## The supplied Roma RAW is 2,337,122 bytes = 1081 x 1081 x 16-bit.
## IMPORTANT: this file is BIG-ENDIAN (the byte order is verified from the actual data).

const MAP_SIZE_M := 2000.0
const HEIGHT_SCALE_M := 48.0
const RAW_BITS := 16
const BYTES_PER_SAMPLE := 2
const RAW_MAX := 65535.0

var terrain: Terrain3D
var file_dialog: FileDialog
var status_label: Label

func _ready() -> void:
    status_label = get_node_or_null("../HUD/Status")
    call_deferred("_setup")

func _setup() -> void:
    if not ClassDB.class_exists("Terrain3D"):
        push_error("Terrain3D non disponibile: controlla il plugin/GDExtension.")
        _set_status("ERRORE: Terrain3D non disponibile")
        return

    terrain = Terrain3D.new()
    terrain.name = "Terrain3D_HEIGHTMAP_2000x2000"
    # 512 gives a reasonable region size for a 2000 m beta while still
    # allowing Terrain3D to slice the 1081x1081 source across regions.
    terrain.region_size = Terrain3D.SIZE_512
    terrain.vertex_spacing = MAP_SIZE_M / 1080.0
    terrain.mesh_lods = 7
    terrain.show_checkered = false
    terrain.show_colormap = false
    terrain.show_grey = false
    add_child(terrain, true)

    # V7 Roman Natural art pass, transferred to native Terrain3D material.
    var roman_assets: Terrain3DAssets = load("res://terrain_materials/terrain_assets_roman_natural.tres")
    if roman_assets:
        terrain.assets = roman_assets
    # FIX15: stop using Terrain3D autoshader for the biome mask.
    # The RAW contains small-scale slope noise, so changing auto_slope repeatedly
    # only moves the same orange patches around. We now build a MANUAL control map
    # from a large-scale slope measurement while leaving the heightmap untouched.
    terrain.material.auto_shader = false
    terrain.material.set_shader_param("macro_variation1", Vector3(0.985, 1.00, 0.96))
    terrain.material.set_shader_param("macro_variation2", Vector3(1.015, 1.00, 0.985))

    await get_tree().process_frame
    if terrain.data == null:
        push_error("Terrain3D Data non inizializzato.")
        _set_status("ERRORE: Terrain3D Data non inizializzato")
        return

    _set_status("Seleziona il file .RAW della heightmap")
    _open_raw_picker()

func _open_raw_picker() -> void:
    file_dialog = FileDialog.new()
    file_dialog.name = "RawHeightmapPicker"
    file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    file_dialog.access = FileDialog.ACCESS_RESOURCES
    file_dialog.filters = PackedStringArray(["*.raw ; RAW 16-bit big-endian"])
    file_dialog.title = "Seleziona la heightmap RAW (16-bit)"
    file_dialog.size = Vector2i(900, 600)
    file_dialog.file_selected.connect(_on_raw_selected)
    add_child(file_dialog)
    file_dialog.popup_centered()

func _on_raw_selected(path: String) -> void:
    _set_status("Lettura RAW: " + path)
    await get_tree().process_frame
    _import_raw(path)

func _import_raw(path: String) -> void:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        _set_status("ERRORE apertura RAW: " + path)
        push_error("Impossibile aprire RAW: " + path)
        return

    var bytes := f.get_buffer(f.get_length())
    f.close()

    if bytes.size() == 0:
        _set_status("ERRORE: RAW vuoto")
        return
    if bytes.size() % BYTES_PER_SAMPLE != 0:
        _set_status("ERRORE: dimensione RAW non compatibile con 16-bit")
        push_error("RAW non compatibile: " + str(bytes.size()) + " bytes")
        return

    var samples: int = bytes.size() / BYTES_PER_SAMPLE
    var side: int = int(sqrt(float(samples)))
    if side * side != samples:
        _set_status("RAW non quadrato: " + str(samples) + " campioni. Inserire dimensioni esplicite.")
        push_error("RAW 16-bit non quadrato: " + str(samples) + " campioni. RAW non contiene metadata dimensionali.")
        return

    var width: int = side
    var height: int = side
    var values: PackedFloat32Array = PackedFloat32Array()
    values.resize(samples)

    var min_u: int = 65535
    var max_u: int = 0

    # RAW is BIG-endian unsigned 16-bit. Decode it ourselves instead of
    # delegating to a generic loader: this removes ambiguity about byte order,
    # bit depth, and dimensions and prevents the striped import seen in the beta.
    for i in range(samples):
        var hi: int = bytes[i * 2]
        var lo: int = bytes[i * 2 + 1]
        var u: int = (hi << 8) | lo
        if u < min_u:
            min_u = u
        if u > max_u:
            max_u = u
        values[i] = float(u)

    # Normalize the real source range, not the full 0..65535 range. The supplied
    # file uses only a subset of 16-bit values (verified range is ~742..16031).
    var source_range: float = maxf(1.0, float(max_u - min_u))
    for i in range(samples):
        values[i] = clampf((values[i] - float(min_u)) / source_range, 0.0, 1.0)

    var img: Image = Image.create_from_data(width, height, false, Image.FORMAT_RF, values.to_byte_array())
    if img == null:
        _set_status("ERRORE: impossibile creare Image RF")
        return

    var maps: Array[Image]
    maps.resize(Terrain3DRegion.TYPE_MAX)
    maps[Terrain3DRegion.TYPE_HEIGHT] = img
    maps[Terrain3DRegion.TYPE_CONTROL] = _build_manual_control_map(values, width, height)

    # Start the map at world 0,0. The 1081 samples span exactly 2000 m at
    # 2000/(1081-1) spacing. Camera is positioned accordingly in main.tscn.
    terrain.data.import_images(
        maps,
        Vector3(0.0, 0.0, 0.0),
        0.0,
        HEIGHT_SCALE_M
    )
    terrain.data.calc_height_range(true)

    print("RAW IMPORT OK")
    print("  file=", path)
    print("  bytes=", bytes.size(), " bits=16 BIG-endian")
    print("  dimensions=", width, "x", height)
    print("  raw min/max=", min_u, "/", max_u)
    print("  world=", MAP_SIZE_M, "x", MAP_SIZE_M, " spacing=", terrain.vertex_spacing)
    print("  height scale=", HEIGHT_SCALE_M)
    print("  height range=", terrain.data.get_height_range())

    _build_river_water(values, width, height)
    _set_status("HEIGHTMAP OK — %dx%d — RAW 16-bit BE — min/max %d/%d — scala %.0f m" % [width, height, min_u, max_u, HEIGHT_SCALE_M])


func _build_manual_control_map(values: PackedFloat32Array, width: int, height: int) -> Image:
    # One control pixel per height sample. Base=Grass(ID 0), Overlay=Soil(ID 1).
    # Slope is measured over ~44 m, deliberately ignoring tiny heightmap noise.
    # This is a material mask only: the original height image is never modified.
    var bytes := PackedByteArray()
    bytes.resize(width * height * 4)
    var spacing := MAP_SIZE_M / float(width - 1)
    var radius := 12
    var slope_start := 9.0
    var slope_full := 18.0

    var bank := Image.load_from_file("res://terrain_materials/river_mask.png")
    var bank_flags := PackedByteArray()
    bank_flags.resize(width * height)
    if bank == null:
        push_warning("river_mask.png non disponibile: bank mask disattivata")
    else:
        for bz in range(height):
            for bx in range(width):
                bank_flags[bz * width + bx] = 1 if bank.get_pixel(bx, bz).r > 0.5 else 0

    # Dilate the centerline by 2 pixels (~3.7 m). This is intentionally narrow.
    var bank_dilated := PackedByteArray()
    bank_dilated.resize(width * height)
    for z in range(height):
        for x in range(width):
            var hit := false
            for oz in range(-2, 3):
                var sz: int = z + oz
                if sz < 0 or sz >= height:
                    continue
                for ox in range(-2, 3):
                    var sx: int = x + ox
                    if sx < 0 or sx >= width:
                        continue
                    if bank_flags[sz * width + sx] != 0:
                        hit = true
                        break
                if hit:
                    break
            bank_dilated[z * width + x] = 1 if hit else 0

    for z in range(height):
        var z0: int = maxi(0, z - radius)
        var z1: int = mini(height - 1, z + radius)
        for x in range(width):
            var x0: int = maxi(0, x - radius)
            var x1: int = mini(width - 1, x + radius)
            var dx_dist := float(x1 - x0) * spacing
            var dz_dist := float(z1 - z0) * spacing
            var dx := 0.0 if dx_dist <= 0.0 else ((values[z * width + x1] - values[z * width + x0]) * HEIGHT_SCALE_M / dx_dist)
            var dz := 0.0 if dz_dist <= 0.0 else ((values[z1 * width + x] - values[z0 * width + x]) * HEIGHT_SCALE_M / dz_dist)
            var slope_deg := rad_to_deg(atan(sqrt(dx * dx + dz * dz)))
            var soil_weight := smoothstep(slope_start, slope_full, slope_deg)

            # Narrow Roman riverbank: at most ~4 m from the supplied centerline mask.
            if bank_dilated[z * width + x] != 0:
                soil_weight = maxf(soil_weight, 0.42)

            var blend := clampi(int(round(soil_weight * 255.0)), 0, 255)
            # Terrain3D control-map bits: base 0, overlay 1, blend 0..255, autoshader=0.
            var packed: int = ((1 & 0x1F) << 22) | ((blend & 0xFF) << 14)
            bytes.encode_u32((z * width + x) * 4, packed)

    return Image.create_from_data(width, height, false, Image.FORMAT_RF, bytes)

func _set_status(text: String) -> void:
    if status_label and is_instance_valid(status_label):
        status_label.text = text


func _build_river_water(values: PackedFloat32Array, width: int, height: int) -> void:
    var f := FileAccess.open("res://terrain_materials/river_path.json", FileAccess.READ)
    if f == null:
        push_warning("river_path.json non disponibile: Tevere water mesh non creato")
        return
    var parsed = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("points"):
        push_warning("river_path.json non valido")
        return
    var points: Array = parsed["points"]
    if points.size() < 2:
        return

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var water_mat := ShaderMaterial.new()
    var sh := Shader.new()
    sh.code = """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Strong, continuous river current. UV.x is the authored river axis (0..1).
// The pattern is intentionally elongated and phase-distorted so it reads as
// water moving downstream, not as square/tiled animation.
float current_layer(float u, float v, float t, float freq, float speed, float bend, float sharp){
    float phase = u * freq - t * speed;
    phase += sin(v * 3.7 + u * 2.2) * bend;
    phase += sin(v * 8.4 - u * 1.3 + t * 0.10) * (bend * 0.34);
    float s = 0.5 + 0.5 * sin(phase * 6.2831853);
    return smoothstep(sharp, 1.0, s);
}

float eddy_layer(float u, float v, float t){
    float p = u * 3.6 - t * 0.48 + sin(v * 5.0) * 0.35;
    float q = 0.5 + 0.5 * sin(p * 6.2831853 + sin(u * 13.0 - t * 0.7) * 0.8);
    return smoothstep(0.60, 0.92, q);
}

void fragment(){
    float t = TIME;
    float u = UV.x;
    float v = (UV.y - 0.5) * 2.0;

    // Three downstream layers at different scales. The phase distortion makes
    // the streaks merge and separate naturally as they travel.
    float broad = current_layer(u, v, t, 8.0, 0.62, 0.22, 0.48);
    float medium = current_layer(u + 0.037, v * 1.15, t * 1.05, 15.0, 1.05, 0.17, 0.55);
    float fine = current_layer(u + 0.081, v * 1.8, t * 1.18, 29.0, 1.55, 0.11, 0.62);
    float eddy = eddy_layer(u, v, t);

    // Strong directional current mask: visible motion, but no checkerboard.
    float current = broad * 0.58 + medium * 0.29 + fine * 0.13;
    current = mix(current, current * 0.72 + eddy * 0.28, 0.32);

    // Animate the normal with the same downstream field so highlights travel
    // with the current instead of merely flickering in place.
    float e = 0.004;
    float c0 = current_layer(u, v, t, 15.0, 1.05, 0.17, 0.55);
    float cx = current_layer(u + e, v, t, 15.0, 1.05, 0.17, 0.55);
    float cy = current_layer(u, v + e, t, 15.0, 1.05, 0.17, 0.55);
    float dx = cx - c0;
    float dy = cy - c0;
    vec3 n = normalize(vec3(-dx * 1.9, -dy * 1.35, 1.0));
    NORMAL = n;

    // Moving bank foam: concentrated at both banks and carried downstream.
    float bank = min(UV.y, 1.0 - UV.y);
    float bank_mask = 1.0 - smoothstep(0.035, 0.18, bank);
    float foam_flow = current_layer(u + 0.17, v * 2.6, t * 1.12, 18.0, 1.28, 0.13, 0.66);
    float foam = bank_mask * foam_flow * 0.20;

    // Deep stylized water + moving surface color + physically-inspired Fresnel.
    vec3 deep = vec3(0.008, 0.055, 0.082);
    vec3 mid = vec3(0.012, 0.115, 0.17);
    vec3 moving = vec3(0.055, 0.235, 0.29);
    vec3 bright = vec3(0.33, 0.56, 0.57);

    vec3 water = mix(deep, mid, 0.46);
    water = mix(water, moving, current * 0.40);

    float fresnel = pow(1.0 - max(dot(normalize(VIEW), n), 0.0), 3.0);
    float sun_glint = pow(max(dot(n, normalize(vec3(-0.32, 0.78, 0.54))), 0.0), 18.0);
    float moving_glint = sun_glint * (0.25 + current * 0.75);
    water += bright * moving_glint * (0.24 + fresnel * 0.30);
    water = mix(water, vec3(0.55, 0.72, 0.70), foam);

    ALBEDO = water;
    ROUGHNESS = 0.16 - fresnel * 0.055;
    SPECULAR = 0.95;
    METALLIC = 0.0;
}
"""
    water_mat.shader = sh
    st.set_material(water_mat)

    var spacing := MAP_SIZE_M / float(width - 1)
    var left_pts: Array[Vector3] = []
    var right_pts: Array[Vector3] = []
    var water_y_values: Array[float] = []

    # First pass: determine a stable water level from the lowest terrain in each
    # local river-bed cross-section. Values are already normalized 0..1.
    for i in range(points.size()):
        var p: Dictionary = points[i]
        var px := float(p["x"])
        var pz := float(p["z"])
        var half_width := float(p["half_width"])
        var prev: Dictionary = points[maxi(0, i - 1)]
        var next: Dictionary = points[mini(points.size() - 1, i + 1)]
        var tangent := Vector2(float(next["x"]) - float(prev["x"]), float(next["z"]) - float(prev["z"])).normalized()
        var normal := Vector2(-tangent.y, tangent.x)
        var gx := clampi(int(round(px)), 0, width - 1)
        var gz := clampi(int(round(pz)), 0, height - 1)
        var radius_px: int = maxi(2, int(ceil(half_width / spacing)))
        var min_h: float = 1.0
        for oz in range(-radius_px, radius_px + 1):
            for ox in range(-radius_px, radius_px + 1):
                var wx := float(ox) * spacing
                var wz := float(oz) * spacing
                var along := wx * tangent.x + wz * tangent.y
                var across := wx * normal.x + wz * normal.y
                if absf(across) <= half_width and absf(along) <= half_width:
                    var sx: int = clampi(gx + ox, 0, width - 1)
                    var sz: int = clampi(gz + oz, 0, height - 1)
                    min_h = minf(min_h, values[sz * width + sx])
        water_y_values.append(min_h * HEIGHT_SCALE_M + 2.75)

    # Moving average removes sharp longitudinal steps. The max with the local
    # target prevents the smoothed surface from sinking back into the terrain.
    var smoothed: Array[float] = []
    smoothed.resize(water_y_values.size())
    for i in range(water_y_values.size()):
        var acc := 0.0
        var count := 0
        for k in range(maxi(0, i - 4), mini(water_y_values.size(), i + 5)):
            acc += water_y_values[k]
            count += 1
        smoothed[i] = acc / float(count)
    for i in range(water_y_values.size()):
        water_y_values[i] = maxf(smoothed[i], water_y_values[i])

    # Smooth the authored river width along the path so bends and banks do not
    # produce abrupt narrowing/widening. The water is only slightly wider than
    # FIX15; terrain, heightmap and the manual control map remain untouched.
    var smooth_half_widths: Array[float] = []
    smooth_half_widths.resize(points.size())
    for i in range(points.size()):
        var width_acc := 0.0
        var width_count := 0
        for k in range(maxi(0, i - 3), mini(points.size(), i + 4)):
            width_acc += float(points[k]["half_width"])
            width_count += 1
        smooth_half_widths[i] = width_acc / float(width_count)

    for i in range(points.size()):
        var p: Dictionary = points[i]
        var px := float(p["x"])
        var pz := float(p["z"])
        var half_width := smooth_half_widths[i]
        var prev: Dictionary = points[maxi(0, i - 1)]
        var next: Dictionary = points[mini(points.size() - 1, i + 1)]
        var tangent := Vector2(float(next["x"]) - float(prev["x"]), float(next["z"]) - float(prev["z"])).normalized()
        var normal := Vector2(-tangent.y, tangent.x)
        var y := water_y_values[i]

        # Keep the wider FIX16 water on straight sections, but reduce the
        # offset locally on sharper bends. This prevents the two offset banks
        # from crossing themselves and creating detached-looking water loops.
        var turn_angle := 0.0
        if i > 0 and i < points.size() - 1:
            var prev_p: Dictionary = points[i - 1]
            var next_p: Dictionary = points[i + 1]
            var v_prev := Vector2(px - float(prev_p["x"]), pz - float(prev_p["z"]))
            var v_next := Vector2(float(next_p["x"]) - px, float(next_p["z"]) - pz)
            if v_prev.length_squared() > 0.001 and v_next.length_squared() > 0.001:
                turn_angle = acos(clampf(v_prev.normalized().dot(v_next.normalized()), -1.0, 1.0))
        var bend_factor := maxf(0.62, 1.0 - 0.50 * (turn_angle / deg_to_rad(45.0)))
        var render_half_width := half_width * 1.25 * bend_factor
        var l := Vector3((px + normal.x * render_half_width) * spacing, y, (pz + normal.y * render_half_width) * spacing)
        var r := Vector3((px - normal.x * render_half_width) * spacing, y, (pz - normal.y * render_half_width) * spacing)
        left_pts.append(l)
        right_pts.append(r)

    for i in range(points.size() - 1):
        var u0 := float(i) / float(points.size() - 1)
        var u1 := float(i + 1) / float(points.size() - 1)
        st.set_uv(Vector2(u0, 0.0)); st.set_normal(Vector3.UP); st.add_vertex(left_pts[i])
        st.set_uv(Vector2(u0, 1.0)); st.set_normal(Vector3.UP); st.add_vertex(right_pts[i])
        st.set_uv(Vector2(u1, 1.0)); st.set_normal(Vector3.UP); st.add_vertex(right_pts[i + 1])
        st.set_uv(Vector2(u0, 0.0)); st.set_normal(Vector3.UP); st.add_vertex(left_pts[i])
        st.set_uv(Vector2(u1, 1.0)); st.set_normal(Vector3.UP); st.add_vertex(right_pts[i + 1])
        st.set_uv(Vector2(u1, 0.0)); st.set_normal(Vector3.UP); st.add_vertex(left_pts[i + 1])

    var mesh := st.commit()
    if mesh == null:
        push_warning("Tevere water mesh vuoto")
        return
    var mi := MeshInstance3D.new()
    mi.name = "TevereWater"
    mi.mesh = mesh
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    mi.material_override = water_mat
    add_child(mi)
    print("TEVERE WATER RIBBON OK points=", points.size())
