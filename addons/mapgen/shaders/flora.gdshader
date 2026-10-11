shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Ground flora: grass, ferns, reeds and flowers.
//
// One shader for all of it, because they differ in geometry rather than in
// shading. Vertex colour carries data, not colour:
//
//   r = wind weight, 0 at the root and 1 at the tip
//   g = exposure, dark at the base of a clump and light at the tips
//   b = petal mask, 0 for stem and leaf, 1 for a bloom
//
// Colour comes from uniforms, so one flower mesh can be a whole meadow of
// different colours by varying only the per-instance data.

uniform vec3 foliage_dark : source_color = vec3(0.16, 0.24, 0.09);
uniform vec3 foliage_light : source_color = vec3(0.44, 0.52, 0.20);
/// Blooms pick a colour between these two per instance.
uniform vec3 petal_a : source_color = vec3(0.92, 0.90, 0.80);
uniform vec3 petal_b : source_color = vec3(0.86, 0.72, 0.22);
/// Kept at zero by default. Glow is enabled in the default environment, so any
/// emission on a saturated petal blooms into a halo and the flower stops
/// reading as a flower.
uniform float petal_emission : hint_range(0.0, 1.0) = 0.0;

uniform float wind_strength : hint_range(0.0, 3.0) = 0.5;
uniform float wind_speed : hint_range(0.0, 8.0) = 1.4;
uniform float bend_height = 0.5;

/// Shrink out with distance rather than popping. These meshes are opaque, so
/// GeometryInstance3D's own fade modes would make them vanish outright.
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;

uniform bool snow_enabled = true;
uniform float snow_line_y = 1e9;
uniform float snow_blend_y = 20.0;
uniform vec3 snow_color : source_color = vec3(0.93, 0.95, 1.0);

uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
uniform float translucency : hint_range(0.0, 2.0) = 0.30;

varying float v_exposure;
varying float v_petal;
varying float v_variation;
varying float v_world_y;


void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;

	if (fade_end > 0.0) {
		float cam_d = length(MODELVIEW_MATRIX[3].xyz);
		VERTEX *= 1.0 - smoothstep(fade_start, fade_end, cam_d);
	}

	float phase = INSTANCE_CUSTOM.x * 6.28318;
	v_variation = INSTANCE_CUSTOM.y;

	// Gusts travel across the map instead of every plant moving in lockstep.
	float gust = 0.6 + 0.4 * sin((origin.x + origin.z) * 0.012 + TIME * wind_speed * 0.4);
	// Wind weight is baked per vertex, so a stem bends and its root does not.
	float w = COLOR.r * COLOR.r;
	VERTEX.x += sin(TIME * wind_speed + phase) * w * wind_strength * gust;
	VERTEX.z += cos(TIME * wind_speed * 0.83 + phase * 1.7) * w * wind_strength * gust * 0.7;

	v_exposure = COLOR.g;
	v_petal = COLOR.b;
	v_world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}


void fragment() {
	vec3 leaf = mix(foliage_dark, foliage_light, clamp(v_exposure, 0.0, 1.0));
	// Vary the whole plant a little as well as the bloom, so a clump of one
	// species is not a field of identical green.
	leaf *= mix(0.85, 1.15, v_variation);
	vec3 bloom = mix(petal_a, petal_b, v_variation);

	vec3 albedo = mix(leaf, bloom, v_petal);

	if (snow_enabled) {
		float s = smoothstep(snow_line_y, snow_line_y + snow_blend_y, v_world_y);
		albedo = mix(albedo, snow_color, clamp(s, 0.0, 1.0));
	}

	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
	// Thin foliage lit from behind glows rather than going black. Petals are
	// thinner than leaves, so they pass more light.
	BACKLIGHT = albedo * translucency * mix(1.0, 1.6, v_petal);
	EMISSION = bloom * petal_emission * v_petal;
}
