shader_type spatial;
render_mode world_vertex_coords, cull_back, shadows_disabled;
// Small solid things thrown by a blow: blood, sparks, splinters, bits of people. Each instance
// is launched once and falls by itself here, so a burst of a hundred costs no script time.
//
// Per instance: custom.xyz = velocity, custom.w = time launched.
// COLOR.rgb = colour, COLOR.a = how far below its start the ground is (0..1 of 4 m).

uniform float now = 0.0;
uniform float life = 1.3;
uniform float gravity = 13.0;
uniform float glow = 0.0;

varying vec3 v_col;

void vertex() {
	float t = now - INSTANCE_CUSTOM.w;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 off = INSTANCE_CUSTOM.xyz * t;
	off.y -= 0.5 * gravity * t * t;
	float drop = COLOR.a * 4.0;
	// Where it lands it stays, flattened, for what is left of its time.
	float landed = step(off.y, -drop);
	if (landed > 0.5) {
		float vy = INSTANCE_CUSTOM.y;
		float tl = (vy + sqrt(max(vy * vy + 2.0 * gravity * drop, 0.0))) / gravity;
		off = vec3(INSTANCE_CUSTOM.x * tl, -drop + 0.02, INSTANCE_CUSTOM.z * tl);
	}
	float k = t < 0.0 || t > life ? 0.0 : 1.0 - smoothstep(life * 0.75, life, t);
	vec3 local = VERTEX - origin;
	if (landed > 0.5) {
		local.y *= 0.25;
		local.xz *= 1.6;
	}
	VERTEX = origin + local * k + off;
	v_col = pow(COLOR.rgb, vec3(2.2));
}

void fragment() {
	ALBEDO = v_col;
	EMISSION = v_col * glow;
	ROUGHNESS = 0.5;
}
