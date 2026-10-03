@tool
extends Node3D
## Logical road grid for future urban planning.
## Editor-only guides: no road meshes and no gameplay geometry are created.

const LINE_THICKNESS := 0.1
const LINE_HEIGHT := 0.04
const LINE_COLOR := Color(0.15, 0.75, 1.0, 0.18)

# Logical intersections, expressed in the existing 2000 x 2000 world.
# The layout keeps a central historic-core network, a west-side river corridor,
# and major north/south + east/west axes. These are planning guides only.
const INTERSECTIONS := [
    {"id":"URB_NW", "position":Vector3(520.0, 0.0, 420.0)},
    {"id":"URB_NC", "position":Vector3(900.0, 0.0, 420.0)},
    {"id":"URB_NE", "position":Vector3(1390.0, 0.0, 420.0)},
    {"id":"URB_W1", "position":Vector3(520.0, 0.0, 760.0)},
    {"id":"URB_C1", "position":Vector3(900.0, 0.0, 760.0)},
    {"id":"URB_E1", "position":Vector3(1390.0, 0.0, 760.0)},
    {"id":"URB_W2", "position":Vector3(520.0, 0.0, 1080.0)},
    {"id":"URB_C2", "position":Vector3(900.0, 0.0, 1080.0)},
    {"id":"URB_E2", "position":Vector3(1390.0, 0.0, 1080.0)},
    {"id":"URB_W3", "position":Vector3(520.0, 0.0, 1400.0)},
    {"id":"URB_C3", "position":Vector3(900.0, 0.0, 1400.0)},
    {"id":"URB_E3", "position":Vector3(1390.0, 0.0, 1400.0)},
    {"id":"URB_S", "position":Vector3(900.0, 0.0, 1660.0)},
    {"id":"URB_R_N", "position":Vector3(700.0, 0.0, 420.0)},
    {"id":"URB_R_C", "position":Vector3(700.0, 0.0, 1080.0)},
    {"id":"URB_R_S", "position":Vector3(700.0, 0.0, 1660.0)}
]

# Pairs of intersection IDs. Every closed loop becomes a future city block.
const CONNECTIONS := [
    ["URB_NW", "URB_NC"], ["URB_NC", "URB_NE"],
    ["URB_W1", "URB_C1"], ["URB_C1", "URB_E1"],
    ["URB_W2", "URB_C2"], ["URB_C2", "URB_E2"],
    ["URB_W3", "URB_C3"], ["URB_C3", "URB_E3"],
    ["URB_NC", "URB_C1"], ["URB_C1", "URB_C2"],
    ["URB_C2", "URB_C3"], ["URB_C3", "URB_S"],
    ["URB_R_N", "URB_NC"], ["URB_R_C", "URB_C2"],
    ["URB_R_S", "URB_S"], ["URB_R_N", "URB_R_C"],
    ["URB_R_C", "URB_R_S"], ["URB_W1", "URB_W2"],
    ["URB_W2", "URB_W3"], ["URB_E1", "URB_E2"],
    ["URB_E2", "URB_E3"]
]

var _built := false

func _ready() -> void:
    if Engine.is_editor_hint():
        call_deferred("_build_grid")

func _enter_tree() -> void:
    if Engine.is_editor_hint():
        call_deferred("_build_grid")

func _build_grid() -> void:
    if _built:
        return
    _built = true

    var old := get_node_or_null("Guides")
    if old != null:
        old.queue_free()

    var guides := Node3D.new()
    guides.name = "Guides"
    add_child(guides)
    if Engine.is_editor_hint():
        guides.owner = get_tree().edited_scene_root

    var points := {}
    for item in INTERSECTIONS:
        var marker := Marker3D.new()
        marker.name = str(item["id"])
        marker.position = item["position"]
        marker.editor_description = "Urban Grid intersection / future road node"
        guides.add_child(marker)
        if Engine.is_editor_hint():
            marker.owner = get_tree().edited_scene_root
        points[marker.name] = marker.position

    var material := StandardMaterial3D.new()
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.albedo_color = LINE_COLOR
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.no_depth_test = true

    for index in range(CONNECTIONS.size()):
        var pair: Array = CONNECTIONS[index]
        var a: Vector3 = points[str(pair[0])]
        var b: Vector3 = points[str(pair[1])]
        var delta := b - a
        var length := delta.length()
        if length <= 0.01:
            continue

        var line := CSGBox3D.new()
        line.name = "Guide_%02d_%s_%s" % [index, str(pair[0]), str(pair[1])]
        line.size = Vector3(LINE_THICKNESS, LINE_HEIGHT, length)
        line.position = (a + b) * 0.5 + Vector3.UP * 0.02
        line.look_at(b, Vector3.UP)
        line.material = material
        line.use_collision = false
        line.editor_description = "Editor-only future road guide; NOT a road mesh"
        line.visible = Engine.is_editor_hint()
        guides.add_child(line)
        if Engine.is_editor_hint():
            line.owner = get_tree().edited_scene_root

    # Guides must never appear during gameplay.
    if not Engine.is_editor_hint():
        guides.visible = false
