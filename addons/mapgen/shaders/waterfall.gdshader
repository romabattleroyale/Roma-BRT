shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;

// Falling water, drawn on the ribbon MapWaterfalls builds down the rock face.
//
// The mesh carries what the shader cannot work out for itself, in the vertex
// colour:
//   r = how steeply the water is moving here -- 0 is the stream above the
//       lip, 1 is the sheer part of the drop
//   g = foam already in the geometry: the broken water at the brink, and the
//       plunge at the bottom
//   b = the fade at both ends, where the ribbon stops and the river does not
//   a = how far down the drop this is. Water leaves a lip clear enough to see
//       the rock through and is white by the time it lands, so aeration drives
//       both the whiteness and the opacity.
//
// UV.x runs across the sheet, 0 to 1. UV.y is *metres travelled*, not a
// normalised coordinate, so the texture scale is the same on a 6 m cascade and
// on a 60 m plunge, and `along_tiling` means something physical.

uniform vec4 water_color : source_color = vec4(0.58, 0.76, 0.80, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.97, 0.99, 1.0);

uniform sampler2D flow_noise : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float flow_speed = 1.0;
uniform float along_tiling = 0.075;
uniform float across_tiling = 0.9;
// How far the falling water pulls the noise out. This one setting is most of
// the difference between "waterfall" and "wet cliff".
uniform float streak_stretch : hint_range(1.0, 16.0) = 6.0;

uniform float alpha_stream : hint_range(0.0, 1.0) = 0.55;
uniform float alpha_fall : hint_range(0.0, 1.0) = 0.93;
uniform float edge_softness : hint_range(0.01, 1.0) = 0.4;
uniform float normal_strength : hint_range(0.0, 4.0) = 1.2;


void fragment() {
	float steep = COLOR.r;
	float t = TIME * flow_speed;

	// Stretch the noise along the direction of travel. Water accelerating off
	// a lip pulls into long vertical strands; the same texture unstretched
	// reads as foam standing still on a wall.
	float stretch = mix(1.0, streak_stretch, steep);
	vec2 uv = vec2(UV.x * across_tiling, UV.y * along_tiling / stretch);
	// Falling water moves faster than the stream that feeds it, and the scroll
	// rate is in stretched UV space, so it has to be scaled the same way.
	float speed = mix(0.5, 2.6, steep) / stretch;

	float n1 = texture(flow_noise, uv - vec2(0.0, t * speed)).r;
	float n2 = texture(flow_noise, uv * vec2(2.3, 1.7) + vec2(0.37, -t * speed * 1.9)).r;
	// Two layers at different rates: one sheet of scrolling noise looks like
	// exactly that, and the beat between two of them reads as turbulence.
	float strands = n1 * 0.6 + n2 * 0.4;

	// Aeration: how much air the falling water has picked up by this point.
	float aer = COLOR.a;
	float foam = clamp(COLOR.g + strands * steep * (0.25 + 0.7 * aer) - 0.12, 0.0, 1.0);

	// Soft sides, broken up by the same noise, so the sheet has no straight
	// edges. A ribbon with parallel sides is instantly a ribbon.
	float across = abs(UV.x * 2.0 - 1.0);
	float edge = 1.0 - smoothstep(1.0 - edge_softness, 1.0, across);
	edge *= mix(1.0, clamp(strands * 1.6, 0.0, 1.0), 0.45 * steep);

	float alpha = mix(alpha_stream, alpha_fall, steep) * mix(0.82, 1.0, aer) * COLOR.b * edge;
	alpha = clamp(alpha + foam * 0.3 * COLOR.b, 0.0, 1.0);

	// Normal from the same field, so the highlights ride the strands instead
	// of sitting still on a flat sheet.
	float e = 0.015;
	float hL = texture(flow_noise, uv - vec2(e, t * speed)).r;
	float hR = texture(flow_noise, uv + vec2(e, -t * speed)).r;
	float hD = texture(flow_noise, uv - vec2(0.0, e + t * speed)).r;
	float hU = texture(flow_noise, uv + vec2(0.0, e - t * speed)).r;
	vec3 nrm = normalize(vec3((hL - hR) * normal_strength,
			(hD - hU) * normal_strength, 1.0));

	ALBEDO = mix(water_color.rgb, foam_color.rgb, foam);
	ALPHA = alpha;
	ROUGHNESS = mix(0.05, 0.7, foam);
	METALLIC = 0.0;
	SPECULAR = 0.9;
	NORMAL_MAP = nrm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
