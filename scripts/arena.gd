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
## The expanded arena is 135m square and divided into a central combat hub,
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

## Half the width of the playable floor, in metres. The arena is 135m square.
const ARENA_HALF := 67.5

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
const TEAM_RED := Color("#FF5477")
const TEAM_BLUE := Color("#4CC9FF")
const ARENA_GLOW := Color("#8BFFB4")

var _accent_time: float = 0.0
var _pulse_materials: Array[StandardMaterial3D] = []


# --- "The Artist's Desk" -----------------------------------------------------
# The arena is themed as the top of a giant artist's desk, and every collision
# box is PAINTED to look like an object on it (scripts/visual/arena_surface.
# gdshader) without changing its shape - so what you see is always exactly what
# you can hit or hide behind. Which look each box gets:
const SKIN_PLAIN := 0
const SKIN_FLOOR := 1          # the canvas being painted, with a wash per zone
const SKIN_SKETCHBOOKS := 2    # low cover
const SKIN_CRAYON_BOX := 3     # the four hub pillars
const SKIN_CANVAS_WALL := 4    # building walls: stretched canvases with murals
const SKIN_BOARD_STACK := 5    # the centre platform, compass rose on top
const SKIN_RULER := 6          # ramps, railings, window bars
const SKIN_CORKBOARD := 7      # the outer walls
const SKIN_TROUGH := 8         # the sunken lane's walls: a metal paint trough
const SKIN_DRAWING_BOARD := 9  # the gallery's upper deck

# Each building is a different zone colour, repeated in its mural, in the floor
# wash around it, and on its point of the centre compass, so you can tell where
# you are at a glance: NW paint storage = ochre, NE mixing room = lilac,
# SW gallery = clay, the south lane = sea-glass.
const OCHRE := Color("#C9A45C")
const LILAC := Color("#9C8FC4")
const CLAY := Color("#B7806E")
const SEAGLASS := Color("#7FA9A3")
const CANVAS := Color("#CFC6B6")
const ZONE_NW := {"skin": SKIN_CANVAS_WALL, "albedo": CANVAS, "zone": OCHRE, "accent": CLAY}
const ZONE_NE := {"skin": SKIN_CANVAS_WALL, "albedo": CANVAS, "zone": LILAC, "accent": SEAGLASS}
const ZONE_SW := {"skin": SKIN_CANVAS_WALL, "albedo": CANVAS, "zone": CLAY, "accent": OCHRE}
## Rocklyn's southeast building (added with the 135 m arena).
const ZONE_SE := {"skin": SKIN_CANVAS_WALL, "albedo": CANVAS, "zone": SEAGLASS, "accent": LILAC}


## Set dressing: decoration only. NONE of it has collision, and every piece
## sits where it cannot be walked into or change a sightline - flat on a wall
## (at most 0.35 m deep), above head height, on top of an existing wall, or flat
## on the floor. Each entry: model, position, turn about Y in degrees, scale.
## Wall pieces are modelled facing +Z; the turn points them into the room.
const DRESSING := [
	# Central hub: crayons poking out of the four crayon-box pillars, and a
	# sculpture hanging far overhead. (The compass rose is painted on the
	# platform by the surface shader.)
	["prop_crayon_cluster", Vector3(-10.0, 4.5, -10.0), 0.0, 1.0],
	["prop_crayon_cluster", Vector3(10.0, 4.5, -10.0), 90.0, 1.0],
	["prop_crayon_cluster", Vector3(-10.0, 4.5, 10.0), 180.0, 1.0],
	["prop_crayon_cluster", Vector3(10.0, 4.5, 10.0), 270.0, 1.0],
	["prop_hub_mobile", Vector3(0.0, 8.7, 0.0), 0.0, 1.0],
	# NW paint storage: paint can stacks on the tops of its walls.
	["prop_can_stack", Vector3(-34.0, 3.8, -30.5), 0.0, 1.0],
	["prop_can_stack", Vector3(-34.0, 3.8, -25.5), 70.0, 1.0],
	["prop_can_stack", Vector3(-32.0, 3.8, -33.0), 20.0, 1.0],
	# NE mixing room: mixing vats on its north wall.
	["prop_mixing_vat", Vector3(23.0, 4.2, -34.0), 0.0, 1.0],
	["prop_mixing_vat", Vector3(33.0, 4.2, -34.0), 140.0, 1.0],
	# SW gallery: framed paintings hung on its canvas walls.
	["prop_frame", Vector3(-37.6, 1.1, 31.0), 90.0, 1.0],
	["prop_frame", Vector3(-37.6, 1.1, 34.8), 90.0, 1.0],
	["prop_frame", Vector3(-37.6, 3.75, 24.0), 90.0, 1.0],
	# South lane: pipes along the top of the paint trough.
	["prop_pipe_run", Vector3(7.5, -0.35, 24.0), -90.0, 1.0],
	["prop_pipe_run", Vector3(7.5, -0.35, 34.0), -90.0, 1.0],
	["prop_pipe_run", Vector3(-7.5, -0.35, 29.0), 90.0, 1.0],
	# The corkboard walls: giant sketches pinned up all round (flat, <= 3 cm).
	# (Positions follow the 135 m arena's walls at +-67.5 m.)
	["sheet:0", Vector3(-36.0, 1.6, -67.5), 0.0, 1.0],
	["sheet:2", Vector3(-9.0, 3.4, -67.5), 0.0, 1.0],
	["sheet:3", Vector3(18.0, 2.0, -67.5), 0.0, 1.0],
	["sheet:1", Vector3(45.0, 4.2, -67.5), 0.0, 1.0],
	["sheet:1", Vector3(-45.0, 3.8, 67.5), 180.0, 1.0],
	["sheet:3", Vector3(-18.0, 1.4, 67.5), 180.0, 1.0],
	["sheet:0", Vector3(30.0, 2.6, 67.5), 180.0, 1.0],
	["sheet:2", Vector3(67.5, 1.8, -36.0), -90.0, 1.0],
	["sheet:0", Vector3(67.5, 3.6, -9.0), -90.0, 1.0],
	["sheet:3", Vector3(67.5, 1.5, 21.0), -90.0, 1.0],
	["sheet:1", Vector3(67.5, 4.4, 45.0), -90.0, 1.0],
	["sheet:3", Vector3(-67.5, 4.0, -21.0), 90.0, 1.0],
	["sheet:2", Vector3(-67.5, 1.7, 6.0), 90.0, 1.0],
	["sheet:0", Vector3(-67.5, 3.2, 18.0), 90.0, 1.0],
	# Giant art tools standing flush in the four corners.
	["prop_giant_brush", Vector3(62.25, 0.0, -67.5), 0.0, 1.25],
	["prop_paint_tube", Vector3(67.5, 0.0, -62.25), -90.0, 1.0],
	["prop_paint_tube", Vector3(62.25, 0.0, 67.5), 180.0, 1.0],
	["prop_giant_brush", Vector3(67.5, 0.0, 62.25), -90.0, 1.25],
	["prop_giant_brush", Vector3(-62.25, 0.0, 67.5), 180.0, 1.25],
	["prop_paint_tube", Vector3(-67.5, 0.0, 62.25), 90.0, 1.0],
	["prop_paint_tube", Vector3(-62.25, 0.0, -67.5), 0.0, 1.0],
	["prop_giant_brush", Vector3(-67.5, 0.0, -62.25), 90.0, 1.25],
	# Strips of painter's tape holding the canvas down at the corners (flat).
	["prop_tape_strip", Vector3(-59.25, 0.0, -59.25), 45.0, 1.0],
	["prop_tape_strip", Vector3(59.25, 0.0, -59.25), -45.0, 1.0],
	["prop_tape_strip", Vector3(59.25, 0.0, 59.25), 45.0, 1.0],
	["prop_tape_strip", Vector3(-59.25, 0.0, 59.25), -45.0, 1.0],
]

## Giant desk objects OUTSIDE the walls, one per side, rising far above them:
## the first landmarks you learn ("the lamp is west"). Model, position, turn,
## scale.
## Far outside the arena, so they never touch gameplay; no shadows, so the
## lighting inside is unchanged. When the arena grew to 135 m they moved 1.5x
## further out and grew 1.5x, so they look the same size from the middle.
const LANDMARKS := [
	["lm_easel", Vector3(-9.0, 0.0, -114.0), 0.0, 2.17],
	["lm_brush_jar", Vector3(12.0, 0.0, 111.0), 180.0, 2.17],
	# Raised: the walls hide everything below ~14 m out here, and the tubes'
	# coloured shoulders and paint curl must clear them. Its base is never
	# visible from inside, so lifting it costs nothing.
	["lm_paint_tubes", Vector3(102.0, 13.5, 9.0), -90.0, 2.1],
	["lm_desk_lamp", Vector3(-114.0, 0.0, -6.0), 90.0, 2.1],
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
	# Outer combat lanes added with the larger footprint. Alternating low and
	# tall cover keeps these new spaces from becoming long empty sightlines.
	{"pos": Vector3(-46.0, 0.0, -12.0), "size": Vector3(8.0, 2.0, 2.0), "color": "teal"},
	{"pos": Vector3(46.0, 0.0, 12.0), "size": Vector3(8.0, 2.0, 2.0), "color": "pink"},
	{"pos": Vector3(-39.0, 0.0, 20.0), "size": Vector3(2.0, 3.0, 8.0), "color": "mint"},
	{"pos": Vector3(39.0, 0.0, -20.0), "size": Vector3(2.0, 3.0, 8.0), "color": "teal"},
	{"pos": Vector3(-52.0, 0.0, -42.0), "size": Vector3(5.0, 2.4, 3.0), "color": "pink"},
	{"pos": Vector3(52.0, 0.0, 42.0), "size": Vector3(5.0, 2.4, 3.0), "color": "mint"},
	{"pos": Vector3(-18.0, 0.0, -52.0), "size": Vector3(8.0, 1.7, 2.0), "color": "pale"},
	{"pos": Vector3(18.0, 0.0, 52.0), "size": Vector3(8.0, 1.7, 2.0), "color": "charcoal"},
	{"pos": Vector3(-48.0, 0.0, 6.0), "size": Vector3(3.0, 1.6, 6.0), "color": "pale"},
	{"pos": Vector3(48.0, 0.0, -6.0), "size": Vector3(3.0, 1.6, 6.0), "color": "mint"},
	{"pos": Vector3(-8.0, 0.0, 47.0), "size": Vector3(2.0, 3.2, 6.0), "color": "teal"},
	{"pos": Vector3(8.0, 0.0, -47.0), "size": Vector3(2.0, 3.2, 6.0), "color": "pink"},
	{"pos": Vector3(-56.0, 0.0, -24.0), "size": Vector3(2.0, 2.7, 8.0), "color": "charcoal"},
	{"pos": Vector3(56.0, 0.0, 24.0), "size": Vector3(2.0, 2.7, 8.0), "color": "pale"},
	{"pos": Vector3(-34.0, 0.0, -54.0), "size": Vector3(6.0, 1.8, 2.0), "color": "mint"},
	{"pos": Vector3(34.0, 0.0, 54.0), "size": Vector3(6.0, 1.8, 2.0), "color": "teal"},
	{"pos": Vector3(-54.0, 0.0, 30.0), "size": Vector3(7.0, 2.0, 2.0), "color": "pink"},
	{"pos": Vector3(54.0, 0.0, -30.0), "size": Vector3(7.0, 2.0, 2.0), "color": "mint"},
	{"pos": Vector3(-32.0, 0.0, 45.0), "size": Vector3(2.0, 2.5, 7.0), "color": "pale"},
	{"pos": Vector3(32.0, 0.0, -45.0), "size": Vector3(2.0, 2.5, 7.0), "color": "charcoal"},
	{"pos": Vector3(-4.0, 0.0, -58.0), "size": Vector3(7.0, 1.5, 2.0), "color": "teal"},
	{"pos": Vector3(4.0, 0.0, 58.0), "size": Vector3(7.0, 1.5, 2.0), "color": "pink"},
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
	_build_visual_accents()
	_build_dressing()


func _process(delta: float) -> void:
	# Small emission changes keep the environment alive without moving cover or
	# changing collision. The offset stops every colour from pulsing in unison.
	_accent_time += delta
	for index in _pulse_materials.size():
		var material := _pulse_materials[index]
		# Toned down for the paper-and-paint look: a gentle glow, not neon.
		material.emission_energy_multiplier = 0.6 + sin(_accent_time * 1.8 + float(index) * 1.7) * 0.15


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
	sun.directional_shadow_max_distance = 120.0

	add_child(sun)


func _build_floor() -> void:
	# Leave a cutout for the recessed lower route; every section retains the
	# original collision-backed box floor.
	# The floor is the canvas being painted: zone washes, pencil guides, flecks.
	_surface = {"skin": SKIN_FLOOR, "fleck": 0.3}
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
	# The outer walls are a giant cork pinboard in a wooden frame.
	_surface = {"skin": SKIN_CORKBOARD}

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

	# (The arena is open-air: Rocklyn's online branch removed the invisible
	# ceiling that used to sit on top of these walls.)
	_surface = {}


func _build_cover() -> void:
	for piece in COVER:
		var size: Vector3 = piece["size"]
		var pos: Vector3 = piece["pos"]
		# The table stores the position of a piece's BASE, which is how you
		# actually think about placing cover. Boxes are centred on their origin,
		# so lift each one by half its height to stand it on the floor.
		var centre: Vector3 = pos + Vector3(0.0, size.y * 0.5, 0.0)
		# The tall "charcoal" pieces (the hub pillars and some of the outer-lane
		# walls) are crayon boxes, the centre platform a stack of boards with
		# the compass rose on top, and every other piece a stack of sketchbooks.
		# (Only the centre gets the boards: the compass belongs in the middle.)
		if pos == Vector3.ZERO:
			_surface = {"skin": SKIN_BOARD_STACK}
		elif str(piece["color"]) == "charcoal":
			_surface = {"skin": SKIN_CRAYON_BOX}
		else:
			_surface = {"skin": SKIN_SKETCHBOOKS}
		_add_solid(centre, size, _palette(piece["color"]), 0.9)
	_surface = {}


func _build_sunken_route() -> void:
	_surface = {"skin": SKIN_FLOOR, "fleck": 0.3}
	_add_solid(Vector3(0.0, -PIT_DEPTH - 0.5, (PIT_NORTH + PIT_SOUTH) * 0.5),
		Vector3(PIT_HALF_WIDTH * 2.0, 1.0, PIT_SOUTH - PIT_NORTH), FLOOR_COLOR, 0.95)
	# The lane is a metal paint trough with ruler ramps at both ends.
	_surface = {"skin": SKIN_TROUGH}
	# Retaining-wall openings align with collision-backed ramps at either end.
	for end_z in [PIT_NORTH + 0.1, PIT_SOUTH - 0.1]:
		for side_x in [-5.3, 5.3]:
			_add_solid(Vector3(side_x, -1.15, end_z),
				Vector3(5.4, 2.5, 0.35), COVER_PALE, 0.9)
	_surface = {"skin": SKIN_RULER}
	_add_solid(Vector3(0.0, -1.33, PIT_NORTH + 3.0),
		Vector3(5.0, 0.4, 6.5), COVER_SAGE, 0.9, true, Vector3(21.25, 0.0, 0.0))
	_add_solid(Vector3(0.0, -1.33, PIT_SOUTH - 3.0),
		Vector3(5.0, 0.4, 6.5), COVER_ROSE, 0.9, true, Vector3(-21.25, 0.0, 0.0))
	_surface = {"skin": SKIN_TROUGH}
	_add_solid(Vector3(-7.75, -1.2, (PIT_NORTH + PIT_SOUTH) * 0.5),
		Vector3(0.5, 2.4, PIT_SOUTH - PIT_NORTH), COVER_SLATE, 0.9)
	_add_solid(Vector3(7.75, -1.2, (PIT_NORTH + PIT_SOUTH) * 0.5),
		Vector3(0.5, 2.4, PIT_SOUTH - PIT_NORTH), COVER_SLATE, 0.9)
	_surface = {"skin": SKIN_SKETCHBOOKS}
	_add_solid(Vector3(0.0, -1.55, 27.0), Vector3(4.5, 1.7, 0.7), COVER_TEAL, 0.9)
	_add_solid(Vector3(-3.5, -1.55, 33.0), Vector3(4.5, 1.7, 0.7), COVER_ROSE, 0.9)
	_surface = {}


func _build_buildings() -> void:
	# Northwest compact room: three exits support quick close-range flanks.
	_surface = ZONE_NW
	_build_room_shell(Vector3(-28.0, 0.0, -28.0), 12.0, 10.0, 3.8,
		COVER_PALE, [&"north", &"south", &"east"])
	_surface = {"skin": SKIN_RULER}
	_add_solid(Vector3(-34.0, 2.8, -28.0), Vector3(0.35, 0.45, 3.0), COVER_ROSE, 0.8)
	_add_solid(Vector3(-22.0, 2.8, -28.0), Vector3(0.35, 0.45, 3.0), COVER_TEAL, 0.8)

	# Northeast two-room building, open to west, east, and south approaches.
	_surface = ZONE_NE
	_build_room_shell(Vector3(28.0, 0.0, -27.0), 17.0, 14.0, 4.2,
		COVER_SAGE, [&"south", &"west", &"east"])
	_build_partition(Vector3(28.0, 0.0, -29.0), 12.0, 3.4, 0.55, COVER_SLATE)

	# Southwest building: multiple ground exits, raised firing lane, walk-up ramp.
	_surface = ZONE_SW
	_build_room_shell(Vector3(-28.0, 0.0, 28.0), 20.0, 18.0, 5.0,
		COVER_ROSE, [&"north", &"east", &"south"])
	_surface = {"skin": SKIN_DRAWING_BOARD}
	_add_solid(Vector3(-28.0, 3.2, 24.0), Vector3(14.0, 0.4, 8.0), COVER_PALE, 0.85)
	_surface = {"skin": SKIN_RULER}
	# The high end meets the south edge of the upper deck instead of running
	# underneath it, so the player can walk cleanly from slope onto floor.
	_add_solid(Vector3(-22.0, 1.6, 32.25), Vector3(3.0, 0.4, 8.5), COVER_TEAL, 0.85,
		true, Vector3(21.8, 0.0, 0.0))
	_add_solid(Vector3(-34.5, 3.75, 25.0), Vector3(0.35, 0.8, 5.0), COVER_SAGE, 0.85)
	_add_solid(Vector3(-27.0, 3.75, 20.2), Vector3(13.0, 0.8, 0.35), COVER_SAGE, 0.85)

	# Southeast building fills the largest area added by the 1.5x expansion.
	# Three entrances make it useful cover without creating a dead-end camp.
	_surface = ZONE_SE
	_build_room_shell(Vector3(45.0, 0.0, 44.0), 18.0, 16.0, 4.4,
		COVER_TEAL, [&"north", &"west", &"south"])
	_build_partition(Vector3(45.0, 0.0, 45.5), 13.0, 3.6, 0.55, COVER_PALE)
	_surface = {"skin": SKIN_SKETCHBOOKS}
	_add_solid(Vector3(49.5, 1.0, 40.0), Vector3(4.0, 2.0, 1.4), COVER_ROSE, 0.88)
	_surface = {}


## Non-colliding arena dressing. These meshes make routes and team sides easy
## to read at a glance while leaving every existing movement lane untouched.
func _build_visual_accents() -> void:
	var red_glow := _glow_material(TEAM_RED)
	var blue_glow := _glow_material(TEAM_BLUE)
	var green_glow := _glow_material(ARENA_GLOW)
	var pale_glow := _glow_material(Color("#FFF2BE"))

	_build_spawn_marker(Vector3(-55.0, 0.04, 0.0), TEAM_RED, red_glow, "RED SPAWN")
	_build_spawn_marker(Vector3(55.0, 0.04, 0.0), TEAM_BLUE, blue_glow, "BLUE SPAWN")

	# Short lane dashes point toward the central fight without turning the floor
	# into one bright uninterrupted stripe.
	for x in [-44.0, -36.0, -28.0, -20.0]:
		_add_visual_box(Vector3(x, 0.025, 0.0), Vector3(4.2, 0.045, 0.16), red_glow)
	for x in [20.0, 28.0, 36.0, 44.0]:
		_add_visual_box(Vector3(x, 0.025, 0.0), Vector3(4.2, 0.045, 0.16), blue_glow)

	# A luminous rim gives the raised middle platform a strong focal point.
	_add_floor_ring(Vector3(0.0, 0.43, 0.0), 5.75, pale_glow)
	for corner in [Vector3(-3.55, 0.44, -3.55), Vector3(3.55, 0.44, -3.55),
			Vector3(-3.55, 0.44, 3.55), Vector3(3.55, 0.44, 3.55)]:
		_add_visual_box(corner, Vector3(0.38, 0.08, 0.38), pale_glow)

	# Green lintels identify the two buildings containing healing stations from
	# across the map. They share the station colour for fast visual navigation.
	_add_visual_box(Vector3(-28.0, 3.35, -22.95), Vector3(3.25, 0.16, 0.12), green_glow)
	_add_visual_box(Vector3(28.0, 3.75, -19.95), Vector3(3.25, 0.16, 0.12), green_glow)
	_add_visual_box(Vector3(36.45, 3.75, -27.0), Vector3(0.12, 0.16, 3.25), green_glow)

	# Wall lights break up the large outer boundary and give players landmarks
	# when turning quickly. They sit high enough to never resemble cover.
	for x in [-45.0, -15.0, 15.0, 45.0]:
		_add_visual_box(Vector3(x, 5.4, -67.48), Vector3(5.0, 0.18, 0.08), blue_glow)
		_add_visual_box(Vector3(x, 5.4, 67.48), Vector3(5.0, 0.18, 0.08), red_glow)
	for z in [-45.0, -15.0, 15.0, 45.0]:
		_add_visual_box(Vector3(-67.48, 5.4, z), Vector3(0.08, 0.18, 5.0), red_glow)
		_add_visual_box(Vector3(67.48, 5.4, z), Vector3(0.08, 0.18, 5.0), blue_glow)

	# The recessed route gets its own guide lights so the lower floor does not
	# disappear into shade when viewed from the plaza.
	for z in [22.5, 27.5, 32.5, 37.0]:
		_add_visual_box(Vector3(-7.48, -1.0, z), Vector3(0.08, 0.12, 2.1), green_glow)
		_add_visual_box(Vector3(7.48, -1.0, z), Vector3(0.08, 0.12, 2.1), green_glow)


func _build_spawn_marker(at: Vector3, color: Color,
		material: StandardMaterial3D, label_text: String) -> void:
	_add_floor_ring(at, 3.2, material)
	_add_visual_box(at + Vector3(0.0, 0.01, 0.0), Vector3(4.4, 0.04, 0.12), material)
	_add_visual_box(at + Vector3(0.0, 0.01, 0.0), Vector3(0.12, 0.04, 4.4), material)
	var label := Label3D.new()
	label.text = label_text
	label.position = at + Vector3(0.0, 0.035, 1.25)
	label.rotation_degrees.x = -90.0
	label.font_size = 48
	label.pixel_size = 0.012
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color("#252038")
	add_child(label)


func _add_floor_ring(at: Vector3, radius: float, material: Material) -> void:
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius - 0.12
	ring_mesh.outer_radius = radius
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.position = at
	ring.material_override = material
	add_child(ring)


func _add_visual_box(at: Vector3, size: Vector3, material: Material) -> void:
	var mesh_node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	mesh_node.position = at
	mesh_node.material_override = material
	add_child(mesh_node)


func _glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.28
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.6
	_pulse_materials.append(material)
	return material


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
	mat.set_shader_parameter("skin", int(_surface.get("skin", SKIN_PLAIN)))
	mat.set_shader_parameter("albedo", _surface.get("albedo", box_color))
	mat.set_shader_parameter("roughness_value", roughness)
	mat.set_shader_parameter("box_size", size)
	mat.set_shader_parameter("fleck_amount", float(_surface.get("fleck", 0.0)))
	if _surface.has("zone"):
		mat.set_shader_parameter("zone_color", _surface["zone"])
		mat.set_shader_parameter("zone_accent", _surface["accent"])
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
		var model_name: String = entry[0]
		var prop: Node3D
		if model_name.begins_with("sheet:"):
			prop = PaintKit.variant("prop_pinned_sheet", "Sheet_" + model_name.substr(6))
		else:
			prop = PaintKit.instance(model_name)
		if prop == null:
			continue
		dressing.add_child(prop)
		prop.position = entry[1]
		prop.rotation.y = deg_to_rad(entry[2])
		prop.scale = Vector3.ONE * float(entry[3])
		# Flat pieces hung on walls or laid on the floor throw no visible
		# shadow, so skip drawing them into the shadow maps at all.
		if model_name in ["prop_frame", "prop_pipe_run", "prop_tape_strip"] or model_name.begins_with("sheet:"):
			PaintKit.set_shadows(prop, false)
	for entry in LANDMARKS:
		var landmark := PaintKit.instance(entry[0])
		if landmark == null:
			continue
		dressing.add_child(landmark)
		landmark.position = entry[1]
		landmark.rotation.y = deg_to_rad(entry[2])
		landmark.scale = Vector3.ONE * float(entry[3])
		PaintKit.set_shadows(landmark, false)
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
