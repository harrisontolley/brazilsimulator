// The sea, shared by its two qualities. With SEA_HIGH defined the water bends what is under
// it and froths round anything standing in it; without, it is the same water drawn blind.
//
// The swell is the one in Layout.WAVES, handed over as uniforms, and only ever lifts the
// water straight up: so a point on the surface is over the same spot on the seabed whatever
// the wave, and script can ask how high the water is anywhere without a picture of it.

uniform float sea_time = 0.0;
uniform float sea_storm = 0.0;
uniform float night = 0.0;
uniform float shore_z = -38.0;
uniform float sea_y = -0.35;
uniform vec2 yacht_xz = vec2(70.0, -215.0);
// The yacht's hull as centre x, centre z, half length, half beam: no water is drawn inside.
uniform vec4 hull = vec4(0.0, 0.0, -1.0, -1.0);
// Each wave as (direction x, direction z, wavenumber, speed) and (height, peakedness).
uniform vec4 wave_a[4];
uniform vec2 wave_b[4];
// The seabed as (z, height), going out.
uniform vec2 seabed[5];
uniform vec3 shallow : source_color = vec3(0.1, 0.74, 0.7);
uniform vec3 deep : source_color = vec3(0.0, 0.2, 0.42);

float sea_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float sea_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(sea_hash(i), sea_hash(i + vec2(1.0, 0.0)), f.x), mix(sea_hash(i + vec2(0.0, 1.0)), sea_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Smooth all the way through, where sea_noise is only smooth in places: this one can be
// leaned on for the tilt of the surface.
float sea_ripple(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(vec2(cos(sea_hash(i) * 6.2832), sin(sea_hash(i) * 6.2832)), f);
	float b = dot(vec2(cos(sea_hash(i + vec2(1.0, 0.0)) * 6.2832), sin(sea_hash(i + vec2(1.0, 0.0)) * 6.2832)), f - vec2(1.0, 0.0));
	float c = dot(vec2(cos(sea_hash(i + vec2(0.0, 1.0)) * 6.2832), sin(sea_hash(i + vec2(0.0, 1.0)) * 6.2832)), f - vec2(0.0, 1.0));
	float d = dot(vec2(cos(sea_hash(i + vec2(1.0, 1.0)) * 6.2832), sin(sea_hash(i + vec2(1.0, 1.0)) * 6.2832)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float sea_chop(vec2 p) {
	vec2 q1 = p * 0.45 + vec2(sea_time * 0.3, sea_time * 0.2);
	vec2 q2 = p * 1.1 + vec2(-sea_time * 0.45, sea_time * 0.3);
	vec2 q3 = p * 2.7 + vec2(sea_time * 0.5, -sea_time * 0.6);
	return sea_ripple(q1) + 0.5 * sea_ripple(q2) + 0.22 * sea_ripple(q3);
}

float sea_amp(vec2 p) {
	float shore = mix(0.18, 1.0, smoothstep(0.0, 50.0, shore_z - p.y));
	float calm = mix(0.3, 1.0, smoothstep(26.0, 70.0, length(p - yacht_xz)));
	return shore * calm * (1.0 + 1.5 * sea_storm);
}

// Height of the surface above still water at p, leaving out any wave too short for a mesh
// with cells this wide to draw.
float sea_h(vec2 p, float cell_w) {
	float h = 0.0;
	for (int i = 0; i < 4; i++) {
		float fit = 1.0 - smoothstep(0.25, 0.5, cell_w * wave_a[i].z / 6.2832);
		float s = 0.5 + 0.5 * sin(dot(wave_a[i].xy, p) * wave_a[i].z - wave_a[i].w * sea_time);
		h += wave_b[i].x * (2.0 * pow(s, wave_b[i].y) - 1.0) * fit;
	}
	return h * sea_amp(p);
}

// Slope of the surface at p. Waves too fine to make out at this distance are left flat,
// or they turn to glitter.
vec2 sea_slope(vec2 p, float dist) {
	vec2 g = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		float lam = 6.2832 / wave_a[i].z;
		float fit = 1.0 - smoothstep(lam * 14.0, lam * 40.0, dist);
		float ph = dot(wave_a[i].xy, p) * wave_a[i].z - wave_a[i].w * sea_time;
		float s = 0.5 + 0.5 * sin(ph);
		g += wave_a[i].xy * (wave_b[i].x * wave_b[i].y * pow(max(s, 0.0001), wave_b[i].y - 1.0) * cos(ph) * wave_a[i].z * fit);
	}
	return g * sea_amp(p);
}

float sea_bed(float z) {
	if (z >= seabed[0].x) {
		return 0.0;
	}
	for (int k = 1; k < 5; k++) {
		if (z >= seabed[k].x) {
			return mix(seabed[k - 1].y, seabed[k].y, (seabed[k - 1].x - z) / (seabed[k - 1].x - seabed[k].x));
		}
	}
	return seabed[4].y;
}

