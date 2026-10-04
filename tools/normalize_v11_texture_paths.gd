extends SceneTree
## CI/mobile bake compatibility patch.
## The V11 source library still contains legacy res://assets/textures paths,
## while the actual texture library lives under the Roma V11 library folder.
## Rewrite only those paths before baking so generated .tres materials point
## to real project files that are portable to Android/mobile Godot.

const TARGET := "res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures/"
const LEGACY := "res://assets/textures/"
const FILES := [
    "res://city_library/buildings/houses/roma_architecture_library_v11/scripts/building_system.gd",
]

func _initialize() -> void:
    var changed := 0
    for path in FILES:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
            push_error("V11 TEXTURE PATH FAIL: cannot open %s" % path)
            quit(2)
            return
        var text := f.get_as_text()
        f.close()
        if text.contains(LEGACY):
            text = text.replace(LEGACY, TARGET)
            var out := FileAccess.open(path, FileAccess.WRITE)
            if out == null:
                push_error("V11 TEXTURE PATH FAIL: cannot write %s" % path)
                quit(3)
                return
            out.store_string(text)
            out.close()
            changed += 1
    print("V11 TEXTURE PATHS: normalized_files=%d" % changed)
    quit(0)
