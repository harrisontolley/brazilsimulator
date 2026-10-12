shader_type spatial;
render_mode cull_disabled;

uniform vec3 deep : source_color = vec3(0.0, 0.32, 0.55);
uniform vec3 shallow : source_color = vec3(0.12, 0.78, 0.72);
uniform float shore_z = -38.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wp.x * 0.15 + TIME * 1.2) * 0.1 + sin(wp.z * 0.3 + TIME * 0.8) * 0.08;
}

void fragment() {
	float d = clamp((shore_z - wp.z) / 70.0, 0.0, 1.0);
	vec3 c = mix(shallow, deep, d);
	float foam = smoothstep(0.8, 1.0, sin(wp.z * 0.9 + TIME * 1.5 + sin(wp.x * 0.2) * 2.0)) * (1.0 - d);
	ALBEDO = mix(c, vec3(1.0), foam * 0.7);
	ALPHA = mix(0.6, 0.96, d);
	ROUGHNESS = 0.15;
}
