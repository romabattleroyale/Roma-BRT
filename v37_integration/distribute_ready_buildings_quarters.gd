extends SceneTree
## Rewrites only the ready-building placement coordinates.
## Terrain3D, Tevere, roads, palette and roofs are untouched.
## 12 compact districts cover the 2000x2000 map; 8 are dense and 4 are sparse.

const MANIFEST := "res://baked_city/ready_templates/manifest.json"
const MAP_HALF := 1000.0
const DISTRICT_SIZE := 300.0
const RIVER_X_SLOPE := 0.28
const RIVER_CLEARANCE := 100.0

# 12 district centers, 4 columns x 3 rows. The two inner columns sit on
# opposite sides of the approximate NW-SE river corridor and leave a clear gap.
const CENTERS := [
    Vector2(-800.0, -650.0), Vector2(-400.0, -650.0), Vector2(400.0, -650.0), Vector2(800.0, -650.0),
    Vector2(-800.0,    0.0), Vector2(-400.0,    0.0), Vector2(400.0,    0.0), Vector2(800.0,    0.0),
    Vector2(-800.0,  650.0), Vector2(-400.0,  650.0), Vector2(400.0,  650.0), Vector2(800.0,  650.0)
]

# 8 dense districts: 487 total. 4 sparse districts: 100 total. Exact manifest: 587.
const COUNTS := [61, 61, 61, 61, 61, 61, 61, 60, 25, 25, 25, 25]

func _initialize() -> void:
    var file := FileAccess.open(MANIFEST, FileAccess.READ)
    if file == null:
        push_error("READY QUARTERS FAIL: missing manifest")
        quit(2)
        return
    var parsed = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Dictionary):
        push_error("READY QUARTERS FAIL: invalid manifest")
        quit(3)
        return
    var payload: Dictionary = parsed
    var placements: Array = payload.get("placements", [])
    if placements.size() != 587:
        push_error("READY QUARTERS FAIL: placement_count=%d expected=587" % placements.size())
        quit(4)
        return

    var index := 0
    for district in range(CENTERS.size()):
        var center: Vector2 = CENTERS[district]
        var count: int = COUNTS[district]
        var dense := count >= 60
        for local in range(count):
            var p: Vector2
            if dense:
                # 10x7 lattice with 3 spare slots removed: compact blocks with
                # roughly 22-26 m building spacing inside each 300x300 district.
                var cols := 10
                var row := int(local / cols)
                var col := local % cols
                var rows := int(ceil(float(count) / float(cols)))
                var sx := 24.0
                var sz := 30.0
                p = center + Vector2((float(col) - 4.5) * sx, (float(row) - float(rows - 1) * 0.5) * sz)
            else:
                # 5x5 sparse lattice, leaving more breathing room for parks/roads.
                var row := int(local / 5)
                var col := local % 5
                p = center + Vector2((float(col) - 2.0) * 42.0, (float(row) - 2.0) * 42.0)

            # Deterministic micro-jitter prevents a visibly perfect grid without
            # changing the district footprint. Keep every point inside its district.
            var jitter_x := float(posmod(local * 17 + district * 11, 9) - 4) * 1.6
            var jitter_z := float(posmod(local * 29 + district * 7, 9) - 4) * 1.6
            p += Vector2(jitter_x, jitter_z)
            p.x = clampf(p.x, center.x - DISTRICT_SIZE * 0.46, center.x + DISTRICT_SIZE * 0.46)
            p.y = clampf(p.y, center.y - DISTRICT_SIZE * 0.46, center.y + DISTRICT_SIZE * 0.46)

            # Keep the building layout on its assigned river bank. This is only a
            # placement constraint; no Tevere geometry is modified here.
            var river_x := RIVER_X_SLOPE * p.y
            if absf(p.x - river_x) < RIVER_CLEARANCE:
                p.x = river_x + (RIVER_CLEARANCE if p.x >= river_x else -RIVER_CLEARANCE)

            p.x = clampf(p.x, -MAP_HALF + 30.0, MAP_HALF - 30.0)
            p.y = clampf(p.y, -MAP_HALF + 30.0, MAP_HALF - 30.0)

            var entry: Dictionary = placements[index]
            entry["x"] = p.x
            entry["z"] = p.y
            placements[index] = entry
            index += 1

    payload["placements"] = placements
    payload["placement_count"] = 587
    var out := FileAccess.open(MANIFEST, FileAccess.WRITE)
    if out == null:
        push_error("READY QUARTERS FAIL: cannot write manifest")
        quit(5)
        return
    out.store_string(JSON.stringify(payload))
    out.close()

    print("READY QUARTERS OK: districts=12 dense=8 sparse=4 placements=587")
    print("READY QUARTERS MAP: 2000x2000 district_size=300 gap=100..200m")
    quit(0)
