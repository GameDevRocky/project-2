// WOODGRAIN - the Paint Blaster's woodgrain gun skin.
//
// Rings of light and dark wood around the gun's length, wobbled by a little
// noise so they read as grain rather than stripes. Works from the mesh's own
// (object-space) position, so the grain stays fixed to the gun as it moves.
// Runs in both renderers.

shader_type spatial;

uniform vec3 light_wood : source_color = vec3(0.69, 0.48, 0.31);
uniform vec3 dark_wood : source_color = vec3(0.45, 0.29, 0.18);
uniform float ring_scale = 90.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// Distance from the gun's long axis (local Z), plus a slow wobble along it.
	float r = length(local_pos.xy);
	float wobble = sin(local_pos.z * 22.0) * 0.004 + (hash(floor(local_pos.zz * 40.0)) - 0.5) * 0.002;
	float rings = 0.5 + 0.5 * sin((r + wobble) * ring_scale + local_pos.z * 6.0);
	rings = smoothstep(0.25, 0.85, rings);
	ALBEDO = mix(dark_wood, light_wood, rings);
	ROUGHNESS = 0.55;
	METALLIC = 0.0;
}
