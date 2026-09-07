shader_type spatial;
render_mode cull_back;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float across = (UV.x - 0.5) * 24.0;
	float distance = UV.y;
	float grain = hash21(floor(vec2(across, distance) * 65.0));
	vec3 asphalt = vec3(0.095, 0.135, 0.155) + (grain - 0.5) * 0.035;
	float far_fade = 1.0 - smoothstep(45.0, 140.0, -VERTEX.z);
	asphalt = mix(vec3(0.105, 0.145, 0.16), asphalt, far_fade);
	vec3 cream = vec3(0.96, 0.90, 0.71);
	vec3 coral = vec3(0.94, 0.25, 0.16);
	float edge = 1.0 - smoothstep(0.09, 0.13, abs(abs(across) - 11.25));
	float dash = (1.0 - step(3.2, mod(distance, 11.0)))
		* (1.0 - smoothstep(0.075, 0.11, abs(across)));
	vec3 color = mix(asphalt, cream, max(edge, dash * 0.52));
	if (abs(across) > 12.0) {
		color = mix(cream, coral, step(2.5, mod(distance, 5.0)));
	}
	if (distance > 54.0 && distance < 56.4 && abs(across) < 11.4) {
		float checker = mod(floor((across + 12.0) / 1.2) + floor((distance - 54.0) / 1.2), 2.0);
		color = mix(vec3(0.045, 0.065, 0.07), cream, checker);
	}
	ALBEDO = color;
	ROUGHNESS = 0.94;
}
