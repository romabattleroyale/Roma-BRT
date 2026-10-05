extends SceneTree
## CI bake: 120 reusable Roman building templates + 587-placement manifest.
const FACTORY_SCRIPT := "res://city_library/buildings/houses/roma_architecture_library_v11/scripts/modular_house_factory.gd"
const POSITIONS_SCRIPT := "res://v37_integration/v37_building_positions_blob.gd"
const VARIATION_SCRIPT := "res://v37_integration/building_variation.gd"
const OUT_DIR := "res://baked_city/ready_templates"
const MANIFEST := "res://baked_city/ready_templates/manifest.json"
const MATERIAL_DIR := OUT_DIR + "/materials"
const TEMPLATE_COUNT := 120

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MATERIAL_DIR))
    var factory_script: Script = load(FACTORY_SCRIPT) as Script
    var positions_script: Script = load(POSITIONS_SCRIPT) as Script
    var variation_script: Script = load(VARIATION_SCRIPT) as Script
    if factory_script == null or positions_script == null or variation_script == null:
        push_error("READY TEMPLATE BAKE: dependency load failed"); quit(1); return
    var factory = factory_script.new()
    if factory == null or not factory.initialize():
        push_error("READY TEMPLATE BAKE: factory initialize failed"); quit(1); return
    var catalog: Array[Dictionary] = factory.get_catalog()
    var source: Array = positions_script.get_buildings()
    if catalog.size() != 27 or source.size() != 587:
        push_error("READY TEMPLATE BAKE: catalog=%d source=%d" % [catalog.size(), source.size()]); quit(1); return

    var groups := {"case": [], "palazzi": [], "angolo": [], "botteghe": [], "ville": [], "portici": []}
    for ci in range(catalog.size()):
        var e: Dictionary = catalog[ci]
        var text := (str(e.get("id", "")) + " " + str(e.get("name", "")) + " " + str(e.get("function", ""))).to_lower()
        groups[_category(text)].append(ci)
    print("READY TEMPLATE GROUPS: ", groups)

    var quotas := {"case": 40, "palazzi": 30, "angolo": 20, "botteghe": 15, "ville": 10, "portici": 5}
    var templates: Array[Dictionary] = []
    var used := {}
    var group_order := ["case", "palazzi", "angolo", "botteghe", "ville", "portici"]
    var roofs := [0, 7, 10, 17, 20, 27]
    var floors := [3, 4, 5]

    for gi in range(group_order.size()):
        var g: String = group_order[gi]
        var candidates: Array = groups[g].duplicate()
        if candidates.is_empty():
            candidates = []
            for ci in range(catalog.size()): candidates.append(ci)
        var quota: int = int(quotas[g])
        for k in range(quota):
            var ci: int = int(candidates[posmod(k + gi * 3, candidates.size())])
            var floor: int = floors[posmod(k + gi, floors.size())]
            var roof: int = roofs[posmod(k + gi * 2, roofs.size())]
            var key := "%d|%d|%d" % [ci, floor, roof]
            var attempts := 0
            while used.has(key) and attempts < 200:
                roof = roofs[posmod(roof + 7 + attempts, roofs.size())]
                floor = floors[posmod(floor + attempts + 1, floors.size())]
                ci = int(candidates[posmod(k + gi * 3 + attempts + 1, candidates.size())])
                key = "%d|%d|%d" % [ci, floor, roof]
                attempts += 1
            if used.has(key):
                push_error("READY TEMPLATE BAKE: unable to create unique template category=%s index=%d candidates=%d" % [g, k, candidates.size()]); quit(1); return
            used[key] = true
            templates.append({"catalog_index": ci, "category": g, "floors": floor, "roof_variant": roof})

    if templates.size() != TEMPLATE_COUNT:
        push_error("READY TEMPLATE BAKE: template count=%d" % templates.size()); quit(1); return

    _write_shared_materials()
    var cache := _load_shared_materials()
    for t in range(TEMPLATE_COUNT):
        var spec: Dictionary = templates[t]
        var entry: Dictionary = catalog[int(spec["catalog_index"])]
        var id := str(entry["id"])
        var variant := int(spec["catalog_index"]) + int(spec["roof_variant"]) + t * 6
        var root := factory.build_mobile_by_id(id, variant) as Node3D
        if root == null:
            push_error("READY TEMPLATE BAKE: build failed template=%d id=%s" % [t,id]); quit(1); return
        root.name = "ReadyTemplate_%03d" % (t + 1)
        root.position = Vector3.ZERO
        root.rotation = Vector3.ZERO
        root.set_meta("ready_template", true)
        root.set_meta("template_index", t)
        root.set_meta("template_category", str(spec["category"]))
        root.set_meta("template_catalog_id", id)
        root.set_meta("template_floors", int(spec["floors"]))
        root.set_meta("template_roof_variant", int(spec["roof_variant"]))
        _apply_shared_materials(root, t, cache)
        _strip_collision_nodes(root)
        _add_box_collision(root, float(entry.get("w", 10.0)), float(entry.get("d", 10.0)), int(spec["floors"]))
        _set_owner_recursive(root, root)
        var packed := PackedScene.new()
        var err := packed.pack(root)
        root.free()
        if err != OK:
            push_error("READY TEMPLATE BAKE: pack failed %d" % t); quit(1); return
        err = ResourceSaver.save(packed, "%s/template_%03d.tscn" % [OUT_DIR, t + 1])
        if err != OK:
            push_error("READY TEMPLATE BAKE: save failed %d" % t); quit(1); return

    _write_manifest(source, catalog, templates, variation_script)
    print("READY TEMPLATE BAKE OK: templates=120 placements=587")
    quit(0)

func _category(text: String) -> String:
    if text.contains("portico"): return "portici"
    if text.contains("villa"): return "ville"
    if text.contains("angolo") or text.contains("angolare"): return "angolo"
    if text.contains("bottega") or text.contains("negozi") or text.contains("negozio") or text.contains("mercante"): return "botteghe"
    if text.contains("palazzo") or text.contains("palazzetto"): return "palazzi"
    return "case"

func _write_manifest(source: Array, catalog: Array[Dictionary], templates: Array[Dictionary], variation_script: Script) -> void:
    var entries: Array = []
    for i in range(source.size()):
        var v: Dictionary = variation_script.call("variation_for", i, int(i / 4))
        var ai := posmod(int(v.get("archetype_index", i)), catalog.size())
        var text := (str(catalog[ai].get("id", "")) + " " + str(catalog[ai].get("name", "")) + " " + str(catalog[ai].get("function", ""))).to_lower()
        var category := _category(text)
        var candidates: Array[int] = []
        for t in range(templates.size()):
            if str(templates[t]["category"]) == category: candidates.append(t)
        if candidates.is_empty(): candidates.append(posmod(i, templates.size()))
        var template := candidates[posmod(i * 17 + ai, candidates.size())]
        entries.append({"template": template, "x": float(source[i].get("x", 0.0)), "z": float(source[i].get("z", 0.0)), "rotation": float(source[i].get("rotation", 0.0)), "seed": int(v.get("seed", i)), "facade_index": posmod(i * 7 + 1, 6), "roof_index": posmod(i * 5 + 2, 3), "floors": int(v.get("height_floors", 3)), "shutters": posmod(i, 2), "balcony": posmod(i + 1, 2), "wear": posmod(i, 4)})
    var payload: Dictionary = {"template_count": TEMPLATE_COUNT, "placement_count": 587, "chunk_size": 200.0, "max_active": 50, "placements": entries}
    var f := FileAccess.open(MANIFEST, FileAccess.WRITE)
    f.store_string(JSON.stringify(payload))
    f.close()

func _write_shared_materials() -> void:
    var colors = [Color("#B97845"), Color("#D3A63A"), Color("#B96F73"), Color("#C7AA83"), Color("#A9573B"), Color("#A99A7E")]
    var albedo := load("res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures/roman_plaster_weathered_albedo.jpg") as Texture2D
    var normal := load("res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures/roman_plaster_weathered_normal.jpg") as Texture2D
    var rough := load("res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures/roman_plaster_weathered_roughness.jpg") as Texture2D
    for i in range(6):
        var m := StandardMaterial3D.new(); m.albedo_color = colors[i]; m.albedo_texture = albedo; m.normal_enabled = normal != null; m.normal_texture = normal; m.normal_scale = 0.58; m.roughness_texture = rough; m.roughness = 0.88; m.uv1_scale = Vector3(3.6, 3.6, 3.6); m.texture_repeat = true; ResourceSaver.save(m, "%s/facade_%d.tres" % [MATERIAL_DIR, i])
    for i in range(3):
        var m := StandardMaterial3D.new(); m.albedo_color = [Color("#B84D32"), Color("#C9783F"), Color("#8F6B4E")][i]; m.roughness = 0.90; ResourceSaver.save(m, "%s/roof_%d.tres" % [MATERIAL_DIR, i])

func _load_shared_materials() -> Dictionary:
    var c = {}
    for i in range(6): c["f%d" % i] = load("%s/facade_%d.tres" % [MATERIAL_DIR, i])
    for i in range(3): c["r%d" % i] = load("%s/roof_%d.tres" % [MATERIAL_DIR, i])
    return c

func _apply_shared_materials(root: Node3D, variant: int, cache: Dictionary) -> void:
    for node in _mesh_nodes(root):
        if not bool(node.get_meta("mobile_merged", false)) or node.mesh == null: continue
        var mesh := node.mesh as ArrayMesh
        if mesh == null: continue
        var roles: Array = mesh.get_meta("surface_roles", []) as Array
        var fi := posmod(variant * 7 + 1, 6)
        var ri := posmod(variant * 5 + 2, 3)
        for s in range(mesh.get_surface_count()):
            var role := str(roles[s]) if s < roles.size() else "other"
            if role == "facade": mesh.surface_set_material(s, cache["f%d" % fi])
            elif role == "roof": mesh.surface_set_material(s, cache["r%d" % ri])

func _mesh_nodes(root: Node3D) -> Array[MeshInstance3D]:
    var a: Array[MeshInstance3D] = []
    _collect(root, a)
    return a

func _collect(n: Node, a: Array[MeshInstance3D]) -> void:
    if n is MeshInstance3D: a.append(n as MeshInstance3D)
    for c in n.get_children(): _collect(c, a)

func _strip_collision_nodes(n: Node) -> void:
    for c in n.get_children():
        if c is StaticBody3D or c is CollisionShape3D or c is CollisionPolygon3D: c.free()
        else: _strip_collision_nodes(c)

func _add_box_collision(root: Node3D, w: float, d: float, floors: int) -> void:
    var b := StaticBody3D.new(); b.name = "Collision"
    var s := CollisionShape3D.new(); s.name = "BoxCollision"
    var box := BoxShape3D.new(); box.size = Vector3(maxf(w, 2.0), maxf(2.0, float(floors) * 3.2), maxf(d, 2.0))
    s.shape = box; b.add_child(s); s.position.y = box.size.y * 0.5; root.add_child(b)

func _set_owner_recursive(n: Node, o: Node) -> void:
    if n != o: n.owner = o
    for c in n.get_children(): _set_owner_recursive(c, o)
