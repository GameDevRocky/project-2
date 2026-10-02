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
var speed: float = 90.0

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

## Paint colour, used for the bullet and its trail.
var color: Color = Color.WHITE

## Seconds before the glob deletes itself if it never hits anything. Without
## this, every missed shot would stay in memory forever and the game would
## slowly grind to a halt over a long run.
var life: float = 4.0
var attacker = null
var attacker_team := ""
## The player who fired this glob, if any. Used ONLY to tell them "you hit
## something" for the crosshair hit marker; the damage code never reads it.
var source_player = null
## Set when this glob damaged anything, directly or by splash.
var _hit_landed := false
var can_deal_damage := true

## How the shot looks, set per gun from scripts/weapons.gd before it is added
## to the scene. The defaults are the Brush Rifle's tracer.
var bullet_radius: float = 0.06
var trail_length: float = 1.15
var trail_radius: float = 0.022

## Downward pull in metres per second per second. 0 (every gun except the
## Blob Lobber) means the shot flies dead straight, exactly as before.
var gravity: float = 0.0


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

# The trail, and how far this shot has flown. The trail grows from nothing to
# its full length over its first `trail_length` metres, so a long trail (the
# Fine Liner's is 4 m) never pokes out behind the gun - through it and past
# the camera - in the first frames after firing.
var _trail: MeshInstance3D
var _travelled: float = 0.0


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
	# A Node3D faces along its local -Z axis. Pointing the projectile node along
	# its travel direction also points the child tracer directly behind it.
	if direction.length() > 0.001:
		var up := Vector3.UP if absf(direction.y) < 0.98 else Vector3.RIGHT
		look_at(from + direction, up)

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
	if not attacker_team.is_empty():
		target_group = "tdm_combatants"
		hit_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_ENEMY


func configure_tdm(source, team_name: String) -> void:
	attacker = source
	attacker_team = team_name


func _ready() -> void:
	add_to_group("projectiles")
	# Build a compact glowing bullet. Collision still uses the frame-to-frame
	# ray below, so shrinking the visible sphere cannot make fast shots tunnel.
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Bullet"
	var sphere := SphereMesh.new()
	sphere.radius = bullet_radius
	sphere.height = bullet_radius * 2.0
	# radial_segments/rings control how many triangles the ball is made of.
	# Low numbers keep it faceted, which suits the GDD's "low-poly" direction
	# and costs almost nothing to draw even with dozens on screen.
	sphere.radial_segments = 8
	sphere.rings = 4
	mesh_node.mesh = sphere

	var mat := glob_material(color)
	mesh_node.material_override = mat

	add_child(mesh_node)
	_build_trail()


## Adds a thin glowing streak behind the bullet. CylinderMesh points along its
## local Y axis, so rotating it 90 degrees lays it along local +Z, behind the
## projectile's -Z travel direction.
func _build_trail() -> void:
	var trail := MeshInstance3D.new()
	trail.name = "Trail"
	var trail_mesh := CylinderMesh.new()
	trail_mesh.top_radius = trail_radius
	trail_mesh.bottom_radius = 0.0
	trail_mesh.height = trail_length
	trail_mesh.radial_segments = 6
	trail_mesh.rings = 1
	trail.mesh = trail_mesh
	trail.rotation.x = deg_to_rad(90.0)
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail = trail
	_grow_trail()

	var trail_material := trail_material_for(color)
	trail.material_override = trail_material
	add_child(trail)


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

	# A lobbed shot curves: gravity bends its direction down a little every
	# step, and it keeps pointing along its path so the trail stays behind it.
	# Straight shots (gravity 0) skip this and move exactly as before.
	if gravity > 0.0:
		var velocity := direction * speed + Vector3.DOWN * gravity * delta
		speed = velocity.length()
		direction = velocity / maxf(speed, 0.001)
		var up := Vector3.UP if absf(direction.y) < 0.98 else Vector3.RIGHT
		look_at(global_position + direction, up)

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
	var hit: Dictionary = {}
	var excluded: Array[RID] = []
	while true:
		query.exclude = excluded
		hit = space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider = hit["collider"]
		if (not attacker_team.is_empty() and collider.is_in_group("tdm_combatants")
				and str(collider.get("tdm_team")) == attacker_team):
			excluded.append(collider.get_rid())
			continue
		break
	if hit:
		_impact(hit["position"], hit["collider"])
		return

	_previous_position = global_position
	global_position = next_position
	_travelled += speed * delta
	_grow_trail()


## Stretches the trail to the distance flown so far, up to its full length.
## Scaling the trail node's own Y stretches the cylinder along its length
## (its Y, laid along +Z by the 90 degree turn), and moving it back by half
## that keeps its thin end touching the bullet.
func _grow_trail() -> void:
	if _trail == null:
		return
	var fraction := clampf(_travelled / maxf(trail_length, 0.01), 0.01, 1.0)
	_trail.scale = Vector3(1.0, fraction, 1.0)
	_trail.position.z = trail_length * fraction * 0.5


## Runs once, at the moment the glob touches something.
## `what` is the node the ray crossed - a wall, an enemy, or the player.
func _impact(at: Vector3, what) -> void:
	_spent = true

	# Direct damage. is_in_group() checks the node was tagged with add_to_group,
	# which is how we tell "an enemy" apart from "a wall" without caring what
	# script is attached. has_method() is a safety net: if something is tagged
	# as a target but has no take_damage function, we skip it instead of
	# crashing the whole game mid-wave.
	var friendly_hit := false
	if not attacker_team.is_empty() and what != null and what.is_in_group("tdm_combatants"):
		friendly_hit = str(what.get("tdm_team")) == attacker_team
	if can_deal_damage and what != null and not friendly_hit and what.is_in_group(target_group) and what.has_method("take_damage"):
		what.take_damage(damage, attacker)
		_hit_landed = true

	# Splash damage, if the shooter's inherited pair grants it. This is a plain
	# distance check against everything in the target group rather than a
	# physics sphere query - with at most a couple of dozen enemies alive it is
	# just as fast, and it is far easier to read and to debug.
	if can_deal_damage and splash_radius > 0.0:
		_splash(at, what)

	if _hit_landed and source_player != null and is_instance_valid(source_player):
		source_player.confirm_hit()

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
		if not attacker_team.is_empty() and str(node.get("tdm_team")) == attacker_team:
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
		target.take_damage(splash_damage * falloff, attacker)
		_hit_landed = true

	_spawn_burst(at)


# --- Effect materials --------------------------------------------------------

## The glob in flight. An emission makes it give off its own light-like glow,
## so it stays readable even in shadow (it does not actually light the world).
## It is lit rather than UNSHADED on purpose: unshaded skips emission entirely,
## and the glow is what pushes the glob past the arena's glow threshold, so
## incoming paint carries a halo you can track and dodge. Fog is off so a glob
## fired from across the room is as crisp as one fired from next to you.
static func glob_material(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 1.8
	mat.disable_fog = true
	return mat


# Built by static functions so scripts/visual/shader_warmup.gd can draw these
# exact materials once while the match loads. The web renderer compiles each
# kind of material the first time it is drawn, which froze the game for
# ~140 ms at the first hit of a match; warming them up moves that to loading.

## The thin streak behind a bullet.
static func trail_material_for(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(c.r, c.g, c.b, 0.72)
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 2.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_fog = true
	return mat


## The Splatter Rounds splash sphere. Only its inside faces are drawn, so it
## reads as a soft cloud you look into rather than an opaque ball.
static func burst_material(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(c.r, c.g, c.b, 0.45)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.disable_fog = true
	return mat


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

	var mat := burst_material(color)
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
