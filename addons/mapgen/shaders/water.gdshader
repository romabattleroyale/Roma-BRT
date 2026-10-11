shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

// Depth-aware lake water. The colour comes from how much water the view ray
// travels through, not from a flat blue plane, which is what makes shallows
// read as shallow and gives you a free shoreline gradient.

uniform vec4 shallow_color : source_color = vec4(0.22, 0.46, 0.48, 1.0);
uniform vec4 deep_color : source_color = vec4(0.02, 0.09, 0.14, 1.0);
uniform float depth_fade = 7.0;
uniform float alpha_shallow : hint_range(0.0, 1.0) = 0.45;
uniform float alpha_deep : hint_range(0.0, 1.0) = 0.96;

uniform sampler2D wave_noise : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float wave_scale = 0.035;
uniform float wave_height = 0.18;
uniform float wave_speed = 0.05;
uniform float normal_strength : hint_range(0.0, 4.0) = 1.4;

uniform vec4 foam_color : source_color = vec4(0.92, 0.95, 0.96, 1.0);
uniform float foam_width = 0.35;

uniform float refraction = 0.025;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.04;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying vec3 v_world;


float wave_at(vec2 p, float t) {
	float a = texture(wave_noise, p * wave_scale + vec2(t * 0.9, t * 0.35)).r;
	float b = texture(wave_noise, p * wave_scale * 2.3 - vec2(t * 0.5, t * 1.1)).r;
	return a * 0.65 + b * 0.35;
}


void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	VERTEX.y += (wave_at(v_world.xz, t) - 0.5) * 2.0 * wave_height;
}


void fragment() {
	float t = TIME * wave_speed;
	// Finite-difference the wave field for a normal. Cheaper and more stable
	// than a scrolling normal map, and it always matches the vertex displacement.
	float e = 1.5;
	float hL = wave_at(v_world.xz - vec2(e, 0.0), t);
	float hR = wave_at(v_world.xz + vec2(e, 0.0), t);
	float hD = wave_at(v_world.xz - vec2(0.0, e), t);
	float hU = wave_at(v_world.xz + vec2(0.0, e), t);
	vec3 nrm = normalize(vec3((hL - hR) * normal_strength, 1.0, (hD - hU) * normal_strength));

	// Scene depth behind the water surface.
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_z = -view.z;
	float frag_z = -VERTEX.z;
	float water_depth = max(scene_z - frag_z, 0.0);

	// Vertical depth, not depth along the view ray. Reconstruct the world
	// position of whatever is behind the water and compare its height to the
	// surface. At a grazing angle the ray travels a long way through shallow
	// water, so ray depth would smear the shoreline foam across half the lake.
	vec3 bed_world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	float vertical_depth = max(v_world.y - bed_world.y, 0.0);

	float d = clamp(water_depth / max(depth_fade, 0.01), 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, d);

	// Refract what is behind the water, then tint it by depth.
	vec2 off = vec2(nrm.x, nrm.z) * refraction;
	vec3 behind = texture(screen_tex, clamp(SCREEN_UV + off, vec2(0.001), vec2(0.999))).rgb;
	col = mix(behind * mix(vec3(1.0), shallow_color.rgb * 1.6, 0.5), col, d * 0.9 + 0.1);

	// Shoreline foam where the bed comes up close under the surface.
	float foam = 1.0 - smoothstep(0.0, max(foam_width, 0.01), vertical_depth);
	foam *= 0.55 + 0.45 * wave_at(v_world.xz * 3.0, t * 2.0);
	foam = clamp(foam, 0.0, 1.0);
	col = mix(col, foam_color.rgb, foam * 0.85);

	// Fresnel: water seen edge-on is a mirror, water seen from above is a
	// window. Without this the whole lake reads as one flat sheet of paint.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);

	ALBEDO = col;
	ALPHA = clamp(mix(alpha_shallow, alpha_deep, d) + foam * 0.35 + fres * 0.6, 0.0, 1.0);
	ROUGHNESS = mix(roughness_value, 0.02, fres);
	METALLIC = 0.0;
	SPECULAR = 0.85;
	NORMAL_MAP = nrm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
