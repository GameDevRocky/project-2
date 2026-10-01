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


const PaintKit = preload("res://scripts/visual/paint_kit.gd")

## Surface splats alive at once. Past this, the oldest is removed early, so a
## long fight can never pile up thousands of them.
const MAX_SPLATS := 64
## Seconds a splat stays fully visible before it starts to fade.
const SPLAT_HOLD := 4.5
const SPLAT_FADE := 1.5

## Every live splat, oldest first. `static` = shared by all globs.
static var _live_splats: Array[Node3D] = []


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
var attacker = null
var attacker_team := ""
## The player who fired this glob, if any. Used ONLY to tell them "you hit
## something" for the crosshair hit marker; the damage code never reads it.
var source_player = null
## Set when this glob damaged anything, directly or by splash.
var _hit_landed := false


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
	if not attacker_team.is_empty():
		target_group = "tdm_combatants"
		hit_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_ENEMY

	# Point the glob's teardrop along its flight path. Purely visual: the
	# movement below uses `direction`, never this node's rotation.
	if direction.length() > 0.001:
		var up := Vector3.UP if absf(direction.y) < 0.98 else Vector3.RIGHT
		look_at(global_position + direction, up)


func configure_tdm(source, team_name: String) -> void:
	attacker = source
	attacker_team = team_name


func _ready() -> void:
	add_to_group("projectiles")
	# The visible glob: the generated teardrop (models/generated/paint_glob.glb),
	# one mesh shared by every glob so dozens in flight cost almost nothing.
	# Falls back to the original low-poly sphere if the model is missing.
	var mesh_node := MeshInstance3D.new()
	var glob_mesh := PaintKit.mesh("paint_glob", "Glob")
	if glob_mesh != null:
		mesh_node.mesh = glob_mesh
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 0.14
		sphere.height = 0.28
		sphere.radial_segments = 8
		sphere.rings = 4
		mesh_node.mesh = sphere

	var mat := glob_material(color)
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
		_impact(hit["position"], hit["collider"], hit["normal"])
		return

	_previous_position = global_position
	global_position = next_position


## Runs once, at the moment the glob touches something.
## `what` is the node the ray crossed - a wall, an enemy, or the player.
func _impact(at: Vector3, what, normal: Vector3 = Vector3.UP) -> void:
	_spent = true

	# Direct damage. is_in_group() checks the node was tagged with add_to_group,
	# which is how we tell "an enemy" apart from "a wall" without caring what
	# script is attached. has_method() is a safety net: if something is tagged
	# as a target but has no take_damage function, we skip it instead of
	# crashing the whole game mid-wave.
	var friendly_hit := false
	if not attacker_team.is_empty() and what != null and what.is_in_group("tdm_combatants"):
		friendly_hit = str(what.get("tdm_team")) == attacker_team
	if what != null and not friendly_hit and what.is_in_group(target_group) and what.has_method("take_damage"):
		what.take_damage(damage, attacker)
		_hit_landed = true

	# Splash damage, if the shooter's inherited pair grants it. This is a plain
	# distance check against everything in the target group rather than a
	# physics sphere query - with at most a couple of dozen enemies alive it is
	# just as fast, and it is far easier to read and to debug.
	if splash_radius > 0.0:
		_splash(at, what)

	if _hit_landed and source_player != null and is_instance_valid(source_player):
		source_player.confirm_hit()

	_spawn_splat(at, normal, what)
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


## Leaves a splat of paint on the surface the glob hit, which later fades.
## Pure decoration - it is what makes the arena visibly get messier as a fight
## goes on, the "clean up canvas-like battlefields" idea from the GDD.
##
## The splat lies FLAT on the surface: the ray that found the hit also returns
## the surface's normal (the direction it faces), and the splat is turned to
## face the same way, lifted 1.2 cm off it so it neither floats visibly nor
## flickers inside the wall. Only world surfaces get splats. A hit on an enemy
## or a player gets a quick puff instead, because a splat left at that spot
## would hang in mid-air the moment the target moved.
func _spawn_splat(at: Vector3, normal: Vector3, what) -> void:
	if what != null and (what.is_in_group("enemies") or what.is_in_group("player")
			or what.is_in_group("tdm_combatants")):
		_spawn_puff(at)
		return
	var splat_mesh := PaintKit.mesh("paint_splat", "Splat_%d" % randi_range(0, 3))
	if splat_mesh == null:
		_spawn_blob_splat(at)
		return

	var splat := MeshInstance3D.new()
	splat.mesh = splat_mesh
	splat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := splat_material(color)
	splat.material_override = mat
	get_parent().add_child(splat)

	# The splat model lies in its local XZ plane with +Y as its "up". Turn +Y
	# onto the surface normal, then spin it randomly around that normal so no
	# two splats look identical.
	var up := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var facing := Basis(Vector3.RIGHT, PI) if up.dot(Vector3.UP) < -0.999 else Basis(Quaternion(Vector3.UP, up))
	facing = facing * Basis(Vector3.UP, randf() * TAU)
	var size := randf_range(0.8, 1.2)
	splat.global_transform = Transform3D(facing, at + up * 0.012)
	splat.scale = Vector3.ONE * size * 0.6

	_live_splats.append(splat)
	_trim_splats()

	var tween := splat.create_tween()
	tween.tween_property(splat, "scale", Vector3.ONE * size, 0.12)
	tween.tween_interval(SPLAT_HOLD)
	tween.tween_property(mat, "albedo_color:a", 0.0, SPLAT_FADE)
	tween.tween_callback(splat.queue_free)


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

## A fresh splat: shaded wet paint with a faint glow, so it reads apart from
## the room's matte dried-paint decoration.
static func splat_material(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.18
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 0.25
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_fog = true
	return mat


## The quick puff where a glob hits a body.
static func puff_material(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(c.r, c.g, c.b, 0.7)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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


## Keeps the number of splats bounded: drop freed ones from the list, then
## remove the oldest until we are back under the cap.
static func _trim_splats() -> void:
	_live_splats = _live_splats.filter(func(n): return is_instance_valid(n))
	while _live_splats.size() > MAX_SPLATS:
		var oldest: Node3D = _live_splats.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


## A small burst of paint where a glob hits a body, gone in a fifth of a second.
func _spawn_puff(at: Vector3) -> void:
	var puff := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 10
	ball.rings = 5
	puff.mesh = ball
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := puff_material(color)
	puff.material_override = mat
	get_parent().add_child(puff)
	puff.global_position = at
	puff.scale = Vector3.ONE * 0.06
	var tween := puff.create_tween()
	tween.set_parallel(true)
	tween.tween_property(puff, "scale", Vector3.ONE * 0.32, 0.16)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tween.chain().tween_callback(puff.queue_free)


## The original squashed-sphere splat, used only if the splat model is missing.
func _spawn_blob_splat(at: Vector3) -> void:
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
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_fog = true
	splat.material_override = mat
	get_parent().add_child(splat)
	splat.global_position = at
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
