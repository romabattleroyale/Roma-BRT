@tool
extends VBoxContainer
## Editor dock: the feature toggles plus seed, wired to whichever
## MapGenerator is currently selected in the scene tree.

signal regenerate_requested()

const FEATURES := [
	["mountain_enabled", "Mountain"],
	["canyon_enabled", "Canyon"],
	["lake_enabled", "Lake"],
	["vegetation_enabled", "Vegetation"],
	["snow_enabled", "Snow"],
	["fog_enabled", "Fog"],
	["waterfall_enabled", "Waterfalls"],
]

var generator: MapGenerator

var _status: Label
var _seed_field: SpinBox
var _size_field: SpinBox
var _res_field: SpinBox
var _checks: Dictionary = {}
var _auto: CheckBox
var _updating := false


func _ready() -> void:
	name = "MapGen"
	add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "Map Generator"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Select a MapGenerator node."
	add_child(_status)

	add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)

	_seed_field = _add_number(grid, "Seed", 0, 2147483647, 1)
	_size_field = _add_number(grid, "Size (m)", 64, 8192, 1)
	_res_field = _add_number(grid, "Resolution", 32, 1024, 1)

	add_child(HSeparator.new())

	var feat_label := Label.new()
	feat_label.text = "Features"
	add_child(feat_label)

	for entry in FEATURES:
		var cb := CheckBox.new()
		cb.text = entry[1]
		cb.button_pressed = true
		cb.toggled.connect(_on_feature_toggled.bind(entry[0]))
		add_child(cb)
		_checks[entry[0]] = cb

	add_child(HSeparator.new())

	_auto = CheckBox.new()
	_auto.text = "Regenerate on change"
	_auto.button_pressed = true
	add_child(_auto)

	var gen := Button.new()
	gen.text = "Generate"
	gen.pressed.connect(_generate)
	add_child(gen)

	var reseed := Button.new()
	reseed.text = "New seed + Generate"
	reseed.pressed.connect(func():
		if generator and generator.settings:
			generator.settings.seed = randi()
			_sync_from_generator()
			_generate())
	add_child(reseed)

	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(func():
		if generator:
			generator.clear_generated()
			_status.text = "Cleared.")
	add_child(clear)


func _add_number(parent: GridContainer, label: String, lo: float, hi: float, step: float) -> SpinBox:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value_changed.connect(_on_number_changed)
	parent.add_child(sb)
	return sb


func set_generator(gen: MapGenerator) -> void:
	generator = gen
	if generator == null:
		_status.text = "Select a MapGenerator node."
		return
	if generator.settings == null:
		generator.settings = MapGenSettings.new()
	_sync_from_generator()
	_status.text = "Editing: %s" % generator.name


func _sync_from_generator() -> void:
	if generator == null or generator.settings == null:
		return
	_updating = true
	var s := generator.settings
	_seed_field.value = s.seed
	_size_field.value = s.map_size
	_res_field.value = s.resolution
	for key in _checks:
		_checks[key].button_pressed = s.get(key)
	_updating = false


func _on_feature_toggled(pressed: bool, property: String) -> void:
	if _updating or generator == null or generator.settings == null:
		return
	generator.settings.set(property, pressed)
	if _auto.button_pressed:
		_generate()


func _on_number_changed(_v: float) -> void:
	if _updating or generator == null or generator.settings == null:
		return
	var s := generator.settings
	s.seed = int(_seed_field.value)
	s.map_size = _size_field.value
	s.resolution = int(_res_field.value)
	if _auto.button_pressed:
		_generate()


func _generate() -> void:
	if generator == null:
		return
	_status.text = "Generating..."
	generator.generate()
	var hf: MapHeightfield = generator.heightfield
	if hf:
		_status.text = "%s\n%d x %d verts, relief %.0f m, water %.0f m" % [
			generator.name, hf.dim, hf.dim, hf.max_h - hf.min_h, hf.water_level]
	regenerate_requested.emit()
