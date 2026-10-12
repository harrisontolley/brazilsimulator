shader_type spatial;

// The bottom of the sea: the beach's own sand carried on under the water, with weed and
// rock further out and the light off the waves playing over it.
uniform vec3 dry : source_color = vec3(0.86, 0.74, 0.5);
uniform float shore_z = -38.0;
uniform float sea_y = -0.35;

varying vec3 wp;

float hash(vec2 p) {
	// Whole numbers in, so the same corner gets the same answer whichever cell asks.
	uvec2 q = uvec2(ivec2(floor(p + 0.5))) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) * (1.0 / 4294967295.0);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The net of light the waves throw on the bottom: ripples bent through each other.
float caustic(vec2 p, float t) {
	vec2 q = p * 0.7;
	for (int k = 0; k < 3; k++) {
		q += vec2(sin(q.y * 1.3 + t * 0.5 + float(k)), cos(q.x * 1.1 - t * 0.4 + float(k) * 2.0)) * 0.65;
	}
	return pow(0.5 + 0.5 * sin(q.x * 1.7 + q.y * 1.3), 7.0);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float big = noise(wp.xz * 0.07);
	float mid = noise(wp.xz * 0.9);
	float grain = hash(floor(wp.xz * 14.0));
	float depth = max(sea_y - wp.y, 0.0);
	// Wet sand at the edge, the same as the beach hands over.
	vec3 col = dry * vec3(0.62, 0.58, 0.52) * (0.9 + 0.1 * big + 0.08 * mid + 0.04 * grain);
	// Ripples the swell leaves in the sand.
	col *= 0.93 + 0.07 * sin(wp.z * 3.1 + noise(wp.xz * 0.3) * 6.0);
	// Weed in patches, and darker rock where it gets deep.
	float weed = smoothstep(0.55, 0.75, noise(wp.xz * 0.11 + 3.0)) * smoothstep(1.5, 4.0, depth);
	col = mix(col, vec3(0.1, 0.22, 0.14) * (0.7 + 0.6 * mid), weed * 0.8);
	float rock = smoothstep(0.62, 0.8, noise(wp.xz * 0.05 + 11.0)) * smoothstep(5.0, 9.0, depth);
	col = mix(col, vec3(0.2, 0.2, 0.22) * (0.6 + 0.8 * big), rock);
	// The deeper it lies, the less light gets down to it.
	col *= mix(vec3(1.0), vec3(0.3, 0.55, 0.62), clamp(depth / 12.0, 0.0, 1.0));
	col += vec3(0.9, 1.0, 0.85) * caustic(wp.xz, TIME) * smoothstep(0.0, 0.4, depth) * exp(-depth * 0.16) * 0.35;
	ALBEDO = col;
	ROUGHNESS = mix(0.35, 0.9, smoothstep(0.0, 1.0, depth));
}
