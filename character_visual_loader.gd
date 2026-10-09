extends Node3D
## Loads the player mesh and imports compatible locomotion clips from the UAL GLB.
## Does not modify Viewer movement, camera, terrain following, or Android controls.

@export_file("*.glb", "*.gltf", "*.tscn") var character_scene_path: String = "res://assets/characters/Superhero_Male_FullBody.gltf"
@export_file("*.glb", "*.gltf") var animation_library_path: String = "res://assets/animations/UAL1_Standard.glb"
@export var visual_scale: Vector3 = Vector3.ONE
@export var visual_rotation_degrees: Vector3 = Vector3(0.0, 180.0, 0.0)
@export var visual_offset: Vector3 = Vector3(0.0, -1.7, 0.0)
@export var blend_seconds: float = 0.18

const CLIPS := [&"Idle_Loop", &"Jog_Fwd_Loop", &"Sprint_Loop", &"Crouch_Idle_Loop", &"Crouch_Fwd_Loop"]
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

    _animation_player = _find_animation_player(character_instance)
    if _animation_player == null:
        push_warning("CharacterVisualLoader: character has no AnimationPlayer; cannot play locomotion.")
        return
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
        var add_error := _animation_player.add_animation_library(&"", library)
        if add_error != OK:
            library_root.queue_free()
            push_warning("CharacterVisualLoader: could not create animation library on character.")
            return

    var imported := 0
    for clip in CLIPS:
        if not source_player.has_animation(clip):
            push_warning("CharacterVisualLoader: clip missing from UAL: " + String(clip))
            continue
        var animation := source_player.get_animation(clip).duplicate(true) as Animation
        if animation == null:
            continue
        if library.has_animation(clip):
            library.remove_animation(clip)
        var error := library.add_animation(clip, animation)
        if error == OK:
            imported += 1
        else:
            push_warning("CharacterVisualLoader: failed to import clip " + String(clip))
    library_root.queue_free()
    print("CharacterVisualLoader: imported ", imported, "/", CLIPS.size(), " locomotion clips. Verify retargeted track paths in Godot.")

func _find_animation_player(root: Node) -> AnimationPlayer:
    if root is AnimationPlayer:
        return root as AnimationPlayer
    for child in root.get_children():
        var found := _find_animation_player(child)
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
