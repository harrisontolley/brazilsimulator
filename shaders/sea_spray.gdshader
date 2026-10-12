shader_type spatial;
render_mode shadows_disabled;

// Water in the air and air in the water: drops thrown up by a splash, which fall, and
// bubbles let go under the surface, which wobble their way up.
// Custom data: when it started, how long it lasts, its size, and its kind (0 a drop,
// 1 a bubble). The instance colour carries the velocity it left with.
uniform float now = 0.0;

varying float fade;

void vertex() {
	float t = now - INSTANCE_CUSTOM.x;
	float life = max(INSTANCE_CUSTOM.y, 0.01);
	float k = clamp(t / life, 0.0, 1.0);
	vec3 off = COLOR.rgb * t;
	float size = INSTANCE_CUSTOM.z;
	if (INSTANCE_CUSTOM.w < 0.5) {
		off.y -= 4.9 * t * t;
		size *= 1.0 - k * 0.6;
	} else {
		// Bubbles slow to a steady climb and shiver sideways as they go.
		off = COLOR.rgb * (1.0 - exp(-t * 3.0)) / 3.0 + vec3(sin(t * 9.0 + INSTANCE_CUSTOM.x * 40.0) * 0.05, t * 0.9, cos(t * 7.0 + INSTANCE_CUSTOM.x * 31.0) * 0.05);
		size *= 0.6 + 0.4 * k;
	}
	if (t > life || INSTANCE_CUSTOM.x <= 0.0) {
		size = 0.0;
	}
	VERTEX = VERTEX * size + (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	fade = INSTANCE_CUSTOM.w;
}

void fragment() {
	ALBEDO = mix(vec3(0.9, 0.97, 1.0), vec3(0.75, 0.95, 1.0), fade);
	ROUGHNESS = 0.2;
	SPECULAR = 0.7;
	EMISSION = vec3(0.12, 0.16, 0.18) * fade;
}
