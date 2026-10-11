// Shared wind model for bark and leaves.
//
// Hierarchical, because a tree that sways as one rigid lollipop is instantly
// readable as fake: the trunk barely moves, limbs lag behind it, and leaves
// flutter at a much higher frequency than either. COLOR.r carries the wind
// weight baked per vertex (0 at the root, 1 at the tips), so one formula covers
// the whole tree.

uniform float wind_strength : hint_range(0.0, 3.0) = 0.35;
uniform float wind_speed : hint_range(0.0, 6.0) = 1.0;
uniform float wind_flutter : hint_range(0.0, 1.0) = 0.0;
uniform vec2 wind_direction = vec2(0.82, 0.57);

vec3 tree_wind(vec3 vertex, vec3 origin, float weight, float phase, float time) {
	// Gusts travel across the map rather than every tree moving in lockstep.
	float gust = 0.62 + 0.38 * sin(dot(origin.xz, vec2(0.011, 0.014)) + time * 0.31);
	float inst = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831;

	// Primary: the whole tree leans downwind, weighted toward the tips.
	float w2 = weight * weight;
	float bend = sin(time * 0.62 + inst) * wind_strength * gust * w2;
	vertex.x += bend * wind_direction.x;
	vertex.z += bend * wind_direction.y;
	// A slower cross-sway keeps it from looking like a metronome.
	vertex.x += cos(time * 0.41 + inst * 1.7) * wind_strength * gust * w2 * 0.35;

	// Secondary: leaf flutter, high frequency and much smaller amplitude.
	if (wind_flutter > 0.0) {
		float f1 = sin(time * 5.7 + phase * 6.2831 + vertex.y * 2.6);
		float f2 = cos(time * 7.9 + phase * 11.3);
		vertex += vec3(f1, f2 * 0.55, f2) * wind_flutter * weight * gust;
	}
	return vertex;
}
