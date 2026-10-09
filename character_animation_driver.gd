extends Node
## Animation driver for Roma Battle Royale's stylized third-person character.
## Attach as a child of the character root after importing the character + UAL1 animation GLB.
## Does not control the camera or move the CharacterBody3D.

@export var animation_player_path: NodePath = NodePath("AnimationPlayer")
@export var locomotion_source_path: NodePath = NodePath("..")
@export var idle_clip: StringName = &"Idle_Loop"
@export var jog_clip: StringName = &"Jog_Fwd_Loop"
@export var crouch_idle_clip: StringName = &"Crouch_Idle_Loop"
@export var crouch_move_clip: StringName = &"Crouch_Fwd_Loop"
@export var jump_start_clip: StringName = &"Jump_Start"
@export var jump_loop_clip: StringName = &"Jump_Loop"
@export var jump_land_clip: StringName = &"Jump_Land"
@export var speed_threshold: float = 0.15
@export var sprint_multiplier: float = 1.35
@export var blend_seconds: float = 0.18

var _player: AnimationPlayer
var _body: CharacterBody3D
var _last_grounded := true
var _was_moving := false
var _current_clip: StringName = &""
var _land_pending := false

func _ready() -> void:
    _player = get_node_or_null(animation_player_path) as AnimationPlayer
    _body = get_node_or_null(locomotion_source_path) as CharacterBody3D
    if _player == null:
        push_warning("CharacterAnimationDriver: AnimationPlayer not found; assign animation_player_path after importing the character.")
        set_physics_process(false)
        return
    if _body == null:
        push_warning("CharacterAnimationDriver: CharacterBody3D not found; assign locomotion_source_path.")
        set_physics_process(false)
        return
    _play_if_available(idle_clip)

func _physics_process(_delta: float) -> void:
    if _player == null or _body == null:
        return

    var planar_speed := Vector2(_body.velocity.x, _body.velocity.z).length()
    var moving := planar_speed > speed_threshold
    var grounded := _body.is_on_floor()

    if not grounded:
        if _last_grounded:
            _play_if_available(jump_start_clip)
        elif _current_clip != jump_start_clip and _current_clip != jump_loop_clip:
            _play_if_available(jump_loop_clip)
    elif not _last_grounded:
        _land_pending = true
        _play_if_available(jump_land_clip)

    if grounded:
        if _land_pending and _current_clip == jump_land_clip and _player.is_playing():
            pass
        else:
            _land_pending = false
            if moving:
                _play_if_available(crouch_move_clip if Input.is_key_pressed(KEY_CTRL) else jog_clip, _playback_scale(planar_speed))
            else:
                _play_if_available(crouch_idle_clip if Input.is_key_pressed(KEY_CTRL) else idle_clip)

    _last_grounded = grounded
    _was_moving = moving

func _playback_scale(planar_speed: float) -> float:
    if _body == null:
        return 1.0
    var base_speed := maxf(_body.velocity.length(), 0.01)
    return clampf(planar_speed / maxf(base_speed, 0.01), 0.85, sprint_multiplier)

func _play_if_available(clip: StringName, speed_scale: float = 1.0) -> void:
    if clip == &"" or _player == null or not _player.has_animation(clip):
        return
    if _current_clip == clip and _player.is_playing():
        _player.speed_scale = speed_scale
        return
    _current_clip = clip
    _player.speed_scale = speed_scale
    _player.play(clip, blend_seconds)
