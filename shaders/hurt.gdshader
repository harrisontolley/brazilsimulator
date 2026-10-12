shader_type canvas_item;
// Red closing in from the edges of the picture when you are hit, or have little left.

uniform float amount = 0.0;

void fragment() {
	vec2 p = UV - 0.5;
	float edge = smoothstep(0.28, 0.75, length(p * vec2(1.0, 1.25)));
	COLOR = vec4(0.75, 0.02, 0.03, edge * amount);
}
