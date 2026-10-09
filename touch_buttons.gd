extends Control
## Lightweight responsive touch HUD. Gameplay actions are emitted for systems to bind.
signal action_pressed(action: StringName, pressed: bool)
const BUTTONS := [
    [&"jump", "SALTA", Vector2(0.90,0.78), 76.0],
    [&"crouch", "ACCOV.", Vector2(0.80,0.84), 58.0],
    [&"sprint", "CORRI", Vector2(0.70,0.88), 60.0],
    [&"aim", "MIRA", Vector2(0.82,0.62), 68.0],
    [&"shoot", "FUOCO", Vector2(0.92,0.62), 86.0],
    [&"reload", "RIC.", Vector2(0.92,0.36), 56.0],
    [&"interact", "USA", Vector2(0.80,0.36), 56.0],
    [&"inventory", "ZAINO", Vector2(0.95,0.10), 56.0],
    [&"build", "BUILD", Vector2(0.84,0.10), 56.0],
]
var _active: Dictionary = {}
var _rects: Dictionary = {}
var _mobile := false
func _ready() -> void:
    _mobile = OS.get_name() in ["Android", "iOS"]
    visible = _mobile
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    queue_redraw()
func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED: queue_redraw()
func _draw() -> void:
    _rects.clear()
    for item in BUTTONS:
        var action: StringName = item[0]
        var label: String = item[1]
        var p: Vector2 = item[2]
        var radius: float = item[3] * 0.5
        var center := Vector2(size.x * p.x, size.y * p.y)
        var rect := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
        _rects[action] = rect
        var pressed: bool = _active.has(action)
        draw_circle(center, radius, Color(0.08,0.10,0.14,0.72 if pressed else 0.43))
        draw_arc(center, radius, 0.0, TAU, 48, Color(1,1,1,0.82), 2.0)
        draw_string(ThemeDB.fallback_font, center + Vector2(-radius * 0.60, 5.0), label, HORIZONTAL_ALIGNMENT_CENTER, radius * 1.2, 14, Color.WHITE)
func _input(event: InputEvent) -> void:
    if not _mobile: return
    if event is InputEventScreenTouch:
        if event.pressed:
            for action in _rects:
                if _rects[action].has_point(event.position):
                    _active[action] = event.index
                    action_pressed.emit(action, true)
                    queue_redraw()
                    get_viewport().set_input_as_handled()
                    return
        else:
            for action in _active.keys():
                if _active[action] == event.index:
                    _active.erase(action)
                    action_pressed.emit(action, false)
                    queue_redraw()
                    get_viewport().set_input_as_handled()
                    return
