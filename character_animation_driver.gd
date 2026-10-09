extends Node
## Animation state driver for Roma Battle Royale.
## Reads metadata from viewer.gd because locomotion currently uses global_position,
## not CharacterBody3D.velocity/move_and_slide. Assign AnimationPlayer path after
## the character and animation GLB are imported into the scene.

@export var animation_player_path: NodePath = NodePath("AnimationPlayer")
@export var locomotion_source_path: NodePath = NodePath("..")
@export var idle_clip: StringName = &"Idle_Loop"
@export var jog_clip: StringName = &"Jog_Fwd_Loop"
@export var sprint_clip: StringName = &"Sprint_Loop"
@export var crouch_idle_clip: StringName = &"Crouch_Idle_Loop"
@export var crouch_move_clip: StringName = &"Crouch_Fwd_Loop"
@export var blend_seconds: float = 0.18

var _player: AnimationPlayer
var _source: Node
var _current_clip: StringName = &""

func _ready() -> void:
    _player = get_node_or_null(animation_player_path) as AnimationPlayer
    _source = get_node_or_null(locomotion_source_path)
    if _player == null:
        push_warning("CharacterAnimationDriver: AnimationPlayer not found. Assign animation_player_path after importing the character and animation library.")
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
    var crouching := bool(_source.get_meta("locomotion_crouching", false))

    if crouching:
        _play_if_available(crouch_move_clip if moving else crouch_idle_clip)
    elif not moving:
        _play_if_available(idle_clip)
    elif sprinting:
        _play_if_available(sprint_clip)
    else:
        _play_if_available(jog_clip)

func _play_if_available(clip: StringName) -> void:
    if clip == &"" or _player == null or not _player.has_animation(clip):
        return
    if _current_clip == clip and _player.is_playing():
        return
    _current_clip = clip
    _player.play(clip, blend_seconds)
