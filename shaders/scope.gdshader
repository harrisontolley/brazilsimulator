shader_type canvas_item;
// The view down a rifle scope: a round window, black round it, hairlines across it.

void fragment() {
	vec2 px = (UV - 0.5) / SCREEN_PIXEL_SIZE;
	float h = 1.0 / SCREEN_PIXEL_SIZE.y;
	float r = length(px);
	float lens = 0.46 * h;
	float a = smoothstep(lens - 2.0, lens + 2.0, r);
	// The glass darkens toward its rim.
	a = max(a, 0.35 * smoothstep(lens * 0.75, lens, r));
	// Hairlines, with the heavy posts coming in from the sides and below.
	float hair = max(step(abs(px.x), 0.8), step(abs(px.y), 0.8)) * step(r, lens);
	float post = max(step(abs(px.y), 3.0) * step(lens * 0.28, abs(px.x)), step(abs(px.x), 3.0) * step(lens * 0.28, px.y)) * step(r, lens);
	a = max(a, max(hair * 0.9, post));
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
