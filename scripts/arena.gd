extends Node3D

## ============================================================================
## ARENA - builds the level, the lighting and the sky in code.
## ============================================================================
##
## WHY THE LEVEL IS BUILT IN CODE RATHER THAN PLACED IN THE EDITOR
## Normally you would lay a level out by dragging nodes around in Godot's 3D
## view and saving it as a .tscn scene file. That is the better workflow once a
## level needs to be pretty. This one is built in code for one practical reason:
## every wall, pillar and light is then a few readable lines you can diff, review
## and re-tune, instead of a few hundred lines of generated scene data. When the
## layout matters for BALANCE - and here it does, because cover is the main thing
## keeping the later waves survivable - being able to see the whole layout as a
## list is worth more than being able to drag it.
##
## THE LAYOUT AND WHY IT IS SHAPED THIS WAY
## The expanded arena is 90m square and divided into a central combat hub,
## perimeter buildings, and a recessed southern lane. Three enterable buildings
## offer close-range routes and cover; the southwest building has a raised,
## reachable firing floor. Open lanes connect these areas, while offset cover
## prevents one uninterrupted sightline across the map.
##
## Nothing here is random. A learnable arena is what separates "hard" from
## "unfair" - dying should teach you the room, and a room reshuffled every run
## teaches you nothing.

const SurfaceShader = preload("res://scripts/visual/arena_surface.gdshader")
const PaintKit = preload("res://scripts/visual/paint_kit.gd")

## Half the width of the playable floor, in metres. The arena is 90m square.
const ARENA_HALF := 45.0

## How tall the boundary walls are. High enough that the Bounder pair's boosted
## jump cannot clear them and escape the level.
const WALL_HEIGHT := 9.0

## How thick the boundary walls are. Deliberately chunky - thin walls are what
## fast projectiles slip through, and thickness costs nothing here.
const WALL_THICKNESS := 2.0
const PIT_HALF_WIDTH := 8.0
const PIT_NORTH := 18.0
const PIT_SOUTH := 40.0
const PIT_DEPTH := 2.4


# --- The environment palette ------------------------------------------------
# The rule behind these colours: the ROOM sits in the middle of the brightness
# range with soft, dusty colour, so that everything you have to react to -
# enemies, cores, paint - can sit above it (brighter, more saturated, glowing)
# or, for the charcoal Monolith, clearly below it. The first version used a
# near-white floor and the exact same pink/mint/teal as the enemies, so a pink
# Sprayer in front of a pink block, or a white Ghost on the white floor, simply
# disappeared.

## Warm primed-canvas grey. Light enough to feel like a gallery floor, dark
## enough that it never blows out to white under the sun.
const FLOOR_COLOR := Color("#C4BCB3")

## Dusty violet. A mid-tone frame around the room, deliberately lighter than
## the charcoal Monolith and darker than the pastel enemies, so both read
## against it.
const WALL_COLOR := Color("#6C6592")

## Muted "room" versions of the GDD palette, used only for cover. Same hue
## family as the enemy colours, but dustier and darker, so the arena still
## looks pastel without ever matching an enemy exactly.
const COVER_SLATE := Color("#5A5578")
const COVER_ROSE := Color("#C4899B")
const COVER_SAGE := Color("#84B895")
const COVER_TEAL := Color("#3F8886")
const COVER_PALE := Color("#CBC2D6")


# --- Area identities -----------------------------------------------------------
# Each area of the map gets a painted band on its walls in its own muted studio
# colour, so you can tell where you are at a glance and learn the room faster.
# These are the same "dried paint" colours as the decoration: dusty, never the
# bright enemy or team colours.
const BAND_NW := {"color": Color("#C9A45C"), "center": 2.3, "height": 0.36}    # paint storage, ochre
const BAND_NE := {"color": Color("#9C8FC4"), "center": 2.6, "height": 0.36}    # mixing room, lilac
const BAND_SW := {"color": Color("#B7806E"), "center": 2.2, "height": 0.36}    # gallery, clay
const BAND_LANE := {"color": Color("#7FA9A3"), "center": -0.9, "height": 0.32} # runoff channel, sea-glass
const BAND_PILLAR := {"color": Color("#B7B2C6"), "center": 3.75, "height": 0.5} # hub pillars: brush-handle ferrules
const BAND_SKIRT := {"color": Color("#4E4870"), "center": 0.25, "height": 0.5}  # perimeter skirting


## Set dressing: decoration only. NONE of it has collision, and every piece
## sits where it cannot be walked into or change a sightline - flat on a wall
## (at most 0.35 m deep), above head height, on top of an existing wall, or flat
## on the floor. Each entry: model, position, turn about Y in degrees, scale.
## Wall pieces are modelled facing +Z; the turn points them into the room.
const DRESSING := [
	# Central hub: a palette inlaid in the platform top, a sculpture far overhead.
	["prop_palette_inlay", Vector3(0.0, 0.802, 0.0), 18.0, 1.0],
	["prop_hub_mobile", Vector3(0.0, 8.7, 0.0), 0.0, 1.0],
	# NW paint storage: paint can stacks on the tops of its walls.
	["prop_can_stack", Vector3(-34.0, 3.8, -30.5), 0.0, 1.0],
	["prop_can_stack", Vector3(-34.0, 3.8, -25.5), 70.0, 1.0],
	["prop_can_stack", Vector3(-32.0, 3.8, -33.0), 20.0, 1.0],
	# NE mixing room: mixing vats on its north wall.
	["prop_mixing_vat", Vector3(23.0, 4.2, -34.0), 0.0, 1.0],
	["prop_mixing_vat", Vector3(33.0, 4.2, -34.0), 140.0, 1.0],
	# SW gallery: framed canvases on the inside of its west wall.
	["prop_frame", Vector3(-37.6, 1.1, 31.0), 90.0, 1.0],
	["prop_frame", Vector3(-37.6, 1.1, 34.8), 90.0, 1.0],
	["prop_frame", Vector3(-37.6, 3.75, 24.0), 90.0, 1.0],
	# South lane runoff channel: pipes along the top of the lane walls.
	["prop_pipe_run", Vector3(7.5, -0.35, 24.0), -90.0, 1.0],
	["prop_pipe_run", Vector3(7.5, -0.35, 34.0), -90.0, 1.0],
	["prop_pipe_run", Vector3(-7.5, -0.35, 29.0), 90.0, 1.0],
	# Perimeter: murals and banners high on the walls (above 4.5 m) ...
	["prop_frame", Vector3(0.0, 5.0, -45.0), 0.0, 1.6],
	["prop_frame", Vector3(0.0, 5.0, 45.0), 180.0, 1.6],
	["prop_frame", Vector3(45.0, 5.0, 0.0), -90.0, 1.6],
	["prop_frame", Vector3(-45.0, 5.0, 0.0), 90.0, 1.6],
	["prop_banner", Vector3(-15.0, 8.7, -45.0), 0.0, 1.0],
	["prop_banner", Vector3(15.0, 8.7, -45.0), 0.0, 1.0],
	["prop_banner", Vector3(-18.0, 8.7, 45.0), 180.0, 1.0],
	["prop_banner", Vector3(18.0, 8.7, 45.0), 180.0, 1.0],
	["prop_banner", Vector3(45.0, 8.7, -15.0), -90.0, 1.0],
	["prop_banner", Vector3(45.0, 8.7, 15.0), -90.0, 1.0],
	["prop_banner", Vector3(-45.0, 8.7, -15.0), 90.0, 1.0],
	["prop_banner", Vector3(-45.0, 8.7, 15.0), 90.0, 1.0],
	# ... and giant art tools standing flush in the four corners.
	["prop_giant_brush", Vector3(41.5, 0.0, -45.0), 0.0, 1.25],
	["prop_paint_tube", Vector3(45.0, 0.0, -41.5), -90.0, 1.0],
	["prop_paint_tube", Vector3(41.5, 0.0, 45.0), 180.0, 1.0],
	["prop_giant_brush", Vector3(45.0, 0.0, 41.5), -90.0, 1.25],
	["prop_giant_brush", Vector3(-41.5, 0.0, 45.0), 180.0, 1.25],
	["prop_paint_tube", Vector3(-45.0, 0.0, 41.5), 90.0, 1.0],
	["prop_paint_tube", Vector3(-41.5, 0.0, -45.0), 0.0, 1.0],
	["prop_giant_brush", Vector3(-45.0, 0.0, -41.5), 90.0, 1.25],
]

## Old dried paint on the floor where fights happen (flat, 1 cm thick):
## position, turn, scale. Matte studio colours, so they never read as fresh
## gameplay paint.
const FLOOR_STAINS := [
	[Vector3(6.0, 0.0, -5.0), 10.0, 1.0], [Vector3(-6.5, 0.0, 4.5), 80.0, 1.2],
	[Vector3(3.0, 0.0, 7.0), 200.0, 0.9], [Vector3(-4.0, 0.0, -7.0), 140.0, 1.1],
	[Vector3(2.0, -2.4, 26.0), 30.0, 1.0], [Vector3(-3.0, -2.4, 36.0), 250.0, 1.3],
	[Vector3(-28.0, 0.0, -21.5), 60.0, 1.0], [Vector3(-21.5, 0.0, -28.0), 300.0, 0.8],
	[Vector3(28.0, 0.0, -19.0), 120.0, 1.1], [Vector3(19.0, 0.0, -27.0), 20.0, 0.9],
	[Vector3(-17.0, 0.0, 28.0), 170.0, 1.2], [Vector3(20.0, 0.0, 0.0), 45.0, 1.0],
	[Vector3(-20.0, 0.0, -3.0), 310.0, 1.1], [Vector3(0.0, 0.0, -22.0), 95.0, 1.3],
	[Vector3(0.0, 0.0, 14.0), 225.0, 0.9], [Vector3(-28.0, 3.4, 25.0), 15.0, 1.0],
]

## Which area the boxes currently being built belong to (set around each
## build step); decides the painted band and floor flecks of their material.
var _surface: Dictionary = {}


## The cover pieces, as a plain list. Each entry is where it sits, how big it
## is, and what colour. Tuning the level means editing numbers in this table.
const COVER := [
	# Central plaza pillars leave four lanes through the hub.
	{"pos": Vector3(-10.0, 0.0, -10.0), "size": Vector3(2.4, 4.5, 2.4), "color": "charcoal"},
	{"pos": Vector3(10.0, 0.0, -10.0), "size": Vector3(2.4, 4.5, 2.4), "color": "charcoal"},
	{"pos": Vector3(-10.0, 0.0, 10.0), "size": Vector3(2.4, 4.5, 2.4), "color": "charcoal"},
	{"pos": Vector3(10.0, 0.0, 10.0), "size": Vector3(2.4, 4.5, 2.4), "color": "charcoal"},
	{"pos": Vector3(-15.0, 0.0, -2.0), "size": Vector3(4.0, 1.8, 2.0), "color": "pink"},
	{"pos": Vector3(15.0, 0.0, 3.0), "size": Vector3(4.0, 1.8, 2.0), "color": "mint"},
	{"pos": Vector3(2.0, 0.0, -15.0), "size": Vector3(2.0, 1.8, 4.0), "color": "teal"},
	{"pos": Vector3(-3.0, 0.0, 15.0), "size": Vector3(2.0, 1.8, 4.0), "color": "pink"},
	{"pos": Vector3(-19.0, 0.0, -11.0), "size": Vector3(5.0, 1.4, 2.0), "color": "mint"},
	{"pos": Vector3(19.0, 0.0, 11.0), "size": Vector3(5.0, 1.4, 2.0), "color": "teal"},
	{"pos": Vector3(18.0, 0.0, -12.0), "size": Vector3(2.0, 1.4, 5.0), "color": "pink"},
	{"pos": Vector3(-18.0, 0.0, 12.0), "size": Vector3(2.0, 1.4, 5.0), "color": "mint"},
	# The raised center is useful high ground but exposed from every approach.
	{"pos": Vector3(0.0, 0.0, 0.0), "size": Vector3(8.0, 0.8, 8.0), "color": "pale"},
]


func _ready() -> void:
	_build_environment()
	_build_light()
	_build_floor()
	_build_walls()
	_build_cover()
	_build_sunken_route()
	_build_buildings()
	_build_dressing()


## The sky and the global lighting settings. A WorldEnvironment node holds an
## Environment resource, which is Godot's catch-all for "how the whole scene is
## lit and graded" - background, ambient light, glow, tonemapping.
func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()

	# A procedural sky, tinted to the GDD's pastel direction rather than the
	# default blue. It is only the backdrop you see over the walls - the
	# ambient light below comes from a fixed colour instead - so it can stay
	# pastel without flooding every shadow in the arena with light.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#8FC9CF")
	sky_material.sky_horizon_color = Color("#F1D9E3")
	sky_material.ground_bottom_color = Color("#E9E4F0")
	sky_material.ground_horizon_color = Color("#F1D9E3")
	# A soft, wide sun disc rather than a hard point, which suits the
	# "soft-edged geometric shadows" the art direction asks for.
	sky_material.sun_angle_max = 24.0
	sky_material.sun_curve = 0.18

	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.background_mode = Environment.BG_SKY

	# Ambient light is the fill light that stops shadows being pure black.
	#
	# It used to come from the sky. The pale sky poured so much light into
	# every shadow that the arena had almost no shading at all - nothing had a
	# lit side and a dark side, so nothing had shape. A fixed, soft lavender
	# fill is dimmer and fully under our control: shadows now read as cool
	# pastel shade rather than grey, which keeps the stylised look while
	# giving every box a readable light side and dark side.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#B3AED6")
	env.ambient_light_energy = 0.6
	# 0 = "none of the ambient comes from the sky". Only matters if the source
	# above is ever switched back to the sky, but it keeps intent obvious.
	env.ambient_light_sky_contribution = 0.0

	# Screen-space ambient occlusion: soft contact shadow where things meet -
	# cover on the floor, props against walls, a character's feet. It gives
	# the room depth without making anything darker overall. Forward+ only;
	# the web (Compatibility) renderer simply ignores it.
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4

	# Glow makes bright things bleed light into their surroundings. The paint
	# globs, the enemy bodies and the dropped cores all use emissive materials,
	# so this is what makes them glow rather than just look brightly coloured.
	#
	# The rule is that ONLY gameplay objects glow. The room is lit to stay
	# below the threshold, and bloom - which makes glow spill out of areas
	# darker than the threshold too - is off, because it was hazing the whole
	# screen and washing out exactly the things glow is meant to pick out.
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0

	# Tonemapping maps the renderer's internal brightness range onto what a
	# monitor can actually show. FILMIC rolls highlights off gently.
	#
	# tonemap_white is the brightness that counts as "pure white". It was 1.0,
	# which meant the sunlit floor - lit well past 1.0 - clipped to flat white,
	# and every pastel enemy standing on it clipped toward white with it. At
	# 3.0 the room lands in the middle of the range, and the top of the range
	# is left free for the things that glow.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 3.0

	# A light pastel haze that gets thicker with distance. The far walls fade
	# slightly toward lavender, which gives the room depth. Enemies, cores and
	# paint switch fog off on their own materials, so they stay crisp at any
	# range and stand out against the hazier room behind them.
	env.fog_enabled = true
	env.fog_light_color = Color("#C9C0DE")
	env.fog_density = 0.007
	# Leave the sky alone - it already has its own colours.
	env.fog_sky_affect = 0.0

	world.environment = env
	add_child(world)


## One directional light, which is the engine's model of the sun: parallel rays
## with a direction but no position, so it lights the whole arena evenly.
func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	# Angled down and across rather than straight overhead, so the pillars throw
	# long readable shadows and the geometry has some shape to it.
	sun.rotation_degrees = Vector3(-52.0, -47.0, 0.0)
	sun.light_energy = 1.0

	# The browser build runs on Godot's Compatibility renderer, not the
	# desktop Forward+ one. Measured on this exact scene in Godot 4.7.2, the
	# Compatibility renderer draws a SHADOW-CASTING sun far brighter than
	# Forward+ does at the same energy - about 2.7x on the floor - while with
	# shadows off the two match pixel for pixel. Left alone, the web version
	# washes straight back out. 0.25 was picked by comparing screenshots from
	# both renderers until the sunlit floor matched.
	#
	# This asks which renderer is running rather than which platform, because
	# a desktop with an old graphics card can fall back to Compatibility too.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		sun.light_energy = 0.25
	# A warm sun against the cool lavender fill. Warm light and cool shade is
	# the classic painter's trick for depth: lit faces and shaded faces differ
	# in colour as well as brightness, so shapes read clearly without the
	# shadows having to go dark and muddy.
	sun.light_color = Color("#FFEEDB")

	sun.shadow_enabled = true
	# A small bias nudges shadows away from the surface casting them, which
	# removes "shadow acne" - the stippled self-shadowing artefact you get on
	# large flat surfaces like this arena's floor.
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	# Four shadow splits keeps shadows sharp near the player and cheap far away.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 80.0

	add_child(sun)


func _build_floor() -> void:
	# Leave a cutout for the recessed lower route; every section retains the
	# original collision-backed box floor.
	# Floors get the scattered dried-paint flecks of a well-used studio floor.
	_surface = {"fleck": 0.3}
	var span := ARENA_HALF * 2.0
	var north_depth := PIT_NORTH + ARENA_HALF
	_add_solid(Vector3(0.0, -0.5, (-ARENA_HALF + PIT_NORTH) * 0.5),
		Vector3(span, 1.0, north_depth), FLOOR_COLOR, 0.95)
	var south_depth := ARENA_HALF - PIT_SOUTH
	_add_solid(Vector3(0.0, -0.5, (PIT_SOUTH + ARENA_HALF) * 0.5),
		Vector3(span, 1.0, south_depth), FLOOR_COLOR, 0.95)
	var side_depth := PIT_SOUTH - PIT_NORTH
	var side_width := ARENA_HALF - PIT_HALF_WIDTH
	_add_solid(Vector3(-(ARENA_HALF + PIT_HALF_WIDTH) * 0.5, -0.5,
		(PIT_NORTH + PIT_SOUTH) * 0.5), Vector3(side_width, 1.0, side_depth), FLOOR_COLOR, 0.95)
	_add_solid(Vector3((ARENA_HALF + PIT_HALF_WIDTH) * 0.5, -0.5,
		(PIT_NORTH + PIT_SOUTH) * 0.5), Vector3(side_width, 1.0, side_depth), FLOOR_COLOR, 0.95)
	_surface = {}


func _build_walls() -> void:
	var span: float = ARENA_HALF * 2.0
	var offset: float = ARENA_HALF + WALL_THICKNESS * 0.5
	var wall_color := WALL_COLOR
	# A darker skirting along the foot of the outer walls grounds them.
	_surface = {"band": BAND_SKIRT}

	# North and south.
	_add_solid(Vector3(0.0, WALL_HEIGHT * 0.5, -offset),
		Vector3(span + WALL_THICKNESS * 2.0, WALL_HEIGHT, WALL_THICKNESS), wall_color, 0.9)
	_add_solid(Vector3(0.0, WALL_HEIGHT * 0.5, offset),
		Vector3(span + WALL_THICKNESS * 2.0, WALL_HEIGHT, WALL_THICKNESS), wall_color, 0.9)
	# East and west.
	_add_solid(Vector3(-offset, WALL_HEIGHT * 0.5, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, span), wall_color, 0.9)
	_add_solid(Vector3(offset, WALL_HEIGHT * 0.5, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, span), wall_color, 0.9)

	# A ceiling, invisible but solid. Nothing should ever reach it, but the
	# Bounder pair's boosted jump off the centre platform gets closer than you
	# would think, and a player who clips over a wall is a run ended by a bug.
	_add_solid(Vector3(0.0, WALL_HEIGHT + 0.5, 0.0),
		Vector3(span, 1.0, span), wall_color, 0.9, false)
	_surface = {}


func _build_cover() -> void:
	for piece in COVER:
		var size: Vector3 = piece["size"]
		var pos: Vector3 = piece["pos"]
		# The table stores the position of a piece's BASE, which is how you
		# actually think about placing cover. Boxes are centred on their origin,
		# so lift each one by half its height to stand it on the floor.
		var centre: Vector3 = pos + Vector3(0.0, size.y * 0.5, 0.0)
		# The four tall hub pillars get a metal ferrule band near the top, so
		# they read as giant brush handles planted round the centre.
		_surface = {"band": BAND_PILLAR} if piece["color"] == "charcoal" else {}
		_add_solid(centre, size, _palette(piece["color"]), 0.9)
	_surface = {}


func _build_sunken_route() -> void:
	_surface = {"fleck": 0.3}
	_add_solid(Vector3(0.0, -PIT_DEPTH - 0.5, (PIT_NORTH + PIT_SOUTH) * 0.5),
		Vector3(PIT_HALF_WIDTH * 2.0, 1.0, PIT_SOUTH - PIT_NORTH), FLOOR_COLOR, 0.95)
	_surface = {"band": BAND_LANE}
	# Retaining-wall openings align with collision-backed ramps at either end.
	for end_z in [PIT_NORTH + 0.1, PIT_SOUTH - 0.1]:
		for side_x in [-5.3, 5.3]:
			_add_solid(Vector3(side_x, -1.15, end_z),
				Vector3(5.4, 2.5, 0.35), COVER_PALE, 0.9)
	_add_solid(Vector3(0.0, -1.33, PIT_NORTH + 3.0),
		Vector3(5.0, 0.4, 6.5), COVER_SAGE, 0.9, true, Vector3(21.25, 0.0, 0.0))
	_add_solid(Vector3(0.0, -1.33, PIT_SOUTH - 3.0),
		Vector3(5.0, 0.4, 6.5), COVER_ROSE, 0.9, true, Vector3(-21.25, 0.0, 0.0))
	_add_solid(Vector3(-7.75, -1.2, (PIT_NORTH + PIT_SOUTH) * 0.5),
		Vector3(0.5, 2.4, PIT_SOUTH - PIT_NORTH), COVER_SLATE, 0.9)
	_add_solid(Vector3(7.75, -1.2, (PIT_NORTH + PIT_SOUTH) * 0.5),
		Vector3(0.5, 2.4, PIT_SOUTH - PIT_NORTH), COVER_SLATE, 0.9)
	_add_solid(Vector3(0.0, -1.55, 27.0), Vector3(4.5, 1.7, 0.7), COVER_TEAL, 0.9)
	_add_solid(Vector3(-3.5, -1.55, 33.0), Vector3(4.5, 1.7, 0.7), COVER_ROSE, 0.9)
	_surface = {}


func _build_buildings() -> void:
	# Northwest compact room: three exits support quick close-range flanks.
	_surface = {"band": BAND_NW}
	_build_room_shell(Vector3(-28.0, 0.0, -28.0), 12.0, 10.0, 3.8,
		COVER_PALE, [&"north", &"south", &"east"])
	_add_solid(Vector3(-34.0, 2.8, -28.0), Vector3(0.35, 0.45, 3.0), COVER_ROSE, 0.8)
	_add_solid(Vector3(-22.0, 2.8, -28.0), Vector3(0.35, 0.45, 3.0), COVER_TEAL, 0.8)

	# Northeast two-room building, open to west, east, and south approaches.
	_surface = {"band": BAND_NE}
	_build_room_shell(Vector3(28.0, 0.0, -27.0), 17.0, 14.0, 4.2,
		COVER_SAGE, [&"south", &"west", &"east"])
	_build_partition(Vector3(28.0, 0.0, -29.0), 12.0, 3.4, 0.55, COVER_SLATE)

	# Southwest building: multiple ground exits, raised firing lane, walk-up ramp.
	_surface = {"band": BAND_SW}
	_build_room_shell(Vector3(-28.0, 0.0, 28.0), 20.0, 18.0, 5.0,
		COVER_ROSE, [&"north", &"east", &"south"])
	_add_solid(Vector3(-28.0, 3.2, 24.0), Vector3(14.0, 0.4, 8.0), COVER_PALE, 0.85)
	# The high end meets the south edge of the upper deck instead of running
	# underneath it, so the player can walk cleanly from slope onto floor.
	_add_solid(Vector3(-22.0, 1.6, 32.25), Vector3(3.0, 0.4, 8.5), COVER_TEAL, 0.85,
		true, Vector3(21.8, 0.0, 0.0))
	_add_solid(Vector3(-34.5, 3.75, 25.0), Vector3(0.35, 0.8, 5.0), COVER_SAGE, 0.85)
	_add_solid(Vector3(-27.0, 3.75, 20.2), Vector3(13.0, 0.8, 0.35), COVER_SAGE, 0.85)
	_surface = {}


func _build_room_shell(center: Vector3, width: float, depth: float, height: float,
		color: Color, doors: Array) -> void:
	var thickness := 0.8
	var opening := 3.6
	var half_w := width * 0.5
	var half_d := depth * 0.5
	for side in [&"north", &"south"]:
		var z := center.z + (-half_d if side == &"north" else half_d)
		if doors.has(side):
			var segment_w := (width - opening) * 0.5
			_add_solid(Vector3(center.x - (opening + segment_w) * 0.5, height * 0.5, z),
				Vector3(segment_w, height, thickness), color, 0.88)
			_add_solid(Vector3(center.x + (opening + segment_w) * 0.5, height * 0.5, z),
				Vector3(segment_w, height, thickness), color, 0.88)
		else:
			_add_solid(Vector3(center.x, height * 0.5, z),
				Vector3(width, height, thickness), color, 0.88)
	for side in [&"west", &"east"]:
		var x := center.x + (-half_w if side == &"west" else half_w)
		if doors.has(side):
			var segment_d := (depth - opening) * 0.5
			_add_solid(Vector3(x, height * 0.5, center.z - (opening + segment_d) * 0.5),
				Vector3(thickness, height, segment_d), color, 0.88)
			_add_solid(Vector3(x, height * 0.5, center.z + (opening + segment_d) * 0.5),
				Vector3(thickness, height, segment_d), color, 0.88)
		else:
			_add_solid(Vector3(x, height * 0.5, center.z),
				Vector3(thickness, height, depth), color, 0.88)


func _build_partition(center: Vector3, width: float, opening: float,
		thickness: float, color: Color) -> void:
	var segment := (width - opening) * 0.5
	_add_solid(center + Vector3(-(opening + segment) * 0.5, 1.7, 0.0),
		Vector3(segment, 3.4, thickness), color, 0.9)
	_add_solid(center + Vector3((opening + segment) * 0.5, 1.7, 0.0),
		Vector3(segment, 3.4, thickness), color, 0.9)


## game.gd calls this while choosing its existing spawn ring. The ring crosses
## the recessed lane and building shells, so reject those footprints and any
## point where a standing enemy capsule would overlap world collision.
func is_enemy_spawn_point_clear(candidate: Vector3) -> bool:
	if (absf(candidate.x) < PIT_HALF_WIDTH + 1.5
			and candidate.z > PIT_NORTH - 1.5
			and candidate.z < PIT_SOUTH + 1.5):
		return false
	if _inside_rect(candidate, Vector2(-35.5, -34.5), Vector2(-20.5, -21.5)):
		return false
	if _inside_rect(candidate, Vector2(18.0, -35.5), Vector2(38.0, -18.5)):
		return false
	if _inside_rect(candidate, Vector2(-39.5, 17.5), Vector2(-16.5, 38.5)):
		return false

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.65
	capsule.height = 2.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, candidate + Vector3(0.0, 1.3, 0.0))
	query.collision_mask = 1
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _inside_rect(point: Vector3, minimum: Vector2, maximum: Vector2) -> bool:
	return (point.x >= minimum.x and point.x <= maximum.x
		and point.z >= minimum.y and point.z <= maximum.y)


## Turns the colour names used in the COVER table into real colours.
##
## The names still say "pink", "mint" and so on, but they now map to the
## muted room versions above rather than the exact Traits colours. Those exact
## colours belong to the enemies and their cores; cover sharing them is what
## made enemies vanish against it.
func _palette(name: String) -> Color:
	match name:
		"charcoal":
			return COVER_SLATE
		"pink":
			return COVER_ROSE
		"mint":
			return COVER_SAGE
		"teal":
			return COVER_TEAL
		"pale":
			return COVER_PALE
		_:
			return FLOOR_COLOR


## Builds one solid box: a StaticBody3D with a matching collision shape and,
## optionally, a visible mesh.
##
## StaticBody3D is the physics body for things that never move. It is far
## cheaper than the alternatives because the engine knows it never has to
## recompute where it is.
##
## Everything built here sits on collision layer 1, which every other script in
## the project refers to as "the world" - it is what paint stops against, what
## blocks enemy line of sight, and what the player walks on.
func _add_solid(centre: Vector3, size: Vector3, box_color: Color,
		roughness: float, visible_mesh: bool = true,
		rotation_degrees: Vector3 = Vector3.ZERO) -> void:

	var body := StaticBody3D.new()
	body.position = centre
	body.rotation_degrees = rotation_degrees
	body.collision_layer = 1
	# A static body never moves, so it never needs to go looking for things to
	# collide with - other bodies find it. Leaving its mask at 0 saves the
	# engine a pile of pointless checks every frame.
	body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	if visible_mesh:
		var mesh_node := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh_node.mesh = box

		mesh_node.material_override = _surface_material(box_color, roughness, size)

		body.add_child(mesh_node)

	add_child(body)


## The painted-studio surface for one box: the flat colour this file always
## used, plus the canvas weave, edge shading, and the current area's band or
## floor flecks (scripts/visual/arena_surface.gdshader). Only how the box LOOKS
## changes; its collision is built separately above.
func _surface_material(box_color: Color, roughness: float, size: Vector3) -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = SurfaceShader
	mat.set_shader_parameter("albedo", box_color)
	mat.set_shader_parameter("roughness_value", roughness)
	mat.set_shader_parameter("box_size", size)
	mat.set_shader_parameter("fleck_amount", float(_surface.get("fleck", 0.0)))
	if _surface.has("band"):
		var band: Dictionary = _surface["band"]
		mat.set_shader_parameter("band_color", Color(band["color"], 0.85))
		mat.set_shader_parameter("band_center", float(band["center"]))
		mat.set_shader_parameter("band_height", float(band["height"]))
	return mat


## Places the decoration from DRESSING and FLOOR_STAINS. Visual nodes only:
## nothing here adds a physics body, so movement, cover and sightlines are
## exactly as before. Skipped quietly if the generated models are missing.
func _build_dressing() -> void:
	# Load the paint glob and splat models now, during setup, instead of at
	# the first shot of the match (which caused a brief stutter).
	PaintKit.warm_up()
	var dressing := Node3D.new()
	dressing.name = "Dressing"
	add_child(dressing)
	for entry in DRESSING:
		var prop := PaintKit.instance(entry[0])
		if prop == null:
			continue
		dressing.add_child(prop)
		prop.position = entry[1]
		prop.rotation.y = deg_to_rad(entry[2])
		prop.scale = Vector3.ONE * float(entry[3])
		# Flat pieces hung on walls or laid on the floor throw no visible
		# shadow, so skip drawing them into the shadow maps at all.
		if entry[0] in ["prop_frame", "prop_banner", "prop_pipe_run", "prop_palette_inlay"]:
			PaintKit.set_shadows(prop, false)
	for i in FLOOR_STAINS.size():
		var stain_mesh := PaintKit.mesh("prop_splat_decor", "Decor_%d" % (i % 4))
		if stain_mesh == null:
			break
		var stain := MeshInstance3D.new()
		stain.mesh = stain_mesh
		stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dressing.add_child(stain)
		var entry: Array = FLOOR_STAINS[i]
		# A hair above the floor so the two surfaces never flicker.
		stain.position = entry[0] + Vector3(0.0, 0.004, 0.0)
		stain.rotation.y = deg_to_rad(entry[1])
		stain.scale = Vector3.ONE * float(entry[2])


## Hands game.gd a ring of positions to spawn enemies at, spread evenly around
## the arena's outer edge.
##
## Spawning on a ring rather than at a handful of fixed points means waves come
## at you from every side, so you are never able to park in one corner and hold
## a single angle for a whole run.
func get_spawn_ring(count: int, radius: float) -> Array:
	var points: Array = []
	if count <= 0:
		return points

	for i in count:
		# TAU is a full turn in radians (2 x PI). Dividing it by the number of
		# spawns spaces them equally around the circle.
		var angle: float = TAU * float(i) / float(count)
		points.append(Vector3(sin(angle) * radius, 0.35, cos(angle) * radius))

	return points
