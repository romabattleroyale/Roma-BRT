extends Control
## Minimal camera-mode toggle only.
## Movement and gameplay actions are handled by HUD/TouchHUD controls to avoid duplicate touch targets.

signal move_changed(value: Vector2)
signal look_delta(value: Vector2)
signal boost_changed(active: bool)
signal camera_toggle_requested

var camera_toggle_rect := Rect2()
var camera_toggle_touch := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	_layout()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()

func _layout() -> void:
	var s := get_viewport_rect().size
	camera_toggle_rect = Rect2(s.x - 300.0, 24.0, 270.0, 62.0)

func _draw() -> void:
	_layout()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.12, 0.68)
	style.border_color = Color(1, 1, 1, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	draw_style_box(style, camera_toggle_rect)
	draw_string(ThemeDB.fallback_font, camera_toggle_rect.position + Vector2(20, 39), "CAMBIA VISUALE", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and camera_toggle_rect.has_point(event.position):
			camera_toggle_touch = event.index
			camera_toggle_requested.emit()
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == camera_toggle_touch:
			camera_toggle_touch = -1
			get_viewport().set_input_as_handled()
