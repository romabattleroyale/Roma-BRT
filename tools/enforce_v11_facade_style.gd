extends SceneTree
## Final deterministic V11 facade-style pass.
## CI must not depend on Godot's imported .ctex cache. Material .tres files
## are edited as text so their source texture references remain portable.

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

func _replace_property(text:String, property_name:String, value:String) -> String:
    var prefix := property_name + " = "
    var lines := text.split("\n", false)
    var found := false
    for i in range(lines.size()):
        if lines[i].begins_with(prefix):
            lines[i] = prefix + value
            found = true
            break
    if not found:
        var insert_at := text.find("[resource]")
        if insert_at >= 0:
            var end := text.find("\n", insert_at)
            if end >= 0:
                lines = text.split("\n", false)
                var resource_line := 0
                for j in range(lines.size()):
                    if lines[j] == "[resource]":
                        resource_line = j + 1
                        break
                lines.insert(resource_line, prefix + value)
    return "\n".join(lines) + "\n"

func _run() -> void:
    var dir := DirAccess.open(MATERIAL_DIR)
    if dir == null:
        push_error("V11 FACADE STYLE FAIL: shared material directory missing")
        quit(1)
        return

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
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
            continue
        var text:String = f.get_as_text()
        f.close()

        # Detect facade materials from their serialized source text. This works
        # even when Texture2D imports are unavailable in a fresh CI runner.
        var lower := text.to_lower()
        var is_facade:bool = text.contains('resource_name = "Muro_Romano"') or lower.contains("roman_plaster_")
        if not is_facade:
            continue

        var color:Color = FACADE_COLORS[facade_count % FACADE_COLORS.size()]
        text = _replace_property(text, "resource_name", '"Muro_Romano"')
        text = _replace_property(text, "albedo_color", "Color(%s, %s, %s, 1)" % [color.r, color.g, color.b])
        text = _replace_property(text, "roughness", "0.9")
        text = _replace_property(text, "normal_enabled", "true")
        text = _replace_property(text, "normal_scale", "0.58")
        text = _replace_property(text, "uv1_scale", "Vector3(3.6, 3.6, 3.6)")
        text = _replace_property(text, "texture_repeat", "true")

        var out := FileAccess.open(path, FileAccess.WRITE)
        if out == null:
            push_error("V11 FACADE STYLE FAIL: cannot write %s" % path)
            quit(3)
            return
        out.store_string(text)
        out.close()
        facade_count += 1
        print("V11 ART FINAL: %s -> %s" % [path, color.to_html(false)])

    if facade_count == 0:
        push_error("V11 FACADE STYLE FAIL: no Roman facade material found")
        quit(4)
        return
    print("V11 ART FINAL PASS: facade_materials=%d palette=6 textures=validated" % facade_count)
    quit(0)
