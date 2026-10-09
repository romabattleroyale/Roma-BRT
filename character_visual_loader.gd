extends Node3D
## Optional visual loader for the player character.
## Add as a child of Viewer after placing the character GLB at the exported path.
## It intentionally does not change Viewer, Head, Camera3D, terrain height or controls.

@export_file("*.glb", "*.gltf", "*.tscn") var character_scene_path: String = "res://assets/characters/Superhero_Male_FullBody.glb"
@export var visual_scale: Vector3 = Vector3.ONE
@export var visual_rotation_degrees: Vector3 = Vector3(0.0, 180.0, 0.0)
@export var visual_offset: Vector3 = Vector3(0.0, -1.7, 0.0)
@export var hide_when_asset_missing: bool = true

var character_instance: Node3D

func _ready() -> void:
    if character_scene_path.is_empty() or not ResourceLoader.exists(character_scene_path):
        if hide_when_asset_missing:
            visible = false
        push_warning("CharacterVisualLoader: character asset is not in the project yet. Expected: " + character_scene_path)
        return

    var packed := load(character_scene_path) as PackedScene
    if packed == null:
        push_warning("CharacterVisualLoader: could not load character scene: " + character_scene_path)
        return

    var instance := packed.instantiate()
    if not (instance is Node3D):
        instance.queue_free()
        push_warning("CharacterVisualLoader: loaded asset root is not Node3D.")
        return

    character_instance = instance as Node3D
    add_child(character_instance)
    character_instance.position = visual_offset
    character_instance.rotation_degrees = visual_rotation_degrees
    character_instance.scale = visual_scale
    _report_animation_nodes(character_instance)

func _report_animation_nodes(root: Node) -> void:
    var animation_player := root.find_child("*", true, false) as AnimationPlayer
    if animation_player != null:
        var clips := animation_player.get_animation_list()
        print("CharacterVisualLoader: AnimationPlayer found with ", clips.size(), " animation(s).")
    else:
        print("CharacterVisualLoader: model loaded; no AnimationPlayer embedded in the character asset.")
