extends Node3D
## Debug camera dall'alto per ispezionare la mappa Roma-BRT.
## Android: 1 dito = ruota, 2 dita = pan + pinch zoom.
## PC: RMB = ruota, MMB = pan, rotella = zoom.

@export var map_size := 2000.0
@export var target := Vector3(1000.0, 0.0, 1000.0)
@export var distance := 1500.0
@export var min_distance := 120.0
@export var max_distance := 3200.0
@export var yaw := 0.0
@export var pitch := -1.22
@export var rotate_speed := 0.008
@export var zoom_speed := 0.0025
@export var pan_speed := 1.2

var camera: Camera3D
var dragging_rotate := false
var dragging_pan := false
var last_pointer := Vector2.ZERO
var touches: Dictionary = {}
var last_pinch_distance := 0.0
var last_touch_center := Vector2.ZERO

func _ready() -> void:
    camera = Camera3D.new()
    camera.name = "DebugTopDownCamera"
    camera.current = true
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 1800.0
    camera.near = 0.1
    camera.far = 6000.0
    add_child(camera)
    update_camera()

func _unhandled_input(event: InputEvent) -> void:
    if camera == null:
        return

    if event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        if mouse.button_index == MOUSE_BUTTON_WHEEL_UP and mouse.pressed:
            distance = maxf(min_distance, distance * 0.88)
            update_camera()
        elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse.pressed:
            distance = minf(max_distance, distance / 0.88)
            update_camera()
        elif mouse.button_index == MOUSE_BUTTON_RIGHT:
            dragging_rotate = mouse.pressed
            last_pointer = mouse.position
        elif mouse.button_index == MOUSE_BUTTON_MIDDLE:
            dragging_pan = mouse.pressed
            last_pointer = mouse.position
        return

    if event is InputEventMouseMotion:
        var motion := event as InputEventMouseMotion
        if dragging_rotate:
            var delta := motion.position - last_pointer
            last_pointer = motion.position
            yaw -= delta.x * rotate_speed
            pitch = clampf(pitch - delta.y * rotate_speed, -1.52, -0.28)
            update_camera()
        elif dragging_pan:
            var pan_delta := motion.position - last_pointer
            last_pointer = motion.position
            pan_camera(pan_delta)
        return

    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            touches[touch.index] = touch.position
        else:
            touches.erase(touch.index)
            if touches.size() < 2:
                last_pinch_distance = 0.0
                last_touch_center = Vector2.ZERO
        return

    if event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        touches[drag.index] = drag.position
        if touches.size() == 1:
            yaw -= drag.relative.x * rotate_speed
            pitch = clampf(pitch - drag.relative.y * rotate_speed, -1.52, -0.28)
            update_camera()
        elif touches.size() >= 2:
            var keys := touches.keys()
            var p0: Vector2 = touches[keys[0]]
            var p1: Vector2 = touches[keys[1]]
            var center := (p0 + p1) * 0.5
            var pinch_distance := p0.distance_to(p1)
            if last_touch_center != Vector2.ZERO:
                pan_camera(center - last_touch_center)
            if last_pinch_distance > 0.0:
                var pinch_delta := pinch_distance - last_pinch_distance
                distance = clampf(distance * (1.0 - pinch_delta * zoom_speed), min_distance, max_distance)
                update_camera()
            last_touch_center = center
            last_pinch_distance = pinch_distance
        return

func pan_camera(delta: Vector2) -> void:
    var basis := Basis(Vector3.UP, yaw)
    var right := basis.x
    var forward := -basis.z
    var amount := distance * pan_speed * 0.001
    target += (-right * delta.x + forward * delta.y) * amount
    target.x = clampf(target.x, 0.0, map_size)
    target.z = clampf(target.z, 0.0, map_size)
    update_camera()

func update_camera() -> void:
    if camera == null:
        return
    var horizontal := cos(pitch) * distance
    var vertical := -sin(pitch) * distance
    var offset := Vector3(sin(yaw) * horizontal, vertical, cos(yaw) * horizontal)
    camera.position = target + offset
    camera.look_at(target, Vector3.UP)
