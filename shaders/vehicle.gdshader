shader_type spatial;
// Vehicles are one vertex-coloured mesh. Parts painted with zero alpha take the paint
// job of the individual vehicle instead; parts with alpha above one glow (lights).

instance uniform vec3 paint : source_color = vec3(0.8);

varying flat vec3 col;
varying flat float glow;

void vertex() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	col = COLOR.a < 0.01 ? paint * (0.55 + 0.45 * COLOR.r) : base;
	glow = COLOR.a > 1.5 ? 2.5 : 0.0;
}

void fragment() {
	ALBEDO = col;
	EMISSION = col * glow;
	ROUGHNESS = 0.45;
	METALLIC = 0.1;
}
