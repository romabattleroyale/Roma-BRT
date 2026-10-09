extends Control
## Right-hand look region; ignores touches begun elsewhere to allow joystick + fire multitouch.
@export var sensitivity := 0.004
@export var width_fraction := 0.60
var _look_fingers: Dictionary = {}
var _pivot: Node3D
func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _pivot = get_node_or_null("../Viewer/CameraPivot") as Node3D
    if _pivot == null: _pivot = get_tree().current_scene.find_child("CameraPivot", true, false) as Node3D
func _input(event: InputEvent) -> void:
    var screen_w := get_viewport().get_visible_rect().size.x
    if event is InputEventScreenTouch:
        if event.pressed and event.position.x >= screen_w * (1.0 - width_fraction):
            _look_fingers[event.index] = true
        elif not event.pressed:
            _look_fingers.erase(event.index)
    elif event is InputEventScreenDrag and _look_fingers.has(event.index):
        if _pivot and _pivot.has_method("apply_look"):
            _pivot.apply_look(event.relative, sensitivity)
