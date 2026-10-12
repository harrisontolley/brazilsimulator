shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled;

// Marks on the water: the ring a splash leaves, and the foam a hull or a swimmer trails.
// Each is a flat square that lies on the waves and spreads as it fades.
// Custom data: when it started, how long it lasts, its size at the end, and its kind
// (0 a ring, 1 a patch of foam).
#include "sea_fn.gdshaderinc"

uniform float now = 0.0;

varying float age;
varying float kind;
varying vec2 at;
varying float born;

void vertex() {
	float life = max(INSTANCE_CUSTOM.y, 0.01);
	age = clamp((now - INSTANCE_CUSTOM.x) / life, 0.0, 1.0);
	kind = INSTANCE_CUSTOM.w;
	born = INSTANCE_CUSTOM.x;
	at = UV * 2.0 - 1.0;
	float grow = mix(0.25, 1.0, 1.0 - (1.0 - age) * (1.0 - age));
	vec3 w = (MODEL_MATRIX * vec4(VERTEX * INSTANCE_CUSTOM.z * grow, 1.0)).xyz;
	w.y = sea_y + sea_h(w.xz, 0.0) + 0.03;
	if (now - INSTANCE_CUSTOM.x > life || INSTANCE_CUSTOM.x <= 0.0) {
		w = vec3(0.0, -500.0, 0.0);
	}
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	float r = length(at);
	float a;
	if (kind < 0.5) {
		a = smoothstep(0.62, 0.8, r) * (1.0 - smoothstep(0.86, 1.0, r));
	} else {
		float n = sea_noise(at * 3.0 + vec2(born * 7.0));
		a = (1.0 - smoothstep(0.35, 1.0, r)) * smoothstep(0.25 + age * 0.5, 0.75 + age * 0.3, n + 0.35);
	}
	ALBEDO = vec3(0.97);
	ROUGHNESS = 0.7;
	ALPHA = a * (1.0 - age) * (1.0 - age) * 0.85;
}
