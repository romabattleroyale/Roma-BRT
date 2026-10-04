extends Node
## Android V11 memory diagnostics.
## Observes the existing V11 bridge without changing terrain, roads, Tevere or building generation.
## Logs process memory after each newly placed V11 building and performs a safe unused-resource cleanup after each 5-building block.

const POLL_FRAMES := 1
const BLOCK_SIZE := 5

var seen_buildings := {}
var last_count := 0
var frame_counter := 0
var last_cleanup_block := 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_process(true)
    print("[MEM] Android V11 memory watcher: START")

func _process(_delta: float) -> void:
    frame_counter += 1
    if frame_counter % POLL_FRAMES != 0:
        return
    var buildings := _find_v11_buildings()
    var count := buildings.size()
    if count > last_count:
        for building in buildings:
            var id: int = building.get_instance_id()
            if seen_buildings.has(id):
                continue
            seen_buildings[id] = true
            _log_building_memory(building, count)
        last_count = count
    var completed_blocks := int(count / BLOCK_SIZE)
    if completed_blocks > last_cleanup_block:
        for block_number in range(last_cleanup_block + 1, completed_blocks + 1):
            _cleanup_after_block(block_number, count)
        last_cleanup_block = completed_blocks

func _find_v11_buildings() -> Array[Node3D]:
    var result: Array[Node3D] = []
    var root := get_tree().current_scene
    if root == null:
        return result
    _collect_v11(root, result)
    return result

func _collect_v11(node: Node, result: Array[Node3D]) -> void:
    if node is Node3D and node.has_meta("prompt4_full_architecture") and bool(node.get_meta("prompt4_full_architecture")):
        result.append(node as Node3D)
    for child in node.get_children():
        _collect_v11(child, result)

func _log_building_memory(building: Node3D, number: int) -> void:
    var memory_bytes := float(Performance.get_monitor(Performance.MEMORY_STATIC))
    var memory_mb := memory_bytes / (1024.0 * 1024.0)
    var stats := _resource_stats(building)
    print("[MEM] Edificio #", number, " piazzato - Memoria processo: %.2f MB - Risorse in cache: %d - Nodi: %d - Mesh: %d - Materiali: %d - Texture: %d" % [memory_mb, stats["resources"], stats["nodes"], stats["meshes"], stats["materials"], stats["textures"]])

func _resource_stats(root: Node) -> Dictionary:
    var stats := _collect_resources(root)
    return {
        "nodes": stats["nodes"],
        "meshes": stats["meshes"].size(),
        "materials": stats["materials"].size(),
        "textures": stats["textures"].size(),
        "resources": stats["resources"].size()
    }

func _collect_resources(node: Node) -> Dictionary:
    var nodes := 1
    var meshes := {}
    var materials := {}
    var textures := {}
    var resources := {}
    if node is MeshInstance3D:
        var mesh_node := node as MeshInstance3D
        var mesh := mesh_node.mesh
        if mesh != null:
            var mesh_id: int = mesh.get_instance_id()
            meshes[mesh_id] = true
            resources[mesh_id] = true
            for surface in range(mesh.get_surface_count()):
                var mat := mesh.surface_get_material(surface)
                if mat != null:
                    var mat_id: int = mat.get_instance_id()
                    materials[mat_id] = true
                    resources[mat_id] = true
                    _collect_material_textures(mat, textures, resources)
        for slot in range(mesh_node.get_surface_override_material_count()):
            var override_mat := mesh_node.get_surface_override_material(slot)
            if override_mat != null:
                var override_id: int = override_mat.get_instance_id()
                materials[override_id] = true
                resources[override_id] = true
                _collect_material_textures(override_mat, textures, resources)
    for child in node.get_children():
        var child_stats := _collect_resources(child)
        nodes += int(child_stats["nodes"])
        for key in child_stats["meshes"].keys():
            meshes[key] = true
        for key in child_stats["materials"].keys():
            materials[key] = true
        for key in child_stats["textures"].keys():
            textures[key] = true
        for key in child_stats["resources"].keys():
            resources[key] = true
    return {"nodes":nodes,"meshes":meshes,"materials":materials,"textures":textures,"resources":resources}

func _collect_material_textures(material: Material, textures: Dictionary, resources: Dictionary) -> void:
    if material is BaseMaterial3D:
        var base := material as BaseMaterial3D
        var candidates := [base.albedo_texture, base.metallic_texture, base.roughness_texture, base.normal_texture, base.emission_texture, base.ao_texture]
        for candidate in candidates:
            var texture: Texture2D = candidate as Texture2D
            if texture != null:
                var id: int = texture.get_instance_id()
                textures[id] = true
                resources[id] = true

func _cleanup_after_block(block_number: int, building_count: int) -> void:
    print("[MEM] Cleanup dopo isolato #", block_number, " - edifici V11 attivi: ", building_count)
    ResourceLoader.unload_unused_resources()
    await get_tree().process_frame
    var memory_bytes := float(Performance.get_monitor(Performance.MEMORY_STATIC))
    var memory_mb := memory_bytes / (1024.0 * 1024.0)
    print("[MEM] Post-cleanup isolato #", block_number, " - Memoria processo: %.2f MB" % memory_mb)
