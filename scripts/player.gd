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
## base_jump_velocity... and the gun's row in weapons.gd) never change - they
## are the tuning knobs for the whole game.
## The LIVE numbers (_speed, _damage...) are recalculated from the base numbers
## times the current pair's multipliers every time a pair is inherited, inside
## _apply_pair(). Nothing else in the file ever touches a multiplier. That means
## adding a new ability later is a change in traits.gd plus one line here, and
## it is impossible for a stale buff to linger after a swap - the live numbers
## are rebuilt from scratch, not adjusted.
##
## THE GUN
## Which gun you carry is `weapon_index` into scripts/weapons.gd (Brush Rifle,
## Fine Liner, Prism Beam, Splat Bucket, Blob Lobber). The gun's own numbers -
## damage, fire interval, tank size, refill - come from that table, and the
## pair multiplies them in _apply_pair() exactly as it multiplied the old
## single gun's numbers. The Brush Rifle row holds the values that used to be
## the base_damage / base_fire_interval / base_max_ammo... exports here.

const Traits = preload("res://scripts/traits.gd")
const Projectile = preload("res://scripts/projectile.gd")
const CustomizationData = preload("res://scripts/character_customization_data.gd")
const PaintKit = preload("res://scripts/visual/paint_kit.gd")
const PaintFx = preload("res://scripts/visual/paint_fx.gd")
const ShaderWarmup = preload("res://scripts/visual/shader_warmup.gd")
const GunSkins = preload("res://scripts/visual/gun_skins.gd")
const Weapons = preload("res://scripts/weapons.gd")


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

## Fired when a different gun is equipped (TDM loadouts), for the HUD.
signal weapon_changed(weapon: Dictionary)

## Fired when you start or stop zooming (Fine Liner), for the scope overlay.
signal zoom_changed(zoomed: bool)


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

# The gun's numbers (damage, fire interval, tank size, refill rate and delay,
# shot speed) live in scripts/weapons.gd, one row per gun. The refill delay is
# what stops a gun being a bottomless hose: hold the trigger and you run dry,
# and you have to break contact for a moment to get going again.

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
var _ammo_delay: float
var _projectile_speed: float


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

## Seconds since the last shot, compared against the gun's refill delay.
var _since_fired: float = 999.0

## Seconds since last taking damage, compared against the Ghost pair's delay.
var _since_hurt: float = 999.0

## Set true on death so input and shooting stop immediately.
var _dead: bool = false

## Which gun you carry: an index into scripts/weapons.gd. Set it before the
## player enters the scene, or call set_weapon() later (TDM respawns).
var weapon_index: int = Weapons.BRUSH_RIFLE
## That gun's row from the table.
var _weapon: Dictionary = {}

## Prism Beam only: true after the charge ran dry, until it is full again.
var _overheated: bool = false

## Fine Liner only: true while right mouse is held to look down the scope.
var _zoomed: bool = false

## Counts shots, so the Prism Beam can step through the rainbow.
var _shot_count: int = 0

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

## The normal field of view (the GDD's wide 105 degrees). The Fine Liner's
## scope narrows it while you hold right mouse.
const BASE_FOV := 105.0

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

	_weapon = Weapons.get_weapon(weapon_index)
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
	_camera.fov = BASE_FOV
	# current = true makes this the camera the game actually renders from.
	_camera.current = true
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

	var model := PaintKit.instance(str(_weapon.get("model", "paint_blaster")))
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
		model.position = _weapon.get("view_offset", Vector3.ZERO)
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


## _unhandled_input receives events that no UI element already consumed. Mouse
## motion is read here rather than in _process because motion arrives as
## discrete events - reading it on a timer would drop movement on slow frames
## and make the aim feel like it is skipping.
func _unhandled_input(event: InputEvent) -> void:
	if _dead or _paused:
		return

	if event is InputEventMouseMotion and _mouse_captured:
		var motion: InputEventMouseMotion = event
		# Looking through the Fine Liner's scope turns slower, in step with the
		# zoom, so aiming feels the same at any magnification.
		var turn_scale: float = _camera.fov / BASE_FOV

		# Turning left/right rotates the whole BODY, so that "forward" for
		# movement always means the way you are facing.
		rotate_y(-motion.relative.x * mouse_sensitivity * turn_scale)

		# Looking up/down rotates only the CAMERA. If it rotated the body the
		# player would tip over and walk into the floor.
		_camera.rotate_x(-motion.relative.y * mouse_sensitivity * turn_scale)
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
	if not _paused:
		_update_zoom(delta)
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
	var cost := float(_weapon.cost)
	if _overheated:
		return
	if ammo < cost:
		# An energy gun that runs dry overheats: it locks until the charge is
		# completely full again (see _regenerate). A paint gun just waits.
		if bool(_weapon.overheat):
			_overheated = true
			stats_changed.emit()
		return

	ammo -= cost
	_fire_cooldown = _fire_interval
	_since_fired = 0.0
	_shot_count += 1

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
	# Spread: a random wobble inside a small cone. The Fine Liner is perfectly
	# accurate only while zoomed.
	var pellets := int(_weapon.pellets)
	var wobble := float(_weapon.zoom_spread) if _zoomed else float(_weapon.spread)
	if pellets == 1:
		shot_direction = Weapons.spread_direction(shot_direction, wobble)
	var shot_color: Color = pair["color"]
	if bool(_weapon.rainbow):
		shot_color = Weapons.rainbow_color(_shot_count)
	for i in pellets:
		# The Splat Bucket throws several droplets at once, each with its own
		# wobble; every other gun fires exactly one shot along shot_direction.
		var direction := shot_direction if pellets == 1 else Weapons.spread_direction(shot_direction, wobble)
		_spawn_shot(shot_origin, direction, shot_color)
	if NetworkSession.is_in_match():
		NetworkSession.report_shot(shot_origin, shot_direction, {
			"damage": _damage,
			"speed": _projectile_speed,
			"splash_radius": _splash_radius,
			"splash_mult": _splash_mult,
			"color": shot_color,
			"weapon": weapon_index,
		})

	_kick_view_model()
	if _muzzle_puff != null:
		_muzzle_puff.color = shot_color
		_muzzle_puff.restart()
	stats_changed.emit()


## Creates one glob and sends it on its way.
func _spawn_shot(origin: Vector3, direction: Vector3, shot_color: Color) -> void:
	var glob = Node3D.new()
	glob.set_script(Projectile)
	glob.damage = _damage
	glob.speed = _projectile_speed
	glob.splash_radius = _splash_radius
	glob.splash_mult = _splash_mult
	glob.color = shot_color
	# Range, arc and bullet size for this gun.
	Weapons.apply_to_shot(glob, _weapon)
	# Who to tell when this glob lands a hit (the crosshair hit marker).
	# Nothing in the damage path reads this.
	glob.source_player = self
	if not tdm_team.is_empty():
		glob.configure_tdm(self, tdm_team)

	# Add the glob to the level, NOT to the player. A child node moves with its
	# parent, so a glob parented to the player would be dragged along behind you
	# forever instead of flying away on its own.
	get_parent().add_child(glob)
	glob.setup(origin, direction, true)


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
	if _since_fired >= _ammo_delay and ammo < _max_ammo:
		ammo = minf(_max_ammo, ammo + _ammo_regen * delta)
		stats_changed.emit()
	# An overheated Prism Beam unlocks only once the charge is full again.
	if _overheated and ammo >= _max_ammo:
		_overheated = false
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
	if _gun_regulator != null and _since_fired >= _ammo_delay and ammo < _max_ammo:
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
	_fire_interval = float(_weapon.interval) / float(pair["fire_rate_mult"])

	_damage = float(_weapon.damage) * float(pair["damage_mult"])
	_speed = base_speed * float(pair["move_mult"])
	_jump_velocity = base_jump_velocity * float(pair["jump_mult"])
	_taken_mult = float(pair["taken_mult"])
	# Splash comes from the pair (Splatter Rounds) or the gun (the Blob
	# Lobber's burst) - whichever is bigger, never both added together.
	_splash_radius = maxf(float(pair["splash_radius"]), float(_weapon.splash_radius))
	_splash_mult = maxf(float(pair["splash_mult"]), float(_weapon.splash_mult))
	_regen = float(pair["regen"])
	_regen_delay = float(pair["regen_delay"])
	_max_ammo = float(_weapon.ammo) * float(pair["ammo_mult"])
	_ammo_regen = float(_weapon.regen) * float(pair["ammo_regen_mult"])
	_ammo_delay = float(_weapon.regen_delay)
	_projectile_speed = float(_weapon.speed)

	# Never leave the reservoir holding more than it can now carry - inheriting
	# Faded Pigment must actually cut you down to the smaller tank.
	ammo = minf(ammo, _max_ammo)

	_paint_muzzle()


## Repaints the brush head (and the paint in the tank) to the pair's colour.
func _paint_muzzle() -> void:
	if _muzzle != null:
		var mat = _muzzle.material_override
		if mat is StandardMaterial3D:
			mat.albedo_color = pair["color"]
			mat.emission = pair["color"]
	if _muzzle_puff != null:
		_muzzle_puff.color = pair["color"]


# ============================================================================
# THE GUN
# ============================================================================

## Equips a different gun (TDM: the loadout picked while waiting to respawn).
## The tank starts full, and every live number is rebuilt from the new gun
## and the pair you carry.
func set_weapon(index: int) -> void:
	weapon_index = posmod(index, Weapons.count())
	_weapon = Weapons.get_weapon(weapon_index)
	_overheated = false
	_set_zoom(false)
	_apply_pair(pair_id)
	ammo = _max_ammo
	_fire_cooldown = 0.0
	if _view_model != null:
		_build_gun()
	weapon_changed.emit(_weapon)
	stats_changed.emit()


func get_weapon() -> Dictionary:
	return _weapon


func is_overheated() -> bool:
	return _overheated


func is_zoomed() -> bool:
	return _zoomed


## Fine Liner only: hold right mouse to zoom. Eases the field of view toward
## the scope's and back, so the zoom slides rather than snaps.
func _update_zoom(delta: float) -> void:
	var can_zoom := float(_weapon.zoom_fov) > 0.0 and _mouse_captured
	_set_zoom(can_zoom and InputMap.has_action("aim") and Input.is_action_pressed("aim"))
	var target := float(_weapon.zoom_fov) if _zoomed else BASE_FOV
	_camera.fov = lerpf(_camera.fov, target, clampf(delta * 14.0, 0.0, 1.0))


func _set_zoom(on: bool) -> void:
	if on == _zoomed:
		return
	_zoomed = on
	# The scope overlay takes over the screen, so hide the gun while zoomed.
	if _view_model != null:
		_view_model.visible = not on
	if not on and _camera != null:
		_camera.fov = BASE_FOV if _dead or _paused else _camera.fov
	zoom_changed.emit(on)


# ============================================================================
# PAUSE
# ============================================================================

## Called by the pause menu (scripts/ui/pause_menu.gd). Frees the mouse and
## ignores your inputs while paused; recaptures the mouse on resume.
func set_paused(on: bool) -> void:
	_paused = on
	if on:
		_set_zoom(false)
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
	if not tdm_team.is_empty() and is_instance_valid(tdm_manager):
		tdm_manager.record_damage(attacker, self)

	health -= amount * _taken_mult
	_since_hurt = 0.0

	hurt.emit()
	stats_changed.emit()

	if health <= 0.0:
		health = 0.0
		_dead = true
		_set_zoom(false)
		_set_mouse_captured(false)
		died.emit()


## Called by one of this player's globs when it damages something. Only
## announces it (for the HUD); see hit_confirmed above.
func confirm_hit() -> void:
	hit_confirmed.emit()


func tdm_respawn(at: Vector3) -> void:
	_dead = false
	health = max_health
	global_position = at
	velocity = Vector3.ZERO
	ammo = _max_ammo
	_overheated = false
	_camera.fov = BASE_FOV
	_camera.current = true
	stats_changed.emit()
	# Stay un-captured if the pause menu is open; resuming captures it.
	if not _paused:
		_set_mouse_captured(true)


func apply_network_health(next_health: float) -> void:
	var was_higher := next_health < health
	health = clampf(next_health, 0.0, max_health)
	if was_higher:
		_since_hurt = 0.0
		hurt.emit()
	stats_changed.emit()
	if health <= 0.0 and not _dead:
		_dead = true
		_set_zoom(false)
		_set_mouse_captured(false)
		died.emit()


func network_pitch() -> float:
	return _camera.rotation.x if is_instance_valid(_camera) else 0.0


## Called by game.gd between waves.
func heal(amount: float) -> void:
	health = minf(max_health, health + amount)
	stats_changed.emit()


## Read by the HUD so it can size the paint bar correctly for the current pair.
func get_max_ammo() -> float:
	return _max_ammo


func is_dead() -> bool:
	return _dead
