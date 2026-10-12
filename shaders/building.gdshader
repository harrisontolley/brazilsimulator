shader_type spatial;
// Walls with a window grid drawn from world position, so a building is one box.
// Instance colour: rgb = wall colour, a = seed. Custom data: x = style (0 tower, 1 favela house).

uniform float night = 0.0;

varying vec3 wp;
varying flat vec3 wn;
varying flat vec3 tint;
varying flat float style;
varying flat float seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = NORMAL;
	tint = pow(COLOR.rgb, vec3(2.2));
	seed = floor(COLOR.a * 97.0);
	style = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec3 col = tint;
	float rough = 0.9;
	vec3 emit = vec3(0.0);
	if (abs(wn.y) > 0.5) {
		col = style > 0.5 ? mix(vec3(0.45, 0.3, 0.24), vec3(0.5), hash(vec2(seed))) : vec3(0.42, 0.41, 0.4);
	} else {
		float u = abs(wn.x) > 0.5 ? wp.z : wp.x;
		bool house = style > 0.5;
		vec2 g = vec2(u, wp.y) / (house ? vec2(2.4, 3.0) : vec2(3.2, 3.5));
		vec2 id = floor(g) + vec2(seed, step(0.5, abs(wn.x)) * 31.0);
		vec2 f = fract(g);
		float h = hash(id);
		float win;
		if (house) {
			// A few small windows and the odd door; bare brick shows its courses.
			win = step(0.3, f.x) * step(f.x, 0.7) * step(0.35, f.y) * step(f.y, 0.75) * step(0.35, h);
			col *= 0.92 + 0.08 * step(0.5, fract(wp.y * 5.0));
		} else if (wp.y < 3.5) {
			// Ground floor shopfronts.
			win = step(0.06, f.x) * step(f.x, 0.94) * step(0.08, f.y) * step(f.y, 0.78);
			col *= 0.7;
		} else {
			win = step(0.14, f.x) * step(f.x, 0.86) * step(0.3, f.y) * step(f.y, 0.82);
			// Floor slab line under each row of windows.
			col *= 1.0 - 0.18 * step(f.y, 0.1);
		}
		if (!house && abs(wn.x) > 0.5) {
			// A wall that looks onto an alley or a side street: grimy toward the ground, damp
			// stains running down it, and the ground floor mostly boarded up.
			float stain = step(0.72, hash(floor(vec2(wp.z * 0.55 + seed, wp.y * 0.35))));
			col *= mix(0.5, 1.0, smoothstep(0.0, 6.0, wp.y)) * (1.0 - 0.22 * stain);
			if (wp.y < 3.5) {
				win *= step(0.65, h);
			}
		}
		vec3 glass = mix(vec3(0.05, 0.09, 0.14), vec3(0.2, 0.32, 0.42), h);
		float lit = step(1.0 - 0.65 * night, hash(id + 7.3)) * night;
		col = mix(col, glass, win);
		rough = mix(0.9, 0.15, win);
		emit = win * lit * mix(vec3(1.0, 0.75, 0.4), vec3(0.6, 0.8, 1.0), step(0.85, h)) * 1.6;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit;
}
