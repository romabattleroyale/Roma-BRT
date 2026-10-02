extends Control
## Simple Android touch controls for the heightmap beta.
## Left thumb: virtual joystick (move)
## Right thumb: swipe anywhere on right half (camera look)
## Bottom-right RUN button: hold for speed boost

signal move_changed(value: Vector2)
signal look_delta(value: Vector2)
signal boost_changed(active: bool)

var joystick_center := Vector2.ZERO
var joystick_value := Vector2.ZERO
var joystick_touch := -1
var look_touch := -1
var last_look := Vector2.ZERO
var boost_rect := Rect2()
var boost_touch := -1

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

func _draw() -> void:
    _layout()
    # Joystick base and knob.
    draw_circle(joystick_center, 72.0, Color(0.05, 0.08, 0.12, 0.38))
    draw_arc(joystick_center, 72.0, 0.0, TAU, 48, Color(1,1,1,0.42), 3.0)
    var knob: Vector2 = joystick_center + joystick_value * 48.0
    draw_circle(knob, 30.0, Color(1,1,1,0.30))
    draw_arc(knob, 30.0, 0.0, TAU, 32, Color(1,1,1,0.65), 2.0)

    # Run button.
    var c: Color = Color(0.78, 0.15, 0.10, 0.55) if boost_touch != -1 else Color(0.05, 0.08, 0.12, 0.38)
    draw_style_box(_box(c, 14.0, Color(1,1,1,0.45), 2.0), boost_rect)
    draw_string(ThemeDB.fallback_font, boost_rect.position + Vector2(25, 43), "CORRI", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

    # Right-side hint.
    draw_string(ThemeDB.fallback_font, Vector2(size.x - 285.0, size.y - 28.0), "TRASCINA QUI PER GUARDARTI", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1,1,1,0.65))

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
            look_touch = event.index
            last_look = p
            get_viewport().set_input_as_handled()
        else:
            if event.index == joystick_touch:
                joystick_touch = -1
                joystick_value = Vector2.ZERO
                move_changed.emit(Vector2.ZERO)
            if event.index == boost_touch:
                boost_touch = -1
                boost_changed.emit(false)
            if event.index == look_touch:
                look_touch = -1
            queue_redraw()
            get_viewport().set_input_as_handled()

    elif event is InputEventScreenDrag:
        if event.index == joystick_touch:
            joystick_value = _joystick_from(event.position)
            move_changed.emit(joystick_value)
            queue_redraw()
            get_viewport().set_input_as_handled()
        elif event.index == look_touch:
            var d: Vector2 = event.position - last_look
            last_look = event.position
            look_delta.emit(d)
            get_viewport().set_input_as_handled()

func _joystick_from(p: Vector2) -> Vector2:
    var v: Vector2 = p - joystick_center
    if v.length() > 72.0:
        v = v.normalized() * 72.0
    return v / 72.0
