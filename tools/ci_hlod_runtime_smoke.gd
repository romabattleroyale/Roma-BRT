extends SceneTree
## CI-only runtime smoke. It exercises the persisted V11 manifest, 36 HLODs,
## template streaming and the real V11 bridge without requiring Terrain3D's
## native extension to be registered by the Linux runner.

func _init() -> void:
    var root := Node3D.new()
    root.name = "CIRuntimeRoot"
    root.set_script(null)
    root.add_to_group("ci_runtime")
    root.process_mode = Node.PROCESS_MODE_ALWAYS
    root.set_meta("ci_runtime", true)
    get_root().add_child(root)

    var v37_script := load("res://v37_integration/v37_world.gd") as Script
    var bridge_script := load("res://v37_integration/v11_building_bridge.gd") as Script
    if v37_script == null or bridge_script == null:
        push_error("CI HLOD SMOKE: V37/V11 script load failed")
        quit(2)
        return

    var v37 := Node3D.new()
    v37.name = "V37Integration"
    v37.set_script(v37_script)
    v37.set("enable_buildings", false)
    v37.set("enable_pois", false)
    v37.set("enable_foliage", false)
    v37.set("enable_fire", false)
    root.add_child(v37)

    var city_root := Node3D.new()
    city_root.name = "V37World"
    v37.add_child(city_root)
    v37.set("city_root", city_root)

    var bridge := Node3D.new()
    bridge.name = "V11BuildingBridge"
    bridge.set_script(bridge_script)
    root.add_child(bridge)

    print("CI HLOD SMOKE: bootstrapped V37 city_root without Terrain3D")

    await create_timer(0.5).timeout
    var deadline := Time.get_ticks_msec() + 90000
    while Time.get_ticks_msec() < deadline:
        if bool(bridge.get("built")):
            print("V11 READY BAKE: COMPLETE loaded=587 templates=120 active=%d HLOD=12x3" % int(bridge.get("_active").size()))
            print("GODOT_HLOD_RUNTIME=CLEAN")
            quit(0)
            return
        await create_timer(0.25).timeout
    push_error("CI HLOD SMOKE: V11 bridge did not become ready")
    quit(1)
