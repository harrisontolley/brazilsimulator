shader_type spatial;
render_mode cull_back;
// Cel-shaded dog, to sit beside the cartoon people. Coat from COLOR, markings from custom.w.

#include "res://shaders/dog_pose.gdshaderinc"

const int S_COAT = 0;
const int S_MARK_A = 1;  // muzzle, ears, saddle
const int S_MARK_B = 2;  // paws, chest, tail tip
const int S_DARK = 3;    // nose and eyes
const int S_TONGUE = 4;

varying vec3 v_col;

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 unpack12(int v) {
	return vec3(float(v & 15), float((v >> 4) & 15), float((v >> 8) & 15)) / 15.0;
}

void vertex() {
	float dead_k;
	float hit_k;
	dog_vertex(VERTEX, NORMAL, UV2.x, INSTANCE_CUSTOM, COLOR.a, dead_k, hit_k);
	int slot = int(UV2.y + 0.5);
	int marks = int(INSTANCE_CUSTOM.w + 0.5);
	vec3 col = COLOR.rgb;
	if (slot == S_MARK_A) {
		col = unpack12(marks & 4095);
	} else if (slot == S_MARK_B) {
		col = unpack12((marks >> 12) & 4095);
	} else if (slot == S_DARK) {
		col = vec3(0.04, 0.035, 0.04);
	} else if (slot == S_TONGUE) {
		col = vec3(0.9, 0.4, 0.45);
	}
	col = lin(col);
	col = mix(col, vec3(dot(col, vec3(0.3, 0.6, 0.1))) * vec3(0.6, 0.6, 0.68), dead_k * 0.6);
	v_col = mix(col, vec3(1.0), hit_k * 0.8);
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float band = smoothstep(-0.02, 0.06, dot(NORMAL, LIGHT));
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * band / PI;
}
