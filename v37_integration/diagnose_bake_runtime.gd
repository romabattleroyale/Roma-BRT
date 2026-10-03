extends SceneTree

func _init() -> void:
	print("=== ROMA BRT TERRAIN RUNTIME DIAGNOSTIC ===")
	var scene_path := "res://main.tscn"
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("DIAG: cannot load main.tscn")
		quit(1)
		return
	var root := packed.instantiate()
	root.name = "DIAG_MAIN"
	root.process_mode = Node.PROCESS_MODE_INHERIT
	root.set_process(true)
	root.set_physics_process(true)
	get_root().add_child(root)
	print("DIAG: main instantiated root=", root.name)
	await process_frame
	await process_frame
	var terrain_nodes := []
	_collect_terrain(root, terrain_nodes)
	print("DIAG: Terrain3D count=", terrain_nodes.size())
	for node in terrain_nodes:
		print("DIAG: Terrain3D node=", node.get_path(), " data=", str(node.get("data")))
	var bootstrap := root.get_node_or_null("TerrainBootstrap")
	print("DIAG: TerrainBootstrap=", str(bootstrap))
	if terrain_nodes.is_empty():
		push_error("DIAG: no Terrain3D exists after main.tscn runtime initialization")
		root.queue_free()
		quit(2)
		return
	print("DIAG: Terrain3D runtime discovery OK")
	root.queue_free()
	quit(0)

func _collect_terrain(node: Node, out: Array) -> void:
	if node.get_class() == "Terrain3D":
		out.append(node)
	for child in node.get_children():
		_collect_terrain(child, out)
