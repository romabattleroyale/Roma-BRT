extends Node3D
## Debug camera dall'alto per Android + controller.
## Joystick sinistro virtuale/fisico = sposta la mappa.
## Touch meta' destra = zoom e pitch; pinch = zoom preciso.

@export var map_size := 2000.0
@export var target := Vector3(1000.0, 0.0, 1000.0)
@export var distance := 1500.0
@export var min_distance := 120.0
@export var max_distance := 3200.0
@export var pitch := -1.22
@export var min_pitch := -1.52
@export var max_pitch := -0.35
@export var touch_zoom_speed := 2.8
@export var touch_pitch_speed := 0.008
@export var controller_move_speed := 520.0

var camera: Camera3D
var touches: Dictionary = {}
var right_touch_indices: Dictionary = {}
var last_pinch_distance := 0.0
var virtual_move := Vector2.ZERO

func _ready() -> void:
    camera = Camera3D.new()
    camera.name = "DebugTopDownCamera3D"
    camera.current = true
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.near = 0.1
    camera.far = 6000.0
    add_child(camera)

    # Collega il joystick virtuale Android direttamente a questa camera.
    var mobile := get_parent().get_node_or_null("MobileControls")
    if mobile != null and mobile.has_signal("move_changed"):
        mobile.move_changed.connect(_on_virtual_move_changed)

    update_camera()

func _process(delta: float) -> void:
    if camera == null:
        return

    # Joystick virtuale sinistro.
    if virtual_move.length_squared() > 0.0001:
        pan_from_controller(virtual_move, delta)

    # Controller fisico: primo joypad connesso.
    var joypads := Input.get_connected_joypads()
    for joy_id in joypads:
        var move_x := Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X)
        var move_y := Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_Y)
        var move := Vector2(move_x, move_y)
        var magnitude := move.length()
        if magnitude > 0.12:
            magnitude = clampf((magnitude - 0.12) / 0.88, 0.0, 1.0)
            move = move.normalized() * magnitude
            pan_from_controller(move, delta)
        break

func _on_virtual_move_changed(value: Vector2) -> void:
    virtual_move = value

func pan_from_controller(move: Vector2, delta: float) -> void:
    var speed := controller_move_speed * maxf(distance / 900.0, 0.45)
    target.x += move.x * speed * delta
    target.z += -move.y * speed * delta
    target.x = clampf(target.x, 0.0, map_size)
    target.z = clampf(target.z, 0.0, map_size)
    update_camera()

func _input(event: InputEvent) -> void:
    if camera == null:
        return

    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            touches[touch.index] = touch.position
            if is_right_side(touch.position):
                right_touch_indices[touch.index] = true
        else:
            touches.erase(touch.index)
            right_touch_indices.erase(touch.index)
            if right_touch_indices.size() < 2:
                last_pinch_distance = 0.0
        return

    if event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        touches[drag.index] = drag.position

        if not right_touch_indices.has(drag.index):
            return

        var right_keys := right_touch_indices.keys()
        if right_keys.size() >= 2:
            if not touches.has(right_keys[0]) or not touches.has(right_keys[1]):
                return
            var p0: Vector2 = touches[right_keys[0]]
            var p1: Vector2 = touches[right_keys[1]]
            var pinch_distance := p0.distance_to(p1)
            if last_pinch_distance > 0.0:
                var pinch_delta := pinch_distance - last_pinch_distance
                distance = clampf(distance * pow(0.9975, pinch_delta), min_distance, max_distance)
                update_camera()
            last_pinch_distance = pinch_distance
            return

        # Un dito nella meta' destra: verticale = zoom, orizzontale = pitch.
        var vertical := drag.relative.y
        var horizontal := drag.relative.x
        if absf(vertical) > 0.01:
            distance = clampf(
                distance * pow(2.0, vertical * touch_zoom_speed / 1000.0),
                min_distance,
                max_distance
            )
        if absf(horizontal) > 0.01:
            pitch = clampf(
                pitch - horizontal * touch_pitch_speed,
                min_pitch,
                max_pitch
            )
        update_camera()

func is_right_side(position: Vector2) -> bool:
    return position.x >= get_viewport().get_visible_rect().size.x * 0.5

func update_camera() -> void:
    if camera == null:
        return

    var horizontal := cos(pitch) * distance
    var vertical := -sin(pitch) * distance
    var offset := Vector3(0.0, vertical, horizontal)
    camera.position = target + offset
    camera.size = clampf(distance * 0.72, 80.0, 3000.0)
    camera.look_at(target, Vector3.UP)
