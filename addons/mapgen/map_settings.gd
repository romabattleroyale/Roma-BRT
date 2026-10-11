@tool
class_name MapGenSettings
extends Resource
## All parameters for one generated map. Save as a .tres to make a reusable biome preset.

# ---------------------------------------------------------------- world
@export_group("World")
## Change this to get a completely different map with the same settings.
@export var seed: int = 1337
## Side length of the map in metres.
@export_range(64.0, 8192.0, 1.0) var map_size: float = 1024.0
## Heightfield grid cells per side. Vertices = resolution + 1. Cost is O(n^2).
@export_range(32, 1024, 1) var resolution: int = 320
## Terrain is split into this many chunks per side, for frustum culling and LOD.
@export_range(1, 16, 1) var chunks_per_side: int = 8
## Metres from the lowest to the highest point of the map.
@export_range(10.0, 2000.0, 1.0) var height_scale: float = 220.0
## Pulls the map edges down so the world ends in water/lowland instead of a cliff.
@export_range(0.0, 1.0, 0.01) var island_falloff: float = 0.25

# ---------------------------------------------------------------- toggles
@export_group("Features")
@export var mountain_enabled: bool = true
@export var canyon_enabled: bool = true
@export var lake_enabled: bool = true
@export var vegetation_enabled: bool = true
@export var snow_enabled: bool = true
@export var fog_enabled: bool = true

# ---------------------------------------------------------------- base shape
@export_group("Base Terrain")
## Metres per feature of the rolling base landform. Bigger = broader hills.
@export_range(50.0, 4000.0, 1.0) var base_scale: float = 900.0
## Domain warp, in metres. This is what turns symmetric noise blobs into
## believable, sinuous landforms. The single biggest realism lever here.
@export_range(0.0, 400.0, 1.0) var warp_strength: float = 130.0
## >1 flattens valleys and keeps relief in the highlands.
@export_range(0.5, 3.0, 0.05) var valley_flatness: float = 1.15

# ---------------------------------------------------------------- mountain
@export_group("Mountain")
## How much height the ridged mountain layer adds, relative to the base.
@export_range(0.0, 2.0, 0.01) var mountain_amount: float = 0.95
## Metres per mountain range. Controls the spacing of the ranges themselves.
@export_range(200.0, 6000.0, 10.0) var range_scale: float = 2200.0
## Higher = mountains occupy less of the map (they form belts, not a blanket).
@export_range(0.0, 1.0, 0.01) var range_coverage: float = 0.45
## Metres per ridge inside a range.
@export_range(50.0, 2000.0, 1.0) var ridge_scale: float = 520.0
## >1 sharpens peaks into blades; <1 gives rounded, older mountains.
@export_range(0.5, 4.0, 0.05) var ridge_sharpness: float = 1.6

# ---------------------------------------------------------------- erosion
@export_group("Erosion")
## Thermal erosion passes. Material above the talus angle slides downhill,
## producing scree slopes and flat valley floors. This is what makes noise
## stop looking like noise. Costs time: O(resolution^2 * iterations).
@export_range(0, 80, 1) var erosion_iterations: int = 18
## Angle of repose. Slopes steeper than this collapse.
@export_range(15.0, 75.0, 0.5) var erosion_talus: float = 38.0
## How much material moves per pass.
@export_range(0.05, 0.9, 0.01) var erosion_rate: float = 0.45

# ---------------------------------------------------------------- canyon
@export_group("Canyon")
## Fraction of the total height range the canyon cuts down.
@export_range(0.0, 0.9, 0.01) var canyon_depth: float = 0.34
## Metres per canyon meander. Bigger = longer, straighter canyons.
@export_range(200.0, 6000.0, 10.0) var canyon_scale: float = 1600.0
## Width of the cut, as a noise band. Bigger = wider canyon.
@export_range(0.01, 0.5, 0.005) var canyon_width: float = 0.12
## Number of rock strata bands in the canyon walls. 0 disables terracing.
@export_range(0, 40, 1) var canyon_terraces: int = 14
@export_range(0.0, 1.0, 0.01) var canyon_terrace_strength: float = 0.55
## Canyons only cut ground above this normalised height, so they carve
## plateaus rather than appearing in the sea.
@export_range(0.0, 1.0, 0.01) var canyon_min_ground: float = 0.18

# ---------------------------------------------------------------- lake
@export_group("Lake / Water")
## Fraction of the map that ends up under water. Water level is derived from
## this as a height quantile, so it stays stable across seeds.
@export_range(0.0, 0.8, 0.005) var lake_coverage: float = 0.16
## Deepens whatever is already below the waterline, so lakes are not puddles.
@export_range(0.0, 3.0, 0.05) var lake_depth_boost: float = 0.85
## Width in metres of the sand/shingle band around water.
@export_range(0.0, 40.0, 0.5) var shore_width: float = 7.0
@export var water_color_shallow: Color = Color(0.20, 0.42, 0.44, 1.0)
@export var water_color_deep: Color = Color(0.02, 0.09, 0.14, 1.0)
@export_range(0.0, 3.0, 0.01) var wave_height: float = 0.18

# ---------------------------------------------------------------- waterfalls
@export_group("Waterfalls")
## Falls are sited on the drainage network worked out from the finished
## terrain, not on slope alone: water arrives along a channel, goes over an
## edge, and carries on downhill afterwards. Nothing here alters the
## heightfield, so turning waterfalls on cannot change the map underneath.
@export var waterfall_enabled: bool = true
## Upper limit. You get fewer when the terrain has fewer places that qualify,
## which is the honest answer -- a flat map should not have six waterfalls.
@export_range(0, 24, 1) var waterfall_count: int = 6
## Metres of drop before a steep run of channel is worth drawing as a fall.
@export_range(2.0, 120.0, 0.5) var waterfall_min_drop: float = 8.0
## How steep that run has to be to start one. Below the angle of repose
## (`erosion_talus`) you are picking out rapids rather than waterfalls.
@export_range(25.0, 80.0, 1.0) var waterfall_min_slope: float = 45.0
## Catchment a channel needs before it counts as a stream, as a fraction of the
## map's cells. The single biggest lever on how many falls you get: lower finds
## smaller headwater streams, higher keeps only the main rivers.
@export_range(0.0002, 0.02, 0.0002) var waterfall_catchment: float = 0.002
## Width in metres of a fall right at the catchment threshold. Bigger streams
## scale up from here with the square root of their catchment.
@export_range(0.5, 20.0, 0.1) var waterfall_width: float = 3.5
## Multiplier on how fast the water appears to move.
@export_range(0.0, 4.0, 0.05) var waterfall_flow_speed: float = 1.0
## Spray at the plunge. A handful of billboards per fall, lit rather than
## unshaded so it does not glow at night.
@export var waterfall_mist: bool = true

# ---------------------------------------------------------------- snow
@export_group("Snow")
## Snow line as a fraction of total height. 0 = snow everywhere.
@export_range(0.0, 1.0, 0.01) var snow_line: float = 0.62
## Vertical softness of the snow line, as a fraction of total height.
@export_range(0.005, 0.5, 0.005) var snow_blend: float = 0.14
## Snow will not stick to slopes steeper than this. Bare rock shows through.
@export_range(10.0, 89.0, 1.0) var snow_max_slope: float = 46.0
## Noise break-up of the snow line so it is not a clean contour ring.
@export_range(0.0, 1.0, 0.01) var snow_noise: float = 0.45

# ---------------------------------------------------------------- vegetation
@export_group("Vegetation")
## Placement *attempts* per square kilometre. Scatter walks a jittered grid at
## this density, then the slope / altitude / water / clump rules reject some, so
## the final count is lower. MapGenerator reports what actually landed.
@export_range(0.0, 60000.0, 100.0) var tree_density: float = 9000.0
## Grass tuft attempts per square kilometre. 450k is roughly 1.5 m spacing,
## which reads as meadow on foot without blowing the instance budget. Tufts are
## culled at 78 m and shrink into the ground before that, so raising this costs
## generation time and memory rather than frame time.
@export_range(0.0, 1600000.0, 1000.0) var grass_density: float = 700000.0
## Rock placement attempts per square kilometre. Split between boulders,
## scree on steep ground, and sparse outcrops -- see MapScatter.default_species.
@export_range(0.0, 40000.0, 100.0) var rock_density: float = 2400.0
## Trees will not grow on slopes steeper than this.
@export_range(5.0, 80.0, 1.0) var tree_max_slope: float = 31.0
## Upper tree line, as a fraction of total height.
@export_range(0.0, 1.0, 0.01) var tree_line: float = 0.66
## Metres of bare ground kept between the waterline and the first tree.
@export_range(0.0, 60.0, 0.5) var tree_water_margin: float = 4.0
## Metres per clump of forest. Uniform scatter is the classic "fake" tell;
## real vegetation clusters. Bigger = larger, sparser forests.
@export_range(50.0, 2000.0, 10.0) var clump_scale: float = 420.0
## 0 = perfectly even scatter, 1 = dense clumps with real clearings.
@export_range(0.0, 1.0, 0.01) var clump_contrast: float = 0.7
@export_range(0.0, 3.0, 0.01) var wind_strength: float = 0.55

# ---------------------------------------------------------------- sky
@export_group("Sky")
## Run a day-night cycle. With it off the sun is parked at `sun_elevation`,
## which is what the rest of the addon has always meant by that setting.
@export var day_night_enabled: bool = true
## 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset.
@export_range(0.0, 1.0, 0.001) var time_of_day: float = 0.35
## Real seconds in one full day. Ten minutes reads as a cycle you can watch;
## an hour reads as weather.
@export_range(20.0, 7200.0, 5.0) var day_length_seconds: float = 600.0
## Multiplier on the clock, for fast-forwarding without changing day length.
@export_range(0.0, 200.0, 0.5) var time_scale: float = 1.0
## Sun altitude at local noon, used when the cycle is running. Much above 60
## and the shadows flatten out for most of the day.
@export_range(5.0, 89.0, 0.5) var noon_altitude: float = 58.0
## How many moons hang in the sky. The first is the largest; later ones are
## smaller and dimmer so four reads as a hierarchy rather than as clutter.
@export_range(0, 4, 1) var moon_count: int = 1
@export_enum("Earth", "Alien", "Twilight", "Thin air") var sky_palette: String = "Earth"
@export_range(0.0, 4.0, 0.05) var star_exposure: float = 1.0
@export_range(0.0, 3.0, 0.05) var galaxy_strength: float = 1.0
@export_range(0.005, 0.15, 0.001) var sun_disc_size: float = 0.032
## Odds this world ever sees a solar eclipse. Left to the orbits alone an
## eclipse is not a chance event -- two drifting circles line up sooner or
## later everywhere -- so the roll is explicit and the geometry is made to
## agree with it.
@export_range(0.0, 1.0, 0.01) var eclipse_chance: float = 0.25
## Floor on the night fill light. There for the player rather than for physics:
## a landscape nobody can make out is not atmospheric, it is broken.
@export_range(0.0, 1.0, 0.01) var night_fill: float = 0.14

# ---------------------------------------------------------------- atmosphere
@export_group("Atmosphere")
## Sun elevation in degrees, used when the day-night cycle is off. Low sun
## (8-20 deg) gives long shadows and rim light and does more for realism than
## any amount of extra polygons. With the cycle on, see `noon_altitude`.
@export_range(-10.0, 90.0, 0.5) var sun_elevation: float = 22.0
@export_range(-180.0, 180.0, 1.0) var sun_azimuth: float = 135.0
@export var sun_color: Color = Color(1.0, 0.89, 0.75, 1.0)
@export_range(0.0, 16.0, 0.05) var sun_energy: float = 3.2
## Angular size of the sun. >0 gives soft, distance-correct shadow penumbrae.
@export_range(0.0, 10.0, 0.05) var sun_angular_size: float = 0.7
## Depth fog per metre. Fog cover at distance d is 1 - exp(-density * d), so
## 0.0016 leaves roughly half the fog at 450 m: haze, not soup. Anything above
## ~0.01 will bury a 1 km map completely.
@export_range(0.0, 0.05, 0.0001) var fog_density: float = 0.0016
@export var fog_color: Color = Color(0.62, 0.69, 0.78, 1.0)
## Metres above the waterline below which fog pools -- valley fog at dawn.
@export_range(-200.0, 800.0, 1.0) var fog_height: float = 30.0
## How fast fog thickens below fog_height, per metre. This compounds with
## fog_density; past ~0.04 the valleys turn into an opaque white sea.
@export_range(0.0, 0.2, 0.001) var fog_height_density: float = 0.018
## Light-scattering fog volume. Expensive but gives god rays through trees.
@export var volumetric_fog: bool = true
@export_range(0.0, 0.2, 0.0005) var volumetric_fog_density: float = 0.003
## Screen-space + SDFGI global illumination. Big quality win, costs frame time.
@export var global_illumination: bool = true

# ---------------------------------------------------------------- output
@export_group("Output")
## Give generated nodes an owner so they are saved into the .tscn. Off by
## default: keeps scene files small and regeneration cheap.
@export var bake_into_scene: bool = false
@export var generate_collision: bool = true


func duplicate_settings() -> MapGenSettings:
	return duplicate(true) as MapGenSettings


## Overwrite every setting here with another resource's, in place. A copy
## rather than a swap because whoever is generating holds a reference to this
## exact object: MapGenerator.settings, the demo and the dock all point at it.
func copy_from(other: MapGenSettings) -> void:
	if other == null:
		return
	for prop in get_property_list():
		var usage: int = prop.usage
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 \
				and (usage & PROPERTY_USAGE_STORAGE) != 0:
			set(prop.name, other.get(prop.name))


## Convenience for the dock and for scripted map generation.
func randomize_seed() -> void:
	seed = randi()
