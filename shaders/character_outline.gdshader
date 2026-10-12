shader_type spatial;
render_mode unshaded, cull_front;
// Inverted-hull ink outline for the cartoon character. Wanted players pulse red.

#include "res://shaders/character_pose.gdshaderinc"

varying vec3 v_col;

void vertex() {
	float dead_k;
	float hit_k;
	char_vertex(VERTEX, NORMAL, UV.x, UV2.x, INSTANCE_CUSTOM, COLOR.a, dead_k, hit_k);
	int heat = (int(INSTANCE_CUSTOM.z + 0.5) >> 18) & 3;
	// Grow with distance so the line stays about a pixel wide, but never swallows the limbs.
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float width = clamp(0.01 + dist * 0.001, 0.012, 0.035);
	float pulse = 0.5 + 0.5 * sin(now * (4.0 + float(heat) * 2.0));
	v_col = vec3(0.02, 0.02, 0.03);
	if (heat > 0) {
		width *= 1.6 + float(heat) * 0.5;
		v_col = mix(vec3(0.5, 0.0, 0.0), vec3(1.0, 0.08, 0.05), pulse);
	}
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = v_col;
}
