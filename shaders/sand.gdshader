shader_type spatial;

// Beach sand: grainy, rippled, and darker where the sea keeps it wet.
uniform vec3 dry : source_color = vec3(0.86, 0.74, 0.5);
uniform float shore_z = -38.0;

varying vec3 wp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float big = noise(wp.xz * 0.07);
	float mid = noise(wp.xz * 0.9);
	float grain = hash(floor(wp.xz * 14.0));
	// Trampled sand is scuffed; near the water the tide leaves it smooth and dark.
	float wet = smoothstep(9.0, 1.0, wp.z - shore_z + sin(wp.x * 0.11 + TIME * 0.5) * 1.2);
	vec3 col = dry * (0.86 + 0.12 * big + 0.1 * mid + 0.06 * grain);
	col = mix(col, dry * vec3(0.62, 0.58, 0.52), wet);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.35, wet);
}
