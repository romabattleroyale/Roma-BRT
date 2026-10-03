extends RefCounted
class_name RomaBuildingVariation

## PROMPT 2: deterministic per-building variation, without placing buildings.
## V12 adds three new Roman typologies while preserving the V11 seed system.

const ARCHETYPE_COUNT: int = 27
const COLORS = [
    "ocra",
    "giallo_romano",
    "rosa_antico",
    "beige",
    "terracotta",
    "travertino"
]
const HEIGHTS = [3, 4, 5]
const ROOFS = ["falda", "altana"]
const WEAR_LEVELS = ["nuovo", "leggero", "medio", "usurato", "scrostato"]

static func seed_for(index: int, salt: int = 20261003) -> int:
    var value: int = int(hash("RomaV12:%d:%d" % [salt, index]))
    if value == 0:
        value = salt + index + 1
    return value

static func variation_for(index: int, block_id: int = 0) -> Dictionary:
    var seed: int = seed_for(index, 20261003 + block_id * 7919)
    var rng := RandomNumberGenerator.new()
    rng.seed = seed

    var archetype: int = _archetype_for(index, rng)
    var height: int = _height_for(index)
    var color: String = _color_for(index, rng)

    return {
        "seed": seed,
        "archetype_index": archetype,
        "facade_color": color,
        "height_floors": height,
        "balconies": rng.randf() >= 0.38,
        "shutters_open": rng.randf() >= 0.52,
        "cornice": rng.randf() >= 0.28,
        "bugnato_ground": rng.randf() >= 0.45,
        "commercial_ground": rng.randf() >= 0.62,
        "roof_type": ROOFS[rng.randi_range(0, ROOFS.size() - 1)],
        "wear_level": WEAR_LEVELS[rng.randi_range(0, WEAR_LEVELS.size() - 1)]
    }

static func _archetype_for(index: int, rng: RandomNumberGenerator) -> int:
    if index < ARCHETYPE_COUNT:
        return index
    var previous: int = _archetype_for(index - 1, rng)
    var candidate: int = rng.randi_range(0, ARCHETYPE_COUNT - 1)
    if candidate == previous:
        candidate = (candidate + 1 + (index % 7)) % ARCHETYPE_COUNT
    return candidate

static func _height_for(index: int) -> int:
    var pattern = [3, 4, 5, 4, 3, 5]
    return int(pattern[index % pattern.size()])

static func _color_for(index: int, rng: RandomNumberGenerator) -> String:
    var previous := ""
    var previous_two := ""
    if index > 0:
        previous = COLORS[(index - 1) % COLORS.size()]
    if index > 1:
        previous_two = COLORS[(index - 2) % COLORS.size()]

    var candidates: Array = []
    for color in COLORS:
        if color == previous or color == previous_two:
            continue
        candidates.append(color)

    if candidates.is_empty():
        candidates = COLORS.duplicate()
    return str(candidates[rng.randi_range(0, candidates.size() - 1)])

static func build_test_report(count: int = 40) -> Dictionary:
    var archetypes := {}
    var heights := {}
    var colors := {}
    var seeds := {}
    var variations: Array = []

    for i in range(max(count, 0)):
        var v: Dictionary = variation_for(i, int(i / 4))
        variations.append(v)
        archetypes[int(v["archetype_index"])] = true
        heights[int(v["height_floors"])] = true
        colors[str(v["facade_color"])] = true
        seeds[int(v["seed"])] = true

    return {
        "count": variations.size(),
        "unique_seeds": seeds.size(),
        "unique_archetypes": archetypes.size(),
        "unique_heights": heights.size(),
        "unique_colors": colors.size(),
        "variations": variations
    }
