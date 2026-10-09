extends Node
## Bridges existing Viewer movement with the new touch joystick and camera pivot.
@export var viewer_path: NodePath = ^"../Viewer"
@export var joystick_path: NodePath = ^"../HUD/TouchHUD/VirtualJoystick"
@export var pivot_path: NodePath = ^"../Viewer/CameraPivot"
@export var buttons_path: NodePath = ^"../HUD/TouchHUD/TouchButtons"
@export var sprint_hold_seconds := 2.0
var viewer: CharacterBody3D
var joystick: Control
var pivot: Node3D
var _sprint_time := 0.0
var _auto_sprint := false
func _ready() -> void:
    viewer = get_node_or_null(viewer_path) as CharacterBody3D
    joystick = get_node_or_null(joystick_path) as Control
    pivot = get_node_or_null(pivot_path) as Node3D
    if joystick and joystick.has_signal("changed"): joystick.changed.connect(_on_joystick_changed)
    var buttons := get_node_or_null(buttons_path)
    if buttons and buttons.has_signal("action_pressed"): buttons.action_pressed.connect(_on_action)
func _process(delta: float) -> void:
    if joystick and "output" in joystick:
        var v: Vector2 = joystick.get("output")
        if v.length() > 0.98: _sprint_time += delta
        else: _sprint_time = 0.0
        _auto_sprint = _sprint_time >= sprint_hold_seconds
    if viewer:
        viewer.set_meta("locomotion_sprinting", _auto_sprint or Input.is_key_pressed(KEY_SHIFT))
func _on_joystick_changed(value: Vector2) -> void:
    if viewer and viewer.has_method("_on_mobile_move"): viewer._on_mobile_move(Vector2(value.x, -value.y))
func _on_action(action: StringName, pressed: bool) -> void:
    if action == &"aim" and pivot and pivot.has_method("set_aiming"): pivot.set_aiming(pressed)
    if action == &"shoot" and pressed and pivot and pivot.has_method("add_shot_recoil"): pivot.add_shot_recoil()
    if action == &"sprint" and viewer: viewer.set_meta("locomotion_sprinting", pressed)
    if action == &"crouch" and viewer: viewer.set_meta("locomotion_crouching", pressed)
    if action == &"jump" and viewer: viewer.set_meta("jump_requested", pressed)
