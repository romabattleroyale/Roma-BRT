extends Node3D
## Debug camera dall'alto per ispezionare la mappa Roma-BRT.
## Android + controller:
## - stick sinistro = sposta la mappa avanti/indietro/sinistra/destra
## - touch nella META' DESTRA = zoom + pitch
## - trascina verso l'alto = zoom avanti
## - trascina verso il basso = zoom indietro
## - trascina orizzontalmente = pitch/inclinazione
## - pinch nella meta destra = zoom preciso

@export var map_size := 2000.0
@export var target := Vector3(1000.0, 0.0, 1000.0)
@export var distance := 1500.0
@export var min_distance := 120.0
@export var max_distance := 3200.0
@export var pitch := -1.22
@export var min_pitch := -1.52
@export var max_pitch := -0.35
@export var touch_zoom_speed := 2.8
@export var touch_pitch_speed := 0.008
@export var controller_move_speed := 520.0

var camera: Camera3D
var touches: Dictionary = {}
var right_touch_indices: Dictionary = {}
var last_pinch_distance := 0.0

func _ready() -> void:
    camera = Camera3D.new()
    camera.name = "DebugTopDownCamera"
    camera.current = true
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.near = 0.1
    camera.far = 6000.0
    add_child(camera)
    update_camera()

func _process(delta: float) -> void:
    if camera == null:
        return

    # Controller su Android: stick SINISTRO = movimento della mappa.
    # X = sinistra/destra, Y = avanti/indietro.
    if Input.get_connected_joypads().size() > 0:
        var move_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
        var move_y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
        var move := Vector2(move_x, move_y)
        if move.length() > 0.12:
            move = move.normalized() * ((move.length() - 0.12) / 0.88)
            pan_from_controller(move, delta)

func pan_from_controller(move: Vector2, delta: float) -> void:
    var basis := Basis(Vector3.UP, 0.0)
    var right := basis.x
    var forward := -basis.z
    var speed := controller_move_speed * maxf(distance / 900.0, 0.45)
    target += (right * move.x + forward * -move.y) * speed * delta
    target.x = clampf(target.x, 0.0, map_size)
    target.z = clampf(target.z, 0.0, map_size)
    update_camera()

func _unhandled_input(event: InputEvent) -> void:
    if camera == null:
        return

    # Touch Android: usiamo la META' DESTRA dello schermo per la camera.
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            touches[touch.index] = touch.position
            if is_right_side(touch.position):
                right_touch_indices[touch.index] = true
        else:
            touches.erase(touch.index)
            right_touch_indices.erase(touch.index)
            if right_touch_indices.size() < 2:
                last_pinch_distance = 0.0
        return

    if event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        touches[drag.index] = drag.position

        # Solo il touch nella parte destra controlla zoom e pitch.
        if not right_touch_indices.has(drag.index):
            return

        var right_keys := right_touch_indices.keys()
        if right_keys.size() >= 2:
            var p0: Vector2 = touches[right_keys[0]]
            var p1: Vector2 = touches[right_keys[1]]
            var pinch_distance := p0.distance_to(p1)
            if last_pinch_distance > 0.0:
                var pinch_delta := pinch_distance - last_pinch_distance
                distance = clampf(
                    distance * pow(0.9975, pinch_delta),
                    min_distance,
                    max_distance
                )
                update_camera()
            last_pinch_distance = pinch_distance
            return

        # Un dito a destra:
        # verticale = zoom, orizzontale = pitch.
        var vertical := drag.relative.y
        var horizontal := drag.relative.x
        if absf(vertical) > 0.01:
            distance = clampf(
                distance * pow(2.0, vertical * touch_zoom_speed / 1000.0),
                min_distance,
                max_distance
            )
        if absf(horizontal) > 0.01:
            pitch = clampf(
                pitch - horizontal * touch_pitch_speed,
                min_pitch,
                max_pitch
            )
        update_camera()
        return

func is_right_side(position: Vector2) -> bool:
    return position.x >= get_viewport().get_visible_rect().size.x * 0.5

func update_camera() -> void:
    if camera == null:
        return

    var horizontal := cos(pitch) * distance
    var vertical := -sin(pitch) * distance
    var offset := Vector3(0.0, vertical, horizontal)
    camera.position = target + offset

    # Orthographic zoom: piu' piccola = piu' vicino/ingrandito.
    camera.size = clampf(distance * 0.72, 80.0, 3000.0)
    camera.look_at(target, Vector3.UP)
