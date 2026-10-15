extends SceneTree

func _initialize() -> void:
	call_deferred("_capture_scene")

func _capture_scene() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		push_error("Cannot load res://main.tscn")
		quit(2)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for frame in range(3):
		await RenderingServer.frame_post_draw
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	scene.add_child(camera)
	camera.current = true
	camera.fov = 56.0
	for child in scene.get_children():
		if child is CanvasLayer:
			child.visible = false
	var workspace := OS.get_environment("GITHUB_WORKSPACE")
	var output_dir := workspace.path_join("artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	camera.current = true
	camera.global_position = Vector3(20, 9, 52)
	camera.look_at(Vector3(0, 12, 0), Vector3.UP)
	await RenderingServer.frame_post_draw
	if not _save_view(output_dir.path_join("colosseo_exterior.png")):
		quit(4)
		return
	camera.global_position = Vector3(0, 8, 0)
	camera.look_at(Vector3(0, 10, -18), Vector3.UP)
	await RenderingServer.frame_post_draw
	if not _save_view(output_dir.path_join("colosseo_interior.png")):
		quit(5)
		return
	camera.global_position = Vector3(0, 68, 82)
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	await RenderingServer.frame_post_draw
	if not _save_view(output_dir.path_join("roma_district_overview.png")):
		quit(6)
		return
	print("Rendered exterior, interior and district overview previews.")
	quit()

func _save_view(output_path: String) -> bool:
	var image := root.get_viewport().get_texture().get_image()
	if image.is_empty():
		push_error("Viewport returned an empty image")
		return false
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save preview PNG: %s" % error)
		return false
	print("Saved ", output_path, " (", image.get_width(), "x", image.get_height(), ")")
	return true
