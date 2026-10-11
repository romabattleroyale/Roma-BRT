shader_type sky;

// Gradient sky with a sun, up to four ray-traced moons, stars and eclipses.
//
// Adapted from the ExoSky shader in /data/space-colony-v3, which in turn takes
// its three-gradient colouring model from Kelvin van Hoorn's skybox tutorial
// (kelvinvanhoorn.com/tutorials/godot_skybox_shader).
//
// Changes made for MapGen:
//   - moons are an array rather than two hardcoded slots, so a world can have
//     none or four
//   - each moon's own frame is derived in the shader from its direction, which
//     removes a mat3-array uniform for nothing lost: the frame was always a
//     pure function of the direction anyway
//   - lunar eclipse applies to whichever moon is opposite the sun, not just
//     the first one
//
// The colouring is not physical. Three gradients are sampled by how high the
// sun stands -- one for the sky, one for the horizon haze, one for the glow
// around the sun -- and added. One input, the sun's altitude, carries the sky
// from noon through dusk to black night.

const int MAX_MOONS = 4;

group_uniforms Directions;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform mat3 star_frame = mat3(1.0);

group_uniforms SkyGradients;
uniform sampler2D sun_zenith_gradient : source_color, repeat_disable;
uniform sampler2D view_zenith_gradient : source_color, repeat_disable;
uniform sampler2D sun_view_gradient : source_color, repeat_disable;

group_uniforms Sun;
uniform float sun_radius : hint_range(0.0, 0.3) = 0.032;
uniform vec3 sun_color : source_color = vec3(1.0, 0.97, 0.92);
/// How much of the sun a moon is covering, 0-1.
uniform float eclipse : hint_range(0.0, 1.0) = 0.0;

group_uniforms Moons;
uniform int moon_count : hint_range(0, 4) = 1;
uniform vec3 moon_dir[MAX_MOONS];
uniform float moon_radius[MAX_MOONS];
uniform vec3 moon_tint[MAX_MOONS];
uniform float moon_exposure[MAX_MOONS];
uniform float moon_detail[MAX_MOONS];

group_uniforms Stars;
uniform float star_exposure : hint_range(0.0, 4.0) = 1.0;
uniform vec3 galaxy_color : source_color = vec3(0.36, 0.34, 0.52);
uniform float galaxy_strength : hint_range(0.0, 3.0) = 1.0;


float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// From Inigo Quilez, https://iquilezles.org/articles/intersectors/
// Clamping the discriminant keeps a grazing ray on the tangent point instead of
// missing, which is what lets the limb be antialiased rather than stair-stepped.
float sphere_intersect(vec3 ray_dir, vec3 sphere_pos, float radius) {
	vec3 oc = -sphere_pos;
	float b = dot(oc, ray_dir);
	float c = dot(oc, oc) - radius * radius;
	return -b - sqrt(max(b * b - c, 0.0));
}

/// A rotation into the moon's own frame. Derived from the direction rather than
/// passed in: it was always a pure function of it, and deriving it here avoids
/// a mat3 array uniform.
mat3 moon_frame_of(vec3 dir) {
	vec3 z = normalize(dir);
	vec3 up = abs(z.y) < 0.995 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0);
	vec3 x = normalize(cross(up, z));
	vec3 y = cross(z, x);
	// Orthonormal, so the inverse is the transpose.
	return transpose(mat3(x, y, z));
}

/// One moon: its disc, its phase, and the mottling on its surface.
vec3 draw_moon(vec3 view_dir, vec3 dir, float radius, vec3 tint,
		float exposure, float detail, vec3 sun, out float mask) {
	float centre_dot = dot(view_dir, dir);
	// cos of the moon's angular radius: inside this, the ray hits.
	float limb = sqrt(max(1.0 - radius * radius, 0.0));
	float edge = radius * radius * 0.09;
	mask = smoothstep(limb - edge, limb + edge, centre_dot);
	if (mask <= 0.0) {
		return vec3(0.0);
	}
	float t = sphere_intersect(view_dir, dir, radius);
	vec3 normal = normalize(view_dir * t - dir);

	// Phase. Sunlight arrives parallel, so the lit half is simply the half
	// facing the sun.
	float ndotl = clamp(dot(normal, sun), 0.0, 1.0);
	// A hard terminator on a disc this small reads as an artefact.
	ndotl = smoothstep(0.0, 0.10, ndotl) * ndotl;

	// Surface sampled in the moon's own frame, so the markings stay put as it
	// crosses the sky instead of sliding across the disc.
	vec3 obj = moon_frame_of(dir) * normal;
	float plains = fbm(obj * 3.4);
	float craters = fbm(obj * 13.0);
	float albedo = mix(0.68, 1.0, smoothstep(0.34, 0.62, plains));
	albedo *= mix(0.88, 1.08, craters);
	vec3 surface = tint * mix(1.0, albedo, detail);

	// The night side catches light bounced off the planet below, the way a
	// young crescent does.
	vec3 planetshine = tint * 0.018 * (1.0 - ndotl);
	return (surface * ndotl * exposure + planetshine) * mask;
}

/// One layer of stars: a single cell lookup with the star parked mid-cell so
/// its falloff never crosses a boundary.
vec3 star_layer(vec3 dir, float density, float cut, float size) {
	vec3 p = dir * density;
	vec3 cell = floor(p);
	vec3 h = hash33(cell);
	if (h.z < cut) {
		return vec3(0.0);
	}
	vec3 star = 0.3 + 0.4 * h;
	float d = length(p - cell - star);
	float core = smoothstep(size, 0.0, d);
	float mag = h.z * h.z;
	// Each star twinkles at its own rate, or they all pulse together and it
	// reads as a fault rather than as air.
	float twinkle = 0.78 + 0.22 * sin(TIME * (0.7 + h.y * 2.2) + h.x * 63.0);
	vec3 tint = mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.82, 0.62),
		smoothstep(0.3, 0.7, h.y));
	return tint * pow(core, 5.0) * mag * twinkle;
}


void sky() {
	vec3 view_dir = EYEDIR;

	float sun_view_dot = dot(sun_dir, view_dir);
	float sun_zenith_dot = sun_dir.y;
	float view_zenith_dot = view_dir.y;
	float sun_zenith_dot01 = (sun_zenith_dot + 1.0) * 0.5;

	// Base colour, plus haze banked along the horizon, plus the glow around the
	// sun. The two masks decide where each of the last two lands.
	vec3 sun_zenith_color = texture(sun_zenith_gradient, vec2(sun_zenith_dot01, 0.5)).rgb;
	vec3 view_zenith_color = texture(view_zenith_gradient, vec2(sun_zenith_dot01, 0.5)).rgb;
	float vz_mask = pow(clamp(1.0 - view_zenith_dot, 0.0, 1.0), 4.0);
	vec3 sun_view_color = texture(sun_view_gradient, vec2(sun_zenith_dot01, 0.5)).rgb;
	float sv_mask = pow(clamp(sun_view_dot, 0.0, 1.0), 4.0);
	vec3 sky_output = sun_zenith_color + vz_mask * view_zenith_color + sv_mask * sun_view_color;

	float sun_limb = 1.0 - sun_radius * sun_radius;
	float sun_mask = smoothstep(sun_limb - sun_radius * sun_radius * 0.06, sun_limb, sun_view_dot);
	vec3 sun_output = sun_color * sun_mask;

	// --- moons ------------------------------------------------------------
	vec3 moon_output = vec3(0.0);
	float moon_mask = 0.0;
	for (int i = 0; i < MAX_MOONS; i++) {
		if (i >= moon_count) {
			break;
		}
		float m;
		vec3 lit = draw_moon(view_dir, moon_dir[i], moon_radius[i], moon_tint[i],
			moon_exposure[i], moon_detail[i], sun_dir, m);
		// Lunar eclipse: a moon opposite the sun falls into the planet's
		// shadow, and the light still reaching it has come the long way through
		// the atmosphere, so it arrives red.
		float shadow = smoothstep(0.9986, 0.99995, -dot(moon_dir[i], sun_dir));
		moon_output += lit * mix(vec3(1.0), vec3(0.34, 0.07, 0.03), shadow);
		moon_mask = max(moon_mask, m);
	}

	// --- stars ------------------------------------------------------------
	// Skipped while the radiance cubemap is being built: they would only add
	// noise to the ambient light, and there are a lot of them.
	vec3 star_output = vec3(0.0);
	if (!AT_CUBEMAP_PASS) {
		vec3 star_dir = star_frame * view_dir;
		vec3 stars = star_layer(star_dir, 42.0, 0.72, 0.30)
			+ star_layer(star_dir, 96.0, 0.86, 0.26) * 0.55;

		// A band of unresolved stars: this galaxy's disc seen edge-on from
		// inside it. Cheap, and most of what makes a night sky read as deep
		// rather than sprinkled.
		vec3 pole = normalize(vec3(0.34, 0.79, 0.51));
		float band = exp(-pow(dot(star_dir, pole) * 2.7, 2.0));
		float dust = fbm(star_dir * 4.5);
		vec3 galaxy = galaxy_color * band * (0.25 + 0.75 * dust) * 0.16 * galaxy_strength;

		star_output = (stars + galaxy) * star_exposure;
		// Nothing shows through the sun or a moon, and daylit air washes the
		// lot out: the stars are always up there, just never a match for it.
		float night = clamp(-sun_zenith_dot * 6.0, 0.0, 1.0);
		star_output *= (1.0 - sun_mask) * (1.0 - moon_mask) * night;
	}

	// --- solar eclipse ------------------------------------------------------
	// The moon is already drawn over the sun by its own mask; what is left is
	// what it does to everything else -- the sky drops away, and the corona the
	// disc was hiding comes out around the edge.
	sky_output *= mix(1.0, 0.30, eclipse);
	sun_output *= (1.0 - moon_mask) * mix(1.0, 10.0, eclipse);
	if (eclipse > 0.01) {
		float corona_dot = clamp(sun_view_dot, 0.0, 1.0);
		float corona = pow(corona_dot, 900.0) + 0.55 * pow(corona_dot, 220.0);
		sun_output += sun_color * corona * eclipse * 1.6 * (1.0 - moon_mask);
	}

	COLOR = sky_output + sun_output + moon_output + star_output;
}
