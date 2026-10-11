shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Four-layer terrain splat driven by slope, altitude and noise.
//
// The three things that decide whether terrain textures read as real:
//   1. cliffs are triplanar, so steep faces are not smeared vertically
//   2. every layer is sampled at two scales and cross-faded by camera
//      distance, which breaks the tiling grid that gives terrain away
//   3. a large-scale macro-variation multiply, so the whole surface is not
//      one flat average colour

group_uniforms Ground;
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 ground_tint : source_color = vec4(0.31, 0.36, 0.19, 1.0);
uniform float ground_tiling = 0.13;

group_uniforms Cliff;
uniform sampler2D cliff_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D cliff_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 cliff_tint : source_color = vec4(0.42, 0.40, 0.37, 1.0);
uniform float cliff_tiling = 0.055;

group_uniforms Shore;
uniform sampler2D shore_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D shore_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shore_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 shore_tint : source_color = vec4(0.62, 0.55, 0.44, 1.0);
uniform float shore_tiling = 0.18;

group_uniforms Snow;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 snow_tint : source_color = vec4(0.92, 0.94, 0.99, 1.0);
uniform float snow_tiling = 0.12;

group_uniforms Blending;
uniform sampler2D blend_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float macro_tiling = 0.0012;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.35;
uniform float detail_fade_start = 25.0;
uniform float detail_fade_end = 220.0;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;

group_uniforms Rules;
uniform float terrain_min_y = 0.0;
uniform float terrain_max_y = 200.0;
uniform float water_level = 0.0;
uniform float shore_width = 7.0;
uniform float cliff_slope_start = 31.0;   // degrees
uniform float cliff_slope_end = 55.0;
uniform bool snow_enabled = true;
uniform float snow_line : hint_range(0.0, 1.0) = 0.62;
uniform float snow_blend : hint_range(0.001, 0.5) = 0.14;
uniform float snow_max_slope = 46.0;
uniform float snow_noise_amount : hint_range(0.0, 1.0) = 0.45;

group_uniforms Strata;
uniform vec4 strata_tint : source_color = vec4(0.55, 0.40, 0.30, 1.0);
uniform float strata_scale = 0.09;
uniform float strata_strength : hint_range(0.0, 1.0) = 0.45;

group_uniforms Wetness;
uniform float wet_band = 3.0;
uniform float wet_darkening : hint_range(0.0, 1.0) = 0.55;

group_uniforms Occlusion;
uniform float cavity_strength : hint_range(0.0, 2.0) = 0.8;

group_uniforms Debug;
// 0 off | 1 splat weights (R ground, G cliff, B shore, white snow)
// 2 slope | 3 altitude | 4 world normal | 5 cavity AO | 6 camera distance
// 7 unlit albedo -- used by the exporter to bake a flat colour map
uniform int debug_view : hint_range(0, 7) = 0;

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec4 v_data;   // r = canyon mask, g = cavity AO


void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_data = COLOR;
}


// Two tiling scales cross-faded by camera distance. Near the camera you get
// the fine grain; far away the small tile would alias into a visible grid, so
// the large scale takes over.
vec4 dual_scale(sampler2D tex, vec2 uv, float far) {
	return mix(texture(tex, uv), texture(tex, uv * 0.21), far);
}

vec4 triplanar(sampler2D tex, vec3 wpos, vec3 bw, float s, float far) {
	vec4 x = dual_scale(tex, wpos.zy * s, far);
	vec4 y = dual_scale(tex, wpos.xz * s, far);
	vec4 z = dual_scale(tex, wpos.xy * s, far);
	return x * bw.x + y * bw.y + z * bw.z;
}


void fragment() {
	float cam_dist = length(VERTEX);
	float far = smoothstep(detail_fade_start, detail_fade_end, cam_dist);

	vec3 wn = normalize(v_wnormal);
	float slope_deg = degrees(acos(clamp(wn.y, -1.0, 1.0)));
	float relief = max(terrain_max_y - terrain_min_y, 0.001);
	float alt = clamp((v_world.y - terrain_min_y) / relief, 0.0, 1.0);

	// Noise used to break up every blend edge. A clean mathematical contour
	// between two materials is the fastest way to look procedural.
	float n = texture(blend_noise, v_world.xz * 0.006).r * 2.0 - 1.0;
	float n2 = texture(blend_noise, v_world.xz * 0.031).r * 2.0 - 1.0;

	// ---- weights ----------------------------------------------------------
	float w_cliff = smoothstep(cliff_slope_start + n * 6.0, cliff_slope_end + n * 6.0, slope_deg);

	float above_water = v_world.y - water_level;
	float w_shore = (1.0 - smoothstep(0.0, max(shore_width, 0.01), above_water))
			* step(-shore_width * 2.0, above_water);
	w_shore *= 1.0 - w_cliff;
	w_shore *= 0.5 + 0.5 * (n2 * 0.5 + 0.5);

	float w_snow = 0.0;
	if (snow_enabled) {
		float line = snow_line + n * snow_noise_amount * snow_blend;
		w_snow = smoothstep(line, line + snow_blend, alt);
		// Snow does not cling to near-vertical rock.
		w_snow *= 1.0 - smoothstep(snow_max_slope - 8.0, snow_max_slope, slope_deg);
	}

	float w_ground = max(1.0 - w_cliff - w_shore, 0.0);
	w_ground = max(w_ground - w_snow, 0.0);
	w_cliff = max(w_cliff - w_snow * 0.55, 0.0);
	float total = max(w_ground + w_cliff + w_shore + w_snow, 0.0001);
	w_ground /= total; w_cliff /= total; w_shore /= total; w_snow /= total;

	// ---- sampling ---------------------------------------------------------
	vec2 uv_flat = v_world.xz;
	vec3 bw = pow(abs(wn), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);

	vec4 c_ground = dual_scale(ground_albedo, uv_flat * ground_tiling, far) * ground_tint;
	vec4 c_cliff  = triplanar(cliff_albedo, v_world, bw, cliff_tiling, far) * cliff_tint;
	vec4 c_shore  = dual_scale(shore_albedo, uv_flat * shore_tiling, far) * shore_tint;
	vec4 c_snow   = dual_scale(snow_albedo, uv_flat * snow_tiling, far) * snow_tint;

	vec3 albedo = c_ground.rgb * w_ground + c_cliff.rgb * w_cliff
			+ c_shore.rgb * w_shore + c_snow.rgb * w_snow;

	vec3 n_ground = dual_scale(ground_normal, uv_flat * ground_tiling, far).rgb;
	vec3 n_cliff  = triplanar(cliff_normal, v_world, bw, cliff_tiling, far).rgb;
	vec3 n_shore  = dual_scale(shore_normal, uv_flat * shore_tiling, far).rgb;
	vec3 n_snow   = dual_scale(snow_normal, uv_flat * snow_tiling, far).rgb;
	vec3 nrm = n_ground * w_ground + n_cliff * w_cliff + n_shore * w_shore + n_snow * w_snow;

	float r_ground = dual_scale(ground_rough, uv_flat * ground_tiling, far).r;
	float r_cliff  = triplanar(cliff_rough, v_world, bw, cliff_tiling, far).r;
	float r_shore  = dual_scale(shore_rough, uv_flat * shore_tiling, far).r;
	float r_snow   = dual_scale(snow_rough, uv_flat * snow_tiling, far).r;
	float rough = r_ground * w_ground + r_cliff * w_cliff + r_shore * w_shore + r_snow * w_snow;
	rough = mix(rough, 0.55, w_snow * 0.5);

	// ---- macro variation --------------------------------------------------
	// Low-frequency multiply over everything. Without it, a large terrain reads
	// as a single flat colour no matter how good the tiling texture is.
	float macro = texture(macro_noise, v_world.xz * macro_tiling).r;
	albedo *= mix(1.0, 0.55 + macro * 0.9, macro_strength);

	// ---- canyon strata ----------------------------------------------------
	// Horizontal sedimentary banding, only inside the carved channel.
	float band = 0.5 + 0.5 * sin(v_world.y * strata_scale * 6.2831 + n2 * 0.8);
	band = smoothstep(0.35, 0.65, band);
	float strata_mask = v_data.r * strata_strength * (1.0 - w_snow);
	albedo = mix(albedo, mix(albedo, strata_tint.rgb, 0.75), band * strata_mask);

	// ---- wet shoreline ----------------------------------------------------
	float wet = 1.0 - smoothstep(0.0, max(wet_band, 0.01), above_water);
	wet = clamp(wet, 0.0, 1.0) * (1.0 - w_snow);
	albedo *= mix(1.0, 1.0 - wet_darkening, wet);
	rough = mix(rough, 0.08, wet * 0.85);

	// ---- cavity occlusion -------------------------------------------------
	float ao = clamp(1.0 - (1.0 - v_data.g) * cavity_strength, 0.0, 1.0);

	if (debug_view > 0) {
		vec3 dbg = vec3(0.0);
		if (debug_view == 1) dbg = vec3(w_ground, w_cliff, w_shore) + vec3(w_snow);
		else if (debug_view == 2) dbg = vec3(slope_deg / 90.0);
		else if (debug_view == 3) dbg = vec3(alt);
		else if (debug_view == 4) dbg = wn * 0.5 + 0.5;
		else if (debug_view == 5) dbg = vec3(v_data.g);
		else if (debug_view == 6) dbg = vec3(far);
		else dbg = albedo;
		ALBEDO = vec3(0.0);
		EMISSION = dbg;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		AO = 1.0;
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	} else {
		ALBEDO = albedo;
		ROUGHNESS = clamp(rough, 0.02, 1.0);
		SPECULAR = 0.4;
		AO = ao;
		AO_LIGHT_AFFECT = 0.6;
		NORMAL_MAP = nrm;
		NORMAL_MAP_DEPTH = normal_strength * (1.0 - far * 0.55);
	}
}
