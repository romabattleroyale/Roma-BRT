extends Node
## Animation state driver for a character whose movement is driven by viewer.gd.
## Reads input-derived metadata instead of CharacterBody3D.velocity, because the
## current terrain controller intentionally updates global_position directly.

@export var animation_player_path: NodePath = NodePath("AnimationPlayer")
@export var locomotion_source_path: NodePath = NodePath("..")
@export var idle_clip: StringName = &"Idle_Loop"
@export var jog_clip: StringName = &"Jog_Fwd_Loop"
@export var sprint_clip: StringName = &"Sprint_Loop"
@export var blend_seconds: float = 0.18

var _player: AnimationPlayer
var _source: Node
var _current_clip: StringName = &""

func _ready() -> void:
    _player = get_node_or_null(animation_player_path) as AnimationPlayer
    _source = get_node_or_null(locomotion_source_path)
    if _player == null:
        push_warning("CharacterAnimationDriver: AnimationPlayer not found. Set animation_player_path to the imported character's AnimationPlayer.")
        set_physics_process(false)
        return
    if _source == null:
        push_warning("CharacterAnimationDriver: locomotion source not found.")
        set_physics_process(false)
        return
    _play_if_available(idle_clip)

func _physics_process(_delta: float) -> void:
    if _player == null or _source == null:
        return
    var moving := bool(_source.get_meta("locomotion_moving", false))
    var sprinting := bool(_source.get_meta("locomotion_sprinting", false))
    if not moving:
        _play_if_available(idle_clip, 1.0)
    elif sprinting:
        _play_if_available(sprint_clip, 1.0)
    else:
        _play_if_available(jog_clip, 1.0)

func _play_if_available(clip: StringName, speed_scale: float = 1.0) -> void:
    if clip == &"" or _player == null or not _player.has_animation(clip):
        return
    if _current_clip == clip and _player.is_playing():
        _player.speed_scale = speed_scale
        return
    _current_clip = clip
    _player.speed_scale = speed_scale
    _player.play(clip, blend_seconds)
