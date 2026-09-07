shader_type spatial;

uniform vec4 rock_color : source_color = vec4(0.69, 0.39, 0.26, 1.0);
uniform vec4 layer_color : source_color = vec4(0.90, 0.66, 0.43, 1.0);
uniform vec4 top_color : source_color = vec4(0.42, 0.48, 0.30, 1.0);
varying vec3 world_position;
varying float upward;

float hash(vec2 point) {
	vec3 p = fract(vec3(point.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(mix(hash(cell), hash(cell + vec2(1, 0)), blend.x),
		mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1, 1)), blend.x), blend.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	upward = dot(normalize(MODEL_NORMAL_MATRIX * NORMAL), vec3(0.0, 1.0, 0.0));
}

void fragment() {
	float erosion = noise(world_position.xz * 0.11);
	float strata = sin(world_position.y * 1.6 + erosion * 2.5) * 0.5 + 0.5;
	vec3 stone = mix(rock_color.rgb, layer_color.rgb, smoothstep(0.3, 0.8, strata) * 0.55);
	float surface_noise = noise(world_position.xz * 0.065) * 0.7 + noise(world_position.xz * 0.38) * 0.3;
	vec3 soil = top_color.rgb * (0.83 + surface_noise * 0.30);
	ALBEDO = mix(stone, soil, smoothstep(0.65, 0.95, upward));
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
