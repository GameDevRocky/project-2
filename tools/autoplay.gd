extends Node

## ============================================================================
## AUTOPLAY - a development tool, not part of the game.
## ============================================================================
##
## WHY THIS EXISTS
## The game can be launched headless from the command line, which is how changes
## get tested without opening the editor. The catch is that a headless run has
## no keyboard and no mouse, so the player just stands still and gets killed -
## which proves the game BOOTS but proves nothing about whether shooting,
## killing, inheriting or advancing a wave actually work.
##
## This node fakes a player. It aims at the nearest enemy, holds the trigger,
## and grabs any core it is standing on. It is not trying to play well - it is
## trying to touch every system in the game so that a headless run can tell us
## something worth knowing.
##
## HOW TO RUN IT
##     godot --headless --path <project> --quit-after 6000 -- --autoplay
##
## The bare `--` matters: everything after it is passed through to the game
## rather than being read by the engine itself.
##
## It is only ever created when that flag is present, so it costs a normal play
## session nothing.

## The player node, untyped for the usual parse-time reason.
var _player = null

## How quickly the fake aim swings onto a target, as a fraction per frame.
## Deliberately not instant - an aimbot that snaps perfectly would never miss,
## and a test that never misses cannot tell us whether the game is winnable by
## a human. This is roughly "a decent but not superhuman player".
const AIM_SPEED := 0.22

## Seconds between attempts to grab a core, so it does not spam the key.
var _interact_cooldown: float = 0.0

## Which way it is currently circling, +1 right or -1 left, and how long until
## it reconsiders. A human player under fire strafes constantly - the enemies in
## this game deliberately shoot at where you ARE rather than where you are
## going, so moving sideways is the main way damage is avoided. A test bot that
## stands still is therefore not a weak player, it is a player using none of the
## game's defensive options, and balancing against it would make the game far
## too easy for anyone who does move.
var _strafe_dir: float = 1.0
var _strafe_timer: float = 0.0

## Counts down between trigger bursts. Holding fire forever drains the paint
## reservoir faster than it refills, so the bot bursts the way a human would.
var _burst_timer: float = 0.0
var _firing: bool = false


func _ready() -> void:
	name = "Autoplay"
	print("[autoplay] enabled - simulating a player")


func _physics_process(delta: float) -> void:
	_interact_cooldown -= delta

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return

	if _player.is_dead():
		# Release the trigger so a dead player is not left holding it down.
		Input.action_release("fire")
		return

	_strafe_timer -= delta
	_burst_timer -= delta

	_aim_at_nearest_enemy()
	if not _grab_core():
		_strafe()


func _aim_at_nearest_enemy() -> void:
	var nearest = null
	var nearest_distance: float = 1e9
	var from: Vector3 = _player.global_position

	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy = node
		var distance: float = from.distance_to(enemy.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy

	if nearest == null:
		Input.action_release("fire")
		return

	# --- Turn the body toward the target (yaw) ---
	var to_target: Vector3 = nearest.global_position - from
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	# Keep firing even if something is almost exactly on top of us - just skip
	# the turn, because a direction of zero length has no angle to turn to.
	if flat.length() < 0.01:
		_manage_trigger()
		return

	# The player's forward is -Z, which is why this is atan2(-x, -z) rather than
	# the atan2(x, z) you would use for a normal "face this way" calculation.
	var target_yaw: float = atan2(-flat.x, -flat.z)
	_player.rotation.y = lerp_angle(_player.rotation.y, target_yaw, AIM_SPEED)

	# --- Tilt the camera toward the target (pitch) ---
	var camera = _player.get_node_or_null("Camera")
	if camera != null:
		# Aim at the enemy's middle rather than its feet.
		var eye: Vector3 = from + Vector3(0.0, 1.6, 0.0)
		var aim_point: Vector3 = nearest.global_position + Vector3(0.0, 0.8, 0.0)
		var offset: Vector3 = aim_point - eye
		var horizontal: float = Vector2(offset.x, offset.z).length()
		var target_pitch: float = atan2(offset.y, horizontal)
		camera.rotation.x = lerp_angle(camera.rotation.x, target_pitch, AIM_SPEED)

	_manage_trigger()


## Fires in bursts rather than holding the trigger down forever.
##
## The paint reservoir refills only after a short pause since your last shot, so
## continuous fire eventually starves itself - especially with the Sprayer pair,
## which spends paint almost exactly as fast as it comes back. Bursting is what
## a human does naturally; the bot has to be told.
func _manage_trigger() -> void:
	if _player.ammo < 4.0:
		# Dry. Stop and let it refill rather than dry-firing.
		_firing = false
		Input.action_release("fire")
		_burst_timer = 1.1
		return

	if _burst_timer > 0.0:
		return

	_firing = not _firing
	if _firing:
		Input.action_press("fire")
		_burst_timer = 0.9
	else:
		Input.action_release("fire")
		_burst_timer = 0.45


## Circles whatever it is fighting, reversing every so often.
func _strafe() -> void:
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(0.7, 1.6)
		if randf() < 0.5:
			_strafe_dir = -_strafe_dir

	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_release("move_right")

	if _strafe_dir > 0.0:
		Input.action_press("move_right")
	else:
		Input.action_press("move_left")


## Walks the fake player onto nearby cores and takes them. This is what makes
## the headless run actually exercise the inheritance mechanic rather than
## leaving every core to time out on the floor.
## Returns true if it is currently busy with a core, so the caller knows not to
## also try to strafe this frame.
func _grab_core() -> bool:
	if _interact_cooldown > 0.0:
		return false

	for node in get_tree().get_nodes_in_group("cores"):
		var core = node
		var distance: float = core.distance_to_player(_player.global_position)

		if distance <= core.pickup_range:
			# Press and release across two frames, because the game reads this
			# with is_action_just_pressed(), which only fires on the transition.
			Input.action_press("interact")
			_interact_cooldown = 0.35
			# call_deferred runs this after the current frame finishes, which is
			# the earliest point the press will have been seen.
			Input.action_release.call_deferred("interact")
			return true

		# Not close enough - walk toward it. Cores drop where enemies die, so
		# this also keeps the fake player moving around the arena instead of
		# rooted to the spawn point.
		if distance < 14.0:
			_walk_toward(core.global_position)
			return true

	return false


func _walk_toward(target: Vector3) -> void:
	# Work out whether the target is in front of or behind the player, and to
	# the left or the right, then hold the matching movement keys.
	var offset: Vector3 = target - _player.global_position
	var local: Vector3 = _player.global_transform.basis.inverse() * offset

	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_release("move_right")

	# Forward is -Z in Godot, so a negative local Z means "ahead of me".
	if local.z < -0.5:
		Input.action_press("move_forward")
	elif local.z > 0.5:
		Input.action_press("move_back")

	if local.x > 0.5:
		Input.action_press("move_right")
	elif local.x < -0.5:
		Input.action_press("move_left")
