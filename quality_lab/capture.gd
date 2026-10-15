extends SceneTree

func _initialize() -> void:
	call_deferred("_capture_scene")

func _capture_scene() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		push_error("Cannot load res://main.tscn")
		quit(2)
		return
	root.add_child(packed.instantiate())
	for frame in range(3):
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	if image.is_empty():
		push_error("Viewport returned an empty image")
		quit(3)
		return
	var workspace := OS.get_environment("GITHUB_WORKSPACE")
	var output_dir := workspace.path_join("artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("colosseo_preview.png")
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save preview PNG: %s" % error)
		quit(4)
		return
	print("Rendered preview saved to: ", output_path, " (", image.get_width(), "x", image.get_height(), ")")
	quit()
