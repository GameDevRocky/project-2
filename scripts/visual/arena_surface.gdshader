// ============================================================================
// ARENA SURFACE - the painted-studio look for every floor, wall and cover box.
// ============================================================================
//
// A SHADER is a small program the graphics card runs for every pixel of a
// surface. This one starts from the box's flat colour (the same colours
// arena.gd always used) and adds, very gently:
//
//   * a canvas weave - two sets of fine threads, faded out with distance so it
//     never shimmers far away
//   * slow, broad brush-stroke variation, so big walls are not flat plastic
//   * soft darkening near each box's edges, which gives the boxes shape
//   * dried paint flecks on floors (muted studio colours, never the bright
//     gameplay colours)
//   * an optional painted band on walls, in each area's colour, so the map's
//     regions can be told apart
//
// Every effect is centred on zero, so the AVERAGE colour of a surface stays
// the colour arena.gd asked for: the room keeps the brightness that the
// Stage-1 lighting pass tuned. Nothing here affects collision or gameplay.
//
// Works in both renderers (Forward+ on desktop, Compatibility on the web).

shader_type spatial;

uniform vec3 albedo : source_color = vec3(0.77, 0.74, 0.70);
uniform float roughness_value = 0.92;
// The box's full size in metres, so edge distance can be worked out.
uniform vec3 box_size = vec3(1.0);
uniform float weave_strength = 0.018;
uniform float stroke_strength = 0.045;
uniform float edge_strength = 0.09;
// Floors only: how many dried paint flecks (0 = none).
uniform float fleck_amount = 0.0;
uniform vec3 fleck_a : source_color = vec3(0.79, 0.64, 0.36);
uniform vec3 fleck_b : source_color = vec3(0.61, 0.56, 0.77);
uniform vec3 fleck_c : source_color = vec3(0.72, 0.50, 0.43);
uniform vec3 fleck_d : source_color = vec3(0.50, 0.66, 0.64);
// Painted band on vertical faces: colour (alpha = strength), centre height in
// world metres, and height.
uniform vec4 band_color : source_color = vec4(0.0);
uniform float band_center = 2.0;
uniform float band_height = 0.3;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth random values on a grid: the basis of the broad brush variation.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec3 n = abs(world_normal);
	bool is_floor = n.y > 0.6;
	// Pick the two world axes that run ALONG this face, so the pattern lies
	// flat on floors and stands up on walls, and continues across boxes.
	vec2 uv = is_floor ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);

	// Canvas weave: threads about 8 cm apart, only up close (gone by 7 m), so
	// it never turns into a shimmering grid at a distance.
	float view_distance = length(VERTEX);
	float near_fade = 1.0 - smoothstep(2.0, 7.0, view_distance);
	float warp = sin(uv.x * 78.0);
	float weft = sin(uv.y * 78.0);
	float weave = (warp * 0.5 + weft * 0.5) * near_fade;

	// Brush strokes: long streaks - horizontal sweeps on floors, vertical
	// drags on walls.
	vec2 stroke_uv = is_floor ? uv * vec2(0.35, 1.4) : uv * vec2(1.6, 0.22);
	float stroke = value_noise(stroke_uv) * 2.0 - 1.0;

	// Distance to the nearest edge of the face this pixel is on. The face's
	// own axis is ignored (its distance is ~0 everywhere on the face).
	vec3 dist_to_face = box_size * 0.5 - abs(local_pos);
	vec3 ln = abs(local_normal);
	dist_to_face += ln * 1000.0;
	float edge = min(min(dist_to_face.x, dist_to_face.y), dist_to_face.z);
	float edge_shade = 1.0 - smoothstep(0.0, 0.22, edge);

	vec3 color = albedo;
	color *= 1.0 + weave * weave_strength + stroke * stroke_strength;
	color *= 1.0 - edge_shade * edge_strength;

	// Dried paint flecks on floors: at most one small fleck per 1.4 m cell.
	if (is_floor && fleck_amount > 0.0) {
		vec2 cell = floor(uv / 1.4);
		float roll = hash(cell);
		if (roll < fleck_amount) {
			vec2 centre = (cell + vec2(hash(cell + 3.1), hash(cell + 7.7)) * 0.8 + 0.1) * 1.4;
			float radius = 0.04 + hash(cell + 11.3) * 0.12;
			float d = length(uv - centre);
			float fleck = 1.0 - smoothstep(radius * 0.8, radius, d);
			float pick = hash(cell + 19.9);
			vec3 fleck_color = pick < 0.25 ? fleck_a : (pick < 0.5 ? fleck_b : (pick < 0.75 ? fleck_c : fleck_d));
			color = mix(color, fleck_color, fleck * 0.65);
		}
	}

	// The painted band, on vertical faces only, with slightly ragged edges.
	if (!is_floor && band_color.a > 0.0) {
		float ragged = (value_noise(uv * vec2(3.0, 0.5)) - 0.5) * 0.06;
		float band = 1.0 - smoothstep(band_height * 0.5 - 0.02, band_height * 0.5, abs(world_pos.y - band_center + ragged));
		color = mix(color, band_color.rgb, band * band_color.a);
	}

	ALBEDO = color;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}
