extends CanvasLayer
## Runtime performance HUD for profiling; does not alter gameplay systems.

@onready var label: Label = $Panel/Label
var fps_history: Array[float] = []
const HISTORY_SIZE: int = 60
var refresh_accumulator := 0.0
const REFRESH_INTERVAL := 0.2

func _ready() -> void:
	layer = 120
	if label:
		label.text = "Performance Monitor: avvio..."

func _process(delta: float) -> void:
	var fps := float(Performance.get_monitor(Performance.TIME_FPS))
	fps_history.append(fps)
	if fps_history.size() > HISTORY_SIZE:
		fps_history.pop_front()

	refresh_accumulator += delta
	if refresh_accumulator < REFRESH_INTERVAL:
		return
	refresh_accumulator = 0.0

	var avg_fps := 0.0
	for value in fps_history:
		avg_fps += value
	if not fps_history.is_empty():
		avg_fps /= float(fps_history.size())

	var frame_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var physics_ms := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var triangles := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var visible_objects := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var static_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	var texture_mb := float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0
	var buffer_mb := float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0
	var active_physics := int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))

	label.text = (
		"PERFORMANCE — LIVE\n"
		+ "FPS: %.1f | media 60 frame: %.1f\n" % [fps, avg_fps]
		+ "Frame process: %.2f ms\n" % frame_ms
		+ "Draw calls: %d\n" % draw_calls
		+ "Primitive/triangoli: %d\n" % triangles
		+ "Nodi scena: %d\n" % nodes
		+ "Oggetti renderizzati: %d\n" % visible_objects
		+ "Memoria statica: %.1f MB\n" % static_mb
		+ "Memoria texture: %.1f MB\n" % texture_mb
		+ "Memoria buffer: %.1f MB\n" % buffer_mb
		+ "Fisica 3D attiva: %d\n" % active_physics
		+ "Process time: %.2f ms\n" % frame_ms
		+ "Physics time: %.2f ms" % physics_ms
	)
