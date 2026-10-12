shader_type spatial;
render_mode cull_back;
// Cel-shaded cartoon character. Colours come from a small palette indexed per vertex (UV2.y),
// varied per instance by COLOR (rgb = top colour, a = look seed) and the flag bits.

#include "res://shaders/character_pose.gdshaderinc"

const int S_SKIN = 0;
const int S_TOP = 1;
const int S_BOTTOM = 2;
const int S_HAIR = 3;
const int S_SHOE = 4;
const int S_GOLD = 5;
const int S_BLACK = 6;
const int S_WHITE = 7;
const int S_SHIN = 8;
const int S_EYE = 9;
const int S_LAMP = 10;
const int S_ACCENT = 11;
const int S_SLEEVE = 12;
const int S_FOREARM = 13;
const int S_CASH = 14;
const int S_STRIPE = 15;
const int S_SACK = 16;
const int S_WATCH = 17;
const int S_VCOL = 18;
const int S_SWIM = 19;

const int F_SHORTS = 1 << 12;
const int F_TANK = 1 << 13;
const int F_SUIT = 1 << 14;
const int F_LAMP_ON = 1 << 15;
const int F_ANGRY = 1 << 16;
const int F_JAIL = 1 << 17;
const int F_SUNBURN = 1 << 20;
const int F_GOLDWATCH = 1 << 21;
const int F_SHIRTLESS = 1 << 23;

varying vec3 v_col;
varying float v_emit;
varying float v_stripe;
varying float v_y;

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

float hash(float s, float k) {
	return fract(sin(s * k + k) * 43758.5453);
}

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

vec3 skin_tone(float h) {
	if (h < 0.2) return vec3(1.0, 0.86, 0.72);
	if (h < 0.45) return vec3(0.96, 0.76, 0.6);
	if (h < 0.7) return vec3(0.85, 0.62, 0.44);
	if (h < 0.88) return vec3(0.66, 0.45, 0.3);
	return vec3(0.45, 0.3, 0.2);
}

vec3 hair_tone(float h) {
	if (h < 0.35) return vec3(0.1, 0.08, 0.07);
	if (h < 0.6) return vec3(0.3, 0.18, 0.1);
	if (h < 0.75) return vec3(0.5, 0.32, 0.15);
	if (h < 0.88) return vec3(0.92, 0.78, 0.4);
	if (h < 0.95) return vec3(0.75, 0.75, 0.75);
	return vec3(0.8, 0.4, 0.15);
}

vec3 bottom_tone(float h) {
	if (h < 0.25) return vec3(0.2, 0.35, 0.65);
	if (h < 0.45) return vec3(0.75, 0.68, 0.5);
	if (h < 0.6) return vec3(0.95, 0.95, 0.92);
	if (h < 0.75) return vec3(0.15, 0.15, 0.18);
	if (h < 0.88) return vec3(0.85, 0.2, 0.2);
	return vec3(0.1, 0.6, 0.6);
}

void vertex() {
	int slot = int(UV2.y + 0.5);
	int flags = int(INSTANCE_CUSTOM.z + 0.5);
	int build = int(floor(COLOR.a + 0.0001));
	float seed = fract(COLOR.a);
	int part = int(UV2.x + 0.5);
	v_y = VERTEX.y;
	float dead_k;
	float hit_k;
	char_vertex(VERTEX, NORMAL, UV.x, UV2.x, INSTANCE_CUSTOM, COLOR.a, dead_k, hit_k);

	bool jail = (flags & F_JAIL) != 0;
	bool suit = (flags & F_SUIT) != 0;
	vec3 skin = skin_tone(hash(seed, 12.9));
	if ((flags & F_SUNBURN) != 0) {
		skin = mix(skin, vec3(1.0, 0.5, 0.45), 0.5);
	}
	if ((flags & F_ANGRY) != 0) {
		skin = mix(skin, vec3(0.95, 0.2, 0.15), 0.4);
	}
	vec3 top = jail ? vec3(1.0, 0.45, 0.05) : COLOR.rgb;
	if ((flags & F_SHIRTLESS) != 0 && !jail) {
		top = skin;
	}
	vec3 bottom = jail ? top : (suit ? top * 0.75 : bottom_tone(hash(seed, 78.2)));
	if (trip > 1.5) {
		// A bad trip: they are all police.
		top = vec3(0.12, 0.22, 0.55);
		bottom = vec3(0.06, 0.08, 0.16);
	}

	vec3 col = vec3(1.0, 0.0, 1.0);
	v_emit = 0.0;
	v_stripe = 0.0;
	if (slot == S_SKIN) {
		col = skin;
	} else if (slot == S_TOP) {
		col = top;
		v_stripe = float(jail);
	} else if (slot == S_BOTTOM) {
		col = bottom;
		if (build == BUILD_WOMAN && !jail) {
			// A bikini: the hips in its colour, the legs bare.
			col = part == PART_TORSO ? COLOR.rgb : skin;
		}
		v_stripe = float(jail);
	} else if (slot == S_SWIM) {
		col = COLOR.rgb;
	} else if (slot == S_HAIR) {
		col = build == BUILD_BIG ? vec3(0.8, 0.8, 0.78) : hair_tone(hash(seed, 37.7));
	} else if (slot == S_SHOE) {
		col = suit ? vec3(0.06) : (hash(seed, 51.3) < 0.5 ? vec3(0.92, 0.92, 0.88) : vec3(0.45, 0.3, 0.2));
	} else if (slot == S_GOLD) {
		col = vec3(1.0, 0.78, 0.1);
		v_emit = 0.3;
	} else if (slot == S_BLACK) {
		col = vec3(0.07, 0.07, 0.08);
	} else if (slot == S_WHITE) {
		col = vec3(0.96);
	} else if (slot == S_SHIN) {
		col = (flags & F_SHORTS) != 0 && !jail ? skin : bottom;
		v_stripe = float(jail);
	} else if (slot == S_EYE) {
		col = vec3(0.06, 0.05, 0.05);
	} else if (slot == S_LAMP) {
		if ((flags & F_LAMP_ON) != 0) {
			col = fract(now * 3.0) < 0.5 ? vec3(1.0, 0.1, 0.1) : vec3(0.15, 0.3, 1.0);
			v_emit = 4.0;
		} else {
			col = vec3(0.5, 0.12, 0.12);
		}
	} else if (slot == S_ACCENT) {
		col = mix(vec3(1.0), hue(hash(seed, 93.1)), 0.75);
	} else if (slot == S_SLEEVE) {
		col = (flags & F_TANK) != 0 && !jail ? skin : top;
		v_stripe = float(jail);
	} else if (slot == S_FOREARM) {
		col = suit || jail ? top : skin;
		v_stripe = float(jail);
	} else if (slot == S_CASH) {
		col = vec3(0.3, 0.85, 0.35);
		v_emit = 0.2;
	} else if (slot == S_STRIPE) {
		col = vec3(0.85, 1.0, 0.1);
		v_emit = 0.25;
	} else if (slot == S_SACK) {
		col = vec3(0.75, 0.62, 0.42);
	} else if (slot == S_WATCH) {
		col = (flags & F_GOLDWATCH) != 0 ? vec3(1.0, 0.78, 0.1) : vec3(0.8, 0.82, 0.86);
	} else if (slot == S_VCOL) {
		// Seven bits a channel, packed into UV.y by the weapon kit.
		int packed = int(UV.y + 0.5);
		col = vec3(float(packed & 127), float((packed >> 7) & 127), float((packed >> 14) & 127)) / 127.0;
	}

	col = lin(col);
	// Corpses drain to a cold grey.
	col = mix(col, vec3(dot(col, vec3(0.3, 0.6, 0.1))) * vec3(0.55, 0.57, 0.65), dead_k * 0.8);
	v_emit *= 1.0 - dead_k;
	col = mix(col, vec3(1.0), hit_k * 0.8);
	v_emit += hit_k * 1.2;
	v_col = col;
}

void fragment() {
	vec3 col = v_col * mix(1.0, 0.5, v_stripe * step(0.5, fract(v_y * 9.0)));
	ALBEDO = col;
	EMISSION = col * v_emit;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float band = smoothstep(-0.02, 0.06, dot(NORMAL, LIGHT));
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * band / PI;
}
