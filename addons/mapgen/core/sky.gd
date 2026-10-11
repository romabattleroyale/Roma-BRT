@tool
class_name MapSky
extends Node3D
## The sky and everything in it: a gradient atmosphere, the sun, up to four
## ray-traced moons, a star field, and the day-night cycle that moves them.
##
## Adapted from the ExoSky node in /data/space-colony-v3. That sky was built for
## one alien world with two named moons and a story beat to hit; this one has to
## take a seed and a moon count and produce something plausible, so the moons
## are generated rather than authored and the palette is a preset.
##
## What is kept, because it is the good part:
##
##   The colouring model. Three gradients sampled by one number -- how high the
##   sun stands -- and added together. Not physical, but it carries a sky from
##   noon through dusk to black night on a single input, and it is trivially
##   re-skinned for an alien world.
##
##   Ray-traced moons. Intersecting a sphere per pixel is what buys the phases,
##   the crisp limb and the eclipses: the same intersection that draws the moon
##   also gives the normal it is lit by.
##
##   The orbital model. Each moon rides a great circle inclined to the sun's
##   path about a node that drifts. That drift is why eclipses arrive in seasons
##   rather than on every conjunction like clockwork.

## Emitted when an eclipse is about to begin, once per eclipse.
signal eclipse_incoming(seconds_until: float)
signal eclipse_started()
signal eclipse_ended()

const MAX_MOONS := 4
const MOON_NAMES := ["Kesh", "Vel", "Tor", "Ilm"]

## Where a scheduled eclipse is allowed to land in the day. Well inside
## daylight -- an eclipse at night is a moon passing an empty patch of sky.
const ECLIPSE_WINDOW := Vector2(0.34, 0.66)
## How far ahead the sky is read when looking for eclipses, in seconds.
const ECLIPSE_HORIZON := 7200.0
const ECLIPSE_WARNING := 30.0

## 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset.
var time_of_day := 0.35
## Seconds since the world started. Moons are placed from this rather than from
## time_of_day, because their periods are nothing like a day -- which is the
## whole reason an eclipse is an event.
var elapsed := 0.0
## Stop the clock. Previews and screenshots want a sky that holds still.
var paused := false

## What a solar panel would see, 0-1. Falls off through dusk, cut by an eclipse.
var daylight := 1.0
## How much of the sun is covered right now, 0-1.
var eclipse := 0.0
## Every eclipse this world will see, as elapsed seconds. Empty in the worlds
## that never get one.
var eclipse_times: PackedFloat32Array = []
var eclipse_at := -1.0

var sun: DirectionalLight3D
## Skylight by day, moonlight by night: the second light that keeps the unlit
## sides of things from going to flat black.
var fill: DirectionalLight3D
var environment: Environment

var _s: MapGenSettings
var _hf: MapHeightfield
var _mat: ShaderMaterial
var _moons: Array[Dictionary] = []
var _sun_dir := Vector3.UP
var _eclipse_called := false
var _next_eclipse := -1
var _was_eclipsed := false


# ---------------------------------------------------------------------------
# palettes
# ---------------------------------------------------------------------------

## Each palette is the six or so colours the three gradients are built from.
## Swapping one is the whole difference between an Earth sky and an alien one.
const PALETTES := {
	"Earth": {
		"night": Color(0.008, 0.011, 0.026), "dusk_sky": Color(0.09, 0.10, 0.17),
		"day_sky": Color(0.20, 0.36, 0.62),
		"night_haze": Color(0.016, 0.019, 0.038), "dusk_haze": Color(0.62, 0.30, 0.16),
		"day_haze": Color(0.56, 0.68, 0.86),
		"sun_glow_dusk": Color(0.85, 0.42, 0.18), "sun_glow_day": Color(0.72, 0.72, 0.62),
		"sun_disc": Color(1.00, 0.97, 0.90), "sun_low": Color(1.00, 0.55, 0.28),
		"fog_day": Color(0.62, 0.69, 0.78), "fog_night": Color(0.05, 0.06, 0.11),
		"galaxy": Color(0.36, 0.34, 0.52), "star_exposure": 1.0,
	},
	"Alien": {
		"night": Color(0.012, 0.014, 0.030), "dusk_sky": Color(0.10, 0.09, 0.14),
		"day_sky": Color(0.42, 0.34, 0.28),
		"night_haze": Color(0.02, 0.022, 0.04), "dusk_haze": Color(0.42, 0.16, 0.12),
		"day_haze": Color(0.50, 0.36, 0.28),
		"sun_glow_dusk": Color(0.30, 0.42, 0.62), "sun_glow_day": Color(0.55, 0.44, 0.32),
		"sun_disc": Color(1.00, 0.95, 0.88), "sun_low": Color(1.00, 0.52, 0.30),
		"fog_day": Color(0.82, 0.55, 0.42), "fog_night": Color(0.06, 0.07, 0.12),
		"galaxy": Color(0.36, 0.34, 0.52), "star_exposure": 1.15,
	},
	"Twilight": {
		"night": Color(0.014, 0.010, 0.034), "dusk_sky": Color(0.14, 0.08, 0.22),
		"day_sky": Color(0.24, 0.24, 0.48),
		"night_haze": Color(0.03, 0.02, 0.06), "dusk_haze": Color(0.52, 0.20, 0.44),
		"day_haze": Color(0.46, 0.42, 0.68),
		"sun_glow_dusk": Color(0.72, 0.28, 0.52), "sun_glow_day": Color(0.58, 0.50, 0.72),
		"sun_disc": Color(0.98, 0.86, 0.94), "sun_low": Color(0.92, 0.40, 0.52),
		"fog_day": Color(0.58, 0.52, 0.74), "fog_night": Color(0.06, 0.05, 0.13),
		"galaxy": Color(0.48, 0.36, 0.62), "star_exposure": 1.3,
	},
	"Thin air": {
		"night": Color(0.004, 0.005, 0.012), "dusk_sky": Color(0.05, 0.06, 0.11),
		"day_sky": Color(0.09, 0.18, 0.40),
		"night_haze": Color(0.008, 0.010, 0.020), "dusk_haze": Color(0.44, 0.24, 0.20),
		"day_haze": Color(0.30, 0.44, 0.66),
		"sun_glow_dusk": Color(0.72, 0.40, 0.24), "sun_glow_day": Color(0.62, 0.66, 0.66),
		"sun_disc": Color(1.00, 0.99, 0.96), "sun_low": Color(1.00, 0.62, 0.36),
		"fog_day": Color(0.52, 0.62, 0.76), "fog_night": Color(0.03, 0.04, 0.08),
		"galaxy": Color(0.42, 0.40, 0.58), "star_exposure": 1.6,
	},
}


static func palette_names() -> PackedStringArray:
	return PackedStringArray(PALETTES.keys())


# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------

func setup(s: MapGenSettings, hf: MapHeightfield) -> void:
	_s = s
	_hf = hf
	name = "Sky"
	paused = not s.day_night_enabled

	var rng := RandomNumberGenerator.new()
	rng.seed = s.seed + 7717
	_build_moons(rng)

	time_of_day = fposmod(s.time_of_day, 1.0)
	elapsed = time_of_day * _day_seconds()
	_schedule_eclipse(rng)

	_build_environment()
	_build_lights()
	_update()
	set_process(true)


func _build_moons(rng: RandomNumberGenerator) -> void:
	_moons.clear()
	var count: int = clampi(_s.moon_count, 0, MAX_MOONS)
	for i in count:
		var t := float(i) / float(maxi(MAX_MOONS - 1, 1))
		var m := {
			"name": MOON_NAMES[i],
			# The first moon is the big one; later ones are smaller and dimmer,
			# so a four-moon sky reads as a hierarchy rather than as clutter.
			"radius": lerpf(0.062, 0.026, t) * rng.randf_range(0.85, 1.15),
			"exposure": lerpf(1.1, 0.45, t) * rng.randf_range(0.85, 1.15),
			"detail": lerpf(1.0, 0.6, t),
			"tint": Color(0.80, 0.74, 0.68).lerp(
					Color(0.60, 0.66, 0.80), rng.randf()),
			# Periods are set relative to the day, so a longer day does not turn
			# the moons into a strobe.
			"period": _day_seconds() * rng.randf_range(0.55, 2.6),
			"incl": rng.randf_range(6.0, 24.0),
			"phase": rng.randf(),
			"node_phase": rng.randf(),
		}
		m["node_period"] = float(m.period) * rng.randf_range(4.0, 12.0)
		_moons.append(m)


func _day_seconds() -> float:
	return maxf(_s.day_length_seconds, 5.0)


## Sun altitude at local noon. With the cycle off the sun is simply parked at
## `sun_elevation`, which is what the rest of the addon has always meant by it.
func _noon_altitude() -> float:
	return _s.noon_altitude if _s.day_night_enabled else _s.sun_elevation


# ---------------------------------------------------------------------------
# eclipses
# ---------------------------------------------------------------------------

## Decides whether this world ever sees an eclipse, and when.
##
## Left purely to the orbits, an eclipse is not a chance event: two circles
## drifting past each other line up sooner or later in every world. So the roll
## is explicit and the geometry is then made to agree with it -- every moon is
## locked off the sun, and if the roll wins, one of them is aimed at a chosen
## daylight moment. The schedule is read back out of the orbits afterwards, so
## what gets announced is what actually happens.
func _schedule_eclipse(rng: RandomNumberGenerator) -> void:
	eclipse_times = PackedFloat32Array()
	for m in _moons:
		_lock_off_sun(m)
	if _moons.is_empty() or rng.randf() >= _s.eclipse_chance:
		return

	var chosen: Dictionary = _moons[rng.randi() % _moons.size()]
	var day := _day_seconds()
	var t := (float(rng.randi_range(1, 2))
			+ rng.randf_range(ECLIPSE_WINDOW.x, ECLIPSE_WINDOW.y)) * day
	# Both phases are free -- nothing else reads them -- so solve them backwards
	# from the moment it should happen. At t, put the moon at the sun's
	# longitude, and on a node so it crosses the sun's path rather than riding
	# over it. What you see is a real conjunction at a real node; it has just
	# been aimed.
	chosen["phase"] = fposmod(t / day - 0.25 - t / float(chosen.period), 1.0)
	chosen["node_phase"] = fposmod(t / day - 0.25 - t / float(chosen.node_period), 0.5)
	eclipse_times = _scan_eclipses()


## Re-aims a moon so it can never reach the sun, however long anyone waits.
##
## Conjunctions repeat on a fixed period. Between two of them the moon gains
## `conj * (1/period - 1/node_period)` turns on its own node, and nodes repeat
## every half turn -- so a node period making that gain a whole number of half
## turns freezes the moon's angle from its node at every conjunction it will
## ever have. Freeze it a quarter turn out and it crosses the sun's longitude a
## full inclination above or below, every time, for good.
func _lock_off_sun(m: Dictionary) -> void:
	var day := _day_seconds()
	var rate := 1.0 / float(m.period) - 1.0 / day
	if absf(rate) < 1e-9:
		return
	var conj := 1.0 / absf(rate)
	m["node_period"] = 1.0 / (1.0 / float(m.period) - 4.0 / (2.0 * conj))
	# The quarter turn has to be measured at a conjunction, not at t = 0: it is
	# only frozen between conjunctions, so where it starts depends on when the
	# first one falls. Setting it at the wrong instant is how a locked moon
	# ends up eclipsing anyway.
	var c := 0.25 + float(m.phase)
	var first := ((ceilf(c) if rate > 0.0 else floorf(c)) - c) / rate
	m["node_phase"] = fposmod(first / float(m.period) + float(m.phase)
			- first / float(m.node_period) - 0.25, 1.0)


## Reads the sky forward and records the moment of deepest cover for each
## eclipse. The same arithmetic run every frame, minus the shader and the
## lights, so the schedule is observed rather than assumed.
func _scan_eclipses() -> PackedFloat32Array:
	var found := PackedFloat32Array()
	var peak := 0.0
	var peak_at := 0.0
	var inside := false
	var t := elapsed
	var step: float = maxf(_day_seconds() / 300.0, 0.5)
	while t < elapsed + ECLIPSE_HORIZON:
		var e := _eclipse_at(t)
		if e > 0.01:
			inside = true
			if e > peak:
				peak = e
				peak_at = t
		elif inside:
			found.append(peak_at)
			inside = false
			peak = 0.0
		t += step
	if inside:
		found.append(peak_at)
	return found


func _check_eclipse_warning() -> void:
	var idx := -1
	for i in eclipse_times.size():
		if elapsed <= eclipse_times[i] + 30.0:
			idx = i
			break
	if idx != _next_eclipse:
		_next_eclipse = idx
		_eclipse_called = false
	if idx < 0:
		eclipse_at = -1.0
		return
	eclipse_at = eclipse_times[idx]
	# wind_to moves the clock in both directions -- a screenshot or a test can
	# land before an eclipse it has already passed. Winding back out of the
	# warning window has to un-announce it, or the warning fires once per world
	# and never again.
	if elapsed < eclipse_at - ECLIPSE_WARNING:
		_eclipse_called = false
	elif not _eclipse_called:
		_eclipse_called = true
		eclipse_incoming.emit(eclipse_at - elapsed)


# ---------------------------------------------------------------------------
# geometry
# ---------------------------------------------------------------------------

func _east() -> Vector3:
	return Vector3(1, 0, 0).rotated(Vector3.UP, deg_to_rad(_s.sun_azimuth))


## Where the sun stands at noon: tilted off vertical, so it crosses the sky at
## an angle and the shadows have some direction to them.
func _noon() -> Vector3:
	var alt := deg_to_rad(_noon_altitude())
	return Vector3(0, sin(alt), -cos(alt)).rotated(Vector3.UP, deg_to_rad(_s.sun_azimuth))


## The sun rides a great circle: up out of the east, over at noon, down in the
## west. Everything else here is positioned relative to it.
func _sun_direction(tod: float) -> Vector3:
	var a := (tod - 0.25) * TAU
	return (_east() * cos(a) + _noon() * sin(a)).normalized()


## A moon's direction: its own circle around the sky, tipped away from the
## sun's path by its inclination, about a node that drifts.
func _moon_direction(m: Dictionary, t: float) -> Vector3:
	var a := (t / float(m.period) + float(m.phase)) * TAU
	var node := (t / float(m.node_period) + float(m.node_phase)) * TAU
	var flat := _east() * cos(a) + _noon() * sin(a)
	var node_axis := (_east() * cos(node) + _noon() * sin(node)).normalized()
	return (Basis(node_axis, deg_to_rad(float(m.incl))) * flat).normalized()


## How much of the sun is covered at a given moment, by whichever moon is
## nearest it. Computable ahead of time, which is what lets the schedule be
## worked out up front.
func _eclipse_at(t: float) -> float:
	var sun_at := _sun_direction(fposmod(t / _day_seconds(), 1.0))
	var worst := 0.0
	for m in _moons:
		var r := float(m.radius)
		var sep := sun_at.dot(_moon_direction(m, t))
		worst = maxf(worst, smoothstep(1.0 - r * r, 1.0, sep))
	return worst


## A rotation whose +Z points along `dir`. A DirectionalLight3D shines down its
## own -Z, so pointing +Z at the sun makes it light from the right side.
static func facing(dir: Vector3) -> Basis:
	var z := dir.normalized()
	var up := Vector3.UP if absf(z.y) < 0.995 else Vector3.FORWARD
	var x := up.cross(z).normalized()
	return Basis(x, z.cross(x), z)


# ---------------------------------------------------------------------------
# construction
# ---------------------------------------------------------------------------

func _palette() -> Dictionary:
	return PALETTES.get(_s.sky_palette, PALETTES["Earth"])


static func _ramp(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop in stops:
		offsets.append(stop[0])
		colors.append(stop[1])
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


# The three ramps are all sampled by the same number: the sun's height remapped
# to 0-1, where 0 is straight down, 0.5 is exactly on the horizon and 1 is
# overhead. So the left half of every ramp is night, the middle is the few
# minutes of dusk, and the right half is day -- which is why the stops bunch up
# around the middle, where all the interesting colour lives.

func _zenith_gradient() -> GradientTexture1D:
	var p := _palette()
	var night: Color = p.night
	var dusk: Color = p.dusk_sky
	var day: Color = p.day_sky
	return _ramp([
		[0.00, night], [0.42, night], [0.48, dusk],
		[0.55, day.darkened(0.45)], [0.70, day], [1.00, day.lightened(0.06)],
	])


func _horizon_gradient() -> GradientTexture1D:
	var p := _palette()
	var night: Color = p.night_haze
	var dusk: Color = p.dusk_haze
	var day: Color = p.day_haze
	return _ramp([
		[0.00, Color(0, 0, 0)], [0.40, night], [0.49, dusk],
		[0.56, dusk.lightened(0.1)], [0.72, day], [1.00, day],
	])


func _glow_gradient() -> GradientTexture1D:
	var p := _palette()
	var dusk: Color = p.sun_glow_dusk
	var day: Color = p.sun_glow_day
	return _ramp([
		[0.00, Color(0, 0, 0)], [0.44, Color(0, 0, 0)], [0.50, dusk * 0.7],
		[0.545, dusk], [0.62, dusk.lerp(day, 0.6)], [1.00, day],
	])


func _build_environment() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://addons/mapgen/shaders/sky.gdshader")
	var p := _palette()
	_mat.set_shader_parameter("sun_zenith_gradient", _zenith_gradient())
	_mat.set_shader_parameter("view_zenith_gradient", _horizon_gradient())
	_mat.set_shader_parameter("sun_view_gradient", _glow_gradient())
	_mat.set_shader_parameter("sun_radius", _s.sun_disc_size)
	_mat.set_shader_parameter("sun_color", p.sun_disc)
	_mat.set_shader_parameter("star_exposure", _s.star_exposure * float(p.star_exposure))
	_mat.set_shader_parameter("galaxy_color", p.galaxy)
	_mat.set_shader_parameter("galaxy_strength", _s.galaxy_strength)
	_mat.set_shader_parameter("moon_count", _moons.size())

	var radii := PackedFloat32Array()
	var exposures := PackedFloat32Array()
	var details := PackedFloat32Array()
	var tints := PackedColorArray()
	for i in MAX_MOONS:
		var m: Dictionary = _moons[i] if i < _moons.size() else {
			"radius": 0.0, "exposure": 0.0, "detail": 0.0, "tint": Color.BLACK}
		radii.append(float(m.radius))
		exposures.append(float(m.exposure))
		details.append(float(m.detail))
		tints.append(m.tint)
	_mat.set_shader_parameter("moon_radius", radii)
	_mat.set_shader_parameter("moon_exposure", exposures)
	_mat.set_shader_parameter("moon_detail", details)
	_mat.set_shader_parameter("moon_tint", tints)

	var sky := Sky.new()
	sky.sky_material = _mat
	# The sky changes every frame, and its radiance is where the world's ambient
	# light comes from, so it has to be rebuilt as it goes. Incremental spreads
	# that over several frames -- invisible on something moving this slowly.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL if _s.day_night_enabled \
			else Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var we := MapAtmosphere.build_environment(_s, _hf)
	environment = we.environment
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	add_child(we)


func _build_lights() -> void:
	sun = MapAtmosphere.build_sun(_s)
	add_child(sun)
	fill = DirectionalLight3D.new()
	fill.name = "Fill"
	# No shadow: its job is to keep the unlit sides of things from going to flat
	# black, not to add a second set of shadows to reason about.
	fill.shadow_enabled = false
	fill.light_energy = 0.4
	add_child(fill)


# ---------------------------------------------------------------------------
# per frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not paused and _s != null:
		elapsed += delta * _s.time_scale
		time_of_day = fposmod(elapsed / _day_seconds(), 1.0)
		_update()


## Winds the whole sky to a given number of seconds. Sun, moons and stars all
## read off that one number, so they move together and land in the arrangement
## they would have reached on their own.
func wind_to(seconds: float) -> void:
	elapsed = maxf(seconds, 0.0)
	time_of_day = fposmod(elapsed / _day_seconds(), 1.0)
	if _mat != null:
		_update()


func set_time_of_day(t: float) -> void:
	wind_to(fposmod(t, 1.0) * _day_seconds())


func _update() -> void:
	if _mat == null:
		return
	_sun_dir = _sun_direction(time_of_day)
	_mat.set_shader_parameter("sun_dir", _sun_dir)

	var dirs := PackedVector3Array()
	var moon_dirs: Array[Vector3] = []
	for i in MAX_MOONS:
		if i < _moons.size():
			var d := _moon_direction(_moons[i], elapsed)
			dirs.append(d)
			moon_dirs.append(d)
		else:
			dirs.append(Vector3.DOWN)
	_mat.set_shader_parameter("moon_dir", dirs)

	var was := eclipse
	eclipse = _eclipse_at(elapsed)
	_mat.set_shader_parameter("eclipse", eclipse)
	if eclipse > 0.02 and not _was_eclipsed:
		_was_eclipsed = true
		eclipse_started.emit()
	elif eclipse <= 0.02 and _was_eclipsed:
		_was_eclipsed = false
		eclipse_ended.emit()
	_check_eclipse_warning()

	# The stars turn a little slower than the sun -- a sidereal day, near
	# enough. The tilt puts the pole off to one side instead of overhead.
	var spin := elapsed / (_day_seconds() * 0.997) * TAU
	var star_basis := Basis(Vector3.UP, -spin) * Basis(Vector3(1, 0, 0), deg_to_rad(32.0))
	_mat.set_shader_parameter("star_frame", star_basis.inverse())

	_update_lights(moon_dirs)


func _update_lights(moon_dirs: Array[Vector3]) -> void:
	var p := _palette()
	var alt := _sun_dir.y
	# Sunlight comes up slowly. A sun two degrees over the horizon shines
	# through a great deal more air than one overhead, so ramping to full over
	# the first fifteen degrees is what keeps dawn from reading as somebody
	# flicking the lights on.
	var day := smoothstep(-0.02, 0.26, alt)
	var up := clampf(alt / 0.30, 0.0, 1.0)

	sun.light_color = (p.sun_low as Color).lerp(_s.sun_color, up)
	sun.light_energy = _s.sun_energy * day * (1.0 - 0.92 * eclipse)
	sun.visible = sun.light_energy > 0.005
	sun.global_transform.basis = facing(_sun_dir)

	# The fill hands over at dusk: skylight while the sun is up, and once it is
	# down, whichever moon is highest and brightest. A night with every moon set
	# is genuinely dark, but never so dark the landscape stops reading.
	var lit_moon := Vector3.UP
	var best := -2.0
	for i in moon_dirs.size():
		var brightness: float = float(_moons[i].exposure) * moon_dirs[i].y
		if brightness > best:
			best = brightness
			lit_moon = moon_dirs[i]
	var moonlit := clampf(lit_moon.y * 3.0, 0.0, 1.0) * (1.0 - day)
	fill.global_transform.basis = facing(lit_moon if day < 0.5 else Vector3(-0.5, 0.6, 0.6))
	fill.light_color = Color(0.55, 0.65, 0.9).lerp(Color(0.62, 0.70, 1.0), 1.0 - day)
	fill.light_energy = 0.40 * day + (_s.night_fill + 0.30 * moonlit) * (1.0 - day)

	# Totality is not a dimmer switch on the sun alone: the sky stops lighting
	# the ground, and the haze stops glowing with it. Without this the sun goes
	# out and the landscape stays sitting in bright fog, which reads as a bug.
	var eclipse_dim: float = 1.0 - 0.80 * eclipse
	fill.light_energy *= eclipse_dim

	# Ambient comes off the sky itself, so night darkens the world on its own.
	# The fog has to be told, though, or the horizon keeps glowing after dark.
	if environment.fog_enabled:
		var fog_day: Color = _s.fog_color
		var fog_night: Color = p.fog_night
		var fog_dusk: Color = p.dusk_haze
		var dusk_amount := 1.0 - absf(clampf(alt, -0.25, 0.25)) / 0.25
		environment.fog_light_color = fog_night.lerp(fog_day, day).lerp(
				fog_dusk, dusk_amount * 0.55) * eclipse_dim
		environment.volumetric_fog_albedo = environment.fog_light_color

	# Colour drains out of a dark scene: at these light levels a real eye is
	# working off rods, which do not see hue. Keeping full daylight saturation
	# after dark is what makes a night render look like a day render with the
	# brightness pulled down.
	if environment.adjustment_enabled:
		var lit: float = maxf(day, 1.0 - eclipse)
		environment.adjustment_saturation = lerpf(0.45, 1.06, lit)
		environment.adjustment_brightness = lerpf(1.06, 1.0, lit)

	daylight = clampf(rad_to_deg(asin(clampf(alt, -1.0, 1.0))) / 15.0, 0.0, 1.0) \
			* (1.0 - 0.95 * eclipse)


# ---------------------------------------------------------------------------
# queries
# ---------------------------------------------------------------------------

func sun_direction() -> Vector3:
	return _sun_dir


func moon_count() -> int:
	return _moons.size()


func moon_info(i: int) -> Dictionary:
	return _moons[i] if i >= 0 and i < _moons.size() else {}


## Human-readable clock, for a HUD.
func clock() -> String:
	var minutes: int = int(time_of_day * 1440.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]
