shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://addons/mapgen/shaders/tree_wind.gdshaderinc"

// Alpha-cut leaf cards.
//
// Two things here do almost all the work:
//
//   Canopy normals. The mesh bakes a normal pointing away from the crown's
//   centre instead of along the card, so the canopy shades as one soft volume.
//   Godot flips normals on back faces of double-sided geometry, which would
//   undo that on half of every leaf, so the flip is reversed below.
//
//   Alpha scissor, not blending. Leaves stay in the opaque pass: correct
//   depth, no sorting, and -- the part that matters most -- real dappled
//   shadows, because the discard applies in the shadow pass too.

uniform sampler2D leaf_albedo : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D leaf_opacity : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_rough : hint_default_white, filter_linear_mipmap_anisotropic;

uniform vec3 tint_young : source_color = vec3(0.92, 0.98, 0.66);
uniform vec3 tint_mature : source_color = vec3(0.70, 0.82, 0.62);
uniform float alpha_cut : hint_range(0.05, 0.95) = 0.45;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.9;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.55;
/// Light passing through the leaf. Backlit foliage glowing instead of going
/// black is most of why a canopy looks alive.
uniform float translucency : hint_range(0.0, 2.0) = 0.22;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.35;

/// Shrink leaves to nothing with distance instead of popping. The mesh has no
/// alpha blending, so GeometryInstance3D's own fade modes cannot be used.
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;

uniform bool snow_enabled = true;
uniform float snow_line_y = 1e9;
uniform float snow_blend_y = 20.0;
uniform vec3 snow_color : source_color = vec3(0.92, 0.95, 1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.8;

varying float v_ao;
varying float v_variation;
varying float v_world_y;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;

	if (fade_end > 0.0) {
		float cam_d = length(MODELVIEW_MATRIX[3].xyz);
		VERTEX *= 1.0 - smoothstep(fade_start, fade_end, cam_d);
	}

	VERTEX = tree_wind(VERTEX, origin, COLOR.r, COLOR.b, TIME);
	v_ao = COLOR.g;
	v_variation = COLOR.b;
	v_world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float a = texture(leaf_opacity, UV).r;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	// Alpha-to-coverage. A hard scissor stipples badly on foliage: at distance
	// the mip chain averages the mask down, and whole leaves flicker in and out
	// around the threshold. This resolves the cut against MSAA samples instead.
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(leaf_opacity, 0));

	vec3 tex = texture(leaf_albedo, UV).rgb;
	// Leaves on the sunlit outside of a crown are younger and yellower than the
	// shaded ones inside it, so drive the tint from the baked exposure term.
	vec3 tint = mix(tint_mature, tint_young, clamp(v_ao * 0.55 + v_variation * 0.25, 0.0, 1.0));
	vec3 albedo = tex * tint;

	if (snow_enabled) {
		float s = smoothstep(snow_line_y, snow_line_y + snow_blend_y, v_world_y);
		albedo = mix(albedo, snow_color, clamp(s * snow_amount, 0.0, 1.0));
	}

	// Undo Godot's automatic back-face normal flip so both sides of a leaf keep
	// the canopy normal the mesh baked in.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	ALBEDO = albedo;
	// The canopy normal makes a whole side of the crown share one normal, so a
	// low roughness turns that side into a single blown-out specular sheet.
	ROUGHNESS = clamp(texture(leaf_rough, UV).r * 0.35 + roughness_value, 0.35, 1.0);
	SPECULAR = 0.18;
	NORMAL_MAP = texture(leaf_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	// Light through a leaf comes out yellow-green, not the leaf's own colour --
	// chlorophyll absorbs the blue and most of the red on the way through.
	BACKLIGHT = mix(albedo, vec3(0.42, 0.52, 0.12), 0.55) * translucency;
	AO = mix(1.0, v_ao, ao_strength);
	AO_LIGHT_AFFECT = 0.55;
}
