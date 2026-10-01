// ============================================================================
// ARENA SURFACE - "The Artist's Desk": the look of every floor, wall and box.
// ============================================================================
//
// A SHADER is a small program the graphics card runs for every pixel of a
// surface. The arena is a set of plain collision boxes (arena.gd); this shader
// paints each box to look like an object on a giant artist's desk, WITHOUT
// changing its shape - so what you see always matches what you can hit.
//
// `skin` picks the look (arena.gd sets it per box):
//   0  PLAIN          the box's own colour with canvas weave and edge shading
//   1  FLOOR          the canvas you fight on: a painting in progress, with a
//                     watercolour wash per zone, pencil construction lines,
//                     dried paint flecks and masking tape round the edge
//   2  SKETCHBOOKS    low cover: a stack of three giant sketchbooks
//   3  CRAYON_BOX     hub pillars: tall crayon boxes with a zigzag label
//   4  CANVAS_WALL    building walls: stretched canvases with a mural in the
//                     building's zone colour, wooden stretcher edges
//   5  BOARD_STACK    the centre platform: stacked boards with a compass rose
//                     on top whose diagonal points use the zone colours
//   6  RULER          ramps, railings and window bars: wooden rulers
//   7  CORKBOARD      the outer walls: a cork pinboard in a wooden frame
//   8  TROUGH         the sunken lane's walls: a brushed metal paint trough
//   9  DRAWING_BOARD  the gallery's upper deck: wooden planks
//
// Effects are kept low-contrast and large, so enemies and paint (the things
// that glow) stay the most readable things on screen. Works in both renderers.

shader_type spatial;

uniform int skin = 0;
uniform vec3 albedo : source_color = vec3(0.77, 0.74, 0.70);
uniform float roughness_value = 0.92;
// The box's full size in metres (edges, book layers, ruler ticks...).
uniform vec3 box_size = vec3(1.0);
uniform float weave_strength = 0.018;
uniform float stroke_strength = 0.045;
uniform float edge_strength = 0.09;
// Floors: how many dried paint flecks (0 = none).
uniform float fleck_amount = 0.0;
// Canvas walls: the building's zone colour and a second accent colour.
uniform vec3 zone_color : source_color = vec3(0.79, 0.64, 0.36);
uniform vec3 zone_accent : source_color = vec3(0.61, 0.56, 0.77);

// Studio palette (dried paint; never the bright gameplay colours).
const vec3 OCHRE = vec3(0.788, 0.643, 0.361);
const vec3 LILAC = vec3(0.612, 0.561, 0.769);
const vec3 CLAY = vec3(0.718, 0.502, 0.431);
const vec3 SEAGLASS = vec3(0.498, 0.663, 0.639);
const vec3 ROSE = vec3(0.769, 0.537, 0.608);
const vec3 SAGE = vec3(0.518, 0.722, 0.584);
const vec3 DEEPTEAL = vec3(0.247, 0.533, 0.525);
const vec3 SLATE = vec3(0.353, 0.333, 0.471);
const vec3 GRAPHITE = vec3(0.29, 0.27, 0.376);
const vec3 PAPER = vec3(0.925, 0.894, 0.827);
const vec3 WOOD = vec3(0.659, 0.459, 0.322);
const vec3 DARKWOOD = vec3(0.431, 0.294, 0.2);
const vec3 TAPE = vec3(0.424, 0.561, 0.69);

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 box_origin;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	box_origin = MODEL_MATRIX[3].xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth random values on a grid: the basis of every soft, painterly shape.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Tints `base` toward `tint` by `amount` while keeping its brightness, so a
// colour wash never darkens or brightens the room.
vec3 wash(vec3 base, vec3 tint, float amount) {
	vec3 matched = tint * (luminance(base) / max(luminance(tint), 0.01));
	return mix(base, matched, amount);
}

// A soft line of `width` metres at distance `d`, faded out beyond `far` m.
float line_mask(float d, float width, float view_distance, float far) {
	return (1.0 - smoothstep(width * 0.5, width, abs(d))) * (1.0 - smoothstep(far * 0.6, far, view_distance));
}

// ---------------------------------------------------------------------------
// 1 FLOOR - a painting in progress
// ---------------------------------------------------------------------------
vec3 floor_skin(vec3 base, vec2 p, float view_distance) {
	vec3 c = base;
	// Watercolour washes: one per zone, with soft wobbly edges.
	float wobble = value_noise(p * 0.08) * 7.0 - 3.5;
	vec2 zones[5] = vec2[5](vec2(-28.0, -28.0), vec2(28.0, -27.0), vec2(-28.0, 28.0), vec2(16.0, 30.0), vec2(0.0, 0.0));
	vec3 tints[5] = vec3[5](OCHRE, LILAC, CLAY, SEAGLASS, ROSE);
	float radii[5] = float[5](17.0, 18.0, 19.0, 17.0, 13.0);
	for (int i = 0; i < 5; i++) {
		float d = length(p - zones[i]) + wobble;
		float amount = (1.0 - smoothstep(radii[i] * 0.5, radii[i], d)) * 0.55;
		c = wash(c, tints[i], amount);
	}
	// Pencil construction lines: long straight guides and two big circles
	// round the hub, as if the artist sketched the arena before painting it.
	float pencil = 0.0;
	pencil = max(pencil, line_mask(p.x - p.y * 0.18 - 6.0, 0.05, view_distance, 45.0));
	pencil = max(pencil, line_mask(p.y + p.x * 0.27 + 11.0, 0.05, view_distance, 45.0));
	pencil = max(pencil, line_mask(p.y - p.x * 0.9 - 3.0, 0.04, view_distance, 45.0));
	pencil = max(pencil, line_mask(length(p) - 22.0, 0.05, view_distance, 45.0));
	pencil = max(pencil, line_mask(length(p) - 31.5, 0.04, view_distance, 45.0));
	c = mix(c, GRAPHITE, pencil * 0.35);
	// Painter's tape holding the canvas down along the outer walls.
	float edge_dist = 45.0 - max(abs(p.x), abs(p.y));
	float torn = (value_noise(p * vec2(1.7, 1.7)) - 0.5) * 0.16;
	float tape = 1.0 - smoothstep(0.85, 0.95, edge_dist + torn);
	c = mix(c, TAPE, tape * 0.85);
	return c;
}

// ---------------------------------------------------------------------------
// 2 SKETCHBOOKS - three giant books stacked up
// ---------------------------------------------------------------------------
vec3 book_color(float index) {
	float r = hash(box_origin.xz + vec2(index * 3.7, index * 1.3));
	vec3 options[7] = vec3[7](ROSE, SAGE, DEEPTEAL, SLATE, OCHRE, LILAC, CLAY);
	return options[int(floor(r * 6.999))];
}

vec3 sketchbook_skin(vec3 p, vec3 ln, vec3 s, float view_distance) {
	float h = p.y + s.y * 0.5;                    // 0 at the bottom
	float f1 = s.y * 0.36;
	float f2 = s.y * 0.68;
	float book = h < f1 ? 0.0 : (h < f2 ? 1.0 : 2.0);
	float book_bottom = book < 0.5 ? 0.0 : (book < 1.5 ? f1 : f2);
	float book_top = book < 0.5 ? f1 : (book < 1.5 ? f2 : s.y);
	vec3 cover = book_color(book);
	float cover_t = clamp((book_top - book_bottom) * 0.22, 0.09, 0.16);
	// Top of the stack: the top book's cover with a paper label.
	if (ln.y > 0.6) {
		vec2 q = p.xz / (s.xz * 0.5);
		float label = step(abs(q.x), 0.42) * step(abs(q.y), 0.3);
		vec3 c = mix(cover, PAPER * 0.92, label);
		float scribble = line_mask(q.y - sin(q.x * 7.0) * 0.08, 0.05, view_distance, 25.0) * label * step(abs(q.x), 0.33);
		return mix(c, GRAPHITE, scribble * 0.6);
	}
	// Which side is the spine: the long edge.
	bool spine_on_z = s.x >= s.z;
	bool is_spine = spine_on_z ? (ln.z > 0.6 && local_normal.z > 0.0) : (ln.x > 0.6 && local_normal.x > 0.0);
	float in_cover = step(h, book_bottom + cover_t) + step(book_top - cover_t, h);
	if (is_spine || in_cover > 0.5) {
		vec3 c = cover;
		if (is_spine) {
			// A slightly darker cloth spine with a small paper title label.
			float rel = (h - book_bottom) / max(book_top - book_bottom, 0.01);
			float along_spine = spine_on_z ? p.x / (s.x * 0.5) : p.z / (s.z * 0.5);
			float label = step(abs(rel - 0.5), 0.2) * step(abs(along_spine - 0.35 + book * 0.3), 0.18);
			c = mix(c * 0.85, PAPER * 0.9, label);
		}
		return c;
	}
	// Page edges: warm paper, shaded darker toward the covers so each book
	// reads as one chunky block, with fine page lines only up close.
	float rel = (h - book_bottom - cover_t) / max(book_top - book_bottom - cover_t * 2.0, 0.01);
	float bulge = 1.0 - pow(abs(rel - 0.5) * 2.0, 2.0) * 0.18;
	float pages = sin(h * 420.0) * (1.0 - smoothstep(3.0, 8.0, view_distance));
	vec3 c = vec3(0.87, 0.82, 0.72) * (bulge + pages * 0.03);
	// A ribbon bookmark hanging out of the middle book.
	float u = ln.x > 0.6 ? p.z : p.x;
	float ribbon = step(abs(u - s.x * 0.17), 0.09) * step(abs(book - 1.0), 0.1);
	return mix(c, book_color(book + 5.0), ribbon);
}

// ---------------------------------------------------------------------------
// 3 CRAYON BOX - a tall box with a zigzag label
// ---------------------------------------------------------------------------
vec3 crayon_box_skin(vec3 p, vec3 ln, vec3 s) {
	vec3 box = vec3(0.30, 0.282, 0.42);
	if (ln.y > 0.6) {
		return box * 0.55;                        // the open top, in shadow
	}
	float u = ln.x > 0.6 ? p.z : p.x;
	float zig = abs(fract(u * 1.1) - 0.5) * 0.5;
	float centre = 0.35;
	float band = step(abs(p.y - centre), 0.75 + zig);
	float stripe = step(abs(p.y - centre + 0.95 + zig), 0.12);
	vec3 c = box;
	c = mix(c, OCHRE, band);
	c = mix(c, LILAC, stripe);
	// A cream oval logo in the middle of the band.
	vec2 q = vec2(u / 0.8, (p.y - centre) / 0.42);
	float logo = 1.0 - step(1.0, length(q));
	c = mix(c, PAPER * 0.92, logo * band);
	c = mix(c, GRAPHITE, (1.0 - step(0.06, abs(q.y - sin(q.x * 3.2) * 0.25))) * logo * 0.7);
	return c;
}

// ---------------------------------------------------------------------------
// 4 CANVAS WALL - stretched canvas with a mural, wooden stretcher edges
// ---------------------------------------------------------------------------
vec3 canvas_wall_skin(vec3 p, vec3 ln, vec3 s, vec3 base_canvas) {
	// The thinnest axis is the wall's thickness; faces across it are the canvas.
	int thin = s.x < s.z ? 0 : 2;
	if (s.y < s.x && s.y < s.z) {
		thin = 1;
	}
	float face_axis = thin == 0 ? ln.x : (thin == 2 ? ln.z : ln.y);
	if (face_axis < 0.6) {
		// Edges and top: raw stretcher wood with staples.
		float grain = value_noise(vec2((p.x + p.z) * 0.6, p.y * 9.0));
		vec3 c = WOOD * (0.85 + grain * 0.25);
		float staples = step(0.8, fract((p.x + p.z + p.y) * 3.0)) * step(abs(fract(p.y * 0.5) - 0.5), 0.05);
		return mix(c, GRAPHITE, staples * 0.6);
	}
	// The canvas face, in world space so a mural runs across a whole building.
	float u = (thin == 0 ? world_pos.z : world_pos.x);
	float v = world_pos.y;
	vec3 c = base_canvas;
	// Two big sweeping brush strokes and some soft blots.
	float s1 = abs(v - (2.1 + sin(u * 0.32) * 0.75 + sin(u * 0.9) * 0.18));
	float s2 = abs(v - (1.0 + sin(u * 0.21 + 2.0) * 0.5));
	float ragged = (value_noise(vec2(u * 2.0, v * 6.0)) - 0.5) * 0.12;
	c = mix(c, zone_color, (1.0 - smoothstep(0.3, 0.42, s1 + ragged)) * 0.62);
	c = mix(c, zone_accent, (1.0 - smoothstep(0.16, 0.24, s2 + ragged)) * 0.5);
	float blot = value_noise(vec2(u, v) * 0.55);
	c = mix(c, zone_color, smoothstep(0.72, 0.8, blot) * 0.4);
	// The canvas folds round its edges: slightly darker near the corners.
	return c;
}

// ---------------------------------------------------------------------------
// 5 BOARD STACK - centre platform with a compass rose painted on top
// ---------------------------------------------------------------------------
vec3 board_stack_skin(vec3 p, vec3 ln, vec3 s, float view_distance) {
	if (ln.y < 0.6) {
		// Three boards seen edge-on, alternating woods.
		float layer = floor((p.y + s.y * 0.5) / (s.y / 3.0));
		vec3 c = mod(layer, 2.0) < 0.5 ? WOOD : DARKWOOD * 1.2;
		float grain = value_noise(vec2((p.x + p.z) * 0.8, p.y * 30.0));
		return c * (0.88 + grain * 0.2);
	}
	vec2 q = p.xz;
	float r = length(q);
	float a = atan(q.y, q.x);
	vec3 c = PAPER * 0.86;
	// 8-point compass rose: diagonal points (toward the buildings) in the zone
	// colours, cardinal points (toward the giant landmarks) in graphite.
	float spikes8 = abs(cos(a * 4.0));
	float diagonal = step(0.5, pow(abs(sin(a * 2.0)), 4.0));
	// Long diagonal points toward the four buildings, shorter cardinal ones.
	float reach = diagonal > 0.5 ? 3.1 : 2.1;
	float star_long = step(r, 0.55 + pow(spikes8, 3.0) * reach);
	vec3 point_color = GRAPHITE;
	// Diagonals: world NE (+x,-z), NW (-x,-z), SW (-x,+z), SE (+x,+z).
	if (diagonal > 0.5) {
		point_color = q.x < 0.0 ? (q.y < 0.0 ? OCHRE : CLAY) : (q.y < 0.0 ? LILAC : SEAGLASS);
	}
	c = mix(c, point_color, star_long * 0.85);
	c = mix(c, GRAPHITE, line_mask(r - 3.25, 0.08, view_distance, 40.0) * 0.6);
	c = mix(c, GRAPHITE, line_mask(r - 3.45, 0.04, view_distance, 40.0) * 0.4);
	c = mix(c, PAPER, step(r, 0.45));
	return c;
}

// ---------------------------------------------------------------------------
// 6 RULER - wooden ruler with tick marks
// ---------------------------------------------------------------------------
vec3 ruler_skin(vec3 p, vec3 ln, vec3 s, float view_distance) {
	vec3 c = vec3(0.847, 0.725, 0.541);
	// Along the box's longest axis.
	int along = s.x >= s.y ? (s.x >= s.z ? 0 : 2) : (s.y >= s.z ? 1 : 2);
	float t = along == 0 ? p.x : (along == 1 ? p.y : p.z);
	float half_len = along == 0 ? s.x * 0.5 : (along == 1 ? s.y * 0.5 : s.z * 0.5);
	float pos = t + half_len;
	// How far across the face we are (0 at one long edge): the axis that is
	// neither the length of the ruler nor the face's own normal.
	vec3 mask = vec3(1.0) - ln;
	if (along == 0) {
		mask.x = 0.0;
	} else if (along == 1) {
		mask.y = 0.0;
	} else {
		mask.z = 0.0;
	}
	float across = dot(p + s * 0.5, mask) / max(dot(s, mask), 0.01);
	float mm = 1.0 - smoothstep(0.0, 0.012, abs(fract(pos * 10.0 + 0.5) - 0.5) / 10.0);
	float half_mark = 1.0 - smoothstep(0.0, 0.015, abs(fract(pos * 2.0 + 0.5) - 0.5) / 2.0);
	float metre = 1.0 - smoothstep(0.0, 0.02, abs(fract(pos + 0.5) - 0.5));
	float fine = 1.0 - smoothstep(4.0, 10.0, view_distance);
	float ticks = max(max(mm * step(across, 0.14) * fine, half_mark * step(across, 0.26)), metre * step(across, 0.42));
	c = mix(c, GRAPHITE, ticks * 0.75);
	// A metal edge along the far side.
	c = mix(c, vec3(0.72, 0.70, 0.78), step(0.9, across));
	return c;
}

// ---------------------------------------------------------------------------
// 7 CORKBOARD - cork in a wooden frame
// ---------------------------------------------------------------------------
vec3 corkboard_skin(vec3 p, vec3 ln, vec3 s, float view_distance) {
	float h = p.y + s.y * 0.5;
	if (h < 0.55 || h > s.y - 0.7 || ln.y > 0.6) {
		float grain = value_noise(vec2((world_pos.x + world_pos.z) * 0.5, h * 10.0));
		return DARKWOOD * (0.85 + grain * 0.3);
	}
	vec2 uv = vec2(world_pos.x + world_pos.z, world_pos.y);
	float granules = hash(floor(uv * 14.0)) * (1.0 - smoothstep(8.0, 22.0, view_distance));
	float mottle = value_noise(uv * 2.2) * 0.6 + value_noise(uv * 0.5) * 0.4;
	vec3 cork = vec3(0.64, 0.46, 0.3);
	vec3 c = cork * (0.78 + mottle * 0.34 + (granules - 0.5) * 0.16);
	// Old pin holes and faint rectangles where sheets used to hang.
	vec2 cell = floor(uv / vec2(3.1, 2.7));
	vec2 f = fract(uv / vec2(3.1, 2.7));
	float ghost_sheet = step(0.72, hash(cell)) * step(abs(f.x - 0.5), 0.3) * step(abs(f.y - 0.5), 0.38);
	return c * (1.0 - ghost_sheet * 0.08);
}

// ---------------------------------------------------------------------------
// 8 TROUGH - brushed metal paint gutter
// ---------------------------------------------------------------------------
vec3 trough_skin(vec3 p, vec3 ln, vec3 s, float view_distance) {
	vec3 c = vec3(0.46, 0.46, 0.53);
	vec2 uv = vec2(world_pos.x + world_pos.z, world_pos.y);
	float brushed = hash(vec2(floor(uv.y * 60.0), 3.0)) * (1.0 - smoothstep(4.0, 12.0, view_distance));
	c *= 0.92 + brushed * 0.1;
	// Paint runs streaking down from the top edge, in sea-glass.
	float column = floor(uv.x * 1.3);
	float run_len = 0.3 + hash(vec2(column, 7.0)) * 1.4;
	float h_from_top = (s.y * 0.5 - p.y);
	float in_column = step(abs(fract(uv.x * 1.3) - 0.5), 0.12);
	float drip = in_column * step(h_from_top, run_len) * step(0.45, hash(vec2(column, 1.0)));
	c = mix(c, SEAGLASS, drip * 0.75);
	// A row of rivets near the top.
	vec2 rivet = vec2(fract(uv.x * 2.0) - 0.5, (h_from_top - 0.15) * 2.0);
	c = mix(c, c * 0.6, 1.0 - step(0.12, length(rivet)));
	return c;
}

// ---------------------------------------------------------------------------
// 9 DRAWING BOARD - wooden planks
// ---------------------------------------------------------------------------
vec3 drawing_board_skin(vec3 p, vec3 ln, vec3 s) {
	float plank = floor(p.x / 1.15);
	float seam = step(0.97, fract(p.x / 1.15));
	float grain = value_noise(vec2(p.x * 2.0 + plank * 13.0, p.z * 0.4));
	vec3 c = mix(WOOD, DARKWOOD * 1.35, hash(vec2(plank, 2.0)) * 0.35);
	c *= 0.86 + grain * 0.22;
	return mix(c, DARKWOOD * 0.7, seam);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec3 ln = abs(local_normal);
	bool is_floor = n.y > 0.6;
	float view_distance = length(VERTEX);
	vec2 uv = is_floor ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);

	// Shared by every skin: faint canvas weave up close, broad brush variation
	// and soft darkening near box edges (which gives the boxes their shape).
	float near_fade = 1.0 - smoothstep(2.0, 7.0, view_distance);
	float weave = (sin(uv.x * 78.0) * 0.5 + sin(uv.y * 78.0) * 0.5) * near_fade;
	vec2 stroke_uv = is_floor ? uv * vec2(0.35, 1.4) : uv * vec2(1.6, 0.22);
	float stroke = value_noise(stroke_uv) * 2.0 - 1.0;
	vec3 dist_to_face = box_size * 0.5 - abs(local_pos);
	dist_to_face += ln * 1000.0;
	float edge = min(min(dist_to_face.x, dist_to_face.y), dist_to_face.z);
	float edge_shade = 1.0 - smoothstep(0.0, 0.22, edge);

	vec3 color = albedo;
	float roughness = roughness_value;
	if (skin == 1) {
		color = floor_skin(albedo, world_pos.xz, view_distance);
	} else if (skin == 2) {
		color = sketchbook_skin(local_pos, ln, box_size, view_distance);
		roughness = 0.82;
	} else if (skin == 3) {
		color = crayon_box_skin(local_pos, ln, box_size);
		roughness = 0.7;
	} else if (skin == 4) {
		color = canvas_wall_skin(local_pos, ln, box_size, albedo);
	} else if (skin == 5) {
		color = board_stack_skin(local_pos, ln, box_size, view_distance);
	} else if (skin == 6) {
		color = ruler_skin(local_pos, ln, box_size, view_distance);
		roughness = 0.6;
	} else if (skin == 7) {
		color = corkboard_skin(local_pos, ln, box_size, view_distance);
	} else if (skin == 8) {
		color = trough_skin(local_pos, ln, box_size, view_distance);
		roughness = 0.45;
	} else if (skin == 9) {
		color = drawing_board_skin(local_pos, ln, box_size);
		roughness = 0.75;
	}
	color *= 1.0 + weave * weave_strength + stroke * stroke_strength;
	color *= 1.0 - edge_shade * edge_strength;

	// Dried paint flecks on floors: at most one small fleck per 1.4 m cell.
	if (is_floor && fleck_amount > 0.0) {
		vec2 cell = floor(uv / 1.4);
		if (hash(cell) < fleck_amount) {
			vec2 centre = (cell + vec2(hash(cell + 3.1), hash(cell + 7.7)) * 0.8 + 0.1) * 1.4;
			float radius = 0.04 + hash(cell + 11.3) * 0.12;
			float fleck = 1.0 - smoothstep(radius * 0.8, radius, length(uv - centre));
			float pick = hash(cell + 19.9);
			vec3 fleck_color = pick < 0.25 ? OCHRE : (pick < 0.5 ? LILAC : (pick < 0.75 ? CLAY : SEAGLASS));
			color = mix(color, fleck_color, fleck * 0.65);
		}
	}

	ALBEDO = color;
	ROUGHNESS = roughness;
	METALLIC = skin == 8 ? 0.35 : 0.0;
}
