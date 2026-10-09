extends Node3D
## Fortnite-inspired third-person camera. Attach to Player/CameraPivot.
@export var base_fov := 80.0
@export var ads_fov := 65.0
@export var ads_duration := 0.15
@export var mouse_sensitivity := 0.0025
@export var touch_sensitivity := 0.004
@export var ads_sensitivity_scale := 0.4
@export var scope_sensitivity_scale := 0.35
@export var min_pitch_degrees := -85.0
@export var max_pitch_degrees := 80.0
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
var yaw := 0.0
var pitch := deg_to_rad(-8.0)
var aiming := false
var scoped := false
var _fov_tween: Tween
var _noise := FastNoiseLite.new()
var _shake_time := 0.0
var _shake_duration := 0.3
var _shake_strength := 0.3
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0
var _recoil_tween: Tween
func _ready() -> void:
    position = Vector3(0.3, 1.8, 0.0)
    spring_arm.spring_length = 4.5
    spring_arm.margin = 0.2
    camera.fov = base_fov
    camera.near = 0.05
    camera.far = 4000.0
    _noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    _noise.frequency = 20.0
    yaw = rotation.y
    pitch = rotation.x
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        apply_look(event.relative, mouse_sensitivity * _sensitivity_scale())
    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_RIGHT:
            set_aiming(event.pressed)
        elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
func apply_look(delta: Vector2, sensitivity: float = -1.0) -> void:
    var sens := touch_sensitivity if sensitivity < 0.0 else sensitivity
    yaw -= delta.x * sens
    pitch -= delta.y * sens
    pitch = clampf(pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
    rotation.y = yaw
    rotation.x = pitch
func set_aiming(active: bool, use_scope: bool = false) -> void:
    aiming = active
    scoped = use_scope and active
    if _fov_tween and _fov_tween.is_running(): _fov_tween.kill()
    _fov_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
    _fov_tween.tween_property(camera, "fov", ads_fov if active else base_fov, ads_duration)
func _sensitivity_scale() -> float:
    if scoped: return scope_sensitivity_scale
    if aiming: return ads_sensitivity_scale
    return 1.0
func add_shot_recoil() -> void:
    _recoil_pitch += deg_to_rad(0.5)
    _recoil_yaw += deg_to_rad(randf_range(-0.2, 0.2))
    if _recoil_tween and _recoil_tween.is_running(): _recoil_tween.kill()
    _recoil_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
    _recoil_tween.tween_property(self, "_recoil_pitch", 0.0, 0.1)
    _recoil_tween.tween_property(self, "_recoil_yaw", 0.0, 0.1)
func impact_shake() -> void:
    _shake_time = _shake_duration
func _process(delta: float) -> void:
    var _profile_start_usec := Time.get_ticks_usec()
    var shake := Vector2.ZERO
    if _shake_time > 0.0:
        _shake_time = maxf(0.0, _shake_time - delta)
        var t := Time.get_ticks_msec() / 1000.0
        shake = Vector2(_noise.get_noise_1d(t * 1000.0), _noise.get_noise_1d(t * 1000.0 + 47.0)) * deg_to_rad(_shake_strength) * (_shake_time / _shake_duration)
    rotation.y = yaw + _recoil_yaw + shake.x
    rotation.x = clampf(pitch + _recoil_pitch + shake.y, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))

    var _profiler := get_node_or_null("/root/ScriptProfiler")
    if _profiler != null:
        _profiler.record_process("player_camera.gd", Time.get_ticks_usec() - _profile_start_usec)
