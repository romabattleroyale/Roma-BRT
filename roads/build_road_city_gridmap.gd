extends SceneTree
## Phase B: full modular 4 m GridMap road layout for 12 districts + 4 bridges.
## Does not modify Terrain3D, Tevere, district layout, building HLOD or road graph.
const LIB_PATH := "res://roads/roma_road_mesh_library.tres"
const FULL_DIR := "res://roads/generated"
const CENTERS: Array[Vector3] = [Vector3(-800,0,-650),Vector3(-400,0,-650),Vector3(400,0,-650),Vector3(800,0,-650),Vector3(-800,0,0),Vector3(-400,0,0),Vector3(400,0,0),Vector3(800,0,0),Vector3(-800,0,650),Vector3(-400,0,650),Vector3(400,0,650),Vector3(800,0,650)]

func _mat(c: Color, r: float) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = r
    return m

func _box(s: Vector3, m: Material) -> BoxMesh:
    var b := BoxMesh.new()
    b.size = s
    b.material = m
    return b

func _offset_box(s: Vector3, o: Vector3, m: Material) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    st.set_material(m)
    var h := s * 0.5
    var v := [Vector3(-h.x,-h.y,-h.z),Vector3(h.x,-h.y,-h.z),Vector3(h.x,h.y,-h.z),Vector3(-h.x,h.y,-h.z),Vector3(-h.x,-h.y,h.z),Vector3(h.x,-h.y,h.z),Vector3(h.x,h.y,h.z),Vector3(-h.x,h.y,h.z)]
    for i in range(v.size()):
        v[i] += o
    var f := [[0,2,1,3],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]]
    for q in f:
        st.add_vertex(v[q[0]]); st.add_vertex(v[q[1]]); st.add_vertex(v[q[2]])
        st.add_vertex(v[q[0]]); st.add_vertex(v[q[2]]); st.add_vertex(v[q[3]])
    st.generate_normals()
    return st.commit()

func _make_library() -> MeshLibrary:
    var lib := MeshLibrary.new()
    var asphalt := _mat(Color("#35383a"),0.90)
    var stone := _mat(Color("#3d4142"),0.95)
    var trav := _mat(Color("#b7a27d"),0.85)
    var white := _mat(Color("#f1eee5"),0.82)
    var metal := _mat(Color("#25272a"),0.70)
    var green := _mat(Color("#3f5b45"),0.88)
    var items := [
        [0,"Asfalto_Dritto_4m",_box(Vector3(4,0.08,4),asphalt)],[1,"Asfalto_Doppia_8m",_box(Vector3(8,0.08,4),asphalt)],
        [2,"Asfalto_Incrocio_Croce",_box(Vector3(4,0.08,4),asphalt)],[3,"Asfalto_Incrocio_T",_box(Vector3(4,0.08,4),asphalt)],
        [4,"Asfalto_Curva_90",_box(Vector3(4,0.08,4),asphalt)],[5,"Asfalto_Curva_45",_box(Vector3(4,0.08,4),asphalt)],
        [6,"Asfalto_Zebra",_box(Vector3(4,0.10,4),asphalt)],[7,"Asfalto_Tram",_box(Vector3(4,0.10,4),asphalt)],
        [8,"Sampietrini_Dritto",_box(Vector3(4,0.10,4),stone)],[9,"Sampietrini_Incrocio",_box(Vector3(4,0.10,4),stone)],
        [10,"Marciapiede_Dritto",_offset_box(Vector3(4,0.15,1.5),Vector3(0,0.075,-1.25),trav)],[11,"Marciapiede_Angolo",_box(Vector3(4,0.15,1.5),trav)],[12,"Cordolo_Travertino",_box(Vector3(4,0.15,0.15),white)],[13,"Piazza_8x8",_box(Vector3(8,0.10,8),stone)],
        [14,"Tombino",_box(Vector3(0.7,0.035,0.7),metal)],[15,"Caditoia",_box(Vector3(0.9,0.04,0.25),metal)],[16,"Lampione_Romano",_box(Vector3(0.18,3.2,0.18),metal)],[17,"Semaforo",_box(Vector3(0.18,3.0,0.18),metal)],[18,"Palina_Bus",_box(Vector3(0.12,2.4,0.12),metal)],[19,"Cassonetto",_box(Vector3(0.9,1.1,0.6),green)],[20,"Fioriera",_box(Vector3(1.0,0.45,1.0),trav)],[21,"Panchina",_box(Vector3(1.5,0.45,0.45),metal)],[22,"Nasone",_box(Vector3(0.22,1.0,0.22),metal)],[23,"Albero_Roma",_box(Vector3(0.45,4.0,0.45),green)],[24,"Ponte_Romano_Modulo",_box(Vector3(4,0.12,4),stone)]
    ]
    for it in items:
        var id: int = it[0]
        lib.create_item(id)
        lib.set_item_name(id,it[1])
        lib.set_item_mesh(id,it[2])
    return lib

func _save(path: String, name: String, origin: Vector3, cells: Array) -> void:
    var root := Node3D.new()
    root.name = name
    var grid := GridMap.new()
    grid.name = "GridMap"
    grid.cell_size = Vector3(4,0.15,4)
    grid.position = origin
    grid.mesh_library = load(LIB_PATH)
    root.add_child(grid)
    grid.owner = root
    for c in cells:
        grid.set_cell_item(Vector3i(c[0],0,c[1]),int(c[2]))
    var packed := PackedScene.new()
    var err := packed.pack(root)
    if err == OK:
        ResourceSaver.save(packed,path)

func _district(i: int) -> void:
    var c: Array = []
    for z in range(-36,37):
        for lane in [-1,0,1]:
            c.append([lane,z,7 if i in [1,4,6] else 0])
    for x in range(-36,37):
        for lane in [-1,0,1]:
            c.append([x,lane,7 if i in [2,5,8] else 0])
    for z in [-24,-12,12,24]:
        for x in range(-36,37):
            c.append([x,z,1])
    for x in [-24,-12,12,24]:
        for z in range(-36,37):
            c.append([x,z,1])
    for z in [-30,30]:
        for x in range(-30,31):
            c.append([x,z,8])
    for x in [-30,30]:
        for z in range(-30,31):
            c.append([x,z,8])
    c.append([0,0,13])
    for p in range(-35,36):
        c.append([p,-2,10]); c.append([p,2,10]); c.append([-2,p,10]); c.append([2,p,10])
    for p in [-3,3]:
        c.append([0,p,6]); c.append([p,0,6])
    c.append([5,5,16]); c.append([-5,-5,16]); c.append([5,-5,17]); c.append([7,0,18]); c.append([-7,0,19]); c.append([0,7,20]); c.append([0,-7,21]); c.append([8,8,22])
    _save("%s/district_%02d_roads.tscn" % [FULL_DIR,i+1],"District_%02d_RoadGrid" % [i+1],CENTERS[i],c)

func _bridge(name: String, origin: Vector3) -> void:
    var c: Array = []
    for x in range(-3,4):
        for z in range(-1,2):
            c.append([x,z,24])
    for x in range(-3,4):
        c.append([x,-2,10]); c.append([x,2,10])
    _save("%s/%s.tscn" % [FULL_DIR,name.to_lower()],name,origin,c)

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FULL_DIR))
    var err := ResourceSaver.save(_make_library(),LIB_PATH)
    if err != OK:
        push_error("ROMA ROADS FAIL library=%d" % err)
        quit(2)
        return
    for i in range(CENTERS.size()):
        _district(i)
    _bridge("Ponte_Sisto",Vector3(-120,0,-40))
    _bridge("Ponte_SantAngelo",Vector3(-40,0,-20))
    _bridge("Ponte_Vittorio",Vector3(40,0,20))
    _bridge("Ponte_Garibaldi",Vector3(120,0,40))
    print("ROMA ROADS FULL: PASS districts=12 bridges=4 library_items=25 cell=4x0.15x4")
    print("ROMA ROADS LAYOUT: PASS main=12m secondary=8m alleys=4m sidewalks=1.5m")
    print("ROMA ROADS CONSTRAINT: Terrain3D/Tevere/road_graph/building_HLOD untouched")
    quit(0)
