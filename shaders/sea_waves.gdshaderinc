// The sea's surface, shared by its two qualities: see sea_fn.gdshaderinc for the waves.
#include "sea_fn.gdshaderinc"

varying vec3 wp;
varying float cell;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Nothing to draw up the beach: fold everything inland of the waterline onto it.
	w.z = min(w.z, shore_z + 2.0);
	cell = UV.x;
	w.y = sea_y + sea_h(w.xz, cell);
	wp = w;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}

void fragment() {
	if (abs(wp.x - hull.x) < hull.z && abs(wp.z - hull.y) < hull.w) {
		discard;
	}
	float dist = length(VERTEX);
	vec2 slope = sea_slope(wp.xz, dist);
	// Chop: two sheets of ripples sliding across each other, fading with distance.
	float near = 1.0 / (1.0 + dist * 0.05);
	float c0 = sea_chop(wp.xz);
	slope += vec2(sea_chop(wp.xz + vec2(0.12, 0.0)) - c0, sea_chop(wp.xz + vec2(0.0, 0.12)) - c0) * (2.2 + 2.0 * sea_storm) * near;
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	if (!FRONT_FACING) {
		n = -n;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// Worked out afresh for every pixel: taken from the mesh, the foam would follow its triangles.
	float h = sea_h(wp.xz, 0.0);
	float under = max(sea_y + h - sea_bed(wp.z), 0.0);
	// Clear over the sand, then green, then the blue of deep water.
	vec3 body = mix(shallow, deep, 1.0 - exp(-under * 0.22));
	body = mix(body, vec3(0.16, 0.22, 0.26), sea_storm * 0.6);
	float thick = clamp(1.0 - exp(-under * 0.55), 0.0, 1.0);

	// Foam: the wash running up the sand, lines of it left behind, and the tops of waves.
	float grain = clamp(0.5 + sea_chop(wp.xz * 1.6 + 31.0) * 0.85, 0.0, 1.0);
	float wash = smoothstep(0.32, 0.02, under) * step(0.001, under);
	float lines = smoothstep(0.55, 1.0, sin(under * 7.0 - sea_time * 1.3 + grain * 4.0)) * smoothstep(2.2, 0.3, under) * 0.6;
	float crest = smoothstep(0.5, 0.95, h / (0.42 * sea_amp(wp.xz))) * smoothstep(0.35, 0.8, grain) * (0.35 + 0.65 * sea_storm) * near;
	float foam = clamp(wash + lines + crest, 0.0, 1.0);

#ifdef SEA_HIGH
	float frag_z = -VERTEX.z;
	float raw = texture(depth_tex, SCREEN_UV).x;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float behind = -v.z / v.w - frag_z;
	// Froth where anything breaks the surface.
	foam = clamp(foam + smoothstep(0.45, 0.0, behind) * (0.5 + 0.5 * grain) * step(1.0, under + 0.75), 0.0, 1.0);
	// What is under the water, seen a little out of place.
	vec2 bent = SCREEN_UV + n.xz * 0.03 * clamp(behind, 0.0, 1.0) / (1.0 + frag_z * 0.05);
	float raw_b = texture(depth_tex, bent).x;
	vec4 vb = INV_PROJECTION_MATRIX * vec4(bent * 2.0 - 1.0, raw_b, 1.0);
	if (-vb.z / vb.w < frag_z) {
		bent = SCREEN_UV;
	}
	vec3 seen = texture(screen_tex, bent).rgb;
	if (FRONT_FACING) {
		// Looking down through more water hides more of the bottom.
		thick = clamp(1.0 - exp(-max(behind, 0.0) * 0.3), thick * 0.35, 1.0);
		thick = max(thick, foam);
		ALBEDO = mix(body, vec3(0.96), foam) * thick;
		EMISSION = seen * (1.0 - thick) * mix(vec3(1.0), shallow + 0.35, 0.35);
	} else {
		// From below: the bright window of the sky, wobbling.
		ALBEDO = body * 0.25;
		EMISSION = seen * vec3(0.55, 0.9, 0.95) * 0.9 + shallow * 0.12 * (1.0 - night);
	}
#else
	ALBEDO = mix(body, vec3(0.96), foam);
	ALPHA = FRONT_FACING ? max(mix(0.5, 0.97, thick), foam) : 0.7;
#endif
	// Far off, a mirror-smooth sea is all glitter: let it go matt toward the horizon.
	ROUGHNESS = mix(0.06, 0.6, foam) + 0.1 * sea_storm + 0.3 * smoothstep(60.0, 500.0, dist);
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
