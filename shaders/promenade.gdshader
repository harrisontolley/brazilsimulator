shader_type spatial;

// Copacabana-style black and white wave paving.
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float w = sin(wp.z * 1.6 + sin(wp.x * 0.9) * 1.6);
	ALBEDO = mix(vec3(0.08), vec3(0.93), smoothstep(-0.05, 0.05, w));
	ROUGHNESS = 0.8;
}
