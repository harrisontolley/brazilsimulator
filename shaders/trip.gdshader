shader_type canvas_item;
// What the screen does on doce and bala: colours that will not sit still, turned up too far,
// on a picture that sways.

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float hue = 0.0;      // turns of the colour wheel
uniform float sat = 1.0;
uniform float wobble = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	uv += vec2(sin(uv.y * 9.0 + TIME * 1.7), cos(uv.x * 7.0 + TIME * 1.3)) * 0.012 * wobble;
	vec3 c = texture(screen, uv).rgb;
	// Rotate about the grey axis.
	float a = hue * 6.2831853;
	vec3 k = vec3(0.57735);
	c = c * cos(a) + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - cos(a));
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(grey), c, sat), 1.0);
}
