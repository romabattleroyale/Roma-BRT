extends Node3D
## Loads the player mesh and copies locomotion clips from the UAL GLB.
## Does not alter Viewer movement, camera, terrain following, or Android controls.

@export_file("*.gltf", "*.glb", "*.tscn") var character_scene_path := "res://assets/characters/Superhero_Male_FullBody.gltf"
@export_file("*.glb", "*.gltf") var animation_library_path := "res://assets/animations/UAL1_Standard.glb"
@export var visual_scale := Vector3.ONE
@export var visual_rotation_degrees := Vector3(0.0, 180.0, 0.0)
@export var visual_offset := Vector3(0.0, -1.7, 0.0)
@export var blend_seconds := 0.18

const CLIPS: Array[StringName] = [&"Idle_Loop", &"Jog_Fwd_Loop", &"Sprint_Loop", &"Crouch_Idle_Loop", &"Crouch_Fwd_Loop"]
var character_instance: Node3D
var _animation_player: AnimationPlayer
var _current_clip: StringName = &""

func _ready() -> void:
    if not ResourceLoader.exists(character_scene_path):
        push_warning("CharacterVisualLoader: character asset missing: " + character_scene_path)
        return
    var packed := load(character_scene_path) as PackedScene
    if packed == null:
        push_warning("CharacterVisualLoader: character scene could not be loaded.")
        return
    var instance := packed.instantiate()
    if not (instance is Node3D):
        instance.queue_free()
        push_warning("CharacterVisualLoader: character root must be Node3D.")
        return

    character_instance = instance as Node3D
    add_child(character_instance)
    character_instance.position = visual_offset
    character_instance.rotation_degrees = visual_rotation_degrees
    character_instance.scale = visual_scale
    # The character GLTF may be a static skinned mesh without its own AnimationPlayer.
    # Create one so the external UAL animation library can be attached to this character.
    _animation_player = _find_animation_player(character_instance)
    if _animation_player == null:
        _animation_player = AnimationPlayer.new()
        _animation_player.name = "AnimationPlayer"
        character_instance.add_child(_animation_player)
    _import_animation_clips()
    _play_clip(&"Idle_Loop")

func _physics_process(_delta: float) -> void:
    if _animation_player == null:
        return
    var source := get_parent()
    if source == null:
        return
    var moving := bool(source.get_meta("locomotion_moving", false))
    var sprinting := bool(source.get_meta("locomotion_sprinting", false))
    var crouching := bool(source.get_meta("locomotion_crouching", false))
    var clip: StringName
    if crouching:
        clip = &"Crouch_Fwd_Loop" if moving else &"Crouch_Idle_Loop"
    elif not moving:
        clip = &"Idle_Loop"
    elif sprinting:
        clip = &"Sprint_Loop"
    else:
        clip = &"Jog_Fwd_Loop"
    _play_clip(clip)

func _import_animation_clips() -> void:
    if not ResourceLoader.exists(animation_library_path):
        push_warning("CharacterVisualLoader: animation library missing: " + animation_library_path)
        return
    var animation_scene := load(animation_library_path) as PackedScene
    if animation_scene == null:
        push_warning("CharacterVisualLoader: animation library could not be loaded.")
        return
    var library_root := animation_scene.instantiate()
    var source_player := _find_animation_player(library_root)
    if source_player == null:
        library_root.queue_free()
        push_warning("CharacterVisualLoader: no AnimationPlayer in animation library.")
        return

    var library := _animation_player.get_animation_library(&"")
    if library == null:
        library = AnimationLibrary.new()
        if _animation_player.add_animation_library(&"", library) != OK:
            library_root.queue_free()
            push_warning("CharacterVisualLoader: could not create animation library.")
            return

    var target_skeleton := _find_skeleton(character_instance)
    if target_skeleton == null:
        library_root.queue_free()
        push_warning("CharacterVisualLoader: no Skeleton3D found in character; cannot retarget clips.")
        return

    var imported := 0
    for clip in CLIPS:
        if not source_player.has_animation(clip):
            push_warning("CharacterVisualLoader: clip missing from UAL: " + String(clip))
            continue
        var animation := source_player.get_animation(clip).duplicate(true) as Animation
        if animation == null:
            continue
        var remapped_tracks := _retarget_bone_tracks(animation, target_skeleton)
        if remapped_tracks == 0:
            push_warning("CharacterVisualLoader: clip has no remappable bone tracks: " + String(clip))
            continue
        if library.has_animation(clip):
            library.remove_animation(clip)
        if library.add_animation(clip, animation) == OK:
            imported += 1
    library_root.queue_free()
    print("CharacterVisualLoader: imported ", imported, "/", CLIPS.size(), " clips with remapped bone tracks. Confirm movement in Godot.")

func _retarget_bone_tracks(animation: Animation, target_skeleton: Skeleton3D) -> int:
    var count := 0
    var target_path := String(_animation_player.get_path_to(target_skeleton))
    for i in range(animation.get_track_count()):
        if animation.track_get_type(i) != Animation.TYPE_POSITION_3D and animation.track_get_type(i) != Animation.TYPE_ROTATION_3D and animation.track_get_type(i) != Animation.TYPE_SCALE_3D:
            continue
        var old_path := animation.track_get_path(i)
        var bone_name := String(old_path.get_concatenated_subnames())
        if bone_name.is_empty():
            continue
        # glTF skeletal animation tracks commonly encode the bone as a subname.
        # Only remap when that bone exists on the target skeleton.
        if target_skeleton.find_bone(bone_name) < 0:
            continue
        animation.track_set_path(i, NodePath(target_path + ":" + bone_name))
        count += 1
    return count

func _find_animation_player(root: Node) -> AnimationPlayer:
    if root is AnimationPlayer:
        return root as AnimationPlayer
    for child in root.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _find_skeleton(root: Node) -> Skeleton3D:
    if root is Skeleton3D:
        return root as Skeleton3D
    for child in root.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _play_clip(clip: StringName) -> void:
    if _animation_player == null or not _animation_player.has_animation(clip):
        return
    if _current_clip == clip and _animation_player.is_playing():
        return
    _current_clip = clip
    _animation_player.play(clip, blend_seconds)
