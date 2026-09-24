extends CharacterBody3D

## ============================================================================
## ENEMY - all five archetypes, driven by one table of numbers.
## ============================================================================
##
## WHY ONE SCRIPT AND NOT FIVE
## Every enemy in this game wants the same things: close to a preferred range,
## keep line of sight, attack on a timer, die, drop a core. Only the NUMBERS
## differ. Writing five scripts would mean fixing every movement bug five times
## and letting the five slowly drift apart. Instead the differences live in the
## TYPES table below and the behaviour lives in one place.
##
## HOW EACH ENEMY TEACHES ITS OWN PAIR
## An archetype always plays the way its dropped pair plays. The Monolith is
## slow and shrugs off damage; inherit from it and you become slow and shrug off
## damage. So by the time you have fought a type you already know what taking
## its pair will feel like, without a tutorial ever telling you.

const Traits = preload("res://scripts/traits.gd")
const Projectile = preload("res://scripts/projectile.gd")
const CorePickup = preload("res://scripts/core_pickup.gd")


## Announced when this enemy dies. game.gd counts these to know when the wave is
## clear. Carrying the position saves game.gd having to look it up after the
## node is already on its way out of the tree.
signal died(at: Vector3)


## The stat block for every archetype. The key is both the enemy's id and the id
## of the pair in traits.gd that it drops - keeping those the same means there
## is no separate mapping table to forget to update.
##
## Field guide:
##   health          hit points at wave 1
##   speed           metres per second
##   damage          health removed from the player per attack
##   interval        seconds between attacks
##   ideal_range     metres it tries to hold from you; it closes if further,
##                   and backs off if much nearer
##   melee           true = attacks by touching you, false = fires paint
##   resist          incoming damage multiplier (0.55 = takes 45% less)
##   regen           health per second regained while not recently hit
##   radius/height   body size, also used for the collision capsule
const TYPES := {

	# The basic target. Fast trigger, weak globs, dies quickly. Wave 1 is made
	# entirely of these so the first pair you are ever offered is a safe one.
	"sprayer": {
		"name": "Sprayer",
		"color": Traits.PINK,
		"health": 45.0,
		"speed": 5.2,
		"damage": 6.0,
		"interval": 0.8,
		"projectile_speed": 30.0,
		"ideal_range": 11.0,
		"melee": false,
		"resist": 1.0,
		"regen": 0.0,
		"regen_delay": 99.0,
		"radius": 0.4,
		"height": 1.6,
		"splash_radius": 0.0,
		"splash_mult": 0.0,
	},

	# The rusher. No gun at all - it sprints at you and slams into you. It is
	# the pressure that stops you standing still and sniping, which is what
	# makes the slower archetypes dangerous instead of free.
	"bounder": {
		"name": "Bounder",
		"color": Traits.MINT,
		"health": 55.0,
		"speed": 9.0,
		"damage": 11.0,
		"interval": 0.85,
		"projectile_speed": 0.0,
		# For a melee type this is the STANDOFF: how close it gets before it
		# stops closing and starts circling. It must not be 0. A rusher told to
		# close to zero distance walks into the exact spot the player is
		# standing, ends up inside them, and becomes impossible to shoot -
		# it is closer than the camera can focus and there is no angle that
		# points at it. That is not a hard enemy, it is a broken one.
		"ideal_range": 1.8,
		"melee": true,
		"resist": 1.0,
		"regen": 0.0,
		"regen_delay": 99.0,
		"radius": 0.45,
		"height": 1.4,
		"splash_radius": 0.0,
		"splash_mult": 0.0,
	},

	# The artillery piece. Slow, tough-ish, lobs splashing paint from far away.
	# You cannot ignore it and you cannot out-strafe the splash, so it forces
	# you to break off whatever you were doing and go deal with it.
	"blotter": {
		"name": "Blotter",
		"color": Traits.TEAL,
		"health": 85.0,
		"speed": 3.2,
		"damage": 15.0,
		"interval": 2.3,
		"projectile_speed": 22.0,
		"ideal_range": 14.0,
		"melee": false,
		"resist": 1.0,
		"regen": 0.0,
		"regen_delay": 99.0,
		"radius": 0.6,
		"height": 1.7,
		"splash_radius": 3.0,
		"splash_mult": 0.7,
		},

	# The wall. Takes 45% less damage and hits very hard, but is slow enough
	# that you can always disengage. This is the "tougher target" the GDD's core
	# loop is pointing at - the one you genuinely want the right pair for.
	"monolith": {
		"name": "Monolith",
		"color": Traits.CHARCOAL,
		"health": 150.0,
		"speed": 2.6,
		"damage": 18.0,
		"interval": 1.7,
		"projectile_speed": 26.0,
		"ideal_range": 9.0,
		"melee": false,
		"resist": 0.55,
		"regen": 0.0,
		"regen_delay": 99.0,
		"radius": 0.75,
		"height": 2.3,
		"splash_radius": 0.0,
		"splash_mult": 0.0,
	},

	# The attrition fight. Heals itself if you stop shooting it, so chip damage
	# is worthless and you have to commit to finishing it. Strafes fast enough
	# to be a genuinely awkward target.
	"ghost": {
		"name": "Ghost",
		"color": Traits.WHITE,
		"health": 65.0,
		"speed": 7.5,
		"damage": 9.0,
		"interval": 1.05,
		"projectile_speed": 34.0,
		"ideal_range": 10.0,
		"melee": false,
		"resist": 1.0,
		"regen": 8.0,
		"regen_delay": 2.5,
		"radius": 0.4,
		"height": 1.7,
		"splash_radius": 0.0,
		"splash_mult": 0.0,
	},
}


## Which archetype this particular enemy is. Set by game.gd before adding it to
## the scene, via setup().
var type_id: String = "sprayer"

## This enemy's copy of the stat block above.
var stats: Dictionary = {}

var health: float = 1.0
var max_health: float = 1.0

## The player node. Deliberately left UNTYPED (no ": CharacterBody3D").
##
## GDScript checks typed variables at parse time, and take_damage() is a
## function this project added to player.gd, not a built-in of any engine class.
## If this variable were typed as its engine class, calling take_damage() on it
## would be a PARSE ERROR - the whole script would refuse to load - even though
## it works perfectly at runtime. An untyped variable is skipped by that check.
## The same trap means `:=` cannot be used on anything read back off this
## variable; write the type by hand instead, as done throughout below.
var _player = null

var _attack_cooldown: float = 0.0
var _since_hurt: float = 999.0

## Counts down after a melee enemy lands a hit, during which it backs away.
##
## WHY RUSHERS RETREAT AFTER HITTING
## Without this, a Bounder closes to arm's length and then simply stays there,
## landing a hit every time its timer comes up. There is no counterplay to that
## at all - you cannot dodge something standing on top of you, so the only
## answer is to kill it first, and two of them out-damage anything you can do
## about it. Backing off after each hit turns them into a rhythm you can read:
## they lunge, they connect, they withdraw, and that gap is your window to deal
## with them or reposition. Same enemy, same damage per hit, completely
## different fight.
var _retreat_timer: float = 0.0
var _dead: bool = false

## Which way it is currently circling, +1 or -1. Chosen once at spawn and
## flipped occasionally, so a group of the same type does not move as one blob.
var _strafe_dir: float = 1.0
var _strafe_timer: float = 0.0

var _gravity: float = 20.0

var _mesh: MeshInstance3D
var _health_bar: MeshInstance3D
var _health_bar_bg: MeshInstance3D


## Called by game.gd before this enemy enters the scene.
## `health_scale` is the per-wave difficulty ramp - later waves hand in a bigger
## number so the same archetype takes more shots to drop.
func setup(id: String, health_scale: float) -> void:
	type_id = id
	if TYPES.has(id):
		stats = TYPES[id]
	else:
		push_warning("Enemy.setup: unknown type '%s', using sprayer." % id)
		stats = TYPES["sprayer"]

	max_health = float(stats["health"]) * health_scale
	health = max_health


func _ready() -> void:
	# Tag this node so the player's paint knows it is a legal target.
	add_to_group("enemies")

	if stats.is_empty():
		stats = TYPES["sprayer"]
		max_health = float(stats["health"])
		health = max_health

	_build_body()
	_build_mesh()
	_build_health_bar()

	# Pick a starting circling direction. randf() gives a random number from 0
	# to 1, so this is a coin flip.
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0
	# Stagger the first attack so a wave that spawns together does not fire in
	# one synchronised volley the instant it appears. That volley is the
	# difference between "hard" and "unfair".
	_attack_cooldown = randf_range(0.4, 1.4)

	# get_first_node_in_group finds the one node tagged "player". Looking the
	# player up by group rather than by a hard-coded path means the enemy does
	# not care where in the scene the player lives.
	_player = get_tree().get_first_node_in_group("player")


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(stats["radius"])
	capsule.height = float(stats["height"])
	shape.shape = capsule
	shape.position = Vector3(0.0, float(stats["height"]) * 0.5, 0.0)
	add_child(shape)

	# Layer 4 = "enemy". Mask 1|2|4 = collide with the world, the player, and
	# each other.
	#
	# Including the player matters more than it looks. Two CharacterBody3Ds
	# never push each other - they just stop - so this does not let a pack shove
	# the player around. What it does is guarantee an enemy can never end up
	# standing INSIDE the player, which would put it at a distance of zero where
	# it cannot be aimed at or shot.
	collision_layer = 4
	collision_mask = 1 | 2 | 4


## The body: a faceted low-poly shape in the archetype's colour, which is also
## the colour of the pair it drops. Colour is the only thing you need to read
## across the arena to know what you are fighting and what it will leave behind.
func _build_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var body := SphereMesh.new()
	body.radius = float(stats["radius"]) * 1.15
	body.height = float(stats["height"])
	# Deliberately few segments, for the GDD's hard-edged low-poly look.
	body.radial_segments = 7
	body.rings = 4
	_mesh.mesh = body
	_mesh.position = Vector3(0.0, float(stats["height"]) * 0.5, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = stats["color"]
	mat.roughness = 0.85
	mat.metallic = 0.0
	# A faint glow of its own colour, so a white Ghost still reads against the
	# white floor and walls.
	mat.emission_enabled = true
	mat.emission = stats["color"]
	mat.emission_energy_multiplier = 0.35
	_mesh.material_override = mat

	add_child(_mesh)


## A small bar floating above the enemy. This is not decoration - without it you
## cannot tell a Monolith you have nearly killed from one you have barely
## scratched, and a fight you cannot read is a fight that feels unfair rather
## than hard.
func _build_health_bar() -> void:
	var bar_y: float = float(stats["height"]) + 0.45

	_health_bar_bg = _make_bar_quad(Color(0.17, 0.18, 0.26, 0.75), 1.0)
	_health_bar_bg.position = Vector3(0.0, bar_y, 0.0)
	add_child(_health_bar_bg)

	_health_bar = _make_bar_quad(Color(1.0, 0.36, 0.45, 1.0), 1.0)
	# Sit the fill a hair in front of the background so they do not fight over
	# the same depth and flicker ("z-fighting").
	_health_bar.position = Vector3(0.0, bar_y, 0.01)
	add_child(_health_bar)


func _make_bar_quad(bar_color: Color, width: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, 0.1)
	node.mesh = quad

	var mat := StandardMaterial3D.new()
	mat.albedo_color = bar_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Billboard mode makes the quad always turn to face the camera, so the bar
	# is readable from any angle instead of vanishing when seen edge-on.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Billboarded quads must not be culled by their facing direction, or they
	# disappear as they spin to face you.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Draw on top of the world so the bar is never buried inside the enemy mesh.
	mat.no_depth_test = true
	node.material_override = mat

	return node


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_attack_cooldown -= delta
	_since_hurt += delta
	_strafe_timer -= delta
	_retreat_timer -= delta

	# Gravity, so enemies sit on the floor rather than hovering.
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	# If the player has died or been removed, stop fighting and just stand.
	if _player == null or not is_instance_valid(_player):
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_regenerate(delta)

	# Explicit types, not `:=` - see the note on the _player variable above.
	var player_position: Vector3 = _player.global_position
	var to_player: Vector3 = player_position - global_position
	# Flatten to the horizontal plane. Without this, an enemy standing below you
	# would try to walk upward into the air to reach you.
	var flat: Vector3 = Vector3(to_player.x, 0.0, to_player.z)
	var distance: float = flat.length()

	_face(flat)
	_steer(flat, distance, delta)
	_try_attack(player_position, distance)

	move_and_slide()


func _regenerate(delta: float) -> void:
	var regen: float = float(stats["regen"])
	if regen <= 0.0:
		return
	if _since_hurt < float(stats["regen_delay"]):
		return
	if health >= max_health:
		return

	health = minf(max_health, health + regen * delta)
	_refresh_health_bar()


## Turn the body to look at the player. Only the visible mesh needs this, but
## rotating the whole body is simpler and the capsule is round so it changes
## nothing about the collisions.
func _face(flat: Vector3) -> void:
	if flat.length() < 0.05:
		return
	var target_yaw: float = atan2(flat.x, flat.z)
	# lerp_angle blends between two angles the SHORT way around the circle.
	# A plain lerp would spin the long way round whenever the angle crossed
	# from +180 to -180 degrees, making enemies pirouette on the spot.
	rotation.y = lerp_angle(rotation.y, target_yaw, 0.15)


## Movement. Three jobs: hold the preferred range, circle rather than stand
## still, and do not pile up on other enemies of the same type.
func _steer(flat: Vector3, distance: float, delta: float) -> void:
	var speed: float = float(stats["speed"])
	var ideal: float = float(stats["ideal_range"])

	# Guard against dividing by zero if an enemy ends up exactly on top of you.
	var toward: Vector3 = Vector3.ZERO
	if distance > 0.01:
		toward = flat / distance

	var move: Vector3 = Vector3.ZERO

	if bool(stats["melee"]):
		# Just landed a hit - pull back out of reach before coming in again.
		if _retreat_timer > 0.0:
			move = -toward
		elif distance > ideal:
			# Close the gap.
			move = toward
		else:
			# In reach and waiting on the attack timer: circle rather than
			# stand still, so it is not a stationary target.
			move = toward.cross(Vector3.UP) * _strafe_dir
	elif distance > ideal + 1.5:
		# Too far to shoot accurately - close the gap.
		move = toward
	elif distance < ideal - 3.0:
		# Uncomfortably close - back off, but keep facing you.
		move = -toward
	else:
		# In the pocket. Circle instead of standing still, which makes shooters
		# a moving target without letting them wander out of the fight.
		# cross() of a direction with "up" gives the direction 90 degrees to it.
		move = toward.cross(Vector3.UP) * _strafe_dir

	# Flip the circling direction every so often so enemies do not orbit
	# predictably enough to be tracked without thinking.
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.2, 2.6)
		if randf() < 0.45:
			_strafe_dir = -_strafe_dir

	move += _separation() * 0.8

	# normalized() here stops the separation push making an enemy faster than
	# its stat block says it can move.
	if move.length() > 0.01:
		move = move.normalized()

	velocity.x = move.x * speed
	velocity.z = move.z * speed


## A gentle shove away from nearby enemies, so a pack spreads into a line you
## can fight instead of merging into one overlapping clump.
func _separation() -> Vector3:
	var push: Vector3 = Vector3.ZERO

	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self:
			continue
		# Untyped on purpose, for the same parse-time reason as _player.
		var neighbour = other
		var offset: Vector3 = global_position - neighbour.global_position
		offset.y = 0.0
		var d: float = offset.length()
		if d > 0.01 and d < 2.2:
			# Divide by distance so the push gets stronger the closer they are.
			push += offset / d * (2.2 - d) / 2.2

	return push


func _try_attack(player_position: Vector3, distance: float) -> void:
	if _attack_cooldown > 0.0:
		return

	if bool(stats["melee"]):
		# Rushers hit from just outside contact. The reach has to be a little
		# longer than the standoff they hold in _steer(), or they would sit
		# politely at arm's length and never actually attack.
		var reach: float = float(stats["ideal_range"]) + 0.6
		if distance <= reach and _retreat_timer <= 0.0:
			_attack_cooldown = float(stats["interval"])
			_retreat_timer = 1.15
			_player.take_damage(float(stats["damage"]))
			_flash()
		return

	# Shooters need to be in range AND to actually be able to see you.
	if distance > float(stats["ideal_range"]) + 6.0:
		return
	if not _has_line_of_sight(player_position):
		return

	_attack_cooldown = float(stats["interval"])
	_fire_at(player_position)


## Checks nothing solid stands between this enemy and the player. Without it,
## enemies would shoot straight through the arena's pillars, which would make
## cover meaningless and the whole level layout pointless.
func _has_line_of_sight(player_position: Vector3) -> bool:
	var from: Vector3 = global_position + Vector3(0.0, float(stats["height"]) * 0.6, 0.0)
	var to: Vector3 = player_position + Vector3(0.0, 1.2, 0.0)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Mask 1 = the world only. We are asking "is there a WALL in the way",
	# not "is there anything at all" - other enemies must not block the shot or
	# a pack would never fire.
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true

	# An empty result means the line reached the player uninterrupted.
	var hit := space.intersect_ray(query)
	return hit.is_empty()


func _fire_at(player_position: Vector3) -> void:
	var from: Vector3 = global_position + Vector3(0.0, float(stats["height"]) * 0.6, 0.0)

	# Aim at the player's chest, and lead the shot slightly by aiming where they
	# are rather than where they were - enemies deliberately do NOT predict your
	# movement, which is what makes strafing a reliable dodge. That is the main
	# reason this game is hard but not unfair.
	var to: Vector3 = player_position + Vector3(0.0, 1.0, 0.0)

	var glob = Node3D.new()
	glob.set_script(Projectile)
	glob.damage = float(stats["damage"])
	glob.speed = float(stats["projectile_speed"])
	glob.splash_radius = float(stats["splash_radius"])
	glob.splash_mult = float(stats["splash_mult"])
	glob.color = stats["color"]

	get_parent().add_child(glob)
	glob.setup(from, to - from, false)

	_flash()


## Called by the player's paint. `amount` has already had the player's own
## damage multipliers applied; the only thing left is this enemy's resistance.
func take_damage(amount: float) -> void:
	if _dead:
		return

	health -= amount * float(stats["resist"])
	_since_hurt = 0.0
	_refresh_health_bar()
	_flash()

	if health <= 0.0:
		_die()


func _refresh_health_bar() -> void:
	if _health_bar == null:
		return
	var fraction: float = clampf(health / max_health, 0.0, 1.0)
	# Scaling the quad on X shrinks it from both edges toward the centre, so
	# also slide it left by half of what was lost to keep the left edge pinned.
	_health_bar.scale.x = fraction
	_health_bar.position.x = -(1.0 - fraction) * 0.5


## A brief white flash on being hit or firing. Hit feedback is the cheapest
## possible way to make a weapon feel like it is connecting.
func _flash() -> void:
	if _mesh == null:
		return
	var mat = _mesh.material_override
	mat.emission_energy_multiplier = 2.2
	var tween := create_tween()
	tween.tween_property(mat, "emission_energy_multiplier", 0.35, 0.18)


func _die() -> void:
	_dead = true
	health = 0.0

	# Drop the paint core that carries this archetype's pair. It is spawned into
	# the level rather than as a child of this enemy, because this enemy is
	# about to be deleted and children are deleted with their parent.
	var core = Node3D.new()
	core.set_script(CorePickup)
	core.pair_id = type_id
	core.color = stats["color"]
	get_parent().add_child(core)
	core.global_position = global_position + Vector3(0.0, 0.7, 0.0)

	died.emit(global_position)

	# A quick collapse before vanishing, so kills read clearly in a busy fight.
	# Collisions are switched off first: a corpse mid-animation must not keep
	# blocking your shots or bumping into you.
	collision_layer = 0
	collision_mask = 0
	remove_from_group("enemies")
	set_physics_process(false)

	if _health_bar != null:
		_health_bar.visible = false
	if _health_bar_bg != null:
		_health_bar_bg.visible = false

	# Squash the MESH, not the body itself. Scaling a CharacterBody3D squashes
	# its collision shape too, and Jolt - the physics engine this project uses -
	# cannot represent a capsule scaled unevenly on different axes. It refuses
	# the scale, falls back to a uniform one, and prints an error every frame of
	# the animation. The mesh is only ever drawn, never simulated, so squashing
	# that instead gets the same look with nothing for physics to object to.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_mesh, "scale", Vector3(1.4, 0.05, 1.4), 0.22)
	tween.tween_property(_mesh, "position:y", 0.05, 0.22)
	tween.chain().tween_callback(queue_free)
