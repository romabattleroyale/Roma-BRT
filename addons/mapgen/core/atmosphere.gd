@tool
class_name MapAtmosphere
extends RefCounted
## Sun + sky + fog + tonemapping.
##
## This file is doing more for perceived realism than the terrain generator is.
## A low sun, aerial-perspective fog and a filmic tonemap will make plain noise
## terrain look like a landscape; a flat overhead white light will make the best
## heightfield in the world look like a clay model.


static func build_sun(s: MapGenSettings) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# x = -elevation aims the light down from the sky, y = compass azimuth.
	sun.rotation_degrees = Vector3(-s.sun_elevation, s.sun_azimuth, 0.0)
	sun.light_color = s.sun_color
	sun.light_energy = s.sun_energy
	# A non-zero angular size gives penumbrae that widen with distance from the
	# occluder. Real sun shadows are never uniformly hard.
	sun.light_angular_distance = s.sun_angular_size
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = clampf(s.map_size * 0.45, 150.0, 2000.0)
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.42
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_pancake_size = 40.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.4
	return sun


static func build_environment(s: MapGenSettings, hf: MapHeightfield) -> WorldEnvironment:
	var env := Environment.new()

	var sky_mat := PhysicalSkyMaterial.new()
	# Turbidity is the haze dial. Low = thin alpine air, high = humid and hazy.
	sky_mat.turbidity = 3.0 if not s.fog_enabled else 5.0
	sky_mat.rayleigh_coefficient = 2.0
	sky_mat.mie_coefficient = 0.008
	sky_mat.mie_eccentricity = 0.78
	sky_mat.sun_disk_scale = 1.4
	# Everything below the horizon is this colour, and a bounded map always
	# shows some of it past its own edge. Matching it to the haze makes the map
	# border dissolve into distance instead of ending at a dark void.
	sky_mat.ground_color = (s.fog_color * 0.85) if s.fog_enabled else Color(0.34, 0.36, 0.34)
	sky_mat.energy_multiplier = 1.0

	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.2
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# Filmic tonemapping. Without it, sunlit snow and specular water clip to
	# flat white and the whole image reads as "engine default".
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	# White point, not a brightness dial: pushing it high compresses the whole
	# range downward and everything comes out muddy.
	env.tonemap_white = 2.0

	# ---- fog ---------------------------------------------------------------
	env.fog_enabled = s.fog_enabled
	if s.fog_enabled:
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = s.fog_color
		env.fog_light_energy = 1.0
		env.fog_sun_scatter = 0.35
		env.fog_density = s.fog_density
		# Aerial perspective tints distant geometry toward the sky colour. This
		# is the cue the eye uses to judge scale; without it a 2 km mountain
		# looks like a 20 m pile of dirt.
		env.fog_aerial_perspective = 0.6
		env.fog_sky_affect = 0.32
		# Fog pools in the valleys instead of sitting as a uniform grey wash.
		env.fog_height = hf.water_level + s.fog_height
		env.fog_height_density = s.fog_height_density

		env.volumetric_fog_enabled = s.volumetric_fog
		if s.volumetric_fog:
			env.volumetric_fog_density = s.volumetric_fog_density
			env.volumetric_fog_albedo = s.fog_color
			env.volumetric_fog_anisotropy = 0.35
			env.volumetric_fog_length = clampf(s.map_size * 0.25, 64.0, 1024.0)
			env.volumetric_fog_detail_spread = 2.0
			env.volumetric_fog_gi_inject = 0.6
			env.volumetric_fog_ambient_inject = 0.3
			env.volumetric_fog_sky_affect = 0.5

	# ---- global illumination ----------------------------------------------
	if s.global_illumination:
		env.sdfgi_enabled = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = clampf(s.map_size / 256.0, 0.5, 8.0)
		env.sdfgi_use_occlusion = true
		env.sdfgi_bounce_feedback = 0.5
		env.sdfgi_energy = 1.0
		env.ssil_enabled = false

	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.6
	env.ssao_power = 1.5

	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.06
	env.adjustment_brightness = 1.0

	var we := WorldEnvironment.new()
	we.name = "Atmosphere"
	we.environment = env
	return we
