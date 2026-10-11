extends CanvasLayer

func _ready() -> void:
    $Panel/Label.text = "ROMA BATTLE ROYALE — MAPGEN\n\nTerreno procedurale • seed 1337\nMondo 2000 × 2000 m • rilievo dinamico\n\nANDROID: joystick sinistro = movimento\nTrascina a destra = visuale • CORRI = boost\nPC: WASD/frecce = movimento • SHIFT = boost\nTasto destro + mouse = visuale"

    var map_generator := get_tree().current_scene.find_child("MapGenerator", true, false)
    var status_label := get_tree().current_scene.get_node_or_null("Status") as Label
    if map_generator == null or status_label == null:
        return

    map_generator.generation_started.connect(_on_map_generation_started.bind(status_label))
    map_generator.generation_finished.connect(_on_map_generation_finished.bind(status_label))
    if map_generator.get("heightfield") != null:
        status_label.text = "MapGen pronto • terreno generato"
    else:
        status_label.text = "MapGen attivo • attendo generazione terreno"


func _on_map_generation_started(status_label: Label) -> void:
    status_label.text = "MapGen: generazione terreno in corso…"


func _on_map_generation_finished(_heightfield: Variant, seconds: float, status_label: Label) -> void:
    status_label.text = "MapGen pronto • terreno generato in %.2f s" % seconds
