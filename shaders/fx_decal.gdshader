shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Marks left on the world: blood, bullet holes, scorching. A flat square per mark, laid on
// the surface; the shape is drawn here, different for every one.
//
// Per instance: custom.x = kind (0 blood, 1 bullet hole, 2 scorch), .y = seed,
// .z = time it was made, .w = seconds it lasts. COLOR = colour.

uniform float now = 0.0;

varying vec4 v_cd;
varying vec3 v_col;

float hash(float n) {
	return fract(sin(n * 91.345) * 47453.5453);
}

void vertex() {
	v_cd = INSTANCE_CUSTOM;
	v_col = pow(COLOR.rgb, vec3(2.2));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float seed = v_cd.y;
	float age = now - v_cd.z;
	float alpha = 0.0;
	vec3 col = v_col;
	if (v_cd.x < 0.5) {
		// A ragged pool that spreads as it lands, and drops flung out round it.
		float grow = smoothstep(0.0, 0.25, age);
		float edge = (0.5 + 0.14 * sin(a * 3.0 + seed * 7.0) + 0.1 * sin(a * 5.0 + seed * 13.0) + 0.07 * sin(a * 11.0 + seed * 29.0)) * (0.35 + 0.65 * grow);
		alpha = smoothstep(edge, edge - 0.07, r);
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			float da = hash(seed + fi * 3.1) * 6.283;
			float dr = 0.55 + hash(seed + fi * 7.7) * 0.38;
			float size = 0.03 + hash(seed + fi * 1.3) * 0.08;
			// Each one a streak pointing away from the middle.
			vec2 c = vec2(cos(da), sin(da)) * dr;
			vec2 q = p - c;
			vec2 along = normalize(c);
			float l = dot(q, along);
			float w = length(q - along * l);
			alpha = max(alpha, smoothstep(size, size * 0.6, length(vec2(l * 0.45, w))) * grow);
		}
		// Darker and duller as it dries.
		col *= mix(1.0, 0.45, smoothstep(2.0, 25.0, age));
		alpha *= 0.94;
	} else if (v_cd.x < 1.5) {
		float edge = 0.28 + 0.06 * sin(a * 5.0 + seed * 9.0);
		alpha = smoothstep(edge, edge - 0.05, r);
		// Chipped paint round it, and a couple of cracks.
		alpha = max(alpha, 0.45 * smoothstep(0.62, 0.3, r) * step(0.4, hash(floor(a * 3.0 + seed * 5.0))));
		alpha = max(alpha, 0.7 * smoothstep(0.035, 0.0, abs(sin(a * 2.5 + seed * 4.0))) * smoothstep(0.95, 0.3, r));
	} else {
		float n = 0.75 + 0.25 * sin(a * 7.0 + seed * 11.0) * sin(a * 3.0 + seed * 5.0);
		alpha = smoothstep(n, n * 0.25, r) * 0.85;
		// Rays of soot thrown outward.
		alpha = max(alpha, 0.6 * smoothstep(0.1, 0.0, abs(sin(a * 9.0 + seed * 3.0))) * smoothstep(1.0, 0.4, r));
	}
	alpha *= 1.0 - smoothstep(v_cd.w * 0.75, v_cd.w, age);
	ALBEDO = col;
	ALPHA = alpha;
	// Wet at first, but never so shiny that it turns the colour of the sky.
	ROUGHNESS = v_cd.x < 0.5 ? mix(0.55, 0.95, smoothstep(2.0, 25.0, age)) : 1.0;
	SPECULAR = v_cd.x < 0.5 ? 0.15 : 0.0;
}
