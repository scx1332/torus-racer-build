shader_type spatial;

uniform vec4 asphalt_color : source_color = vec4(0.14, 0.19, 0.23, 1.0);
uniform vec4 marking_color : source_color = vec4(0.37, 0.53, 0.56, 1.0);
uniform float marking_spacing : hint_range(2.0, 20.0) = 6.0;
uniform float marking_fade_distance : hint_range(10.0, 120.0) = 50.0;

varying vec3 world_position;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(hash(cell), hash(cell + vec2(1, 0)), t.x),
		mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1, 1)), t.x), t.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 point = world_position.xz;
	vec2 pixel_width = max(fwidth(point), vec2(0.0001));
	float distance_to_camera = length(VERTEX);
	float patches = noise(point * 0.09) * 0.65 + noise(point * 0.40) * 0.35;
	// Fine aggregate disappears smoothly before it becomes subpixel shimmer.
	float aggregate_visibility = 1.0 - smoothstep(0.02, 0.12, length(pixel_width));
	float aggregate = mix(0.5, noise(point * 37.0), aggregate_visibility);
	vec3 asphalt = asphalt_color.rgb * (0.78 + patches * 0.40 + (aggregate - 0.5) * 0.18);
	vec2 grid_distance = abs(mod(point + marking_spacing * 0.5, marking_spacing) - marking_spacing * 0.5);
	vec2 line = vec2(1.0) - smoothstep(vec2(0.022), vec2(0.022) + pixel_width, grid_distance);
	// Short survey dashes preserve a clear sense of speed without a dense horizon grid.
	vec2 dash_distance = abs(mod(point + 0.75, 1.5) - 0.75);
	vec2 dash = vec2(1.0) - smoothstep(vec2(0.28), vec2(0.28) + pixel_width, dash_distance);
	float markings = max(line.x * dash.y, line.y * dash.x);
	float fade = 1.0 - smoothstep(marking_fade_distance * 0.35, marking_fade_distance, distance_to_camera);
	float paint_wear = 0.72 + 0.28 * noise(point * 9.0);
	ALBEDO = mix(asphalt, marking_color.rgb, markings * fade * paint_wear * 0.36);
	ROUGHNESS = 0.92 - aggregate * 0.07;
	SPECULAR = 0.18;
}
