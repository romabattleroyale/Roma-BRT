shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://addons/mapgen/shaders/tree_wind.gdshaderinc"

uniform sampler2D bark_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 bark_tint : source_color = vec4(0.62, 0.56, 0.48, 1.0);
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.85;

uniform bool snow_enabled = true;
uniform float snow_line_y = 1e9;
uniform float snow_blend_y = 20.0;
uniform vec3 snow_color : source_color = vec3(0.90, 0.93, 1.0);

varying float v_ao;
varying float v_world_y;
varying float v_up;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	VERTEX = tree_wind(VERTEX, origin, COLOR.r, COLOR.b, TIME);
	v_ao = COLOR.g;
	v_world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	v_up = clamp(NORMAL.y, 0.0, 1.0);
}

void fragment() {
	vec3 albedo = texture(bark_albedo, UV).rgb * bark_tint.rgb;

	if (snow_enabled) {
		// Snow settles on the upper faces of limbs, not on vertical trunk.
		float s = smoothstep(snow_line_y, snow_line_y + snow_blend_y, v_world_y);
		albedo = mix(albedo, snow_color, clamp(s * v_up * v_up, 0.0, 1.0));
	}

	ALBEDO = albedo;
	ROUGHNESS = texture(bark_rough, UV).r;
	SPECULAR = 0.25;
	NORMAL_MAP = texture(bark_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	AO = mix(1.0, v_ao, ao_strength);
	AO_LIGHT_AFFECT = 0.5;
}
