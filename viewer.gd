extends CharacterBody3D
## Desktop + Android controls.
## Android: left virtual joystick moves; swipe right half looks; CORRI boosts.

@export var speed := 45.0
@export var mouse_sensitivity := 0.003
@export var touch_sensitivity := 0.008
@export var boost := 3.0

var pitch: float = deg_to_rad(-28.0)
var yaw: float = deg_to_rad(-35.0)
var looking := false
var mobile_move := Vector2.ZERO
var mobile_boost := false
var terrain_data: Object
var terrain_node: Node3D
@export var eye_height := 1.7
@export var terrain_follow_rate := 12.0

@onready var head: Node3D = $Head
@onready var cam: Camera3D = $Head/Camera3D

func _ready() -> void:
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
    yaw = rotation.y
    pitch = head.rotation.x
    _find_terrain_data()
    var controls: Node = get_node_or_null("../MobileControls")
    if controls:
        controls.move_changed.connect(_on_mobile_move)
        controls.look_delta.connect(_on_mobile_look)
        controls.boost_changed.connect(_on_mobile_boost)

func _on_mobile_move(v: Vector2) -> void:
    mobile_move = v

func _on_mobile_look(d: Vector2) -> void:
    yaw -= d.x * touch_sensitivity
    pitch -= d.y * touch_sensitivity
    pitch = clamp(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
    rotation.y = yaw
    head.rotation.x = pitch

func _on_mobile_boost(active: bool) -> void:
    mobile_boost = active

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_RIGHT:
            looking = event.pressed
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE)
    elif event is InputEventMouseMotion and looking:
        yaw -= event.relative.x * mouse_sensitivity
        pitch -= event.relative.y * mouse_sensitivity
        pitch = clamp(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
        rotation.y = yaw
        head.rotation.x = pitch
    elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        looking = false
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
    var input_vec: Vector2 = mobile_move
    if input_vec.length() < 0.05:
        input_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

    # Mobile joystick Y points down, while Godot's forward input is negative Z.
    var dir_local: Vector3 = Vector3(input_vec.x, 0.0, input_vec.y)
    var dir_raw: Vector3 = transform.basis * dir_local
    dir_raw.y = 0.0
    var dir: Vector3 = Vector3.ZERO
    if dir_raw.is_finite() and dir_raw.length_squared() > 0.0001:
        dir = dir_raw.normalized()
    var sprinting := mobile_boost or Input.is_key_pressed(KEY_SHIFT)
    var current_speed: float = speed * (boost if sprinting else 1.0)
    # Publish input-derived locomotion state for animation. This project moves by
    # position (not velocity/move_and_slide), so velocity is not a reliable signal.
    set_meta("locomotion_moving", dir != Vector3.ZERO)
    set_meta("locomotion_sprinting", sprinting and dir != Vector3.ZERO)
    set_meta("locomotion_direction", dir)
    if dir != Vector3.ZERO:
        global_position += dir * current_speed * delta

    # Keep terrain-following independent from camera pitch and movement direction.
    # Terrain3D height queries use the same world X/Z coordinates as SimpleRoads.
    _follow_terrain(delta)



func _find_terrain_data() -> void:
    var terrain := get_tree().current_scene.find_child("Terrain3D_HEIGHTMAP_2000x2000", true, false)
    if terrain != null:
        terrain_node = terrain as Node3D
        terrain_data = terrain.get("data") as Object

func _follow_terrain(delta: float) -> void:
    if terrain_data == null:
        _find_terrain_data()
    if terrain_data == null or not terrain_data.has_method("get_height"):
        return
    var h_variant: Variant = terrain_data.call("get_height", Vector3(global_position.x, 0.0, global_position.z))
    if not (h_variant is float or h_variant is int):
        return
    var ground_y := float(h_variant)
    if is_nan(ground_y) or is_inf(ground_y):
        return
    var target_y := ground_y + eye_height
    global_position.y = lerpf(global_position.y, target_y, clampf(terrain_follow_rate * delta, 0.0, 1.0))
