// SUIT PATTERN - the two patterned suit colours of the Canvas Runner.
//
//   mode 1  RAINBOW GRADIENT: bands of colour from the boots up to the collar
//   mode 2  CAMO GREEN: soft blobs of three greens
//
// Works from the mesh's own (object-space) position so the pattern stays put on
// the moving character. The legs are separate parts whose origin is the hip,
// so their material sets height_offset = 0.78 (the hip height) to keep the
// rainbow bands continuous from boots to collar. Runs in both renderers.

shader_type spatial;

uniform int mode = 1;
uniform vec3 base_color : source_color = vec3(0.39, 0.48, 0.28);
uniform float height_offset = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX + vec3(0.0, height_offset, 0.0);
}

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n = mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), u.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), u.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), u.x), u.y), u.z);
	return n;
}

void fragment() {
	vec3 color = base_color;
	if (mode == 1) {
		float h = clamp(local_pos.y / 1.45, 0.0, 1.0) * 5.0;
		vec3 a = vec3(0.95, 0.25, 0.55);
		vec3 b = vec3(0.95, 0.72, 0.22);
		vec3 c = vec3(0.30, 0.92, 0.62);
		vec3 d = vec3(0.25, 0.68, 0.96);
		vec3 e = vec3(0.62, 0.42, 0.95);
		color = h < 1.25 ? mix(a, b, h / 1.25) : (h < 2.5 ? mix(b, c, (h - 1.25) / 1.25)
			: (h < 3.75 ? mix(c, d, (h - 2.5) / 1.25) : mix(d, e, (h - 3.75) / 1.25)));
	} else if (mode == 2) {
		float n = noise(local_pos * 7.0) * 0.65 + noise(local_pos * 15.0) * 0.35;
		vec3 dark = base_color * 0.55;
		vec3 light = base_color * 1.25;
		color = n < 0.42 ? dark : (n < 0.62 ? base_color : light);
	}
	ALBEDO = color;
	ROUGHNESS = 0.7;
}
