extends Node3D
## Runtime integration for the persisted manual GridMap road system.
## Loads 12 district road scenes + 4 authorized bridges without touching Terrain3D,
## Tevere, the road graph, district layout or building/HLOD assets.

const DISTRICT_SCENES:Array[String] = [
    "res://roads/generated/district_01_roads.tscn",
    "res://roads/generated/district_02_roads.tscn",
    "res://roads/generated/district_03_roads.tscn",
    "res://roads/generated/district_04_roads.tscn",
    "res://roads/generated/district_05_roads.tscn",
    "res://roads/generated/district_06_roads.tscn",
    "res://roads/generated/district_07_roads.tscn",
    "res://roads/generated/district_08_roads.tscn",
    "res://roads/generated/district_09_roads.tscn",
    "res://roads/generated/district_10_roads.tscn",
    "res://roads/generated/district_11_roads.tscn",
    "res://roads/generated/district_12_roads.tscn",
]

const BRIDGE_SCENES:Array[String] = [
    "res://roads/generated/ponte_sisto.tscn",
    "res://roads/generated/ponte_santangelo.tscn",
    "res://roads/generated/ponte_vittorio.tscn",
    "res://roads/generated/ponte_garibaldi.tscn",
]

func _ready() -> void:
    var loaded:int = 0
    for path:String in DISTRICT_SCENES + BRIDGE_SCENES:
        var packed:=ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
        if packed == null:
            push_error("ROMA ROADS: missing persisted scene " + path)
            continue
        var instance:=packed.instantiate()
        if instance == null:
            push_error("ROMA ROADS: failed to instantiate " + path)
            continue
        add_child(instance)
        loaded += 1
    if loaded == 16:
        print("ROMA ROADS RUNTIME: PASS districts=12 bridges=4 GridMap=manual")
    else:
        push_error("ROMA ROADS RUNTIME: loaded=%d/16" % loaded)
