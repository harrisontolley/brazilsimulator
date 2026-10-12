shader_type spatial;
render_mode world_vertex_coords, blend_mix, unshaded, cull_back, depth_draw_never, shadows_disabled;
// Soft things that hang in the air and thin out: smoke, dust, flame.
//
// Per instance: custom.xyz = velocity (it slows as it goes), custom.w = time it appeared.
// COLOR.rgb = colour, COLOR.a = how solid it starts, and above 0.5 it burns.

uniform float now = 0.0;
uniform float life = 1.6;

varying vec4 v_col;

void vertex() {
	float t = now - INSTANCE_CUSTOM.w;
	float u = clamp(t / life, 0.0, 1.0);
	vec3 origin = MODEL_MATRIX[3].xyz;
	// Fast out, then drifting.
	vec3 off = INSTANCE_CUSTOM.xyz * (1.0 - exp(-t * 2.2)) / 2.2;
	float k = t < 0.0 || t > life ? 0.0 : 0.6 + u * 1.7;
	VERTEX = origin + (VERTEX - origin) * k + off;
	bool hot = COLOR.a > 0.5;
	vec3 col = COLOR.rgb;
	if (hot) {
		// Flame cools to soot as it rises.
		col = mix(col, vec3(0.12, 0.1, 0.1), smoothstep(0.35, 1.0, u));
	}
	v_col = vec4(col, (hot ? 0.9 : COLOR.a * 2.0) * (1.0 - u) * smoothstep(0.0, 0.06, u + 0.02));
}

void fragment() {
	// Thinner toward the edge, so it reads as a puff and not a ball.
	float rim = pow(clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.5);
	ALBEDO = v_col.rgb;
	ALPHA = v_col.a * rim;
}
