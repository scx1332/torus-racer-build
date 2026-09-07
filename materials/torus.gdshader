shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 dough_color : source_color = vec4(0.91, 0.52, 0.17, 1.0);
uniform vec4 crust_color : source_color = vec4(0.55, 0.23, 0.065, 1.0);
uniform vec4 icing_color : source_color = vec4(1.0, 0.20, 0.36, 1.0);
uniform float sprinkle_density : hint_range(0.0, 1.0) = 0.70;

varying vec3 mesh_position;
varying vec3 mesh_normal;

float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(mix(hash(cell), hash(cell + vec3(1, 0, 0)), t.x),
		mix(hash(cell + vec3(0, 1, 0)), hash(cell + vec3(1, 1, 0)), t.x), t.y),
		mix(mix(hash(cell + vec3(0, 0, 1)), hash(cell + vec3(1, 0, 1)), t.x),
		mix(hash(cell + vec3(0, 1, 1)), hash(cell + vec3(1, 1, 1)), t.x), t.y), t.z);
}

vec3 candy_color(float choice) {
	if (choice < 0.20) { return vec3(1.0, 0.83, 0.27); }
	if (choice < 0.40) { return vec3(0.20, 0.86, 0.87); }
	if (choice < 0.60) { return vec3(1.0, 0.89, 0.81); }
	if (choice < 0.80) { return vec3(0.55, 0.23, 0.80); }
	return vec3(0.98, 0.31, 0.11);
}

void vertex() {
	mesh_position = VERTEX;
	mesh_normal = NORMAL;
}

void fragment() {
	// All detail follows the mesh as it rolls; no texture files or fixed radii needed.
	float angle = atan(mesh_position.z, mesh_position.x);
	float baked = noise(mesh_position * 4.0) * 0.70 + noise(mesh_position * 11.0) * 0.30;
	float pores = noise(mesh_position * 95.0);
	float pore_visibility = 1.0 - smoothstep(0.30, 1.2, length(fwidth(mesh_position * 95.0)));
	pores = mix(0.5, pores, pore_visibility);
	vec3 dough = mix(dough_color.rgb, crust_color.rgb, smoothstep(0.26, 0.91, baked) * 0.65);
	// The pale frying belt and uneven toast also make spin easy to read.
	float belt = 1.0 - smoothstep(0.08, 0.29, abs(mesh_normal.y + 0.04 * sin(angle * 5.0)));
	dough = mix(dough, vec3(1.0, 0.70, 0.34), belt * 0.30);
	dough *= 0.90 + pores * 0.18;
	float drips = 0.14 * sin(angle * 7.0 + 0.8) + 0.10 * sin(angle * 11.0 - 1.2);
	drips += 0.21 * pow(0.5 + 0.5 * sin(angle * 5.0), 6.0);
	float icing_edge = mesh_normal.y + 0.08 + drips;
	float edge_width = max(fwidth(icing_edge), 0.016);
	float icing = smoothstep(-edge_width, edge_width, icing_edge);
	vec3 glaze = icing_color.rgb * (0.91 + 0.14 * noise(mesh_position * 7.0));
	// A softly raised lip catches the light around individual icing drips.
	float lip = exp(-abs(icing_edge) * 30.0) * icing;
	glaze = mix(glaze, vec3(1.0, 0.47, 0.52), lip * 0.24);
	ALBEDO = mix(dough, glaze, icing);
	ROUGHNESS = mix(0.79 + pores * 0.10, 0.36, icing);
	SPECULAR = mix(0.25, 0.44, icing);
	float height = (pores - 0.5) * 0.0022 * (1.0 - icing) + lip * 0.0035;

	// Rounded, randomly rotated sprinkles. Integer UV repeats keep the seams closed.
	vec2 sprinkle_uv = UV * vec2(34.0, 12.0);
	vec2 cell = floor(sprinkle_uv);
	vec2 point = fract(sprinkle_uv) - 0.5;
	float seed = hash(vec3(cell, 2.4));
	point -= vec2(hash(vec3(cell, 4.1)), hash(vec3(cell, 8.7))) * 0.28 - 0.14;
	float turn = seed * TAU;
	point = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * point;
	vec2 capsule = vec2(max(abs(point.x) - 0.16, 0.0), point.y);
	float distance_to_candy = length(capsule) - 0.066;
	float candy_width = max(fwidth(distance_to_candy), 0.015);
	float candy = (1.0 - smoothstep(-candy_width, candy_width, distance_to_candy));
	candy *= step(seed, sprinkle_density) * smoothstep(0.06, 0.15, icing_edge);
	ALBEDO = mix(ALBEDO, candy_color(hash(vec3(cell, 15.0))), candy);
	ROUGHNESS = mix(ROUGHNESS, 0.43, candy);
	// Subpixel sugar relief fades before it creates isolated specular sparkles.
	float candy_relief = 1.0 - smoothstep(0.055, 0.16, candy_width);
	height += candy * candy_relief * 0.002;
	// Screen derivatives add tiny pore/sugar relief without changing the collision.
	vec3 surface_x = dFdx(VERTEX);
	vec3 surface_y = dFdy(VERTEX);
	vec3 across_y = cross(surface_y, NORMAL);
	vec3 across_x = cross(NORMAL, surface_x);
	float determinant = dot(surface_x, across_y);
	vec3 gradient = across_y * dFdx(height) + across_x * dFdy(height);
	NORMAL = normalize(NORMAL - gradient * sign(determinant) / max(abs(determinant), 0.000001));
}
