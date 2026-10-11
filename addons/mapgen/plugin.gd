@tool
extends EditorPlugin

const DockScene := preload("res://addons/mapgen/ui/mapgen_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	add_custom_type("MapGenerator", "Node3D",
		preload("res://addons/mapgen/map_generator.gd"), null)

	_dock = DockScene.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, _dock)

	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	call_deferred("_bind_generator_in_edited_scene")


func _exit_tree() -> void:
	var sel := EditorInterface.get_selection()
	if sel.selection_changed.is_connected(_on_selection_changed):
		sel.selection_changed.disconnect(_on_selection_changed)
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	remove_custom_type("MapGenerator")


func _bind_generator_in_edited_scene() -> void:
	if _dock == null:
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MapGenerator:
			_dock.set_generator(node)
			return
		for child in node.get_children():
			pending.append(child)


func _on_selection_changed() -> void:
	if _dock == null:
		return
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is MapGenerator:
			_dock.set_generator(node)
			return
	_dock.set_generator(null)
