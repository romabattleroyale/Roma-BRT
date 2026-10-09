extends SceneTree

func _initialize() -> void:
    call_deferred("_run_checks")

func _run_checks() -> void:
    var character_path := "res://assets/characters/Superhero_Male_FullBody.gltf"
    var animation_path := "res://assets/animations/UAL1_Standard.glb"
    var required_clips: Array[StringName] = [
        &"Idle_Loop",
        &"Jog_Fwd_Loop",
        &"Sprint_Loop",
        &"Crouch_Idle_Loop",
        &"Crouch_Fwd_Loop",
    ]

    var failed := false
    for path in [character_path, animation_path]:
        if not FileAccess.file_exists(path):
            push_error("CHARACTER ASSET CHECK: missing file: " + path)
            failed = true
    if failed:
        quit(1)
        return

    var character_resource := load(character_path)
    if not (character_resource is PackedScene):
        push_error("CHARACTER ASSET CHECK: GLTF did not import as PackedScene")
        quit(1)
        return
    var character := (character_resource as PackedScene).instantiate()
    var skeleton := _find_skeleton(character)
    if skeleton == null:
        push_error("CHARACTER ASSET CHECK: character has no Skeleton3D")
        character.free()
        quit(1)
        return
    print("CHARACTER ASSET CHECK: character imported; bones=", skeleton.get_bone_count())

    var animation_resource := load(animation_path)
    if not (animation_resource is PackedScene):
        push_error("CHARACTER ASSET CHECK: UAL GLB did not import as PackedScene")
        character.free()
        quit(1)
        return
    var animation_root := (animation_resource as PackedScene).instantiate()
    var player := _find_animation_player(animation_root)
    if player == null:
        push_error("CHARACTER ASSET CHECK: UAL GLB has no AnimationPlayer")
        animation_root.free()
        character.free()
        quit(1)
        return

    for clip in required_clips:
        if not player.has_animation(clip):
            push_error("CHARACTER ASSET CHECK: missing clip " + String(clip))
            failed = true
        else:
            print("CHARACTER ASSET CHECK: clip OK: ", clip)

    animation_root.free()
    character.free()
    if failed:
        quit(1)
    else:
        print("CHARACTER ASSET CHECK: PASS")
        quit(0)

func _find_skeleton(root: Node) -> Skeleton3D:
    if root is Skeleton3D:
        return root as Skeleton3D
    for child in root.get_children():
        var result := _find_skeleton(child)
        if result != null:
            return result
    return null

func _find_animation_player(root: Node) -> AnimationPlayer:
    if root is AnimationPlayer:
        return root as AnimationPlayer
    for child in root.get_children():
        var result := _find_animation_player(child)
        if result != null:
            return result
    return null
