extends Node3D
## Runtime integration for the persisted manual GridMap road system.
## Loads 12 district road scenes + 4 authorized bridges without touching Terrain3D,
## Tevere, the road graph, district layout or building/HLOD assets.

const WORLD_OFFSET := Vector3(1000.0, 0.0, 1000.0)
# Diagnostic/runtime elevation only. Persisted road cells are authored at Y=0,
# while the Terrain3D heightmap spans 0..48 m. Lift the rendered road layer so
# it cannot be buried by the terrain. This does not modify baked road scenes.
const ROAD_RUNTIME_LIFT_Y := 4.0
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
        var instance:=packed.instantiate() as Node3D
        if instance == null:
            push_error("ROMA ROADS: failed to instantiate " + path)
            continue
        # Road scenes are authored in the centered V11 frame; move each loaded
        # scene once into the same 0..2000 runtime frame as buildings and terrain.
        instance.position += WORLD_OFFSET
        instance.position.y += ROAD_RUNTIME_LIFT_Y
        add_child(instance)
        loaded += 1
    if loaded == 16:
        print("ROMA ROADS RUNTIME: PASS districts=12 bridges=4 GridMap=manual world_offset=+1000,+1000 lift_y=4.0")
    else:
        push_error("ROMA ROADS RUNTIME: loaded=%d/16" % loaded)
