extends SceneTree
## Mobile V11 texture budget pass.
## Reads source images directly so CI does not depend on imported .ctex cache files.
## Caps the largest source dimension at 1024px for Android-friendly memory usage.

const TEX_DIR := "res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures"
const MAX_SIZE := 1024
const JPEG_QUALITY := 0.86

func _initialize() -> void:
    var dir := DirAccess.open(TEX_DIR)
    if dir == null:
        push_error("V11 TEXTURE OPT FAIL: missing %s" % TEX_DIR)
        quit(2)
        return
    var changed:int = 0
    var seen:int = 0
    dir.list_dir_begin()
    while true:
        var name:String = dir.get_next()
        if name.is_empty():
            break
        if dir.current_is_dir():
            continue
        var path:String = TEX_DIR + "/" + name
        var ext:String = name.get_extension().to_lower()
        if ext != "jpg" and ext != "jpeg" and ext != "png":
            continue
        seen += 1

        # Read the actual source file. Do not use load(path): CI may not have
        # generated Godot .ctex imports for these source images yet.
        var image:Image = Image.load_from_file(path)
        if image == null or image.is_empty():
            push_error("V11 TEXTURE OPT FAIL: cannot read source image %s" % path)
            quit(3)
            return

        var before:Vector2i = Vector2i(image.get_width(), image.get_height())
        var largest:int = maxi(before.x, before.y)
        if largest <= MAX_SIZE:
            print("V11 TEXTURE KEEP: %s %dx%d" % [name, before.x, before.y])
            image = null
            continue

        var scale:float = float(MAX_SIZE) / float(largest)
        var new_w:int = maxi(1, roundi(float(before.x) * scale))
        var new_h:int = maxi(1, roundi(float(before.y) * scale))
        image.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)

        var err:Error
        if ext == "png":
            err = image.save_png(path)
        else:
            err = image.save_jpg(path, JPEG_QUALITY)
        if err != OK:
            push_error("V11 TEXTURE OPT FAIL: save error %s" % path)
            quit(4)
            return
        changed += 1
        print("V11 TEXTURE RESIZE: %s %dx%d -> %dx%d" % [name, before.x, before.y, new_w, new_h])
        image = null
    dir.list_dir_end()
    print("V11 TEXTURE OPT PASS: scanned=%d resized=%d max=%dpx" % [seen, changed, MAX_SIZE])
    quit(0)
