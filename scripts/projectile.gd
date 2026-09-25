extends Node3D

## ============================================================================
## PROJECTILE - one glob of paint in flight.
## ============================================================================
##
## Used by BOTH the player and the enemies. Who fired it is just a setting, so
## there is only one flight/impact code path to get right and to balance.
##
## WHY THIS IS A PLAIN Node3D AND NOT AN Area3D
## The obvious way to do a bullet in Godot is an Area3D that reports what it
## overlaps. The problem is speed. An Area3D is checked once per physics frame,
## so a glob travelling 60 metres a second moves a full metre between checks -
## and if a wall happens to be thinner than that gap, the glob is on one side at
## one check and the far side at the next, and the engine never sees a touch.
## The bullet sails through a solid wall. That bug is called "tunnelling".
##
## Instead, every frame this script fires a RAY from where the glob was to where
## it is about to be, and asks the physics engine "did this line cross anything?"
## A line cannot skip over a wall no matter how fast the glob moves, so
## tunnelling is impossible by construction rather than by careful tuning.


# --- Set by whoever fires this, via setup() below ---------------------------

## Direction of travel. Always a unit vector (length exactly 1) so that speed is
## controlled purely by `speed` below and never accidentally by the direction.
var direction: Vector3 = Vector3.FORWARD

## Metres per second.
var speed: float = 60.0

## Health removed from a target hit head-on.
var damage: float = 22.0

## Which physics layers this glob is allowed to hit. See setup() for the values.
var hit_mask: int = 1

## Which node group counts as a target: "enemies" or "player". Used so a glob
## cannot damage the side that fired it.
var target_group: String = "enemies"

## Splash settings, from the shooter's inherited pair. A radius of 0 means this
## glob does no splash at all and only damages what it directly hits.
var splash_radius: float = 0.0
var splash_mult: float = 0.0

## Paint colour, used for the glob mesh and the splat it leaves behind.
var color: Color = Color.WHITE

## Seconds before the glob deletes itself if it never hits anything. Without
## this, every missed shot would stay in memory forever and the game would
## slowly grind to a halt over a long run.
var life: float = 4.0


# --- Physics layer numbers, named so the code reads clearly -----------------
# In Godot every physics body sits on one or more numbered "layers", and each
# body also has a "mask" saying which layers it is allowed to notice. The values
# are powers of two so they can be combined with the | (bitwise or) operator:
# LAYER_WORLD | LAYER_ENEMY means "walls and enemies, but nothing else".
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4


# Where the glob was at the end of the previous frame. The ray each frame is
# drawn from here to the new position.
var _previous_position: Vector3

# Set true the instant we hit something, so that a glob cannot somehow register
# two impacts in the same frame and deal double damage.
var _spent: bool = false


## Called by the player or an enemy right after spawning the glob, to hand it
## everything it needs to know. Doing setup through one function like this -
## rather than poking at the variables from outside one at a time - means there
## is a single place to look when a glob behaves oddly.
##
## `fired_by_player` decides both what the glob can hit and what it looks for.
func setup(from: Vector3, dir: Vector3, fired_by_player: bool) -> void:
	global_position = from
	_previous_position = from
	# normalized() rescales a vector to length 1 while keeping its direction.
	# Doing it here means callers can hand in any length and still get a glob
	# that travels at exactly `speed`.
	direction = dir.normalized()

	if fired_by_player:
		# The player's paint hits walls and enemies, and passes over the player.
		hit_mask = LAYER_WORLD | LAYER_ENEMY
		target_group = "enemies"
	else:
		# Enemy paint hits walls and the player, and passes through other
		# enemies - so enemies at the back of a pack cannot kill their own
		# front line, which would make crowds trivial to beat.
		hit_mask = LAYER_WORLD | LAYER_PLAYER
		target_group = "player"


func _ready() -> void:
	# Build the visible glob in code: a small sphere that glows slightly so it
	# reads clearly against the pale arena.
	var mesh_node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	# radial_segments/rings control how many triangles the ball is made of.
	# Low numbers keep it faceted, which suits the GDD's "low-poly" direction
	# and costs almost nothing to draw even with dozens on screen.
	sphere.radial_segments = 8
	sphere.rings = 4
	mesh_node.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	# An emission makes the material give off its own light-like glow, so the
	# glob stays readable even in shadow. It does not actually light the world.
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	# Unshaded ignores scene lighting entirely - the glob is always full colour.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_node.material_override = mat

	add_child(mesh_node)


## _physics_process runs on the engine's fixed physics clock (60 times a second
## by default) rather than once per drawn frame. Anything that asks the physics
## engine questions belongs here, because this is the clock physics itself runs
## on - using _process instead gives inconsistent results on fast machines.
func _physics_process(delta: float) -> void:
	if _spent:
		return

	life -= delta
	if life <= 0.0:
		queue_free()
		return

	var next_position: Vector3 = global_position + direction * speed * delta

	# --- The anti-tunnelling ray ---
	# direct_space_state is the physics world's "answer questions right now"
	# interface. PhysicsRayQueryParameters3D.create() builds the question:
	# a straight line from A to B.
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(_previous_position, next_position)
	query.collision_mask = hit_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true

	# intersect_ray gives back a Dictionary describing the first thing the line
	# crossed, or an EMPTY dictionary if it crossed nothing. In GDScript an
	# empty dictionary is "falsy", so `if hit:` reads as "if we hit something".
	var hit := space.intersect_ray(query)
	if hit:
		_impact(hit["position"], hit["collider"])
		return

	_previous_position = global_position
	global_position = next_position


## Runs once, at the moment the glob touches something.
## `what` is the node the ray crossed - a wall, an enemy, or the player.
func _impact(at: Vector3, what) -> void:
	_spent = true

	# Direct damage. is_in_group() checks the node was tagged with add_to_group,
	# which is how we tell "an enemy" apart from "a wall" without caring what
	# script is attached. has_method() is a safety net: if something is tagged
	# as a target but has no take_damage function, we skip it instead of
	# crashing the whole game mid-wave.
	if what != null and what.is_in_group(target_group) and what.has_method("take_damage"):
		what.take_damage(damage)

	# Splash damage, if the shooter's inherited pair grants it. This is a plain
	# distance check against everything in the target group rather than a
	# physics sphere query - with at most a couple of dozen enemies alive it is
	# just as fast, and it is far easier to read and to debug.
	if splash_radius > 0.0:
		_splash(at, what)

	_spawn_splat(at)
	queue_free()


func _splash(at: Vector3, already_hit) -> void:
	var splash_damage: float = damage * splash_mult

	for node in get_tree().get_nodes_in_group(target_group):
		# Skip the thing we already damaged directly - otherwise a direct hit
		# would also collect full splash and land far more damage than the
		# numbers in traits.gd say it should.
		if node == already_hit:
			continue
		if not node is Node3D:
			continue
		if not node.has_method("take_damage"):
			continue

		# Deliberately untyped: see the note in _impact about static method checks.
		var target = node
		var distance: float = target.global_position.distance_to(at)
		if distance > splash_radius:
			continue

		# Falloff: full damage at the centre of the burst, fading to zero at the
		# edge. Without this, splash would be a flat circle of instant death and
		# positioning would not matter, which makes the Blotter pair strictly
		# better than every other pair instead of a trade-off.
		var falloff: float = 1.0 - (distance / splash_radius)
		target.take_damage(splash_damage * falloff)

	_spawn_burst(at)


## Leaves a flat disc of paint where the glob landed, which fades out. Pure
## decoration - it is what makes the arena visibly get messier as a fight goes
## on, which is the whole "clean up canvas-like battlefields" idea from the GDD.
func _spawn_splat(at: Vector3) -> void:
	var splat := MeshInstance3D.new()
	var quad := SphereMesh.new()
	quad.radius = 0.35
	quad.height = 0.12
	quad.radial_segments = 7
	quad.rings = 3
	splat.mesh = quad

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Transparency has to be switched on explicitly before an alpha value in
	# albedo_color will do anything at all.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	splat.material_override = mat

	# Add the splat to the level rather than to this glob - this glob is about
	# to delete itself, and a child always dies with its parent.
	get_parent().add_child(splat)
	splat.global_position = at

	# A Tween animates values over time. This one grows the splat slightly and
	# fades it to fully transparent, then deletes it. tween_property takes the
	# property path as a string, the value to reach, and how many seconds.
	# set_parallel makes the two animations run at the same time instead of
	# one after the other.
	var tween := splat.create_tween()
	tween.set_parallel(true)
	tween.tween_property(splat, "scale", Vector3(1.6, 0.6, 1.6), 0.25)
	tween.tween_property(mat, "albedo_color:a", 0.0, 1.8).set_delay(0.5)
	tween.chain().tween_callback(splat.queue_free)


## A quick expanding ring drawn when a Splatter Round bursts, so the player can
## actually see the radius they are being rewarded for lining up.
func _spawn_burst(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 12
	ball.rings = 6
	ring.mesh = ball

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.45)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Drawing only the inside faces of the sphere makes it read as a soft cloud
	# you are looking into, rather than a hard opaque ball blocking your view.
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	ring.material_override = mat

	get_parent().add_child(ring)
	ring.global_position = at
	# Start tiny, then snap out to the real splash radius, so the size you see
	# is the size that actually dealt damage.
	ring.scale = Vector3.ONE * 0.2

	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * splash_radius, 0.18)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(ring.queue_free)
