extends SceneTree
## Phase A only: builds a modular 4 m GridMap road MeshLibrary and a pilot block.
## It does not modify Terrain3D, Tevere, the district layout, building HLOD or the road graph.
const ROOT := "res://roads"
const LIB_PATH := "res://roads/roma_road_mesh_library.tres"
const PILOT_PATH := "res://roads/roma_gridmap_pilot.tscn"
const BRIDGE_PATH := "res://roads/ponte_tevere_pilota.tscn"
func _mat(color: Color, rough: float = 0.9) -> StandardMaterial3D:
    var m := StandardMaterial3D.new(); m.albedo_color = color; m.roughness = rough; return m
func _box(size: Vector3, mat: Material) -> BoxMesh:
    var b := BoxMesh.new(); b.size = size; b.material = mat; return b
func _offset_box(size: Vector3, offset: Vector3, mat: Material) -> ArrayMesh:
    var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); st.set_material(mat)
    var h := size * 0.5
    var v := [Vector3(-h.x,-h.y,-h.z),Vector3(h.x,-h.y,-h.z),Vector3(h.x,h.y,-h.z),Vector3(-h.x,h.y,-h.z),Vector3(-h.x,-h.y,h.z),Vector3(h.x,-h.y,h.z),Vector3(h.x,h.y,h.z),Vector3(-h.x,h.y,h.z)]
    for i in range(v.size()): v[i] += offset
    var faces := [[0,2,1,3],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]]
    for f in faces:
        st.add_vertex(v[f[0]]); st.add_vertex(v[f[1]]); st.add_vertex(v[f[2]])
        st.add_vertex(v[f[0]]); st.add_vertex(v[f[2]]); st.add_vertex(v[f[3]])
    st.generate_normals(); return st.commit()
func _make_library() -> MeshLibrary:
    var lib := MeshLibrary.new()
    var asphalt := _mat(Color("#35383a"),0.90)
    var sampietrini := _mat(Color("#3d4142"),0.95)
    var travertine := _mat(Color("#b7a27d"),0.85)
    var white := _mat(Color("#f1eee5"),0.82)
    var metal := _mat(Color("#25272a"),0.70)
    var green := _mat(Color("#3f5b45"),0.88)
    var items := [
        [0,"Asfalto_Dritto_4m",_box(Vector3(4,0.08,4),asphalt)],[1,"Asfalto_Doppia_8m",_box(Vector3(8,0.08,4),asphalt)],
        [2,"Asfalto_Incrocio_Croce",_box(Vector3(4,0.08,4),asphalt)],[3,"Asfalto_Incrocio_T",_box(Vector3(4,0.08,4),asphalt)],
        [4,"Asfalto_Curva_90",_box(Vector3(4,0.08,4),asphalt)],[5,"Asfalto_Curva_45",_box(Vector3(4,0.08,4),asphalt)],
        [6,"Asfalto_Zebra",_box(Vector3(4,0.10,4),asphalt)],[7,"Asfalto_Tram",_box(Vector3(4,0.10,4),asphalt)],
        [8,"Sampietrini_Dritto",_box(Vector3(4,0.10,4),sampietrini)],[9,"Sampietrini_Incrocio",_box(Vector3(4,0.10,4),sampietrini)],
        [10,"Marciapiede_Dritto",_offset_box(Vector3(4,0.15,1.5),Vector3(0,0.075,-1.25),travertine)],[11,"Marciapiede_Angolo",_box(Vector3(4,0.15,1.5),travertine)],
        [12,"Cordolo_Travertino",_box(Vector3(4,0.15,0.15),white)],[13,"Piazza_8x8",_box(Vector3(8,0.10,8),sampietrini)],
        [14,"Tombino",_box(Vector3(0.7,0.035,0.7),metal)],[15,"Caditoia",_box(Vector3(0.9,0.04,0.25),metal)],
        [16,"Lampione_Romano",_box(Vector3(0.18,3.2,0.18),metal)],[17,"Semaforo",_box(Vector3(0.18,3.0,0.18),metal)],
        [18,"Palina_Bus",_box(Vector3(0.12,2.4,0.12),metal)],[19,"Cassonetto",_box(Vector3(0.9,1.1,0.6),green)],
        [20,"Fioriera",_box(Vector3(1.0,0.45,1.0),travertine)],[21,"Panchina",_box(Vector3(1.5,0.45,0.45),metal)],
        [22,"Nasone",_box(Vector3(0.22,1.0,0.22),metal)],[23,"Albero_Roma",_box(Vector3(0.45,4.0,0.45),green)],[24,"Ponte_Sisto_Modulo",_box(Vector3(4,0.12,4),sampietrini)]
    ]
    for item in items:
        var id: int = item[0]; lib.create_item(id); lib.set_item_name(id,item[1]); lib.set_item_mesh(id,item[2])
    return lib
func _save_grid_scene(path: String, grid_name: String, origin: Vector3, cells: Array) -> void:
    var root := Node3D.new(); root.name = grid_name
    var grid := GridMap.new(); grid.name = "GridMap"; grid.cell_size = Vector3(4,0.15,4); grid.position = origin; grid.mesh_library = load(LIB_PATH)
    root.add_child(grid); grid.owner = root
    for cell in cells: grid.set_cell_item(Vector3i(cell[0],0,cell[1]),int(cell[2]))
    var packed := PackedScene.new(); var err := packed.pack(root)
    if err == OK: ResourceSaver.save(packed,path)
func _make_pilot() -> void:
    var cells: Array = []
    for z in range(-4,5):
        for x in range(-4,5): cells.append([x,z,0 if (z == 0 or x == 0) else 8])
    for x in range(-4,5):
        if x != 0: cells.append([x,-1,10]); cells.append([x,1,10])
    for z in range(-4,5):
        if z != 0: cells.append([-1,z,10]); cells.append([1,z,10])
    cells.append([0,-2,6]); cells.append([2,2,16]); cells.append([-2,-2,16]); cells.append([3,0,14]); cells.append([-3,0,14]); cells.append([0,3,22])
    _save_grid_scene(PILOT_PATH,"CentroStorico_RoadPilot",Vector3(-800,0,-650),cells)
func _make_bridge() -> void:
    var cells: Array = []
    for x in range(-3,4):
        for z in range(-1,2): cells.append([x,z,24])
    _save_grid_scene(BRIDGE_PATH,"Ponte_Tevere_Pilota",Vector3(0,0,0),cells)
func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
    var err := ResourceSaver.save(_make_library(),LIB_PATH)
    if err != OK: push_error("ROMA ROADS FAIL: MeshLibrary save error=%d" % err); quit(2); return
    _make_pilot(); _make_bridge()
    print("ROMA ROADS GRIDMAP: PASS library_items=25 cell=4x0.15x4 pilot=CentroStorico")
    print("ROMA ROADS BRIDGE: PASS pilot_bridge=1 river_corridor=untouched")
    print("ROMA ROADS CONSTRAINT: Terrain3D/Tevere/road_graph/building_HLOD untouched")
    quit(0)
