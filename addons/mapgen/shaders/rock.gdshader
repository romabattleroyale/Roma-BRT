shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Rock surfacing.
//
// Triplanar in *world* space, deliberately: adjacent boulders then sample
// different regions of the same texture, so a field of them does not read as
// the same decal stamped over and over. It also keeps texel density constant in
// world units, so a scaled-up instance gets more detail rather than a blurrier
// version of the same detail.
//
// Three things beyond the base material do most of the work:
//   - moss on upward faces, weighted toward crevices where moisture sits
//   - the base tinting into soil, which is what makes a rock read as embedded
//     in the ground rather than dropped onto it
//   - cavity occlusion baked per vertex, darkening the gaps between facets

group_uniforms Rock;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 rock_tint : source_color = vec4(1.0, 0.99, 0.96, 1.0);
/// World metres per texture tile.
uniform float rock_tiling = 0.85;
uniform float blend_sharpness : hint_range(1.0, 12.0) = 4.0;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;

group_uniforms Moss;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 moss_tint : source_color = vec4(0.78, 0.86, 0.62, 1.0);
uniform float moss_tiling = 0.55;
uniform float moss_strength : hint_range(0.0, 1.0) = 0.32;
/// Up-ness where moss starts and where it takes over completely.
uniform float moss_start : hint_range(-1.0, 1.0) = 0.35;
uniform float moss_end : hint_range(-1.0, 1.0) = 0.95;
/// Break-up so the moss line is not a clean latitude ring around the rock.
uniform float moss_noise : hint_range(0.0, 1.0) = 0.55;
/// Extra moss in crevices, where water lingers.
uniform float moss_in_cavities : hint_range(0.0, 2.0) = 0.30;

group_uniforms Soil;
uniform vec4 soil_color : source_color = vec4(0.20, 0.18, 0.13, 1.0);
/// Fraction of the rock's height over which it blends into the ground.
uniform float soil_height : hint_range(0.0, 1.0) = 0.16;
uniform float soil_strength : hint_range(0.0, 1.0) = 0.8;

group_uniforms Snow;
uniform bool snow_enabled = true;
uniform float snow_line_y = 1e9;
uniform float snow_blend_y = 20.0;
uniform vec3 snow_color : source_color = vec3(0.92, 0.95, 1.0);
uniform float snow_max_slope_dot : hint_range(0.0, 1.0) = 0.35;

group_uniforms Detail;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float macro_tiling = 0.035;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.42;
uniform float detail_fade_start = 12.0;
uniform float detail_fade_end = 90.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.9;

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec4 v_data;      // r = cavity AO, g = colour variation, b = height up the rock
varying float v_instance;


void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_data = COLOR;
	v_instance = INSTANCE_CUSTOM.y;
}


// Two tiling scales cross-faded by camera distance: the fine scale aliases into
// a visible grid at range, the coarse one has no detail up close.
vec4 dual(sampler2D tex, vec2 uv, float far) {
	return mix(texture(tex, uv), texture(tex, uv * 0.23), far);
}

vec4 triplanar(sampler2D tex, vec3 wpos, vec3 bw, float s, float far) {
	return dual(tex, wpos.zy * s, far) * bw.x
		 + dual(tex, wpos.xz * s, far) * bw.y
		 + dual(tex, wpos.xy * s, far) * bw.z;
}

// Triplanar normal mapping, whiteout blend, resolved in WORLD space.
//
// Writing a triplanar-sampled normal to NORMAL_MAP does not work: Godot
// interprets NORMAL_MAP in the mesh's tangent frame, which here comes from
// spherical UVs and therefore rotates arbitrarily across the rock, while the
// sampled normal is in one of three world-axis frames. The two disagree
// everywhere, the shading normal ends up close to random, and the rock comes
// out dark and crawling with noise. Resolving in world space and handing the
// result to NORMAL (which Godot expects in view space) sidesteps the tangent
// frame entirely.
vec3 triplanar_normal(sampler2D tex, vec3 wpos, vec3 wn, vec3 bw, float s, float far) {
	vec3 nx = dual(tex, wpos.zy * s, far).rgb * 2.0 - 1.0;
	vec3 ny = dual(tex, wpos.xz * s, far).rgb * 2.0 - 1.0;
	vec3 nz = dual(tex, wpos.xy * s, far).rgb * 2.0 - 1.0;
	nx = vec3(nx.xy + wn.zy, abs(nx.z) * wn.x);
	ny = vec3(ny.xy + wn.xz, abs(ny.z) * wn.y);
	nz = vec3(nz.xy + wn.xy, abs(nz.z) * wn.z);
	return normalize(nx.zyx * bw.x + ny.xzy * bw.y + nz.xyz * bw.z);
}


void fragment() {
	float far = smoothstep(detail_fade_start, detail_fade_end, length(VERTEX));

	vec3 wn = normalize(v_wnormal);
	vec3 bw = pow(abs(wn), vec3(blend_sharpness));
	bw /= (bw.x + bw.y + bw.z);

	float rs = 1.0 / max(rock_tiling, 0.01);
	float ms = 1.0 / max(moss_tiling, 0.01);

	vec3 rock = triplanar(rock_albedo, v_world, bw, rs, far).rgb * rock_tint.rgb;
	vec3 rock_n = triplanar_normal(rock_normal, v_world, wn, bw, rs, far);
	float rock_r = triplanar(rock_rough, v_world, bw, rs, far).r;

	// ---- colour variation ----------------------------------------------
	// Per-vertex large-scale noise plus a per-instance offset, so no two rocks
	// in a scatter are the same shade of grey.
	float macro = texture(macro_noise, v_world.xz * macro_tiling).r;
	float shade = mix(1.0, 0.62 + macro * 0.76, macro_strength);
	shade *= mix(0.88, 1.12, v_data.g);
	shade *= mix(0.90, 1.10, v_instance);
	rock *= shade;

	// ---- moss ------------------------------------------------------------
	// Two frequencies of break-up: the coarse one decides which parts of the
	// rock the moss has colonised at all, the fine one gives its edge the
	// ragged margin that a single smooth threshold never has.
	float n = texture(macro_noise, v_world.xz * 0.6 + v_world.y * 0.3).r * 2.0 - 1.0;
	float nf = texture(macro_noise, v_world.xz * 3.1 - v_world.y * 1.7).r * 2.0 - 1.0;
	float upness = wn.y + (n * 0.65 + nf * 0.35) * moss_noise * 0.55;
	float moss_w = smoothstep(moss_start, moss_end, upness) * moss_strength;
	// Crevices hold damp, so moss creeps into them even off the top faces.
	moss_w *= clamp(1.0 + (1.0 - v_data.r) * moss_in_cavities, 0.0, 2.0);
	moss_w = clamp(moss_w, 0.0, 1.0);

	vec3 moss = triplanar(moss_albedo, v_world, bw, ms, far).rgb * moss_tint.rgb;
	vec3 moss_n = triplanar_normal(moss_normal, v_world, wn, bw, ms, far);

	vec3 albedo = mix(rock, moss, moss_w);
	vec3 nrm = normalize(mix(rock_n, moss_n, moss_w));
	float rough = mix(rock_r, 0.95, moss_w);

	// ---- buried base -----------------------------------------------------
	// Without this a rock reads as dropped on the ground rather than sitting in
	// it, however well the geometry is bedded in.
	float soil = 1.0 - smoothstep(0.0, max(soil_height, 0.001), v_data.b);
	soil *= soil_strength;
	albedo = mix(albedo, soil_color.rgb, soil);
	rough = mix(rough, 0.98, soil);

	// ---- snow ------------------------------------------------------------
	if (snow_enabled) {
		float s = smoothstep(snow_line_y, snow_line_y + snow_blend_y, v_world.y);
		// Snow will not hold on a near-vertical face.
		s *= smoothstep(snow_max_slope_dot, snow_max_slope_dot + 0.35, wn.y + n * 0.15);
		albedo = mix(albedo, snow_color, clamp(s, 0.0, 1.0));
		rough = mix(rough, 0.6, clamp(s, 0.0, 1.0));
	}

	// Ease the perturbation back toward the geometric normal with distance and
	// with normal_strength, then hand it over in view space.
	vec3 shaped = normalize(mix(wn, nrm, normal_strength * (1.0 - far * 0.5)));

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.15, 1.0);
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(shaped, 0.0)).xyz);
	AO = mix(1.0, v_data.r, ao_strength);
	AO_LIGHT_AFFECT = 0.25;
}
