extends Control
## Android controls for the debug top-down camera.
## Left thumb: virtual joystick = move map.
## Right half: reserved for debug camera zoom/pitch; this Control does not consume it.
## Bottom-right RUN button is kept for the existing gameplay UI.

signal move_changed(value: Vector2)
signal look_delta(value: Vector2)
signal boost_changed(active: bool)
signal camera_toggle_requested

var joystick_center := Vector2.ZERO
var joystick_value := Vector2.ZERO
var joystick_touch := -1
var boost_rect := Rect2()
var boost_touch := -1
var camera_toggle_rect := Rect2()
var camera_toggle_touch := -1

func _ready() -> void:
    set_process_input(true)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    queue_redraw()

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        queue_redraw()

func _layout() -> void:
    var s: Vector2 = size
    joystick_center = Vector2(145.0, s.y - 145.0)
    boost_rect = Rect2(s.x - 150.0, s.y - 130.0, 105.0, 70.0)
    camera_toggle_rect = Rect2(s.x - 300.0, 24.0, 270.0, 62.0)

func _draw() -> void:
    _layout()
    draw_circle(joystick_center, 72.0, Color(0.05, 0.08, 0.12, 0.38))
    draw_arc(joystick_center, 72.0, 0.0, TAU, 48, Color(1,1,1,0.42), 3.0)
    var knob: Vector2 = joystick_center + joystick_value * 48.0
    draw_circle(knob, 30.0, Color(1,1,1,0.30))
    draw_arc(knob, 30.0, 0.0, TAU, 32, Color(1,1,1,0.65), 2.0)

    var c: Color = Color(0.78, 0.15, 0.10, 0.55) if boost_touch != -1 else Color(0.05, 0.08, 0.12, 0.38)
    draw_style_box(_box(c, 14.0, Color(1,1,1,0.45), 2.0), boost_rect)
    draw_string(ThemeDB.fallback_font, boost_rect.position + Vector2(25, 43), "CORRI", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
    draw_style_box(_box(Color(0.05, 0.08, 0.12, 0.60), 12.0, Color(1,1,1,0.55), 2.0), camera_toggle_rect)
    draw_string(ThemeDB.fallback_font, camera_toggle_rect.position + Vector2(20, 39), "CAMBIA VISUALE", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
    draw_string(ThemeDB.fallback_font, Vector2(size.x - 285.0, size.y - 28.0), "DESTRA: ZOOM / PITCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1,1,1,0.65))

func _box(bg: Color, radius: float, border: Color, width: float) -> StyleBoxFlat:
    var b: StyleBoxFlat = StyleBoxFlat.new()
    b.bg_color = bg
    b.border_color = border
    b.set_border_width_all(int(width))
    b.set_corner_radius_all(int(radius))
    return b

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        var p: Vector2 = event.position
        if event.pressed:
            if camera_toggle_rect.has_point(p):
                camera_toggle_touch = event.index
                camera_toggle_requested.emit()
                get_viewport().set_input_as_handled()
                return
            if boost_rect.has_point(p):
                boost_touch = event.index
                boost_changed.emit(true)
                queue_redraw()
                get_viewport().set_input_as_handled()
                return
            if p.x < size.x * 0.42:
                joystick_touch = event.index
                joystick_value = _joystick_from(p)
                move_changed.emit(joystick_value)
                queue_redraw()
                get_viewport().set_input_as_handled()
                return
            # Right half is intentionally NOT consumed: debug_topdown_camera.gd receives it.
            return
        else:
            if event.index == joystick_touch:
                joystick_touch = -1
                joystick_value = Vector2.ZERO
                move_changed.emit(Vector2.ZERO)
                queue_redraw()
                get_viewport().set_input_as_handled()
                return
            if event.index == boost_touch:
                boost_touch = -1
                boost_changed.emit(false)
                queue_redraw()
                get_viewport().set_input_as_handled()
                return
            # Right-side release is left untouched for the debug camera.

    elif event is InputEventScreenDrag:
        if event.index == joystick_touch:
            joystick_value = _joystick_from(event.position)
            move_changed.emit(joystick_value)
            queue_redraw()
            get_viewport().set_input_as_handled()
            return
        # Right-side drag is intentionally NOT consumed.

func _joystick_from(p: Vector2) -> Vector2:
    var v: Vector2 = p - joystick_center
    if v.length() > 72.0:
        v = v.normalized() * 72.0
    return v / 72.0
