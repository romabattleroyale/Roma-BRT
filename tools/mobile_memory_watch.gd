extends Node
## Lightweight Android memory watcher.
## Uses a Timer instead of scanning the scene tree every frame.
## Does not inspect buildings or allocate per-node resource dictionaries.

const POLL_INTERVAL_SECONDS := 2.0

var _timer: Timer

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_process(false)
    set_physics_process(false)
    _timer = Timer.new()
    _timer.name = "MemoryPollTimer"
    _timer.wait_time = POLL_INTERVAL_SECONDS
    _timer.one_shot = false
    _timer.autostart = true
    _timer.timeout.connect(_check_memory)
    add_child(_timer)
    print("[MEM] Android memory watcher: TIMER MODE interval=%.1fs" % POLL_INTERVAL_SECONDS)

func _check_memory() -> void:
    var memory_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
    print("[MEM] static=%.2f MB" % memory_mb)
