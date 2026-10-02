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
##
## ONLINE: SHIELD AND POWERS (Rocklyn's online branch)
## Online, you have 100 shield on top of 100 health (damage takes shield
## first), and the server hands you a POWER when you shoot down a flying power
## ball (scripts/power_abilities.gd). _apply_power() rebuilds your gun and
## movement from the base numbers and that power, the same way _apply_pair()
## does for pairs. The gun MODEL in your hands follows the power too
## (scripts/weapons.gd), so other players can see what you picked up.

const Traits = preload("res://scripts/traits.gd")
const Projectile = preload("res://scripts/projectile.gd")
const CustomizationData = preload("res://scripts/character_customization_data.gd")
const PaintKit = preload("res://scripts/visual/paint_kit.gd")
const PaintFx = preload("res://scripts/visual/paint_fx.gd")
const ShaderWarmup = preload("res://scripts/visual/shader_warmup.gd")
const GunSkins = preload("res://scripts/visual/gun_skins.gd")
const Weapons = preload("res://scripts/weapons.gd")
const Powers = preload("res://scripts/power_abilities.gd")


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

## Fired when one of YOUR globs damaged something, so the HUD can flash a hit
## marker on the crosshair. Feedback only: the damage has already happened in
## projectile.gd exactly as before; this just reports it.
signal hit_confirmed

## Fired when the server gives you a power, takes it away, or turns your
## invisibility on or off. The HUD shows the power card from it.
signal power_changed(power_id: String, invisible: bool)


# --- Base tuning numbers ----------------------------------------------------
# @export puts these in the Godot editor's Inspector panel, so they can be
# tweaked by clicking rather than by editing code. These are the ONLY balance
# numbers for the player; everything else is derived from them.

## Hit points at full health.
@export var max_health: float = 100.0
## Online shield, on top of health. Damage removes shield first.
@export var max_shield: float = 100.0

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

## Health removed by one direct glob, before multipliers. Online this is the
## 4.4 of an ordinary paint bullet (scripts/power_abilities.gd).
@export var base_damage: float = Powers.BASE_DAMAGE

## How much paint the reservoir holds. One shot costs one unit.
@export var base_max_ammo: float = 30.0

## Paint refilled per second, once the refill delay below has passed.
@export var base_ammo_regen: float = 11.0

## Seconds after your last shot before paint starts refilling. This is what
## stops the gun being a bottomless hose: hold the trigger and you run dry, and
## you have to break contact for a moment to get going again.
@export var ammo_regen_delay: float = 0.6

## How fast your globs travel, in metres per second.
@export var projectile_speed: float = 90.0

## How far the mouse turns you. Radians of turn per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.0022

## Maximum right-stick turn speed in radians per second.
@export var controller_look_speed: float = 2.8


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
var _projectile_speed: float = 90.0
var _projectile_kind := "bullet"


# --- Live state -------------------------------------------------------------
var health: float
var shield: float
var ammo: float
## The power the server gave you ("" = none), and whether you are invisible.
var current_power := ""
var power_invisible := false

## The id of the pair currently inherited, e.g. "monolith". Starts as the
## deliberately blank "apprentice" pair.
var pair_id: String = Traits.starting_id()

## The full data for that pair, so the HUD can read names and descriptions.
var pair: Dictionary = {}

## Counts down to zero; you may fire when it reaches zero.
var _fire_cooldown: float = 0.0

## Seconds since the last shot, compared against the gun's refill delay.
var _since_fired: float = 999.0

## Seconds since last taking damage, compared against the Ghost pair's delay.
var _since_hurt: float = 999.0

## Set true on death so input and shooting stop immediately.
var _dead: bool = false

## True while the pause menu is open. Online matches cannot really stop, so
## the world carries on; this just stops YOUR inputs - no looking, moving or
## shooting - until you resume.
var _paused: bool = false

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
var _camera_home := Vector3(0.0, 1.6, 0.0)
var _view_model: Node3D
## The gun model inside _view_model. Swapped when a new gun is equipped.
var _gun: Node3D
var _muzzle: MeshInstance3D

## Parts of the Paint Blaster model (models/generated/paint_blaster.glb) that
## move. All purely visual: they READ ammo, they never change it.
var _skin_band: MeshInstance3D
var _gun_fill: Node3D
var _gun_needle: Node3D
var _gun_regulator: Node3D
## A little puff of paint thrown from the bristles on each shot.
var _muzzle_puff: CPUParticles3D

## Where globs leave the gun, in view-model space. Unchanged since the
## original box gun; the Paint Blaster model is built around it.
const MUZZLE_POINT := Vector3(0.0, 0.0, -0.36)
const VIEW_GUN_SCALE := 1.15

## The normal field of view (the GDD's wide 105 degrees).
const BASE_FOV := 105.0
## A render layer only for your OWN power halo. Your camera (and the spectator
## camera) leave this layer out, so the ring 0.7 m above your eyes never fills
## the screen when you look up. Other players see the halo on their copy of
## you (remote_player.gd), which is on the normal layer.
const OWN_HALO_LAYER := 1 << 10
## Which gun model is in the view-model now, so it is only rebuilt on change.
var _gun_model_name := ""
## True while dead and watching someone (the match controller's spectator
## camera draws the view; this only parks the body).
var _spectating := false
## A glowing ring over your head while you carry a power.
var _power_halo: MeshInstance3D

## Where the view-model sits when you are perfectly still. Sway and bob are
## always applied as an offset from this, so the gun can never drift away from
## its home position over a long play session.
var _view_model_home: Vector3 = Vector3(0.32, -0.26, -0.6)

## Accumulated mouse movement, used to make the gun lag behind the camera.
var _sway: Vector2 = Vector2.ZERO

## Ever-increasing timer used to drive the walking bob with a sine wave.
var _bob_time: float = 0.0
var customization: Dictionary = {}
var tdm_team := ""
var tdm_manager = null


func _ready() -> void:
	# add_to_group tags this node with a name other scripts can search for.
	# Enemy paint looks for the "player" group to know what it may damage.
	add_to_group("player")
	if not tdm_team.is_empty():
		add_to_group("tdm_combatants")

	_build_body()
	_build_camera()
	_build_view_model()
	_build_power_halo()

	health = max_health
	shield = max_shield
	_apply_pair(Traits.starting_id())
	_apply_power()
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
	_camera.position = _camera_home
	# The GDD asks for a wide 105 degree field of view. Wide FOV shows more of
	# the arena at once and makes movement feel faster, at the cost of some
	# distortion at the screen edges.
	_camera.fov = BASE_FOV
	# current = true makes this the camera the game actually renders from.
	_camera.current = true
	_camera.cull_mask &= ~OWN_HALO_LAYER
	add_child(_camera)


## The paintbrush-rifle you see in your hands. It is parented to the CAMERA,
## not to the player body, so it turns with your view for free - if it hung off
## the body it would stay level while you looked up and down.
##
## The gun is the generated Paint Blaster model. Its `Muzzle` part (the bristle
## tuft) has its origin exactly where the old white cube sat, (0, 0, -0.36) in
## view-model space, so globs spawn from the same point as before and the
## aim-toward-the-crosshair maths in _shoot() is unchanged. If the model file is
## missing, the original three-box gun is built instead.
func _build_view_model() -> void:
	_view_model = Node3D.new()
	_view_model.position = _view_model_home
	_camera.add_child(_view_model)
	_build_gun()
	# Draw every effect material once while the match loads (see the script),
	# so the web build does not freeze at the first hit of the match.
	var warmup := Node3D.new()
	warmup.set_script(ShaderWarmup)
	_camera.add_child(warmup)


## Builds the model of the gun you carry inside the view-model, replacing any
## previous one. Each gun model (models/generated/) has a `Muzzle` part whose
## origin is where shots leave it, and a `Fill` part showing the paint left.
func _build_gun() -> void:
	if _gun != null:
		_gun.queue_free()
	_gun = null
	_muzzle = null
	_skin_band = null
	_gun_fill = null
	_gun_needle = null
	_gun_regulator = null
	_muzzle_puff = null

	# Which gun model: the one that goes with your power (scripts/weapons.gd).
	var look := Weapons.for_power(current_power)
	_gun_model_name = str(look.model)
	var model := PaintKit.instance(_gun_model_name)
	if model == null:
		model = PaintKit.instance("paint_blaster")
	if model == null:
		_build_box_gun()
		_apply_menu_customization()
		return
	_gun = model
	# Drawn 1.15x bigger so it reads as a chunky tool in first person. The
	# Paint Blaster is scaled AROUND its muzzle point, so its Muzzle node (and
	# so the glob spawn point) stays exactly at (0, 0, -0.36).
	model.scale = Vector3.ONE * VIEW_GUN_SCALE
	if model.scene_file_path.get_file() == "paint_blaster.glb":
		model.position = MUZZLE_POINT * (1.0 - VIEW_GUN_SCALE)
	else:
		model.position = look.get("view_offset", Vector3.ZERO)
	_view_model.add_child(model)
	# The first-person gun must not throw a shadow onto the floor in front
	# of you - it is not really there in the world.
	PaintKit.set_shadows(model, false)
	_muzzle = PaintKit.part(model, "Muzzle") as MeshInstance3D
	_skin_band = PaintKit.part(model, "SkinBand") as MeshInstance3D
	_gun_fill = PaintKit.part(model, "Fill")
	_gun_needle = PaintKit.part(model, "Needle")
	_gun_regulator = PaintKit.part(model, "Regulator")
	if _muzzle == null:
		# A model without a Muzzle part: fire from the old muzzle point.
		_muzzle = MeshInstance3D.new()
		_muzzle.position = MUZZLE_POINT
		_view_model.add_child(_muzzle)
	# The bristles (or nib, prism, bell...), the paint in the tank and the
	# drips all show the pair colour. They share ONE material, which
	# _apply_pair() repaints, so the existing "repaint the muzzle" code colours
	# all three at once.
	var pair_mat := StandardMaterial3D.new()
	pair_mat.roughness = 0.3
	pair_mat.emission_enabled = true
	pair_mat.emission_energy_multiplier = 0.5
	_muzzle.material_override = pair_mat
	for part_name in ["Fill", "PaintDrips"]:
		var painted := PaintKit.part(model, part_name) as GeometryInstance3D
		if painted != null:
			painted.material_override = pair_mat
	# The muzzle puff rides on the muzzle (local_coords), so it stays with the
	# gun as you turn instead of hanging in the air behind you.
	_muzzle_puff = PaintFx.make(Color.WHITE, 6, 1.6, 0.3, 0.16)
	_muzzle_puff.local_coords = true
	_muzzle_puff.direction = Vector3.FORWARD
	_muzzle_puff.spread = 28.0
	_muzzle_puff.gravity = Vector3.ZERO
	_muzzle.add_child(_muzzle_puff)
	_apply_menu_customization()
	if not pair.is_empty():
		_paint_muzzle()
	_view_model.visible = not power_invisible and not _spectating


## The original prototype gun: three boxes and a bristle cube. Only used if the
## generated model is missing.
func _build_box_gun() -> void:
	# The rifle body - a charcoal block, the GDD's "structural accent".
	_view_model.add_child(_make_box(
		Vector3(0.09, 0.1, 0.55), Vector3(0.0, 0.0, 0.0), Traits.CHARCOAL))
	# The handle, angled down and back.
	_view_model.add_child(_make_box(
		Vector3(0.07, 0.2, 0.09), Vector3(0.0, -0.13, 0.14), Traits.CHARCOAL))
	# A teal band, so the gun is not one flat slab of dark.
	_skin_band = _make_box(Vector3(0.1, 0.045, 0.12), Vector3(0.0, 0.035, -0.06), Traits.TEAL)
	_view_model.add_child(_skin_band)
	# The bristle head at the muzzle, repainted to the inherited pair's colour.
	_muzzle = _make_box(Vector3(0.12, 0.13, 0.16), Vector3(0.0, 0.0, -0.36), Traits.WHITE)
	var muzzle_mat: StandardMaterial3D = _muzzle.material_override
	muzzle_mat.emission_enabled = true
	muzzle_mat.emission = Traits.WHITE
	muzzle_mat.emission_energy_multiplier = 0.5
	_view_model.add_child(_muzzle)


func _apply_menu_customization() -> void:
	if customization.is_empty():
		return
	var gun_skin_index := int(customization.get("gun_skin", customization.get("GUN SKINS", 0)))
	# A gun model: the gun skin restyles the whole gun (body, trim, band,
	# grip). The bristles and tank keep showing your pair colour.
	if _gun != null:
		GunSkins.apply(_gun, gun_skin_index, false)
		return
	# Fallback box gun: only its band takes the skin colour.
	var palette := [Color("#FF6FAE"), Color("#63D9C7"), Color("#54C9E8"), Color("#F5C45E"), Color("#A78BFA"), Color("#F5F4F0"), Color("#FF867C"), Color("#79C991"), Color("#70BCEB"), Color("#C18B67")]
	# Found by name when the gun was built (it used to be "child number 2",
	# which silently broke as soon as the gun's parts changed).
	var band := _skin_band
	if band == null:
		return
	var gun_mat := band.material_override as StandardMaterial3D
	if gun_mat == null:
		gun_mat = StandardMaterial3D.new()
		gun_mat.roughness = 0.4
		band.material_override = gun_mat
	var gun_skin := int(customization.get("gun_skin", customization.get("GUN SKINS", 0)))
	gun_mat.albedo_color = palette[gun_skin % palette.size()]
	var material_path := CustomizationData.gun_material_path(gun_skin)
	if not material_path.is_empty() and ResourceLoader.exists(material_path):
		band.material_override = load(material_path) as Material


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


## A glowing ring over your head while you carry a power, in the power's
## colour. It sits above your own camera, out of your view; other players see
## the matching ring on their copy of you (remote_player.gd).
func _build_power_halo() -> void:
	_power_halo = MeshInstance3D.new()
	_power_halo.name = "PowerHalo"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.43
	_power_halo.mesh = torus
	_power_halo.position = Vector3(0.0, 2.28, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#FFE66D")
	material.emission_enabled = true
	material.emission = Color("#FFE66D")
	material.emission_energy_multiplier = 2.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_power_halo.material_override = material
	_power_halo.visible = false
	_power_halo.layers = OWN_HALO_LAYER
	add_child(_power_halo)


## _unhandled_input receives events that no UI element already consumed. Mouse
## motion is read here rather than in _process because motion arrives as
## discrete events - reading it on a timer would drop movement on slow frames
## and make the aim feel like it is skipping.
func _unhandled_input(event: InputEvent) -> void:
	if _dead or _paused:
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

	# Right mouse / left shoulder: the Invisibility power's on/off switch. The
	# server decides; it answers through set_network_power().
	if event.is_action_pressed("toggle_power") and current_power == "invisibility":
		NetworkSession.request_invisibility(not power_invisible)


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_tick_timers(delta)
	if not _paused:
		_look_with_controller(delta)
	_move(delta)
	if not _paused:
		_shoot(delta)
	_regenerate(delta)
	_animate_view_model(delta)


## Right-stick aiming for a controller (Rocklyn's online branch).
func _look_with_controller(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.2)
	if look.is_zero_approx():
		return
	rotate_y(-look.x * controller_look_speed * delta)
	_camera.rotation.x = clampf(
		_camera.rotation.x - look.y * controller_look_speed * delta,
		deg_to_rad(-89.0), deg_to_rad(89.0))
	# Feed a smaller version into the existing weapon sway so stick aiming has
	# the same sense of weight as mouse aiming.
	_sway += look * 18.0 * delta


func _tick_timers(delta: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_since_fired += delta
	_since_hurt += delta


func _move(delta: float) -> void:
	# Gravity, applied whenever we are not standing on something.
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and not _paused:
		velocity.y = _jump_velocity

	# Input.get_vector reads four actions and returns a direction of length at
	# most 1. Because it normalises, holding W and D together does NOT make you
	# move faster diagonally, which is a classic bug in hand-rolled movement.
	# While paused the keys are ignored, so you come to a stop where you are.
	var input_dir := Vector2.ZERO
	if not _paused:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

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
	# Invisibility hides you, and the price is that you cannot shoot.
	if power_invisible:
		return
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
	glob.speed = _projectile_speed
	glob.splash_radius = _splash_radius
	glob.splash_mult = _splash_mult
	glob.projectile_kind = _projectile_kind
	# A rocket's blast can hurt the one who fired it, up close.
	glob.allow_self_damage = _projectile_kind == "rocket"
	glob.color = _shot_color()
	# Who to tell when this glob lands a hit (the crosshair hit marker).
	# Nothing in the damage path reads this.
	glob.source_player = self
	if not tdm_team.is_empty():
		glob.configure_tdm(self, tdm_team)

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
	var shot_origin := _muzzle.global_position
	var shot_direction := (aim - shot_origin).normalized()
	glob.setup(shot_origin, shot_direction, true)
	if NetworkSession.is_in_match():
		NetworkSession.report_shot(shot_origin, shot_direction, {
			"damage": _damage,
			"speed": _projectile_speed,
			"splash_radius": _splash_radius,
			"splash_mult": _splash_mult,
			"projectile_kind": _projectile_kind,
			"color": glob.color,
		})

	_kick_view_model()
	if _muzzle_puff != null:
		_muzzle_puff.restart()
	stats_changed.emit()


## Your paint colour: the power's colour while you carry one, otherwise the
## inherited pair's.
func _shot_color() -> Color:
	if not current_power.is_empty():
		return Powers.color_for(current_power)
	return pair.get("color", Color.WHITE)


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

	var excluded: Array[RID] = []
	var hit: Dictionary = {}
	while true:
		query.exclude = excluded
		hit = space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider = hit["collider"]
		if (not tdm_team.is_empty() and collider.is_in_group("tdm_combatants")
				and str(collider.get("tdm_team")) == tdm_team):
			excluded.append(collider.get_rid())
			continue
		break
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
	if not NetworkSession.is_in_match() and _regen > 0.0 and _since_hurt >= _regen_delay and health < max_health:
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
	_animate_gun_parts(delta)


## The Paint Blaster's tank is a second paint gauge: the paint inside drains
## toward the back of the tank as `ammo` falls, and the pressure needle follows.
## The brass regulator spins while the reservoir refills. All of this only READS
## ammo and the refill timer; nothing here changes how the gun behaves.
func _animate_gun_parts(delta: float) -> void:
	if _gun_fill == null:
		return
	var fraction: float = clampf(ammo / maxf(_max_ammo, 1.0), 0.0, 1.0)
	var smoothing := clampf(delta * 12.0, 0.0, 1.0)
	# The Fill part's origin is the back of the tank and it extends forward
	# along -Z, so scaling Z shortens the paint toward the back. Never exactly
	# zero - a zero scale makes the node's transform degenerate.
	_gun_fill.scale.z = lerpf(_gun_fill.scale.z, maxf(fraction, 0.02), smoothing)
	if _gun_needle != null:
		_gun_needle.rotation.x = lerp_angle(_gun_needle.rotation.x, lerpf(1.1, -1.1, fraction), smoothing)
	if _gun_regulator != null and _since_fired >= ammo_regen_delay and ammo < _max_ammo:
		_gun_regulator.rotate_z(delta * 7.0)


## A short recoil shove, run on every shot. Animating the gun rather than the
## camera means recoil is felt but never fights the player for their aim.
func _kick_view_model() -> void:
	_view_model.position.z += 0.05
	_view_model.position.y -= 0.012
	# The bristles squash a little on each shot. Scaling the Muzzle node does
	# not move its origin, so the glob spawn point is unaffected.
	if _muzzle != null and _gun_fill != null:
		_muzzle.scale = Vector3(1.12, 1.12, 0.8)
		var tween := create_tween()
		tween.tween_property(_muzzle, "scale", Vector3.ONE, 0.12)


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
	_projectile_speed = projectile_speed

	# Never leave the reservoir holding more than it can now carry - inheriting
	# Faded Pigment must actually cut you down to the smaller tank.
	ammo = minf(ammo, _max_ammo)

	_paint_muzzle()


## Repaints the brush head (and the paint in the tank) to your paint colour:
## the power's while you carry one, otherwise the pair's.
func _paint_muzzle() -> void:
	var paint := _shot_color()
	if _muzzle != null:
		var mat = _muzzle.material_override
		if mat is StandardMaterial3D:
			mat.albedo_color = paint
			mat.emission = paint
	if _muzzle_puff != null:
		_muzzle_puff.color = paint


# ============================================================================
# POWERS (online)
# ============================================================================

## Called by the match controller when the server gives you a power, takes it
## away, or turns your invisibility on or off.
func set_network_power(power_id: String, invisible: bool) -> void:
	current_power = power_id if Powers.is_valid(power_id) else ""
	power_invisible = invisible and current_power == "invisibility"
	_apply_power()
	power_changed.emit(current_power, power_invisible)
	stats_changed.emit()


## Rebuilds your gun and movement for the current power.
func _apply_power() -> void:
	# Begin from the ordinary online weapon and movement tuning every time so a
	# swapped or traded power cannot leave stale modifiers behind.
	_speed = base_speed
	_damage = Powers.BASE_DAMAGE
	_fire_interval = base_fire_interval
	_projectile_speed = projectile_speed
	_projectile_kind = "bullet"
	_splash_radius = 0.0
	_splash_mult = 0.0
	var power := Powers.get_power(current_power)
	if not power.is_empty():
		_speed = base_speed * float(power.get("move_mult", 1.0))
		_damage = float(power.get("damage", Powers.BASE_DAMAGE))
		_fire_interval = float(power.get("fire_interval", base_fire_interval))
		_projectile_speed = float(power.get("projectile_speed", projectile_speed))
		_projectile_kind = str(power.get("projectile_kind", "bullet"))
		_splash_radius = float(power.get("splash_radius", 0.0))
		_splash_mult = float(power.get("splash_mult", 0.0))
	if is_instance_valid(_power_halo):
		_power_halo.visible = not current_power.is_empty() and not power_invisible
		var halo_material := _power_halo.material_override as StandardMaterial3D
		var halo_color := Powers.color_for(current_power)
		halo_material.albedo_color = halo_color
		halo_material.emission = halo_color
	# The gun in your hands shows the power (scripts/weapons.gd). Rebuilt only
	# when the model actually changes.
	if _view_model != null and str(Weapons.for_power(current_power).model) != _gun_model_name:
		_build_gun()
	if is_instance_valid(_view_model):
		_view_model.visible = not power_invisible and not _spectating
	_paint_muzzle()


func has_current_power() -> bool:
	return not current_power.is_empty()


func get_current_power_type() -> String:
	return current_power


func can_trade_power_at_station() -> bool:
	return has_current_power() and not _dead


func try_consume_power_for_station() -> bool:
	if NetworkSession.is_in_match() or not can_trade_power_at_station():
		return false
	set_network_power("", false)
	return true


# ============================================================================
# PAUSE
# ============================================================================

## Called by the pause menu (scripts/ui/pause_menu.gd). Frees the mouse and
## ignores your inputs while paused; recaptures the mouse on resume.
func set_paused(on: bool) -> void:
	_paused = on
	if on:
		Input.action_release("fire")
		_set_mouse_captured(false)
	elif not _dead:
		_set_mouse_captured(true)


func is_paused() -> bool:
	return _paused


# ============================================================================
# DAMAGE
# ============================================================================

## Called by enemy paint and by charging Bounders. The weakness multiplier is
## applied HERE, in one place, so no attack anywhere in the game can bypass
## Thick Coat or dodge Brittle Canvas.
func take_damage(amount: float, attacker = null) -> void:
	if _dead:
		return
	# Online, the server owns health: other players' hits arrive through
	# apply_network_vitals(). The only damage this client reports itself is a
	# rocket's blast hitting the one who fired it.
	if NetworkSession.is_in_match():
		if attacker == self:
			NetworkSession.report_self_damage(amount)
		return
	if not tdm_team.is_empty() and is_instance_valid(tdm_manager):
		tdm_manager.record_damage(attacker, self)

	# Shield soaks damage first; what is left comes off health.
	var applied := amount * _taken_mult
	var absorbed := minf(shield, applied)
	shield -= absorbed
	health -= applied - absorbed
	_since_hurt = 0.0

	hurt.emit()
	stats_changed.emit()

	if health <= 0.0:
		health = 0.0
		_dead = true
		_set_mouse_captured(false)
		died.emit()


## Called by one of this player's globs when it damages something. Only
## announces it (for the HUD); see hit_confirmed above.
func confirm_hit() -> void:
	hit_confirmed.emit()


func tdm_respawn(at: Vector3) -> void:
	stop_spectating()
	_dead = false
	health = max_health
	shield = max_shield
	global_position = at
	velocity = Vector3.ZERO
	stats_changed.emit()
	# Stay un-captured if the pause menu is open; resuming captures it.
	if not _paused:
		_set_mouse_captured(true)


## Dead and watching someone: the match controller's spectator camera draws
## the view (scripts/spectator_camera.gd). This parks the body - no collision,
## no gun on screen, mouse free for the death screen's buttons.
func start_spectating() -> void:
	_spectating = true
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(_view_model):
		_view_model.visible = false
	_set_mouse_captured(false)


func stop_spectating() -> void:
	_spectating = false
	collision_layer = 2
	collision_mask = 1 | 4
	if is_instance_valid(_view_model):
		_view_model.visible = not power_invisible
	if is_instance_valid(_camera):
		_camera.position = _camera_home
		_camera.current = true


func is_spectating() -> bool:
	return _spectating


func apply_network_health(next_health: float) -> void:
	apply_network_vitals(next_health, shield)


## Health and shield from the server.
func apply_network_vitals(next_health: float, next_shield: float) -> void:
	var was_higher := next_health < health or next_shield < shield
	health = clampf(next_health, 0.0, max_health)
	shield = clampf(next_shield, 0.0, max_shield)
	if was_higher:
		_since_hurt = 0.0
		hurt.emit()
	stats_changed.emit()
	if health <= 0.0 and not _dead:
		_dead = true
		_set_mouse_captured(false)
		died.emit()


func network_pitch() -> float:
	return _camera.rotation.x if is_instance_valid(_camera) else 0.0


## Called by game.gd between waves.
func heal(amount: float) -> void:
	health = minf(max_health, health + amount)
	stats_changed.emit()


## A trade station's reward: full health and shield.
func restore_full_vitals() -> void:
	health = max_health
	shield = max_shield
	stats_changed.emit()


## Read by the HUD so it can size the paint bar correctly for the current pair.
func get_max_ammo() -> float:
	return _max_ammo


func is_dead() -> bool:
	return _dead
