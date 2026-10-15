extends CharacterBody3D
@export var walk_speed := 6.0
@export var run_speed := 10.5
@export var mouse_sensitivity := 0.0022
var pitch := 0.0
var touch_look_id := -1
var touch_move_id := -1
var touch_run_id := -1
var touch_jump_id := -1
var touch_jump_requested := false
var touch_origin := Vector2.ZERO
var touch_move := Vector2.ZERO
@onready var pivot: Node3D = $Node3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	pitch = -0.12
	pivot.rotation.x = pitch

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, -1.25, 1.25)
		pivot.rotation.x = pitch
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventScreenTouch:
		var screen_size := get_viewport().get_visible_rect().size
		if event.pressed:
			if event.position.x < screen_size.x * 0.48 and touch_move_id == -1:
				touch_move_id = event.index
				touch_origin = event.position
				touch_move = Vector2.ZERO
			elif event.position.x > screen_size.x * 0.78 and event.position.y > screen_size.y * 0.80 and touch_jump_id == -1:
				touch_jump_id = event.index
				touch_jump_requested = true
			elif event.position.x > screen_size.x * 0.78 and event.position.y > screen_size.y * 0.62 and touch_run_id == -1:
				touch_run_id = event.index
			elif touch_look_id == -1:
				touch_look_id = event.index
		else:
			if event.index == touch_move_id:
				touch_move_id = -1
				touch_move = Vector2.ZERO
			if event.index == touch_look_id:
				touch_look_id = -1
			if event.index == touch_run_id:
				touch_run_id = -1
			if event.index == touch_jump_id:
				touch_jump_id = -1
	if event is InputEventScreenDrag:
		if event.index == touch_move_id:
			touch_move = (event.position - touch_origin).limit_length(90.0) / 90.0
		elif event.index == touch_look_id:
			rotate_y(-event.relative.x * mouse_sensitivity * 1.6)
			pitch = clampf(pitch - event.relative.y * mouse_sensitivity * 1.6, -1.25, 1.25)
			pivot.rotation.x = pitch

func _physics_process(delta: float) -> void:
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	axis += touch_move
	axis = axis.limit_length(1.0)
	var speed := run_speed if Input.is_key_pressed(KEY_SHIFT) or touch_run_id != -1 else walk_speed
	var direction := (transform.basis * Vector3(axis.x, 0, axis.y)).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	else:
		velocity.y = -0.5
		if Input.is_action_just_pressed("jump") or touch_jump_requested:
			velocity.y = 6.5
	move_and_slide()
	touch_jump_requested = false
