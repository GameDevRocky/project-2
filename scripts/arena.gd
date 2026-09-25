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
## A flat empty box would make this game either trivial or impossible: with
## nothing to hide behind, eight enemies all shooting at once is unsurvivable,
## and the only viable tactic is backing into a corner. So the arena is a square
## with a deliberate spread of cover:
##
##   - Four tall pillars in the inner ring. These break line of sight, which is
##     what lets you fight a Monolith without also eating fire from everything
##     else in the wave.
##   - Four mid-height blocks at the edge midpoints, to break up the long open
##     runs along the walls so you cannot simply circle the outside forever.
##   - A low platform in the middle. It is jumpable by any pair, and standing on
##     it gives you sightlines over the mid blocks - a real reward that is also
##     a real risk, because up there everything can see you too.
##
## Nothing here is random. A learnable arena is what separates "hard" from
## "unfair" - dying should teach you the room, and a room reshuffled every run
## teaches you nothing.

const Traits = preload("res://scripts/traits.gd")

## Half the width of the playable floor, in metres. The floor runs from
## -ARENA_HALF to +ARENA_HALF on both axes, so the arena is 46m square.
const ARENA_HALF := 23.0

## How tall the boundary walls are. High enough that the Bounder pair's boosted
## jump cannot clear them and escape the level.
const WALL_HEIGHT := 9.0

## How thick the boundary walls are. Deliberately chunky - thin walls are what
## fast projectiles slip through, and thickness costs nothing here.
const WALL_THICKNESS := 2.0


## The cover pieces, as a plain list. Each entry is where it sits, how big it
## is, and what colour. Tuning the level means editing numbers in this table.
const COVER := [
	# --- Inner ring: four tall pillars that break line of sight -------------
	{"pos": Vector3(-9.0, 0.0, -9.0), "size": Vector3(2.5, 7.0, 2.5), "color": "charcoal"},
	{"pos": Vector3(9.0, 0.0, -9.0), "size": Vector3(2.5, 7.0, 2.5), "color": "charcoal"},
	{"pos": Vector3(-9.0, 0.0, 9.0), "size": Vector3(2.5, 7.0, 2.5), "color": "charcoal"},
	{"pos": Vector3(9.0, 0.0, 9.0), "size": Vector3(2.5, 7.0, 2.5), "color": "charcoal"},

	# --- Outer ring: mid-height blocks that break the long wall runs --------
	{"pos": Vector3(0.0, 0.0, -16.0), "size": Vector3(7.0, 2.8, 2.0), "color": "pink"},
	{"pos": Vector3(0.0, 0.0, 16.0), "size": Vector3(7.0, 2.8, 2.0), "color": "mint"},
	{"pos": Vector3(-16.0, 0.0, 0.0), "size": Vector3(2.0, 2.8, 7.0), "color": "teal"},
	{"pos": Vector3(16.0, 0.0, 0.0), "size": Vector3(2.0, 2.8, 7.0), "color": "pink"},

	# --- Corners: low blocks, enough to crouch a fight behind ---------------
	{"pos": Vector3(-17.0, 0.0, -17.0), "size": Vector3(4.5, 1.7, 4.5), "color": "mint"},
	{"pos": Vector3(17.0, 0.0, -17.0), "size": Vector3(4.5, 1.7, 4.5), "color": "teal"},
	{"pos": Vector3(-17.0, 0.0, 17.0), "size": Vector3(4.5, 1.7, 4.5), "color": "teal"},
	{"pos": Vector3(17.0, 0.0, 17.0), "size": Vector3(4.5, 1.7, 4.5), "color": "mint"},

	# --- Centre: the low platform. 0.8m tall, which every pair can jump ----
	{"pos": Vector3(0.0, 0.0, 0.0), "size": Vector3(8.0, 0.8, 8.0), "color": "pale"},
]


func _ready() -> void:
	_build_environment()
	_build_light()
	_build_floor()
	_build_walls()
	_build_cover()


## The sky and the global lighting settings. A WorldEnvironment node holds an
## Environment resource, which is Godot's catch-all for "how the whole scene is
## lit and graded" - background, ambient light, glow, tonemapping.
func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()

	# A procedural sky, tinted to the GDD's pastel direction rather than the
	# default blue. This is also the main source of ambient light below, so its
	# colours quietly tint everything in the arena.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#BFE9E4")
	sky_material.sky_horizon_color = Color("#FFEFF3")
	sky_material.ground_bottom_color = Color("#E9E4F0")
	sky_material.ground_horizon_color = Color("#FFEFF3")
	# A soft, wide sun disc rather than a hard point, which suits the
	# "soft-edged geometric shadows" the art direction asks for.
	sky_material.sun_angle_max = 24.0
	sky_material.sun_curve = 0.18

	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.background_mode = Environment.BG_SKY

	# Ambient light is the fill light that stops shadows being pure black.
	# Sourcing it from the sky means the pastel sky colours bounce into every
	# shadow, which is what keeps the whole scene reading as bright and clean
	# instead of high-contrast and harsh.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.15

	# Glow makes bright things bleed light into their surroundings. The paint
	# globs, the enemy bodies and the dropped cores all use emissive materials,
	# so this is what actually makes them glow rather than just look brightly
	# coloured - it is the single biggest visual win in the whole project.
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.15
	# Only things brighter than this threshold bloom, so the white floor does
	# not smear the entire screen.
	env.glow_hdr_threshold = 1.0

	# Tonemapping maps the renderer's internal brightness range onto what a
	# monitor can actually show. FILMIC rolls highlights off gently instead of
	# clipping them to flat white, which matters a lot in a mostly-white arena.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0

	world.environment = env
	add_child(world)


## One directional light, which is the engine's model of the sun: parallel rays
## with a direction but no position, so it lights the whole arena evenly.
func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	# Angled down and across rather than straight overhead, so the pillars throw
	# long readable shadows and the geometry has some shape to it.
	sun.rotation_degrees = Vector3(-52.0, -47.0, 0.0)
	sun.light_energy = 1.25
	# A faintly warm sun against the cool sky, which is what gives the pastel
	# palette its depth.
	sun.light_color = Color("#FFF6EC")

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
	# The floor is a very flat box rather than a plane, because a plane has no
	# thickness and things moving fast can end up on the wrong side of it.
	_add_solid(
		Vector3(0.0, -0.5, 0.0),
		Vector3(ARENA_HALF * 2.0, 1.0, ARENA_HALF * 2.0),
		Color("#FBFBFD"),
		0.95)


func _build_walls() -> void:
	var span: float = ARENA_HALF * 2.0
	var offset: float = ARENA_HALF + WALL_THICKNESS * 0.5
	var wall_color := Color("#3A3D57")

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


func _build_cover() -> void:
	for piece in COVER:
		var size: Vector3 = piece["size"]
		var pos: Vector3 = piece["pos"]
		# The table stores the position of a piece's BASE, which is how you
		# actually think about placing cover. Boxes are centred on their origin,
		# so lift each one by half its height to stand it on the floor.
		var centre: Vector3 = pos + Vector3(0.0, size.y * 0.5, 0.0)
		_add_solid(centre, size, _palette(piece["color"]), 0.9)


## Turns the colour names used in the COVER table into real colours.
func _palette(name: String) -> Color:
	match name:
		"charcoal":
			return Traits.CHARCOAL
		"pink":
			return Traits.PINK
		"mint":
			return Traits.MINT
		"teal":
			return Traits.TEAL
		"pale":
			return Color("#F0EAF6")
		_:
			return Traits.WHITE


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
		roughness: float, visible_mesh: bool = true) -> void:

	var body := StaticBody3D.new()
	body.position = centre
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

		var mat := StandardMaterial3D.new()
		mat.albedo_color = box_color
		mat.roughness = roughness
		mat.metallic = 0.0
		mesh_node.material_override = mat

		body.add_child(mesh_node)

	add_child(body)


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
