extends Node3D

const BUILDINGS: Array[Dictionary] = [
    {"id":"casa_trastevere","name":"Casa Trastevere","w":8.5,"d":8.0,"floors":3,"function":"RESIDENZIALE","style":"plaster_cream"},
    {"id":"casa_vicolo","name":"Casa del Vicolo","w":7.5,"d":9.5,"floors":3,"function":"RESIDENZIALE","style":"plaster_terracotta"},
    {"id":"casa_mercante","name":"Casa Mercante","w":11.0,"d":9.0,"floors":4,"function":"BOTTEGA / RESIDENZA","style":"brick"},
    {"id":"palazzetto","name":"Palazzetto Romano","w":14.0,"d":11.0,"floors":4,"function":"PALAZZO NOBILE / RESIDENZA","style":"plaster_cream"},
    {"id":"palazzo_nobile","name":"Palazzo Nobile","w":20.0,"d":14.0,"floors":5,"function":"PALAZZO NOBILE / UFFICI","style":"plaster_pale"},
    {"id":"palazzo_angolo","name":"Palazzo d'Angolo","w":18.0,"d":16.0,"floors":5,"function":"NEGOZI / RESIDENZA","style":"plaster_cream"},
    {"id":"palazzo_portico","name":"Palazzo con Portico","w":24.0,"d":13.0,"floors":4,"function":"BAR / NEGOZI / RESIDENZA","style":"plaster_cream"},
    {"id":"palazzo_lungo","name":"Palazzo a Balconata","w":28.0,"d":12.0,"floors":5,"function":"RESIDENZA","style":"plaster_pale"},
    {"id":"palazzo_cortile","name":"Palazzo a Corte","w":22.0,"d":20.0,"floors":4,"function":"RESIDENZA / CORTILE","style":"brick"},
    {"id":"villa_urbana","name":"Villa Urbana","w":17.0,"d":15.0,"floors":3,"function":"VILLA / CORTILE","style":"plaster_cream"},
    {"id":"villa_angolo","name":"Villa d'Angolo","w":19.0,"d":17.0,"floors":3,"function":"VILLA / RESIDENZA","style":"travertine"},
    {"id":"casa_cortile","name":"Casa a Corte","w":16.0,"d":18.0,"floors":3,"function":"RESIDENZA / CORTILE","style":"brick"},
    {"id":"edificio_commerciale","name":"Edificio Commerciale","w":15.0,"d":10.0,"floors":4,"function":"NEGOZI / UFFICI","style":"plaster_pale"},
    {"id":"bar_roma","name":"Bar / Caffetteria","w":10.0,"d":9.0,"floors":3,"function":"BAR","style":"plaster_cream"},
    {"id":"ristorante","name":"Ristorante / Pizzeria","w":13.0,"d":11.0,"floors":3,"function":"RISTORANTE","style":"brick"},
    {"id":"trattoria","name":"Trattoria Romana","w":12.0,"d":10.0,"floors":3,"function":"RISTORANTE","style":"plaster_terracotta"},
    {"id":"pasticceria","name":"Pasticceria / Forno","w":9.0,"d":8.5,"floors":3,"function":"PASTICCERIA","style":"plaster_pale"},
    {"id":"gelateria","name":"Gelateria","w":8.5,"d":8.0,"floors":3,"function":"GELATERIA","style":"plaster_cream"},
    {"id":"alimentari","name":"Alimentari / Minimarket","w":11.0,"d":9.0,"floors":3,"function":"ALIMENTARI","style":"plaster_terracotta"},
    {"id":"farmacia","name":"Farmacia","w":10.0,"d":9.0,"floors":4,"function":"FARMACIA","style":"travertine"},
    {"id":"bottega","name":"Bottega Artigiana","w":9.5,"d":8.5,"floors":3,"function":"BOTTEGA","style":"brick"},
    {"id":"libreria","name":"Libreria","w":12.0,"d":9.0,"floors":3,"function":"LIBRERIA","style":"plaster_cream"},
    {"id":"piccolo_hotel","name":"Piccolo Hotel / B&B","w":18.0,"d":12.0,"floors":4,"function":"HOTEL / B&B","style":"travertine"},
    {"id":"palazzo_hotel","name":"Palazzo Hotel","w":24.0,"d":15.0,"floors":5,"function":"HOTEL","style":"travertine"}
]

var system: RomaBuildingSystem
var showroom: Node3D
var camera: Camera3D
var info: Label
var index_label: Label
var current_index: int = 0
var orbit_yaw: float = 32.0
var orbit_pitch: float = -15.0
var orbit_distance: float = 34.0
var look_id: int = -1
var last_look: Vector2 = Vector2.ZERO

func _ready() -> void:
    system = RomaBuildingSystem.new()
    system.name = "RomaBuildingSystem"
    add_child(system)
    system.setup_materials()
    _make_environment()
    _make_ground()
    _make_ui()
    _show_current()

func _make_environment() -> void:
    var world: WorldEnvironment = WorldEnvironment.new()
    var env: Environment = Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky: Sky = Sky.new()
    var sky_mat: PanoramaSkyMaterial = PanoramaSkyMaterial.new()
    var hdr: Texture2D = load("res://assets/textures/EveningSkyHDRI045B_2K_HDR.exr") as Texture2D
    sky_mat.panorama = hdr
    sky_mat.energy_multiplier = 0.92
    sky.sky_material = sky_mat
    env.sky = sky
    env.background_energy_multiplier = 0.86
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.88
    env.ambient_light_sky_contribution = 1.0
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.ssao_enabled = true
    env.ssao_radius = 1.35
    env.ssao_intensity = 0.72
    world.environment = env
    add_child(world)

    var sun: DirectionalLight3D = DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-53.0, -34.0, 0.0)
    sun.light_energy = 1.32
    sun.light_color = Color("#FFF0D0")
    sun.shadow_enabled = true
    sun.light_size = 2.0
    add_child(sun)

func _make_ground() -> void:
    var ground: MeshInstance3D = MeshInstance3D.new()
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = Vector3(70.0, 0.24, 56.0)
    ground.mesh = mesh
    ground.position = Vector3(0, -0.12, 0)
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    mat.albedo_color = Color("#B7AC96")
    mat.roughness = 0.94
    ground.material_override = mat
    add_child(ground)

func _make_ui() -> void:
    var layer: CanvasLayer = CanvasLayer.new()
    add_child(layer)

    var title: Label = Label.new()
    title.position = Vector2(24, 20)
    title.text = "ROMA ROYALE • ARCHITECTURE LIBRARY V8 • ROMA AUTENTICA"
    title.add_theme_font_size_override("font_size", 24)
    layer.add_child(title)

    info = Label.new()
    info.position = Vector2(24, 56)
    info.add_theme_font_size_override("font_size", 18)
    layer.add_child(info)

    index_label = Label.new()
    index_label.position = Vector2(24, 88)
    index_label.add_theme_font_size_override("font_size", 15)
    layer.add_child(index_label)

    var note: Label = Label.new()
    note.position = Vector2(24, 112)
    note.text = "TRASCINA = ruota • struttura 360° • vetri trasparenti • interni visibili • PBR • balconi secondo la regola definitiva"
    note.add_theme_font_size_override("font_size", 14)
    layer.add_child(note)

    var prev: Button = Button.new()
    prev.text = "‹  PRECEDENTE"
    prev.position = Vector2(24, 625)
    prev.size = Vector2(190, 58)
    prev.pressed.connect(_previous)
    layer.add_child(prev)

    var next: Button = Button.new()
    next.text = "SUCCESSIVA  ›"
    next.position = Vector2(225, 625)
    next.size = Vector2(190, 58)
    next.pressed.connect(_next)
    layer.add_child(next)

    var foot: Label = Label.new()
    foot.position = Vector2(845, 615)
    foot.text = "FOOTPRINT DEFINITO\nprima della rete stradale"
    foot.add_theme_font_size_override("font_size", 15)
    layer.add_child(foot)

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        var touch: InputEventScreenTouch = event as InputEventScreenTouch
        if touch.pressed:
            if touch.position.y < 610.0:
                look_id = touch.index
                last_look = touch.position
        elif touch.index == look_id:
            look_id = -1
    elif event is InputEventScreenDrag:
        var drag: InputEventScreenDrag = event as InputEventScreenDrag
        if drag.index == look_id:
            var delta: Vector2 = drag.position - last_look
            last_look = drag.position
            orbit_yaw -= delta.x * 0.28
            orbit_pitch = clamp(orbit_pitch - delta.y * 0.15, -52.0, 6.0)
            _update_camera()

func _previous() -> void:
    current_index = (current_index - 1 + BUILDINGS.size()) % BUILDINGS.size()
    _show_current()

func _next() -> void:
    current_index = (current_index + 1) % BUILDINGS.size()
    _show_current()

func _show_current() -> void:
    if showroom != null:
        showroom.queue_free()
    var data: Dictionary = BUILDINGS[current_index]
    showroom = system.build(data, current_index)
    add_child(showroom)
    var w: float = float(data["w"])
    var d: float = float(data["d"])
    var floors: int = int(data["floors"])
    info.text = "%s  •  %.1f × %.1f m  •  %d piani  •  %s" % [str(data["name"]), w, d, floors, str(data["function"])]
    index_label.text = "Archetipo %d / %d  •  Classe: %s  •  Porte: INTERACTION READY" % [current_index + 1, BUILDINGS.size(), "GRANDE" if w >= 18.0 else ("MEDIA" if w >= 13.0 else "PICCOLA")]
    orbit_distance = max(24.0, max(w, d) * 2.05 + float(floors) * 1.4)
    orbit_yaw = 32.0
    orbit_pitch = -15.0
    _update_camera()

func _update_camera() -> void:
    if camera == null:
        camera = Camera3D.new()
        camera.current = true
        camera.fov = 52.0
        add_child(camera)
    var target: Vector3 = Vector3(0, float(BUILDINGS[current_index]["floors"]) * 1.45, 0)
    var yaw: float = deg_to_rad(orbit_yaw)
    var pitch: float = deg_to_rad(orbit_pitch)
    var dir: Vector3 = Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
    camera.position = target + dir * orbit_distance
    camera.look_at(target, Vector3.UP)
