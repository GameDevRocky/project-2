extends Node3D

## ============================================================================
## GAME - the orchestrator. This is the Game Logic system.
## ============================================================================
##
## It owns everything that is true about the RUN rather than about any one
## object: which wave you are on, what is left alive, when you have won or lost,
## and whether there is a pair on the floor you are close enough to take.
##
## WHY ALL OF THAT IS IN ONE PLACE
## Each of those questions needs to see more than one object at once. "Is the
## wave over" is not something an enemy can answer, because an enemy only knows
## about itself. "Can I inherit right now" is not something a core can answer,
## because two cores could both be in range and only one can be the offer. Give
## those decisions to the objects and they end up voting on the answer, which is
## where the genuinely nasty bugs in a game like this come from. So the objects
## stay dumb and this script does the deciding.
##
## HOW THE SEAMS RUN
## The GDD names two seams. Both cross here, and both cross in one direction
## only, on purpose:
##
##   Game logic -> UX     This script calls into the HUD (set_wave, announce,
##                        set_offer). The HUD never calls back into here.
##   Game logic -> world  This script spawns and configures the player, arena
##                        and enemies. They report back only by SIGNAL - the
##                        enemy's died, the player's died - never by reaching
##                        into this script and changing something.
##
## Multiplayer, which the GDD lists as the seam most likely to break first, is
## Cut #1 - it is not in this build. The place it would attach is marked further
## down, in _spawn_enemy().

const Traits = preload("res://scripts/traits.gd")
const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const ArenaScript = preload("res://scripts/arena.gd")
const HudScript = preload("res://scripts/hud.gd")


## The whole difficulty curve, as one readable table.
##
## The shape of it is deliberate. Wave 1 is a single archetype so your first
## inheritance is an easy read. Each later wave introduces at most one new type,
## so you always have a wave to learn it in before it starts appearing in a mix.
## The Monolith - the one enemy you really want a specific pair for - does not
## show up until wave 4, by which point you have had three chances to pick up
## something that handles it.
const WAVES := [
	{"sprayer": 3},
	{"sprayer": 3, "bounder": 2},
	{"bounder": 2, "blotter": 3},
	{"sprayer": 3, "bounder": 2, "monolith": 1},
	{"ghost": 3, "blotter": 2, "bounder": 2},
	{"monolith": 2, "ghost": 3, "sprayer": 3, "bounder": 2},
]

## How much tougher enemies get per wave. At wave 6 this is 1.30, so a Sprayer
## has 58 health instead of 45. Kept gentle on purpose: the difficulty in this
## game is supposed to come from the MIX of enemies and from the pair you are
## carrying, not from bullet-sponge scaling, which just makes fights longer
## rather than more interesting.
const HEALTH_SCALE_PER_WAVE := 0.06

## Health handed back after clearing a wave. Not a full heal - a run should
## accumulate pressure - but enough that one bad wave does not doom the rest.
const HEAL_BETWEEN_WAVES := 40.0

## Seconds of quiet after a wave is cleared. This is the window where you decide
## which core to take, so it has to be long enough to actually cross the arena
## and short enough to still feel like a breather rather than a shopping trip.
const BREATHER := 5.0

## Seconds between individual enemies appearing. Spawning a whole wave on one
## frame is what turns a hard wave into an unfair one.
const SPAWN_STAGGER := 0.35


var _arena: Node3D
var _player = null
var _hud: CanvasLayer

var _wave_index: int = 0
var _alive: int = 0
var _spawning: bool = false
var _run_over: bool = false

## The core currently being offered, or null. Recalculated every frame in
## _update_offer().
var _offered_core = null

## Set by the --verbose or --autoplay command-line flags. When on, the run
## prints what it is doing to the console, which is the only way to see what a
## headless test run actually did.
var _verbose: bool = false


func _ready() -> void:
	# Seed the random number generator differently each launch, so strafe
	# directions and spawn angles are not identical every run.
	randomize()

	# get_cmdline_user_args() returns only the arguments after a bare "--", so
	# these cannot be confused with the engine's own flags.
	var flags: PackedStringArray = OS.get_cmdline_user_args()
	_verbose = flags.has("--verbose") or flags.has("--autoplay")

	_ensure_input_actions()

	_build_arena()
	_build_player()
	_build_hud()

	# Wait one frame before starting. _ready() runs while nodes are still being
	# added to the tree, and the enemies about to spawn need to be able to find
	# the player by group - which only works once the player is fully in.
	# await pauses this function and resumes it when the signal fires.
	await get_tree().process_frame

	# Development only: a fake player, so a headless run can exercise shooting,
	# killing and inheriting instead of just standing still. Never created in a
	# normal play session - see tools/autoplay.gd.
	if flags.has("--autoplay"):
		var harness := Node.new()
		harness.set_script(load("res://tools/autoplay.gd"))
		add_child(harness)

	_log("run started")
	_player.pair_inherited.connect(func(pair): _log("inherited %s" % pair["name"]))

	_hud.announce("PROJECT 2", "Hunt. Inherit. Overwrite.")
	await get_tree().create_timer(2.2).timeout

	_start_wave()


## Prints only when a verbose flag was passed, so a normal run stays silent.
func _log(message: String) -> void:
	if _verbose:
		print("[game] %s" % message)


# ============================================================================
# SETUP
# ============================================================================

## Registers the keys the game uses, at runtime, if they are not already set up
## in Project Settings.
##
## WHY DO THIS IN CODE
## Input actions normally live in Project > Project Settings > Input Map. The
## problem with relying on that alone is that the settings live in project.godot
## - so if a teammate pulls this branch and that file merges badly, the game
## launches with no controls at all and the cause is not remotely obvious. Doing
## it here means the game is playable from a fresh clone with no setup, and the
## has_action() guard means anything already configured in the editor still wins.
func _ensure_input_actions() -> void:
	# Each entry is an action name and the physical key that triggers it.
	# PHYSICAL keycodes are used rather than plain ones: a physical keycode is
	# the key's POSITION on the board, so WASD stays as the same four keys under
	# your fingers on an AZERTY or Dvorak layout instead of scattering.
	var keys := {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
		"interact": KEY_E,
		"restart": KEY_R,
	}

	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action, event)

	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", click)


func _build_arena() -> void:
	_arena = Node3D.new()
	_arena.set_script(ArenaScript)
	_arena.name = "Arena"
	add_child(_arena)


func _build_player() -> void:
	_player = CharacterBody3D.new()
	_player.set_script(PlayerScript)
	_player.name = "Player"
	add_child(_player)
	# Start on the centre platform, which is 0.8m tall - so spawn just above it.
	_player.global_position = Vector3(0.0, 1.2, 0.0)

	# Listen for the player's death. A signal connection is how this script
	# finds out without having to check the player's health every frame.
	_player.died.connect(_on_player_died)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.set_script(HudScript)
	_hud.name = "HUD"
	add_child(_hud)
	_hud.bind_player(_player)
	_hud.set_wave(1, WAVES.size())


# ============================================================================
# WAVES
# ============================================================================

func _start_wave() -> void:
	if _run_over:
		return

	var wave_number: int = _wave_index + 1
	_hud.set_wave(wave_number, WAVES.size())
	_hud.announce("WAVE %d" % wave_number, _describe_wave(WAVES[_wave_index]))
	_log("wave %d starting: %s" % [wave_number, _describe_wave(WAVES[_wave_index])])

	_spawn_wave(WAVES[_wave_index])


## Turns a wave's contents into a readable line for the banner, so you know what
## is coming before it arrives rather than having to work it out under fire.
func _describe_wave(wave: Dictionary) -> String:
	var parts: Array = []
	for type_id in wave:
		var count: int = wave[type_id]
		var type_name: String = str(EnemyScript.TYPES[type_id]["name"])
		if count > 1:
			# A crude plural, but every name in this game takes a plain "s".
			parts.append("%d %ss" % [count, type_name])
		else:
			parts.append("1 %s" % type_name)
	return "  ·  ".join(parts)


## Spawns a wave one enemy at a time, with a short pause between each.
## This function is `async` in effect - the awaits inside it mean it returns to
## the caller immediately and finishes in the background over the next second or
## two, which is exactly what we want.
func _spawn_wave(wave: Dictionary) -> void:
	_spawning = true

	# Count the whole wave up front, BEFORE any of it spawns. If we counted as
	# we went, the first enemy could be killed before the last one existed, the
	# alive count would touch zero, and the wave would be declared clear while
	# half of it was still queued to appear.
	for type_id in wave:
		_alive += int(wave[type_id])
	_hud.set_enemies_left(_alive)

	for type_id in wave:
		for i in int(wave[type_id]):
			# The scene can be torn down mid-spawn if the player dies, so check
			# we are still valid before touching anything.
			if _run_over or not is_instance_valid(self):
				_spawning = false
				return
			_spawn_enemy(type_id)
			await get_tree().create_timer(SPAWN_STAGGER).timeout

	_spawning = false


func _spawn_enemy(type_id: String) -> void:
	var enemy = CharacterBody3D.new()
	enemy.set_script(EnemyScript)
	# setup() must be called BEFORE add_child, because add_child triggers the
	# enemy's _ready(), which builds its body from the stats setup() chose.
	enemy.setup(type_id, 1.0 + HEALTH_SCALE_PER_WAVE * float(_wave_index))

	# ------------------------------------------------------------------------
	# MULTIPLAYER SEAM (Cut #1 - not in this build).
	# This is where an online version would diverge: the server would decide the
	# spawn and broadcast it, rather than every client rolling its own. Enemy
	# spawning is deliberately the ONLY place in this script that invents new
	# world state, so that when multiplayer is added there is exactly one
	# function to make authoritative rather than a hunt through the whole file.
	# ------------------------------------------------------------------------
	add_child(enemy)
	enemy.global_position = _pick_spawn_point()

	enemy.died.connect(_on_enemy_died)


## Finds somewhere on the outer ring to drop an enemy that is not right on top
## of the player. Being spawned on top of is the single cheapest-feeling way to
## lose health in a wave game, so it is worth a few tries to avoid.
func _pick_spawn_point() -> Vector3:
	var player_position: Vector3 = Vector3.ZERO
	if _player != null and is_instance_valid(_player):
		player_position = _player.global_position

	var radius: float = 19.0

	# Try several random spots and take the first one far enough away.
	for attempt in 12:
		var angle: float = randf() * TAU
		var candidate := Vector3(sin(angle) * radius, 0.6, cos(angle) * radius)
		if candidate.distance_to(player_position) > 13.0:
			return candidate

	# If twelve tries all failed - which needs the player to be standing in a
	# very odd spot - fall back to the point directly opposite them. Always
	# returning SOMETHING matters more than returning the perfect spot: a spawn
	# function that can fail is a wave that can hang forever.
	var away: Vector3 = -player_position.normalized() * radius
	return Vector3(away.x, 0.6, away.z)


## Runs when any enemy dies, via the signal each one is connected to on spawn.
func _on_enemy_died(_at: Vector3) -> void:
	_alive -= 1
	_hud.set_enemies_left(maxi(_alive, 0))
	_log("enemy down - %d left, player at %.0f health, %.0f paint" % [
		maxi(_alive, 0), float(_player.health), float(_player.ammo)])

	if _run_over:
		return
	# Do not declare the wave clear while more of it is still queued to appear.
	if _spawning:
		return
	if _alive > 0:
		return

	_on_wave_cleared()


func _on_wave_cleared() -> void:
	_log("wave %d cleared, player health %.0f, carrying %s" % [
		_wave_index + 1, float(_player.health), _player.pair["name"]])
	_wave_index += 1

	# Was that the last wave?
	if _wave_index >= WAVES.size():
		_win()
		return

	if _player != null and is_instance_valid(_player):
		_player.heal(HEAL_BETWEEN_WAVES)

	_hud.announce("WAVE CLEAR", "+%d health  ·  next wave in %ds" % [
		int(HEAL_BETWEEN_WAVES), int(BREATHER)])

	await get_tree().create_timer(BREATHER).timeout

	if _run_over:
		return
	_start_wave()


# ============================================================================
# THE INHERIT OFFER
# ============================================================================

func _process(_delta: float) -> void:
	if _run_over:
		# Allow a restart from the end screen.
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
		return

	_update_offer()


## Works out which core - if any - the player is standing close enough to take,
## and tells the HUD to offer it.
##
## Deciding this here rather than inside each core is what guarantees only ONE
## offer can ever be on screen. If two cores overlap, the nearer one wins,
## every frame, with no argument.
func _update_offer() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var player_position: Vector3 = _player.global_position

	var nearest = null
	var nearest_distance: float = 1e9

	for node in get_tree().get_nodes_in_group("cores"):
		# Untyped, because distance_to_player() and get_pair() are functions
		# this project added rather than engine built-ins.
		var core = node
		var distance: float = core.distance_to_player(player_position)
		if distance > core.pickup_range:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = core

	_offered_core = nearest

	if nearest == null:
		_hud.set_offer({}, false)
		return

	var pair: Dictionary = nearest.get_pair()
	var already_held: bool = (str(_player.pair_id) == str(nearest.pair_id))
	_hud.set_offer(pair, already_held)

	if already_held:
		return

	if Input.is_action_just_pressed("interact"):
		nearest.collect(_player)
		_offered_core = null
		_hud.set_offer({}, false)


# ============================================================================
# ENDINGS
# ============================================================================

func _on_player_died() -> void:
	if _run_over:
		return
	_run_over = true

	var reached: int = _wave_index + 1
	_log("player died on wave %d carrying %s" % [reached, _player.pair["name"]])
	_hud.show_ending(
		"PAINTED OVER",
		"You fell on wave %d of %d, carrying the %s.\n\nPress R to start a new run." % [
			reached, WAVES.size(), _player.pair["name"]],
		Color("#FF6B81"))


func _win() -> void:
	_run_over = true
	_log("run won, finished with %s at %.0f health" % [
		_player.pair["name"], float(_player.health)])

	# Stop everything still in flight, so the victory screen is not interrupted
	# by a glob that was already on its way.
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_hud.show_ending(
		"CANVAS CLEAN",
		"All %d waves cleared, finishing with the %s.\n\nPress R to run it again." % [
			WAVES.size(), _player.pair["name"]],
		Color("#00A896"))
