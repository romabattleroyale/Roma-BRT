extends CharacterBody3D

@export var move_speed: float = 5.0
@export var look_sensitivity: float = 0.006
var yaw := 0.0
var pitch := -0.15
var touch_look_id := -1
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
    camera.current = true

func _physics_process(_delta: float) -> void:
    var input_vec := Vector2(float(Input.is_action_pressed("move_right")) - float(Input.is_action_pressed("move_left")), float(Input.is_action_pressed("move_back")) - float(Input.is_action_pressed("move_forward")))
    if input_vec.length() > 1.0: input_vec = input_vec.normalized()
    var dir := (transform.basis * Vector3(input_vec.x, 0, input_vec.y)).normalized()
    velocity.x = dir.x * move_speed
    velocity.z = dir.z * move_speed
    velocity.y = 0.0
    move_and_slide()

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed and event.position.x > get_viewport().size.x * 0.42: touch_look_id = event.index
        elif not event.pressed and event.index == touch_look_id: touch_look_id = -1
    elif event is InputEventScreenDrag and event.index == touch_look_id:
        yaw -= event.relative.x * look_sensitivity
        pitch = clamp(pitch - event.relative.y * look_sensitivity, -1.15, 1.15)
        rotation.y = yaw
        camera.rotation.x = pitch
