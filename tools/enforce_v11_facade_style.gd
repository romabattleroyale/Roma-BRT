extends SceneTree
## Final deterministic V11 facade-style pass.
## Reads source images directly so CI does not depend on imported .ctex caches.
## Existing material texture references are preserved; this pass only validates
## the Roman source images and applies the warm Roman palette/style settings.

const MATERIAL_DIR := "res://baked_city/v11_shared_materials"
const TEXTURE_DIR := "res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures"

const FACADE_COLORS := [
    Color("#B97845"),
    Color("#D3A63A"),
    Color("#B96F73"),
    Color("#C7AA83"),
    Color("#A9573B"),
    Color("#A99A7E")
]

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var dir := DirAccess.open(MATERIAL_DIR)
    if dir == null:
        push_error("V11 FACADE STYLE FAIL: shared material directory missing")
        quit(1)
        return

    # Validate source files directly. Do not call load(source_path), because a
    # fresh headless runner may not yet have generated .godot/imported/*.ctex.
    var required_sources:Array[String] = [
        "%s/roman_plaster_weathered_albedo.jpg" % TEXTURE_DIR,
        "%s/roman_plaster_weathered_normal.jpg" % TEXTURE_DIR,
        "%s/roman_plaster_weathered_roughness.jpg" % TEXTURE_DIR
    ]
    for source_path in required_sources:
        var image:Image = Image.load_from_file(source_path)
        if image == null or image.is_empty():
            push_error("V11 FACADE STYLE FAIL: required Roman weathered source missing %s" % source_path)
            quit(2)
            return

    var facade_count:int = 0
    var files := dir.get_files()
    files.sort()
    for file_name in files:
        if not file_name.ends_with(".tres"):
            continue
        var path:String = "%s/%s" % [MATERIAL_DIR, file_name]
        var material:StandardMaterial3D = load(path) as StandardMaterial3D
        if material == null:
            continue

        var current_path:String = ""
        if material.albedo_texture != null:
            current_path = material.albedo_texture.resource_path.to_lower()
        var is_facade:bool = material.resource_name == "Muro_Romano" or current_path.contains("roman_plaster_")
        if not is_facade:
            continue

        var color:Color = FACADE_COLORS[facade_count % FACADE_COLORS.size()]
        material.resource_name = "Muro_Romano"
        material.albedo_color = color
        material.normal_enabled = material.normal_texture != null
        material.normal_scale = 0.58
        material.roughness = 0.90
        material.uv1_scale = Vector3(3.6, 3.6, 3.6)
        material.texture_repeat = true

        var err:Error = ResourceSaver.save(material, path)
        if err != OK:
            push_error("V11 FACADE STYLE FAIL: cannot save %s" % path)
            quit(3)
            return
        facade_count += 1
        print("V11 ART FINAL: %s -> %s + existing Roman textures" % [path, color.to_html(false)])

    if facade_count == 0:
        push_error("V11 FACADE STYLE FAIL: no Roman facade material found")
        quit(4)
        return
    print("V11 ART FINAL PASS: facade_materials=%d palette=6 textures=validated" % facade_count)
    quit(0)
