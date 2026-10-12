shader_type spatial;
render_mode unshaded, cull_front;
// Inverted-hull ink outline for the dogs, to match the people.

#include "res://shaders/dog_pose.gdshaderinc"

void vertex() {
	float dead_k;
	float hit_k;
	dog_vertex(VERTEX, NORMAL, UV2.x, INSTANCE_CUSTOM, COLOR.a, dead_k, hit_k);
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX += NORMAL * clamp(0.01 + dist * 0.001, 0.012, 0.03);
}

void fragment() {
	ALBEDO = vec3(0.02, 0.02, 0.03);
}
