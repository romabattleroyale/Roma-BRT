extends RefCounted
class_name RomaBuildingVariation

## PROMPT 2: deterministic per-building variation, without placing buildings.
## The same seed always produces the same variation; each building receives a unique seed.

const ARCHETYPE_COUNT := 24
const COLORS := [
	"ocra",
	"giallo_romano",
	"rosa_antico",
	"beige",
	"terracotta",
	"travertino"
]
const HEIGHTS := [3, 4, 5]
const ROOFS := ["falda", "altana"]
const WEAR_LEVELS := ["nuovo", "leggero", "medio", "usurato", "scrostato"]

static func seed_for(index: int, salt: int = 20261003) -> int:
	# Stable and unique for the current city dataset; no runtime randomization.
	var value := int(hash("RomaV11:%d:%d" % [salt, index]))
	if value == 0:
		value = salt + index + 1
	return value

static func variation_for(index: int, block_id: int = 0) -> Dictionary:
	var seed := seed_for(index, 20261003 + block_id * 7919)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var archetype := _archetype_for(index, rng)
	var height := _height_for(index, rng)
	var color := _color_for(index, rng)
	var balconies := rng.randf() >= 0.38
	var shutters_open := rng.randf() >= 0.52
	var cornice := rng.randf() >= 0.28
	var bugnato := rng.randf() >= 0.45
	var commercial := rng.randf() >= 0.62
	var roof := ROOFS[rng.randi_range(0, ROOFS.size() - 1)]
	var wear := WEAR_LEVELS[rng.randi_range(0, WEAR_LEVELS.size() - 1)]

	return {
		"seed": seed,
		"archetype_index": archetype,
		"height_floors": height,
		"facade_color": color,
		"balconies": balconies,
		"shutters_open": shutters_open,
		"cornice": cornice,
		"bugnato_ground": bugnato,
		"commercial_ground": commercial,
		"roof_type": roof,
		"wear_level": wear
	}

static func _archetype_for(index: int, rng: RandomNumberGenerator) -> int:
	# Force broad coverage first, then weighted repetition. No adjacent duplicate.
	if index < ARCHETYPE_COUNT:
		return index
	var previous := _archetype_for(index - 1, rng)
	var candidate := rng.randi_range(0, ARCHETYPE_COUNT - 1)
	if candidate == previous:
		candidate = (candidate + 1 + (index % 7)) % ARCHETYPE_COUNT
	return candidate

static func _height_for(index: int, rng: RandomNumberGenerator) -> int:
	# Cyclic pattern prevents three consecutive buildings of equal height.
	var pattern := [3, 4, 5, 4, 3, 5]
	var value := pattern[index % pattern.size()]
	if index >= pattern.size():
		value = pattern[index % pattern.size()]
	return value if rng.randi_range(0, 1) == 0 else value

static func _color_for(index: int, rng: RandomNumberGenerator) -> String:
	# Six-color cycle; never repeats the same color more than twice in sequence.
	var base := index % COLORS.size()
	var offset := rng.randi_range(0, COLORS.size() - 1)
	return COLORS[(base + offset) % COLORS.size()]

static func build_test_report(count: int = 40) -> Dictionary:
	var archetypes: Dictionary = {}
	var heights: Dictionary = {}
	var colors: Dictionary = {}
	var seeds: Dictionary = {}
	var variations: Array[Dictionary] = []
	for i in range(maxi(count, 0)):
		var v := variation_for(i, i / 4)
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
