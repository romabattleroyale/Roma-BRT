@tool
extends RomaLibraryBuildingSystem
class_name RomaEditorLibraryBuildingSystem

# Tool-only wrapper used by the one-time editor bake.
# It reuses the existing V11 library unchanged; this only makes the
# procedural Node3D builder executable from an EditorScript.

# V11's base implementation uses Node3D.look_at() while the building root
# is still outside the SceneTree. Godot 4.7 rejects that call in editor bake.
# Keep the exact same geometry/orientation, but calculate the Y rotation
# directly so the wrapper remains editor-safe without touching the V11 base.
func _add_laundry(root: Node3D, a: Vector3, b: Vector3) -> void:
    var mid: Vector3 = (a + b) * 0.5
    var length: float = a.distance_to(b)
    var rope: MeshInstance3D = _box(root, mid, Vector3(0.025, 0.025, length), mats["metal"], false)
    var dir: Vector3 = b - a
    if dir.length_squared() > 0.000001:
        rope.rotation.y = atan2(dir.x, dir.z)
    for i in range(4):
        var t: float = (float(i) + 0.5) / 4.0
        var p: Vector3 = a.lerp(b, t)
        _box(root, p + Vector3(0, -0.28, 0), Vector3(0.35, 0.55, 0.035), mats["painted_wood"], false)
