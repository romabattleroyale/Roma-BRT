shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Instanced foliage. Two things do the heavy lifting here:
//   - per-instance wind phase from INSTANCE_CUSTOM, so a forest does not sway
//     as one rigid block
//   - per-instance colour jitter, so a MultiMesh of identical meshes stops
//     looking like a MultiMesh of identical meshes

uniform vec3 tint_a : source_color = vec3(0.16, 0.26, 0.11);
uniform vec3 tint_b : source_color = vec3(0.31, 0.40, 0.16);
uniform float wind_strength : hint_range(0.0, 3.0) = 0.55;
uniform float wind_speed : hint_range(0.0, 8.0) = 1.1;
uniform float wind_gust_scale = 0.012;
uniform float bend_height = 3.0;

uniform bool snow_enabled = true;
uniform float snow_line_y = 1e9;
uniform float snow_blend_y = 20.0;
uniform vec3 snow_color : source_color = vec3(0.93, 0.95, 1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.85;

// Distance fade by shrinking the instance into the ground rather than fading
// alpha. GeometryInstance3D's FADE_SELF needs a transparent material, and this
// shader is deliberately opaque -- using FADE_SELF here makes ground cover
// vanish entirely instead of fading. Shrinking costs nothing, needs no
// sorting, and reads better than a hard pop.
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;

uniform float roughness_value : hint_range(0.0, 1.0) = 0.82;
uniform float translucency : hint_range(0.0, 1.0) = 0.35;

varying float v_variation;
varying float v_world_y;
varying float v_up;


void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;

	if (fade_end > 0.0) {
		// Instance origin in view space: its length is the camera distance,
		// and it stays correct regardless of how world space is anchored.
		float cam_d = length(MODELVIEW_MATRIX[3].xyz);
		// Mesh origins sit at the base of the plant, so scaling VERTEX sinks it
		// into the ground rather than shrinking it toward its own middle.
		VERTEX *= 1.0 - smoothstep(fade_start, fade_end, cam_d);
	}

	float phase = INSTANCE_CUSTOM.x * 6.28318;
	v_variation = INSTANCE_CUSTOM.y;

	// Gusts travel across the map instead of every plant moving in lockstep.
	float gust = sin((origin.x + origin.z) * wind_gust_scale + TIME * wind_speed * 0.37);
	float amp = wind_strength * (0.6 + 0.4 * gust);

	// Only the upper part of the plant bends; the base stays planted.
	float infl = clamp(VERTEX.y / max(bend_height, 0.01), 0.0, 1.0);
	infl *= infl;

	VERTEX.x += sin(TIME * wind_speed + phase) * infl * amp;
	VERTEX.z += cos(TIME * wind_speed * 0.83 + phase * 1.7) * infl * amp * 0.7;

	v_world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	v_up = clamp(NORMAL.y, 0.0, 1.0);
}


void fragment() {
	vec3 base = mix(tint_a, tint_b, clamp(v_variation, 0.0, 1.0));
	// COLOR carries the mesh's own vertex colours, which is how a single
	// surface can hold a brown trunk and green foliage.
	vec3 albedo = COLOR.rgb * base * 2.0;

	if (snow_enabled) {
		float s = smoothstep(snow_line_y, snow_line_y + snow_blend_y, v_world_y);
		// Snow settles on upward-facing surfaces only.
		s *= v_up * snow_amount;
		albedo = mix(albedo, snow_color, clamp(s, 0.0, 1.0));
	}

	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.25;
	// Cheap stand-in for leaf subsurface scattering: leaves lit from behind
	// glow instead of going black, which is most of why foliage looks alive.
	BACKLIGHT = vec3(translucency) * base;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
