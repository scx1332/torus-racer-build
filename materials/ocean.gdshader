shader_type spatial;

uniform vec4 deep_color : source_color = vec4(0.025, 0.25, 0.34, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.10, 0.57, 0.54, 1.0);
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_position.x * 0.025 + TIME * 0.65) * 0.16;
	VERTEX.y += sin(world_position.z * 0.037 - TIME * 0.50) * 0.10;
}

void fragment() {
	vec2 point = world_position.xz;
	float shore = length(point / vec2(157.0, 273.0)) - 1.0;
	float shallows = exp(-max(shore, 0.0) * 8.0);
	float swell = sin(point.x * 0.055 + point.y * 0.035 + TIME * 0.65);
	float ripple = sin(point.x * 0.25 - point.y * 0.18 + TIME * 1.25);
	float detail = 1.0 - smoothstep(0.6, 2.0, length(fwidth(point)));
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, shallows * 0.82);
	ALBEDO *= 0.95 + swell * 0.035 + ripple * detail * 0.025;
	float foam_edge = shore - 0.009 * sin(atan(point.y, point.x) * 17.0 + TIME * 0.6);
	float foam_width = max(fwidth(foam_edge), 0.002);
	float foam = 1.0 - smoothstep(0.004, 0.020 + foam_width, abs(foam_edge));
	foam *= 0.5 + 0.5 * sin(point.x * 0.13 + point.y * 0.20 - TIME * 0.8);
	ALBEDO = mix(ALBEDO, vec3(0.78, 0.95, 0.86), foam * 0.28);
	vec3 water_normal = normalize(vec3(-cos(point.x * 0.12 + TIME) * 0.045,
		1.0, -cos(point.y * 0.16 - TIME * 0.8) * 0.04));
	NORMAL = normalize((VIEW_MATRIX * vec4(water_normal, 0.0)).xyz);
	ROUGHNESS = 0.65;
	SPECULAR = 0.20;
}
