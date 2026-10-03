extends Node3D
## Runtime loader for the editor-baked 587-building city.
## No V11 building construction happens here.

const BAKED_SCENE := "res://baked_city/roma_city_587.tscn"

func _ready() -> void:
    if not ResourceLoader.exists(BAKED_SCENE):
        push_warning("BAKED CITY: %s non trovata. Eseguire bake_587_city_editor.gd dall'editor una volta." % BAKED_SCENE)
        return
    var packed := load(BAKED_SCENE) as PackedScene
    if packed == null:
        push_error("BAKED CITY: PackedScene non caricabile: %s" % BAKED_SCENE)
        return
    var city := packed.instantiate()
    city.name = "RomaCity_BAKED_587"
    add_child(city)
    print("BAKED CITY — caricata scena persistente: ", BAKED_SCENE)
