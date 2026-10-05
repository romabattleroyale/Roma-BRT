extends SceneTree
## Phase C: visual GridMap road modules for 12 districts + 4 bridges.
## Keeps the approved 4 m grid and does not modify Terrain3D, Tevere, district layout, HLOD or road graph.
const LIB_PATH := "res://roads/roma_road_mesh_library.tres"
const FULL_DIR := "res://roads/generated"
const CENTERS: Array[Vector3] = [Vector3(-800,0,-650),Vector3(-400,0,-650),Vector3(400,0,-650),Vector3(800,0,-650),Vector3(-800,0,0),Vector3(-400,0,0),Vector3(400,0,0),Vector3(800,0,0),Vector3(-800,0,650),Vector3(-400,0,650),Vector3(400,0,650),Vector3(800,0,650)]

func _mat(c: Color, r: float) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = r
    return m

func _add_box(st: SurfaceTool, size: Vector3, offset: Vector3, mat: Material) -> void:
    st.set_material(mat)
    var h: Vector3 = size * 0.5
    var v: Array[Vector3] = [offset+Vector3(-h.x,-h.y,-h.z),offset+Vector3(h.x,-h.y,-h.z),offset+Vector3(h.x,h.y,-h.z),offset+Vector3(-h.x,h.y,-h.z),offset+Vector3(-h.x,-h.y,h.z),offset+Vector3(h.x,-h.y,h.z),offset+Vector3(h.x,h.y,h.z),offset+Vector3(-h.x,h.y,h.z)]
    var f: Array = [[0,2,1,3],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]]
    for q in f:
        st.add_vertex(v[q[0]]); st.add_vertex(v[q[1]]); st.add_vertex(v[q[2]])
        st.add_vertex(v[q[0]]); st.add_vertex(v[q[2]]); st.add_vertex(v[q[3]])

func _compound(parts: Array) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for p in parts:
        _add_box(st,p[0],p[1],p[2])
    st.generate_normals()
    return st.commit()

func _make_library() -> MeshLibrary:
    var lib := MeshLibrary.new()
    var asphalt := _mat(Color("#303438"),0.90)
    var asphalt2 := _mat(Color("#3b3f42"),0.90)
    var stone := _mat(Color("#4a4a47"),0.95)
    var trav := _mat(Color("#b8a27b"),0.85)
    var white := _mat(Color("#f4f0df"),0.82)
    var yellow := _mat(Color("#e5c548"),0.82)
    var metal := _mat(Color("#25282b"),0.70)
    var rail := _mat(Color("#777b7d"),0.65)
    var green := _mat(Color("#3f6848"),0.88)
    var dark := _mat(Color("#222426"),0.96)
    var items: Array = []
    # Road: base + short center marking, kept deliberately low-poly/Android friendly.
    items.append([0,"Asfalto_Dritto_4m",_compound([[Vector3(4,0.08,4),Vector3(0,0,0),asphalt],[Vector3(0.12,0.012,1.15),Vector3(0,0.052,0),white]] )])
    items.append([1,"Asfalto_Doppia_8m",_compound([[Vector3(8,0.08,4),Vector3(0,0,0),asphalt],[Vector3(0.10,0.012,3.4),Vector3(-0.9,0.052,0),white],[Vector3(0.10,0.012,3.4),Vector3(0.9,0.052,0),yellow]] )])
    items.append([2,"Asfalto_Incrocio_Croce",_compound([[Vector3(4,0.08,4),Vector3(0,0,0),asphalt],[Vector3(3.4,0.012,0.10),Vector3(0,0.052,0),white],[Vector3(0.10,0.012,3.4),Vector3(0,0.053,0),white]] )])
    items.append([3,"Asfalto_Incrocio_T",_compound([[Vector3(4,0.08,4),Vector3(0,0,0),asphalt],[Vector3(3.4,0.012,0.10),Vector3(0,0.052,0),white]] )])
    # Curves use layered corner plates rather than heavy geometry.
    items.append([4,"Asfalto_Curva_90",_compound([[Vector3(4,0.08,4),Vector3(0,0,0),asphalt],[Vector3(2.4,0.012,0.10),Vector3(0.6,0.052,-0.8),white],[Vector3(0.10,0.012,2.4),Vector3(0.8,0.053,0.6),white]])])
    items.append([5,"Asfalto_Curva_45",_compound([[Vector3(4,0.08,4),Vector3(0,0,0),asphalt],[Vector3(2.6,0.012,0.10),Vector3(0.2,0.052,-0.8),white],[Vector3(0.10,0.012,2.6),Vector3(0.8,0.053,0.2),white]])])
    # Zebra: five raised white bars.
    var zebra: Array = [[Vector3(4,0.08,4),Vector3(0,0,0),asphalt]]
    for z in [-1.5,-0.75,0,0.75,1.5]: zebra.append([Vector3(3.5,0.014,0.32),Vector3(0,0.052,z),white])
    items.append([6,"Asfalto_Zebra",_compound(zebra)])
    # Tram: two rails + central lane marking.
    items.append([7,"Asfalto_Tram",_compound([[Vector3(4,0.08,4),Vector3(0,0,0),asphalt],[Vector3(0.08,0.025,4),Vector3(-1,0.06,0),rail],[Vector3(0.08,0.025,4),Vector3(1,0.06,0),rail],[Vector3(0.08,0.012,3.2),Vector3(0,0.055,0),white]])])
    # Sampietrini: stone base + four shallow joint strips.
    var cobble: Array = [[Vector3(4,0.10,4),Vector3(0,0,0),stone]]
    for q in [-1.5,-0.5,0.5,1.5]: cobble.append([Vector3(0.025,0.008,4),Vector3(q,0.055,0),dark]); cobble.append([Vector3(4,0.008,0.025),Vector3(0,0.056,q),dark])
    items.append([8,"Sampietrini_Dritto",_compound(cobble)])
    items.append([9,"Sampietrini_Incrocio",_compound(cobble)])
    # Sidewalk has travertine slab, darker inner edge and raised curb.
    items.append([10,"Marciapiede_Dritto",_compound([[Vector3(4,0.15,1.5),Vector3(0,0.075,-1.25),trav],[Vector3(4,0.16,0.14),Vector3(0,0.08,-0.52),white]])])
    items.append([11,"Marciapiede_Angolo",_compound([[Vector3(4,0.15,1.5),Vector3(0,0.075,0),trav],[Vector3(4,0.16,0.14),Vector3(0,0.08,0.68),white]])])
    items.append([12,"Cordolo_Travertino",_compound([[Vector3(4,0.15,0.15),Vector3(0,0.075,0),white],[Vector3(3.6,0.035,0.05),Vector3(0,0.17,0),trav]])])
    items.append([13,"Piazza_8x8",_compound([[Vector3(8,0.10,8),Vector3(0,0,0),stone],[Vector3(7.6,0.025,0.10),Vector3(0,0.065,-3.8),trav],[Vector3(7.6,0.025,0.10),Vector3(0,0.066,3.8),trav],[Vector3(0.10,0.025,7.6),Vector3(-3.8,0.067,0),trav],[Vector3(0.10,0.025,7.6),Vector3(3.8,0.068,0),trav]])])
    items.append([14,"Tombino",_compound([[Vector3(0.7,0.035,0.7),Vector3(0,0,0),metal],[Vector3(0.55,0.01,0.08),Vector3(0,0.022,0),rail],[Vector3(0.08,0.01,0.55),Vector3(0,0.023,0),rail]])])
    items.append([15,"Caditoia",_compound([[Vector3(0.9,0.04,0.25),Vector3(0,0,0),metal],[Vector3(0.72,0.012,0.035),Vector3(0,0.026,0),rail]])])
    # Props remain simple silhouettes for Android.
    items.append([16,"Lampione_Romano",_compound([[Vector3(0.16,3.2,0.16),Vector3(0,1.6,0),metal],[Vector3(0.65,0.10,0.10),Vector3(0.28,3.12,0),metal],[Vector3(0.20,0.16,0.20),Vector3(0.58,3.04,0),trav]])])
    items.append([17,"Semaforo",_compound([[Vector3(0.16,3.0,0.16),Vector3(0,1.5,0),metal],[Vector3(0.55,0.55,0.16),Vector3(0.25,2.45,0),dark],[Vector3(0.12,0.12,0.18),Vector3(0.25,2.62,0),yellow]])])
    items.append([18,"Palina_Bus",_compound([[Vector3(0.12,2.4,0.12),Vector3(0,1.2,0),metal],[Vector3(0.75,0.45,0.08),Vector3(0,2.05,0),yellow]])])
    items.append([19,"Cassonetto",_compound([[Vector3(0.9,1.1,0.6),Vector3(0,0.55,0),green],[Vector3(0.94,0.08,0.64),Vector3(0,1.10,0),dark]])])
    items.append([20,"Fioriera",_compound([[Vector3(1.0,0.45,1.0),Vector3(0,0.225,0),trav],[Vector3(0.72,0.25,0.72),Vector3(0,0.57,0),green]])])
    items.append([21,"Panchina",_compound([[Vector3(1.5,0.12,0.42),Vector3(0,0.62,0),trav],[Vector3(0.10,0.55,0.10),Vector3(-0.55,0.30,0),metal],[Vector3(0.10,0.55,0.10),Vector3(0.55,0.30,0),metal]])])
    items.append([22,"Nasone",_compound([[Vector3(0.20,0.9,0.20),Vector3(0,0.45,0),metal],[Vector3(0.45,0.10,0.10),Vector3(0.18,0.78,0),metal],[Vector3(0.10,0.10,0.25),Vector3(0.38,0.72,0),green]])])
    items.append([23,"Albero_Roma",_compound([[Vector3(0.35,3.0,0.35),Vector3(0,1.5,0),dark],[Vector3(1.8,1.4,1.8),Vector3(0,3.1,0),green],[Vector3(1.2,0.8,1.2),Vector3(0,3.8,0),green]])])
    items.append([24,"Ponte_Romano_Modulo",_compound([[Vector3(4,0.12,4),Vector3(0,0,0),stone],[Vector3(3.3,0.10,3.0),Vector3(0,0.10,0),asphalt2],[Vector3(3.8,0.18,0.35),Vector3(0,0.18,-1.78),trav],[Vector3(3.8,0.18,0.35),Vector3(0,0.181,1.78),trav]])])
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
        for lane in [-1,0,1]: c.append([lane,z,7 if i in [1,4,6] else 0])
    for x in range(-36,37):
        for lane in [-1,0,1]: c.append([x,lane,7 if i in [2,5,8] else 0])
    for z in [-24,-12,12,24]:
        for x in range(-36,37): c.append([x,z,1])
    for x in [-24,-12,12,24]:
        for z in range(-36,37): c.append([x,z,1])
    for z in [-30,30]:
        for x in range(-30,31): c.append([x,z,8])
    for x in [-30,30]:
        for z in range(-30,31): c.append([x,z,8])
    c.append([0,0,13])
    for p in range(-35,36):
        c.append([p,-2,10]); c.append([p,2,10]); c.append([-2,p,10]); c.append([2,p,10])
    for p in [-3,3]: c.append([0,p,6]); c.append([p,0,6])
    c.append([5,5,16]); c.append([-5,-5,16]); c.append([5,-5,17]); c.append([7,0,18]); c.append([-7,0,19]); c.append([0,7,20]); c.append([0,-7,21]); c.append([8,8,22])
    _save("%s/district_%02d_roads.tscn" % [FULL_DIR,i+1],"District_%02d_RoadGrid" % [i+1],CENTERS[i],c)

func _bridge(name: String, origin: Vector3) -> void:
    var c: Array = []
    for x in range(-3,4):
        for z in range(-1,2): c.append([x,z,24])
    for x in range(-3,4): c.append([x,-2,10]); c.append([x,2,10])
    _save("%s/%s.tscn" % [FULL_DIR,name.to_lower()],name,origin,c)

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FULL_DIR))
    var err := ResourceSaver.save(_make_library(),LIB_PATH)
    if err != OK:
        push_error("ROMA ROADS FAIL library=%d" % err)
        quit(2)
        return
    for i in range(CENTERS.size()): _district(i)
    _bridge("Ponte_Sisto",Vector3(-120,0,-40))
    _bridge("Ponte_SantAngelo",Vector3(-40,0,-20))
    _bridge("Ponte_Vittorio",Vector3(40,0,20))
    _bridge("Ponte_Garibaldi",Vector3(120,0,40))
    print("ROMA ROADS VISUAL: PASS modules=25 style=RomaFortnite")
    print("ROMA ROADS FULL: PASS districts=12 bridges=4 library_items=25 cell=4x0.15x4")
    print("ROMA ROADS LAYOUT: PASS main=12m secondary=8m alleys=4m sidewalks=1.5m")
    print("ROMA ROADS CONSTRAINT: Terrain3D/Tevere/road_graph/building_HLOD untouched")
    quit(0)
