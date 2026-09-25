extends CharacterBody3D

## ============================================================================
## PLAYER - first-person movement, the paintbrush-rifle, and inheritance.
## ============================================================================
##
## WHAT CharacterBody3D IS
## Godot gives you three kinds of physics body. RigidBody3D is fully simulated -
## you push it and physics decides where it ends up, which is wrong for a player
## because the player must feel directly controlled. StaticBody3D never moves.
## CharacterBody3D is the in-between made for exactly this job: YOU set a
## velocity each frame, then call move_and_slide(), and the engine moves the
## body and slides it along any walls it meets instead of sticking or passing
## through. You stay in control; the engine only handles the bumping.
##
## HOW INHERITANCE LANDS HERE
## This script keeps two sets of numbers. The BASE numbers (base_speed,
## base_damage...) never change - they are the tuning knobs for the whole game.
## The LIVE numbers (_speed, _damage...) are recalculated from the base numbers
## times the current pair's multipliers every time a pair is inherited, inside
## _apply_pair(). Nothing else in the file ever touches a multiplier. That means
## adding a new ability later is a change in traits.gd plus one line here, and
## it is impossible for a stale buff to linger after a swap - the live numbers
## are rebuilt from scratch, not adjusted.

const Traits = preload("res://scripts/traits.gd")
const Projectile = preload("res://scripts/projectile.gd")


# --- Signals ----------------------------------------------------------------
# A signal is an announcement this node makes when something happens. Other
# nodes "connect" to it and get called. The point is that the player does not
# need to know the HUD exists - it just shouts "my stats changed" and whoever
# cares listens. That keeps the Game Logic system and the UX system genuinely
# separate, which is one of the seams named in the GDD.

## Fired whenever health, paint or the current pair changes, so the HUD redraws.
signal stats_changed

## Fired when the player is hurt, so the HUD can flash the screen.
signal hurt

## Fired once when health reaches zero. game.gd listens for this.
signal died

## Fired when a new pair is inherited, carrying the pair data for the HUD popup.
signal pair_inherited(pair: Dictionary)


# --- Base tuning numbers ----------------------------------------------------
# @export puts these in the Godot editor's Inspector panel, so they can be
# tweaked by clicking rather than by editing code. These are the ONLY balance
# numbers for the player; everything else is derived from them.

## Hit points at full health.
@export var max_health: float = 100.0

## Ground movement speed in metres per second, before any pair multiplier.
@export var base_speed: float = 7.0

## Upward launch speed on jumping, in metres per second.
@export var base_jump_velocity: float = 6.0

## Downward acceleration, metres per second per second. Real gravity is 9.8, but
## games almost always use a much higher value - real gravity makes a jump feel
## floaty and slow to come down from. 20 gives a crisp, snappy arc.
@export var gravity: float = 20.0

## Seconds between shots before any pair multiplier. Smaller = faster gun.
@export var base_fire_interval: float = 0.28

## Health removed from an enemy by one direct glob, before multipliers.
@export var base_damage: float = 22.0

## How much paint the reservoir holds. One shot costs one unit.
@export var base_max_ammo: float = 30.0

## Paint refilled per second, once the refill delay below has passed.
@export var base_ammo_regen: float = 11.0

## Seconds after your last shot before paint starts refilling. This is what
## stops the gun being a bottomless hose: hold the trigger and you run dry, and
## you have to break contact for a moment to get going again.
@export var ammo_regen_delay: float = 0.6

## How fast your globs travel, in metres per second.
@export var projectile_speed: float = 60.0

## How far the mouse turns you. Radians of turn per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.0022


# --- Live numbers, rebuilt by _apply_pair() ---------------------------------
var _speed: float
var _jump_velocity: float
var _fire_interval: float
var _damage: float
var _max_ammo: float
var _ammo_regen: float
var _taken_mult: float
var _splash_radius: float
var _splash_mult: float
var _regen: float
var _regen_delay: float


# --- Live state -------------------------------------------------------------
var health: float
var ammo: float

## The id of the pair currently inherited, e.g. "monolith". Starts as the
## deliberately blank "apprentice" pair.
var pair_id: String = Traits.starting_id()

## The full data for that pair, so the HUD can read names and descriptions.
var pair: Dictionary = {}

## Counts down to zero; you may fire when it reaches zero.
var _fire_cooldown: float = 0.0

## Seconds since the last shot, compared against ammo_regen_delay.
var _since_fired: float = 999.0

## Seconds since last taking damage, compared against the Ghost pair's delay.
var _since_hurt: float = 999.0

## Set true on death so input and shooting stop immediately.
var _dead: bool = false

## Whether the game currently considers the mouse grabbed.
##
## This deliberately does NOT ask the display server by reading
## Input.mouse_mode. Two reasons. The first is correctness: mouse capture is a
## REQUEST, and a display server is free to ignore it - a headless run does
## exactly that, and reading it back meant the fire check saw "not captured"
## forever and the gun never fired at all. The second is that whether the player
## is allowed to shoot is a rule of the game, and a rule of the game should not
## be stored in the windowing system. We keep our own answer and tell the
## display server about it, rather than the other way round.
var _mouse_captured: bool = false


# --- Nodes built in _ready() ------------------------------------------------
var _camera: Camera3D
var _view_model: Node3D
var _muzzle: MeshInstance3D

## Where the view-model sits when you are perfectly still. Sway and bob are
## always applied as an offset from this, so the gun can never drift away from
## its home position over a long play session.
var _view_model_home: Vector3 = Vector3(0.32, -0.26, -0.6)

## Accumulated mouse movement, used to make the gun lag behind the camera.
var _sway: Vector2 = Vector2.ZERO

## Ever-increasing timer used to drive the walking bob with a sine wave.
var _bob_time: float = 0.0


func _ready() -> void:
	# add_to_group tags this node with a name other scripts can search for.
	# Enemy paint looks for the "player" group to know what it may damage.
	add_to_group("player")

	_build_body()
	_build_camera()
	_build_view_model()

	health = max_health
	_apply_pair(Traits.starting_id())
	ammo = _max_ammo

	# Capture the mouse: the cursor disappears and all mouse movement is fed to
	# us as relative motion instead of a screen position. This is what makes
	# mouse-look work - without it the cursor would hit the edge of the screen
	# and you could not keep turning.
	_set_mouse_captured(true)


## Records whether the mouse should be grabbed, and asks the display server to
## make it so. Everything in the game reads the flag; only this one function
## talks to the display server.
func _set_mouse_captured(captured: bool) -> void:
	_mouse_captured = captured
	if captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Builds the collision capsule. A capsule - a cylinder with domed ends - is the
## standard player shape in every 3D engine because the rounded bottom slides
## over small bumps and stair edges instead of catching on them the way a box
## corner would.
func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	# The capsule's origin is its centre, so lift it half its height to put the
	# player's feet on the floor rather than sunk half a body into it.
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)

	# Layer 2 = "player". Mask 1|4 = collide with the world and with enemies,
	# so enemies are solid obstacles you cannot walk through.
	collision_layer = 2
	collision_mask = 1 | 4


func _build_camera() -> void:
	_camera = Camera3D.new()
	# Named so the development autoplay harness can find it. Nothing in the
	# game itself looks it up by name.
	_camera.name = "Camera"
	# Eye height, a little below the 1.8m total so you are looking out of a head
	# rather than out of the top of your skull.
	_camera.position = Vector3(0.0, 1.6, 0.0)
	# The GDD asks for a wide 105 degree field of view. Wide FOV shows more of
	# the arena at once and makes movement feel faster, at the cost of some
	# distortion at the screen edges.
	_camera.fov = 105.0
	# current = true makes this the camera the game actually renders from.
	_camera.current = true
	add_child(_camera)


## The paintbrush-rifle you see in your hands. It is parented to the CAMERA,
## not to the player body, so it turns with your view for free - if it hung off
## the body it would stay level while you looked up and down.
func _build_view_model() -> void:
	_view_model = Node3D.new()
	_view_model.position = _view_model_home
	_camera.add_child(_view_model)

	# The rifle body - a charcoal block, the GDD's "structural accent".
	_view_model.add_child(_make_box(
		Vector3(0.09, 0.1, 0.55), Vector3(0.0, 0.0, 0.0), Traits.CHARCOAL))
	# The handle, angled down and back.
	_view_model.add_child(_make_box(
		Vector3(0.07, 0.2, 0.09), Vector3(0.0, -0.13, 0.14), Traits.CHARCOAL))
	# A teal band, so the gun is not one flat slab of dark.
	_view_model.add_child(_make_box(
		Vector3(0.1, 0.045, 0.12), Vector3(0.0, 0.035, -0.06), Traits.TEAL))

	# The bristle head at the muzzle. This one is stored so its colour can be
	# repainted to match whatever pair you have inherited - it is the clearest
	# possible readout of "what am I right now", sitting in the middle of the
	# screen where you are already looking.
	_muzzle = _make_box(Vector3(0.12, 0.13, 0.16), Vector3(0.0, 0.0, -0.36), Traits.WHITE)
	_view_model.add_child(_muzzle)


## Small helper so the view-model above reads as a parts list instead of forty
## lines of near-identical mesh setup.
func _make_box(box_size: Vector3, at: Vector3, box_color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	node.mesh = box
	node.position = at

	var mat := StandardMaterial3D.new()
	mat.albedo_color = box_color
	# Fully rough and non-metal: flat matte colour, which is what the GDD's
	# cel-shaded, hard-edged direction calls for.
	mat.roughness = 1.0
	mat.metallic = 0.0
	node.material_override = mat

	return node


## _unhandled_input receives events that no UI element already consumed. Mouse
## motion is read here rather than in _process because motion arrives as
## discrete events - reading it on a timer would drop movement on slow frames
## and make the aim feel like it is skipping.
func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return

	if event is InputEventMouseMotion and _mouse_captured:
		var motion: InputEventMouseMotion = event

		# Turning left/right rotates the whole BODY, so that "forward" for
		# movement always means the way you are facing.
		rotate_y(-motion.relative.x * mouse_sensitivity)

		# Looking up/down rotates only the CAMERA. If it rotated the body the
		# player would tip over and walk into the floor.
		_camera.rotate_x(-motion.relative.y * mouse_sensitivity)
		# Clamp the pitch to just under straight up and straight down. Without
		# this you could roll the camera over backwards and the view would
		# flip upside down.
		_camera.rotation.x = clampf(_camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

		# Feed the motion into the sway so the gun lags behind the view.
		_sway.x += motion.relative.x
		_sway.y += motion.relative.y

	# Escape frees the mouse so you can alt-tab or reach the window's close
	# button. Clicking in the window re-captures it, handled in _process.
	if event.is_action_pressed("ui_cancel"):
		_set_mouse_captured(false)


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_tick_timers(delta)
	_move(delta)
	_shoot(delta)
	_regenerate(delta)
	_animate_view_model(delta)


func _tick_timers(delta: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_since_fired += delta
	_since_hurt += delta


func _move(delta: float) -> void:
	# Gravity, applied whenever we are not standing on something.
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = _jump_velocity

	# Input.get_vector reads four actions and returns a direction of length at
	# most 1. Because it normalises, holding W and D together does NOT make you
	# move faster diagonally, which is a classic bug in hand-rolled movement.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# That direction is in "screen" terms - x is right, y is forward. Turn it
	# into a world direction by combining the body's own axes. basis.x is the
	# way the body calls "right", basis.z is the way it calls "backward", so
	# forward is -basis.z. Doing it this way means WASD always moves relative to
	# where you are looking, at any angle, with no trigonometry of our own.
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction.length() > 0.0:
		velocity.x = direction.x * _speed
		velocity.z = direction.z * _speed
		# Advance the head-bob clock only while actually walking, so the gun
		# goes still the instant you stop.
		_bob_time += delta * _speed
	else:
		# move_toward eases a value to a target by at most a set step, so
		# releasing the keys slides you to a stop over a short distance instead
		# of halting dead. The number is metres per second of deceleration.
		velocity.x = move_toward(velocity.x, 0.0, _speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, _speed * 8.0 * delta)

	move_and_slide()


func _shoot(_delta: float) -> void:
	# Re-capture the mouse if the player clicked back into the window after
	# pressing Escape. Checked before firing so the click that returns focus
	# does not also fire a shot.
	if not _mouse_captured:
		if Input.is_action_just_pressed("fire"):
			_set_mouse_captured(true)
		return

	if not Input.is_action_pressed("fire"):
		return
	if _fire_cooldown > 0.0:
		return
	if ammo < 1.0:
		return

	ammo -= 1.0
	_fire_cooldown = _fire_interval
	_since_fired = 0.0

	var glob = Node3D.new()
	glob.set_script(Projectile)
	glob.damage = _damage
	glob.speed = projectile_speed
	glob.splash_radius = _splash_radius
	glob.splash_mult = _splash_mult
	glob.color = pair["color"]

	# Add the glob to the level, NOT to the player. A child node moves with its
	# parent, so a glob parented to the player would be dragged along behind you
	# forever instead of flying away on its own.
	get_parent().add_child(glob)

	# Fire FROM the brush head, but TOWARD wherever the crosshair is pointing.
	#
	# Those are two different directions and the difference matters enormously.
	# The brush head sits about 32cm to the right of the camera and 26cm below
	# it, because that is where a gun looks right on screen. If the glob simply
	# travelled the way the CAMERA faces, it would fly along a line parallel to
	# your view but permanently offset 32cm right and 26cm low - so every shot
	# would land beside what the crosshair was on, at every range, forever. With
	# enemies well under a metre wide that is the difference between a gun that
	# works and one that mostly misses.
	#
	# So we ask where the crosshair actually lands first, then aim the glob from
	# the brush head at THAT point. The shot still visibly leaves the gun, but it
	# goes where you are looking.
	var aim: Vector3 = _aim_point()
	glob.setup(_muzzle.global_position, aim - _muzzle.global_position, true)

	_kick_view_model()
	stats_changed.emit()


## Finds the point in the world the crosshair is currently over, by casting a
## ray straight out of the middle of the camera.
##
## If the ray hits nothing - you are aiming at open sky - it returns a point far
## away down the same line, which gives the same direction to shoot in.
func _aim_point() -> Vector3:
	var from: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_transform.basis.z
	var far: Vector3 = from + forward * 250.0

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, far)
	# Walls and enemies, the same things a glob can hit.
	query.collision_mask = 1 | 4
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := space.intersect_ray(query)
	if not hit:
		return far

	var point: Vector3 = hit["position"]

	# If the crosshair is on something almost touching your face, aiming the
	# glob at it from the offset brush head would send the shot sharply sideways.
	# Below a couple of metres, just fire straight ahead instead.
	if from.distance_to(point) < 2.0:
		return far

	return point


## Refills the paint reservoir and, if the Ghost pair is inherited, health.
func _regenerate(delta: float) -> void:
	if _since_fired >= ammo_regen_delay and ammo < _max_ammo:
		ammo = minf(_max_ammo, ammo + _ammo_regen * delta)
		stats_changed.emit()

	# _regen is 0 for every pair except Ghost, so this costs nothing to leave
	# running for the other five.
	if _regen > 0.0 and _since_hurt >= _regen_delay and health < max_health:
		health = minf(max_health, health + _regen * delta)
		stats_changed.emit()


## Sway and bob, both asked for by name in the GDD's camera direction.
func _animate_view_model(delta: float) -> void:
	# Bleed the accumulated mouse movement back toward zero, so the gun drifts
	# home after you stop turning. lerp blends from one value to the other;
	# doing it every frame gives a smooth exponential settle.
	_sway = _sway.lerp(Vector2.ZERO, clampf(delta * 9.0, 0.0, 1.0))

	# Turning right pushes the gun left on screen, as if it has weight and is
	# being dragged around behind your hands. Clamped so a fast flick cannot
	# throw the gun off the side of the screen.
	var sway_offset := Vector3(
		clampf(-_sway.x * 0.0016, -0.06, 0.06),
		clampf(_sway.y * 0.0016, -0.06, 0.06),
		0.0)

	# Walking bob: two sine waves, the vertical one at twice the rate of the
	# horizontal one, which traces a figure-eight and reads as footsteps.
	var bob_offset := Vector3(
		sin(_bob_time * 1.1) * 0.012,
		abs(sin(_bob_time * 2.2)) * 0.012,
		0.0)

	var target := _view_model_home + sway_offset + bob_offset
	_view_model.position = _view_model.position.lerp(target, clampf(delta * 14.0, 0.0, 1.0))


## A short recoil shove, run on every shot. Animating the gun rather than the
## camera means recoil is felt but never fights the player for their aim.
func _kick_view_model() -> void:
	_view_model.position.z += 0.05
	_view_model.position.y -= 0.012


# ============================================================================
# INHERITANCE
# ============================================================================

## Called when the player walks into a fallen enemy's paint core. Swaps the
## whole pair - you cannot keep the old ability, and you cannot refuse the new
## weakness. Returns false if you already have this pair, so the pickup can stay
## on the ground instead of being wasted.
func inherit_pair(id: String) -> bool:
	if id == pair_id:
		return false

	_apply_pair(id)

	# Top the reservoir up to the new capacity so that inheriting a pair with a
	# bigger reservoir is felt right away, and so swapping mid-fight is not a
	# punishment on its own.
	ammo = minf(_max_ammo, maxf(ammo, _max_ammo * 0.5))

	pair_inherited.emit(pair)
	stats_changed.emit()
	return true


## Rebuilds every live number from the base numbers times the new pair's
## multipliers. Rebuilding from base each time - rather than adjusting whatever
## the numbers currently are - is what guarantees an old pair leaves nothing
## behind when it is replaced.
func _apply_pair(id: String) -> void:
	pair_id = id
	pair = Traits.get_pair(id)

	# A faster fire RATE means a shorter INTERVAL between shots, so the
	# multiplier divides here rather than multiplying. Getting this backwards
	# would silently invert every gun-speed ability in the game.
	_fire_interval = base_fire_interval / float(pair["fire_rate_mult"])

	_damage = base_damage * float(pair["damage_mult"])
	_speed = base_speed * float(pair["move_mult"])
	_jump_velocity = base_jump_velocity * float(pair["jump_mult"])
	_taken_mult = float(pair["taken_mult"])
	_splash_radius = float(pair["splash_radius"])
	_splash_mult = float(pair["splash_mult"])
	_regen = float(pair["regen"])
	_regen_delay = float(pair["regen_delay"])
	_max_ammo = base_max_ammo * float(pair["ammo_mult"])
	_ammo_regen = base_ammo_regen * float(pair["ammo_regen_mult"])

	# Never leave the reservoir holding more than it can now carry - inheriting
	# Faded Pigment must actually cut you down to the smaller tank.
	ammo = minf(ammo, _max_ammo)

	# Repaint the brush head to the new pair's colour.
	if _muzzle != null:
		var mat = _muzzle.material_override
		mat.albedo_color = pair["color"]


# ============================================================================
# DAMAGE
# ============================================================================

## Called by enemy paint and by charging Bounders. The weakness multiplier is
## applied HERE, in one place, so no attack anywhere in the game can bypass
## Thick Coat or dodge Brittle Canvas.
func take_damage(amount: float) -> void:
	if _dead:
		return

	health -= amount * _taken_mult
	_since_hurt = 0.0

	hurt.emit()
	stats_changed.emit()

	if health <= 0.0:
		health = 0.0
		_dead = true
		_set_mouse_captured(false)
		died.emit()


## Called by game.gd between waves.
func heal(amount: float) -> void:
	health = minf(max_health, health + amount)
	stats_changed.emit()


## Read by the HUD so it can size the paint bar correctly for the current pair.
func get_max_ammo() -> float:
	return _max_ammo


func is_dead() -> bool:
	return _dead
