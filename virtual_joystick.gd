extends Control
## Drawn virtual joystick; no external textures required.
signal changed(value: Vector2)
@export var base_radius := 75.0
@export var knob_radius := 30.0
@export var dead_zone := 0.15
var output := Vector2.ZERO
var _touch_id := -1
var _center := Vector2.ZERO
var _knob := Vector2.ZERO
func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _center = size * 0.5
    _knob = _center
    queue_redraw()
func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _center = size * 0.5
        if _touch_id == -1: _knob = _center
        queue_redraw()
func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed and _touch_id == -1 and get_global_rect().has_point(event.position):
            _touch_id = event.index
            _update_value(event.position)
            get_viewport().set_input_as_handled()
        elif not event.pressed and event.index == _touch_id:
            _touch_id = -1
            output = Vector2.ZERO
            _knob = _center
            changed.emit(output)
            queue_redraw()
            get_viewport().set_input_as_handled()
    elif event is InputEventScreenDrag and event.index == _touch_id:
        _update_value(event.position)
        get_viewport().set_input_as_handled()
func _update_value(global_pos: Vector2) -> void:
    var local := global_pos - global_position
    var delta := local - _center
    if delta.length() > base_radius: delta = delta.normalized() * base_radius
    _knob = _center + delta
    output = Vector2(delta.x / base_radius, -delta.y / base_radius)
    if output.length() < dead_zone: output = Vector2.ZERO
    else: output = output.normalized() * inverse_lerp(dead_zone, 1.0, minf(output.length(), 1.0))
    changed.emit(output)
    queue_redraw()
func _draw() -> void:
    _center = size * 0.5
    draw_circle(_center, base_radius, Color(0.03, 0.05, 0.08, 0.40))
    draw_arc(_center, base_radius, 0.0, TAU, 64, Color(1,1,1,0.55), 3.0)
    draw_circle(_knob, knob_radius, Color(0.9,0.94,1,0.38))
    draw_arc(_knob, knob_radius, 0.0, TAU, 48, Color(1,1,1,0.8), 2.0)
