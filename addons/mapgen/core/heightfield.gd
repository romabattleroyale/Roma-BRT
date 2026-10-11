@tool
class_name MapHeightfield
extends RefCounted
## The heightfield is the single source of truth for the map. Everything else
## (mesh, collision, water, scatter) reads from it, so they can never disagree.
##
## Pipeline, in order, because the order is what makes it look right:
##   1. warped fBm base landform
##   2. ridged multifractal mountains, masked into belts
##   3. canyon carving with strata terracing
##   4. thermal erosion  <- turns "noise" into "terrain"
##   5. water level as a height quantile, then basin deepening

const MAX_RES := 1024

var size_m: float = 1024.0
var res: int = 320            ## cells per side
var dim: int = 321            ## vertices per side (res + 1)
var cell: float = 3.2         ## metres per cell

var height := PackedFloat32Array()   ## metres, indexed [z * dim + x]
var canyon := PackedFloat32Array()   ## 0..1 canyon channel mask
var min_h := 0.0
var max_h := 0.0
var water_level := 0.0               ## metres; below min_h when lakes are off

var _s: MapGenSettings


static func _make_noise(p_seed: int, period_m: float, octaves: int, gain: float,
		lacunarity: float, ridged: bool, warp_m: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = p_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.0 / maxf(period_m, 1.0)
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED if ridged else FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_gain = gain
	n.fractal_lacunarity = lacunarity
	if warp_m > 0.0:
		n.domain_warp_enabled = true
		n.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
		n.domain_warp_amplitude = warp_m
		n.domain_warp_frequency = 0.5 / maxf(period_m, 1.0)
		n.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
		n.domain_warp_fractal_octaves = 3
	return n


func generate(s: MapGenSettings) -> void:
	_s = s
	size_m = s.map_size
	res = clampi(s.resolution, 16, MAX_RES)
	dim = res + 1
	cell = size_m / float(res)

	var count := dim * dim
	height.resize(count)
	canyon.resize(count)

	var n_base := _make_noise(s.seed + 11, s.base_scale, 5, 0.5, 2.0, false, s.warp_strength)
	var n_range := _make_noise(s.seed + 23, s.range_scale, 3, 0.5, 2.0, false, s.range_scale * 0.12)
	var n_ridge := _make_noise(s.seed + 37, s.ridge_scale, 6, 0.5, 2.15, true, s.warp_strength * 1.4)
	var n_canyon := _make_noise(s.seed + 53, s.canyon_scale, 3, 0.5, 2.0, false, s.canyon_scale * 0.22)
	var n_detail := _make_noise(s.seed + 71, 45.0, 3, 0.5, 2.0, false, 0.0)
	var n_snowbreak := _make_noise(s.seed + 89, 160.0, 3, 0.5, 2.0, false, 0.0)

	var half := size_m * 0.5
	var i := 0
	for zi in dim:
		var wz := -half + float(zi) * cell
		for xi in dim:
			var wx := -half + float(xi) * cell

			# --- base landform -------------------------------------------
			var h := n_base.get_noise_2d(wx, wz) * 0.5 + 0.5
			h = pow(h, s.valley_flatness) * 0.58

			# --- mountains ------------------------------------------------
			if s.mountain_enabled:
				var belt := smoothstep(s.range_coverage, s.range_coverage + 0.30,
						n_range.get_noise_2d(wx, wz) * 0.5 + 0.5)
				var ridge := n_ridge.get_noise_2d(wx, wz) * 0.5 + 0.5
				ridge = pow(ridge, s.ridge_sharpness)
				h += ridge * belt * s.mountain_amount

			# --- fine relief ---------------------------------------------
			h += n_detail.get_noise_2d(wx, wz) * 0.012

			# --- edge falloff --------------------------------------------
			if s.island_falloff > 0.0:
				var d: float = maxf(absf(wx), absf(wz)) / half
				h *= 1.0 - s.island_falloff * smoothstep(0.55, 1.0, d)

			# --- canyon ---------------------------------------------------
			var c := 0.0
			if s.canyon_enabled and s.canyon_depth > 0.0:
				var band := absf(n_canyon.get_noise_2d(wx, wz))
				c = 1.0 - smoothstep(0.0, maxf(s.canyon_width, 0.001), band)
				# Steepen the walls: a linear profile reads as a soft ditch.
				c = pow(c, 0.6)
				# Canyons cut plateaus, not lowlands.
				c *= smoothstep(s.canyon_min_ground, s.canyon_min_ground + 0.22, h)
				h -= c * s.canyon_depth
				if s.canyon_terraces > 1 and s.canyon_terrace_strength > 0.0:
					var t := float(s.canyon_terraces)
					var scaled := h * t
					var f := scaled - floorf(scaled)
					# Sharp riser, flat tread: rock strata, not a smooth staircase.
					var stepped := (floorf(scaled) + smoothstep(0.38, 0.62, f)) / t
					h = lerpf(h, stepped, c * s.canyon_terrace_strength)

			canyon[i] = c
			height[i] = h
			i += 1

	_normalise_to_metres(s.height_scale)

	if s.erosion_iterations > 0:
		_thermal_erode(s.erosion_iterations, s.erosion_talus, s.erosion_rate)

	_recompute_bounds()

	# --- water ---------------------------------------------------------------
	if s.lake_enabled and s.lake_coverage > 0.0:
		water_level = _height_quantile(s.lake_coverage)
		if s.lake_depth_boost > 0.0:
			_deepen_basins(s.lake_depth_boost)
			_recompute_bounds()
	else:
		# Keep the plane well below the terrain so nothing accidentally floats.
		water_level = min_h - maxf(1.0, s.height_scale * 0.05)

	# Snow-line break-up noise is consumed by the shader, but the scatter pass
	# needs the same field to keep trees out of snow, so cache it here.
	_snow_noise = n_snowbreak


var _snow_noise: FastNoiseLite


# ---------------------------------------------------------------------------
# passes
# ---------------------------------------------------------------------------

func _normalise_to_metres(scale_m: float) -> void:
	var lo := INF
	var hi := -INF
	for v in height:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var inv := 1.0 / maxf(hi - lo, 0.00001)
	for j in height.size():
		height[j] = (height[j] - lo) * inv * scale_m


## Thermal (talus) erosion. Any cell steeper than the angle of repose sheds
## material to its lowest neighbour. Cheap, stable, and it is what produces
## scree fans below cliffs and flat, deposited valley floors.
func _thermal_erode(iterations: int, talus_deg: float, rate: float) -> void:
	var talus := tan(deg_to_rad(talus_deg)) * cell
	var delta := PackedFloat32Array()
	delta.resize(height.size())

	for _it in iterations:
		delta.fill(0.0)
		for zi in range(1, dim - 1):
			var row := zi * dim
			for xi in range(1, dim - 1):
				var idx := row + xi
				var h := height[idx]

				var lowest := idx
				var drop := 0.0
				var d := h - height[idx - 1]
				if d > drop:
					drop = d
					lowest = idx - 1
				d = h - height[idx + 1]
				if d > drop:
					drop = d
					lowest = idx + 1
				d = h - height[idx - dim]
				if d > drop:
					drop = d
					lowest = idx - dim
				d = h - height[idx + dim]
				if d > drop:
					drop = d
					lowest = idx + dim

				if drop > talus:
					var moved := (drop - talus) * rate * 0.5
					delta[idx] -= moved
					delta[lowest] += moved

		for j in height.size():
			height[j] += delta[j]


func _recompute_bounds() -> void:
	min_h = INF
	max_h = -INF
	for v in height:
		min_h = minf(min_h, v)
		max_h = maxf(max_h, v)


## Water level as a quantile of the height distribution: asking for "16% of the
## map under water" gives the same lake coverage on every seed, which a fixed
## world-space water height never does.
func _height_quantile(q: float) -> float:
	var n := height.size()
	var stride: int = maxi(1, n / 40000)
	var sample := PackedFloat32Array()
	var k := 0
	while k < n:
		sample.append(height[k])
		k += stride
	sample.sort()
	var idx: int = clampi(int(float(sample.size() - 1) * clampf(q, 0.0, 1.0)), 0, sample.size() - 1)
	return sample[idx]


func _deepen_basins(boost: float) -> void:
	for j in height.size():
		var h := height[j]
		if h < water_level:
			height[j] = water_level - (water_level - h) * (1.0 + boost)


# ---------------------------------------------------------------------------
# sampling
# ---------------------------------------------------------------------------

func height_at_index(xi: int, zi: int) -> float:
	return height[clampi(zi, 0, dim - 1) * dim + clampi(xi, 0, dim - 1)]


## World-space bilinear height sample. Used by the scatter pass and by anything
## in game code that needs to sit an object on the ground without a raycast.
func height_at(wx: float, wz: float) -> float:
	var half := size_m * 0.5
	var fx := clampf((wx + half) / cell, 0.0, float(dim - 1) - 0.0001)
	var fz := clampf((wz + half) / cell, 0.0, float(dim - 1) - 0.0001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var h00 := height_at_index(x0, z0)
	var h10 := height_at_index(x0 + 1, z0)
	var h01 := height_at_index(x0, z0 + 1)
	var h11 := height_at_index(x0 + 1, z0 + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func normal_at_index(xi: int, zi: int) -> Vector3:
	var hl := height_at_index(xi - 1, zi)
	var hr := height_at_index(xi + 1, zi)
	var hd := height_at_index(xi, zi - 1)
	var hu := height_at_index(xi, zi + 1)
	return Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()


func normal_at(wx: float, wz: float) -> Vector3:
	var half := size_m * 0.5
	var xi := int(round((wx + half) / cell))
	var zi := int(round((wz + half) / cell))
	return normal_at_index(xi, zi)


## Slope in degrees from horizontal.
func slope_at(wx: float, wz: float) -> float:
	return rad_to_deg(acos(clampf(normal_at(wx, wz).y, -1.0, 1.0)))


## Height as a 0..1 fraction of the map's total relief.
func normalised_height(h: float) -> float:
	return clampf((h - min_h) / maxf(max_h - min_h, 0.0001), 0.0, 1.0)


## Snow coverage 0..1 at a point, matching what the terrain shader draws, so
## scatter and shading agree about where the snow line is.
func snow_at(wx: float, wz: float, h: float, slope_deg: float) -> float:
	if not _s.snow_enabled:
		return 0.0
	var relief: float = maxf(max_h - min_h, 0.0001)
	var break_up := 0.0
	if _snow_noise:
		break_up = _snow_noise.get_noise_2d(wx, wz) * _s.snow_noise * _s.snow_blend
	var line := _s.snow_line + break_up
	var cover := smoothstep(line, line + _s.snow_blend, (h - min_h) / relief)
	cover *= 1.0 - smoothstep(_s.snow_max_slope - 8.0, _s.snow_max_slope, slope_deg)
	return clampf(cover, 0.0, 1.0)


func aabb() -> AABB:
	var half := size_m * 0.5
	return AABB(Vector3(-half, min_h, -half), Vector3(size_m, maxf(max_h - min_h, 1.0), size_m))
