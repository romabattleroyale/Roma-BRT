extends SceneTree

const REQUIRED_CLIPS: Array[StringName] = [
    &"Idle",
    &"Jog_Fwd",
    &"Sprint",
    &"Crouch_Idle",
    &"Crouch_Fwd",
]

func _initialize() -> void:
    call_deferred("_run_checks")

func _run_checks() -> void:
    var character_path := "res://assets/characters/Superhero_Male_FullBody.gltf"
    var animation_path := "res://assets/animations/UAL1_Standard.glb"
    var failed := false

    for path in [character_path, animation_path]:
        if not FileAccess.file_exists(path):
            push_error("CHARACTER ANIMATION CHECK: missing file: " + path)
            failed = true
    if failed:
        quit(1)
        return

    var character_resource := load(character_path)
    var animation_resource := load(animation_path)
    if not (character_resource is PackedScene):
        push_error("CHARACTER ANIMATION CHECK: character GLTF did not import as PackedScene")
        quit(1)
        return
    if not (animation_resource is PackedScene):
        push_error("CHARACTER ANIMATION CHECK: UAL GLB did not import as PackedScene")
        quit(1)
        return

    var character := (character_resource as PackedScene).instantiate() as Node3D
    var target_skeleton := _find_skeleton(character)
    if target_skeleton == null:
        push_error("CHARACTER ANIMATION CHECK: character has no Skeleton3D")
        character.free()
        quit(1)
        return
    print("CHARACTER ANIMATION CHECK: target skeleton bones=", target_skeleton.get_bone_count())

    var source_root := (animation_resource as PackedScene).instantiate()
    var source_player := _find_animation_player(source_root)
    if source_player == null:
        push_error("CHARACTER ANIMATION CHECK: UAL has no AnimationPlayer")
        source_root.free()
        character.free()
        quit(1)
        return

    var target_player := AnimationPlayer.new()
    target_player.name = "AnimationPlayer"
    character.add_child(target_player)
    var library := AnimationLibrary.new()
    var add_library_error := target_player.add_animation_library(&"", library)
    if add_library_error != OK:
        push_error("CHARACTER ANIMATION CHECK: cannot attach AnimationLibrary, error=" + str(add_library_error))
        source_root.free()
        character.free()
        quit(1)
        return

    var remapped_count := 0
    var target_skeleton_path := String(target_player.get_path_to(target_skeleton))
    for clip in REQUIRED_CLIPS:
        if not source_player.has_animation(clip):
            push_error("CHARACTER ANIMATION CHECK: source clip missing: " + String(clip))
            failed = true
            continue
        var animation := source_player.get_animation(clip).duplicate(true) as Animation
        var mapped_tracks := 0
        var transform_tracks := 0
        for track_index in range(animation.get_track_count()):
            var track_type := animation.track_get_type(track_index)
            if track_type != Animation.TYPE_POSITION_3D and track_type != Animation.TYPE_ROTATION_3D and track_type != Animation.TYPE_SCALE_3D:
                continue
            transform_tracks += 1
            var old_path := animation.track_get_path(track_index)
            var bone_name := String(old_path.get_concatenated_subnames())
            if bone_name.is_empty() or target_skeleton.find_bone(bone_name) < 0:
                continue
            animation.track_set_path(track_index, NodePath(target_skeleton_path + ":" + bone_name))
            mapped_tracks += 1

        if mapped_tracks == 0:
            push_error("CHARACTER ANIMATION CHECK: no bone tracks mapped for " + String(clip) +
                "; transform tracks=" + str(transform_tracks))
            failed = true
            continue
        var add_error := library.add_animation(StringName(clip), animation)
        if add_error != OK:
            push_error("CHARACTER ANIMATION CHECK: failed to add remapped clip " + String(clip) +
                "; error=" + str(add_error))
            failed = true
            continue
        remapped_count += 1
        print("CHARACTER ANIMATION CHECK: ", clip, " mapped ", mapped_tracks,
            "/", transform_tracks, " transform tracks to target skeleton")

    source_root.free()
    if failed or remapped_count != REQUIRED_CLIPS.size():
        character.free()
        quit(1)
        return

    # Exercise the same AnimationPlayer path used at runtime and ensure playback starts.
    for clip in [&"Idle", &"Jog_Fwd", &"Sprint", &"Crouch_Idle", &"Crouch_Fwd"]:
        target_player.play(clip)
        await process_frame
        if not target_player.is_playing() or target_player.current_animation != clip:
            push_error("CHARACTER ANIMATION CHECK: playback did not start for " + String(clip))
            failed = true
        else:
            print("CHARACTER ANIMATION CHECK: playback started: ", clip)

    character.free()

    # Exercise the actual runtime loader and its five metadata-driven locomotion states.
    var runtime_root := Node3D.new()
    root.add_child(runtime_root)
    runtime_root.set_meta("locomotion_moving", false)
    runtime_root.set_meta("locomotion_sprinting", false)
    runtime_root.set_meta("locomotion_crouching", false)
    var visual_loader := Node3D.new()
    visual_loader.name = "CharacterVisual"
    visual_loader.set_script(load("res://character_visual_loader.gd"))
    runtime_root.add_child(visual_loader)
    await process_frame
    await physics_frame
    await process_frame
    var runtime_player := _find_animation_player(visual_loader)
    if runtime_player == null:
        push_error("CHARACTER ANIMATION CHECK: runtime loader did not create an AnimationPlayer")
        failed = true
    else:
        var states := [
            {"name": "idle", "moving": false, "sprinting": false, "crouching": false, "clip": &"Idle_Loop"},
            {"name": "jog", "moving": true, "sprinting": false, "crouching": false, "clip": &"Jog_Fwd_Loop"},
            {"name": "sprint", "moving": true, "sprinting": true, "crouching": false, "clip": &"Sprint_Loop"},
            {"name": "crouch idle", "moving": false, "sprinting": false, "crouching": true, "clip": &"Crouch_Idle_Loop"},
            {"name": "crouch move", "moving": true, "sprinting": false, "crouching": true, "clip": &"Crouch_Fwd_Loop"},
        ]
        for state in states:
            runtime_root.set_meta("locomotion_moving", state.moving)
            runtime_root.set_meta("locomotion_sprinting", state.sprinting)
            runtime_root.set_meta("locomotion_crouching", state.crouching)
            await physics_frame
            await process_frame
            if runtime_player.current_animation != state.clip:
                push_error("CHARACTER ANIMATION CHECK: runtime state '" + state.name + "' selected " + String(runtime_player.current_animation) + ", expected " + String(state.clip))
                failed = true
            else:
                print("CHARACTER ANIMATION CHECK: runtime state ", state.name, " -> ", state.clip)
    runtime_root.queue_free()
    await process_frame

    if failed:
        push_error("CHARACTER ANIMATION CHECK: FAIL")
        quit(1)
    else:
        print("CHARACTER ANIMATION CHECK: PASS — all required clips mapped to target skeleton and playback started")
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
