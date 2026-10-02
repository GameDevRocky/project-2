extends SceneTree

## ============================================================================
## WEAPONS CHECKLIST - a development tool, not part of the game.
## ============================================================================
##
## Builds a bare test room (a floor, the real player, and a practice dummy in
## the "enemies" group), gives the player each of Rocklyn's powers in turn
## (scripts/power_abilities.gd) and fires the REAL fire button at the dummy,
## printing PASS/FAIL per check: the gun MODEL in your hands for that power
## (scripts/weapons.gd) and what the power does to your shots.
##
##   godot --headless --path . --script res://tools/tests/weapons_checklist.gd
##
## Add `-- --shots=DIR` (and drop --headless) to build the real arena instead
## of the bare room, dress the dummy as a Canvas Runner, and save a first-person
## screenshot of every gun into DIR.
##
## No server: the player is not in an online match, so it fires exactly as it
## would online but does not report shots anywhere, and set_network_power()
## stands in for the server handing out a power.

const Weapons = preload("res://scripts/weapons.gd")
const Powers = preload("res://scripts/power_abilities.gd")
const RunnerDresser = preload("res://scripts/visual/runner_dresser.gd")

var _passed := 0
var _failed := 0
var _world: Node3D
var _player
var _dummy: CharacterBody3D
var _shots_dir := ""
var _hits_confirmed := 0
## Where the player stands, and which way "ahead" is. The bare room uses the
## world origin; the arena uses the RED spawn side, looking at the middle.
var _origin := Vector3(0, 0.05, 0)
var _ahead := Vector3(0, 0, -1)


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
	# A watchdog: if a script error stops _run part-way, quit anyway instead of
	# leaving a headless Godot running forever.
	create_timer(150.0).timeout.connect(func():
		print("[weapons] TIMEOUT - the run stopped early (look for a SCRIPT ERROR above)")
		quit(2))
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[weapons] %s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _actions() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "interact",
			"restart", "fire", "toggle_power", "look_left", "look_right", "look_up", "look_down"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


## A practice dummy: a capsule on the enemy layer that adds up the damage it
## takes. Made from source code so the test needs no extra file.
func _make_dummy() -> CharacterBody3D:
	var script := GDScript.new()
	script.source_code = """extends CharacterBody3D
var taken := 0.0
var hits := 0
var health := 1000.0
func take_damage(amount: float, _attacker = null) -> void:
	taken += amount
	hits += 1
"""
	script.reload()
	var dummy := CharacterBody3D.new()
	dummy.set_script(script)
	dummy.collision_layer = 4
	dummy.collision_mask = 0
	dummy.add_to_group("enemies")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	dummy.add_child(shape)
	return dummy


func _run() -> void:
	_actions()
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	if not _shots_dir.is_empty():
		await _build_arena_for_shots()
	else:
		_build_bare_room()
	_player = CharacterBody3D.new()
	# load() here rather than preload() at the top: player.gd uses the
	# NetworkSession autoload, which does not exist yet while this test script
	# itself is being compiled.
	_player.set_script(load("res://scripts/player.gd"))
	_player.name = "Player"
	_world.add_child(_player)
	_player.global_position = _origin
	_player.hit_confirmed.connect(func(): _hits_confirmed += 1)
	_dummy = _make_dummy()
	_world.add_child(_dummy)
	if not _shots_dir.is_empty():
		var look := RunnerDresser.build({"skin": "default", "body_color": 2, "hat": 3}, Color("#58D7F2"), true)
		if look != null:
			_dummy.add_child(look)
	await _wait(0.5)

	await _no_power()
	await _sprayer()
	await _rocket_launcher()
	await _two_shot()
	await _speed()
	await _invisibility()
	await _shield()
	print("[weapons] RESULT %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _build_bare_room() -> void:
	var floor := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor.add_child(floor_shape)
	_world.add_child(floor)


func _build_arena_for_shots() -> void:
	var arena := Node3D.new()
	arena.set_script(load("res://scripts/arena.gd"))
	_world.add_child(arena)
	_origin = Vector3(-30, 0.05, 6)
	_ahead = Vector3(1, 0, 0)
	# Keep the real mouse free while the test window is open.
	process_frame.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
	await _wait(1.0)


func _shot(label: String) -> void:
	if _shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var path := _shots_dir.path_join("gun_%s.png" % label)
	root.get_texture().get_image().save_png(path)
	print("[weapons] shot %s" % path)


## Gives the player `power_id`, puts the dummy `distance` metres ahead and
## resets its counters.
func _setup(power_id: String, distance: float, invisible := false) -> void:
	_player.set_network_power(power_id, invisible)
	_player.ammo = _player.get_max_ammo()
	# Test-only: forget the previous power's reload (the rocket launcher's
	# 1.2 s would otherwise swallow the next gun's first shot).
	_player._fire_cooldown = 0.0
	_player.global_position = _origin
	_player.velocity = Vector3.ZERO
	_dummy.global_position = Vector3(_origin.x, 0.0, _origin.z) + _ahead * distance
	_dummy.taken = 0.0
	_dummy.hits = 0
	_hits_confirmed = 0
	for glob in get_nodes_in_group("projectiles"):
		glob.queue_free()
	await _wait(0.3)
	_aim_at(_dummy.global_position + Vector3(0, 1.0, 0))


func _aim_at(point: Vector3) -> void:
	var camera: Camera3D = _player.get_node("Camera")
	_player.look_at(Vector3(point.x, _player.global_position.y, point.z), Vector3.UP)
	var eye := camera.global_position
	camera.rotation.x = atan2(point.y - eye.y, Vector2(point.x - eye.x, point.z - eye.z).length())


func _press(action: String, down: bool) -> void:
	await physics_frame
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)


## Holds fire for exactly one shot's worth of time.
func _tap_fire() -> void:
	await _press("fire", true)
	await physics_frame
	await physics_frame
	await _press("fire", false)


## The file the gun model in your hands came from, e.g. "paint_blaster.glb".
func _gun_model() -> String:
	return _player._gun.scene_file_path.get_file() if _player._gun != null else "(box gun)"


func _expect_model(power_id: String) -> void:
	var want := str(Weapons.for_power(power_id).model) + ".glb"
	_check("%s: gun model %s" % [power_id if not power_id.is_empty() else "no power", want],
		_gun_model() == want, _gun_model())


func _no_power() -> void:
	await _setup("", 10.0)
	_expect_model("")
	await _shot("paint_blaster")
	_check("no power: no halo", not _player._power_halo.visible)
	await _tap_fire()
	await _wait(0.4)
	_check("no power: 4.4 damage per bullet", is_equal_approx(_dummy.taken, Powers.BASE_DAMAGE), str(_dummy.taken))
	_check("hit marker fires on a hit", _hits_confirmed == 1, str(_hits_confirmed))


func _sprayer() -> void:
	await _setup("sprayer", 10.0)
	_expect_model("sprayer")
	await _shot("prism_beam")
	_check("sprayer: halo in its colour", _player._power_halo.visible
		and (_player._power_halo.material_override as StandardMaterial3D).albedo_color.is_equal_approx(Powers.color_for("sprayer")))
	await _press("fire", true)
	await _wait(1.0)
	await _press("fire", false)
	await _wait(0.3)
	_check("sprayer: about 9 shots a second", _dummy.hits >= 7 and _dummy.hits <= 11, "%d hits" % _dummy.hits)


func _rocket_launcher() -> void:
	await _setup("rocket_launcher", 12.0)
	_expect_model("rocket_launcher")
	await _shot("blob_lobber")
	await _tap_fire()
	var globs := get_nodes_in_group("projectiles")
	_check("rocket: fires a rocket", globs.size() == 1 and str(globs[0].projectile_kind) == "rocket")
	await _wait(0.6)
	_check("rocket: 90 direct + splash", _dummy.taken >= 90.0, str(_dummy.taken))
	_check("rocket: sparks on impact", _world.find_child("RocketSparks", true, false) != null)
	# Splash: a rocket into the floor beside the dummy still hurts it.
	_dummy.taken = 0.0
	await _wait(1.3)
	_aim_at(_dummy.global_position + _ahead.cross(Vector3.UP) * 3.0)
	await _tap_fire()
	await _wait(0.6)
	_check("rocket: splash hurts nearby", _dummy.taken > 5.0 and _dummy.taken < 90.0, str(_dummy.taken))


func _two_shot() -> void:
	await _setup("two_shot", 20.0)
	_expect_model("two_shot")
	await _shot("fine_liner")
	await _tap_fire()
	await _wait(0.5)
	_check("2 shot: 100 damage", is_equal_approx(_dummy.taken, 100.0), str(_dummy.taken))


func _speed() -> void:
	await _setup("speed", 10.0)
	_expect_model("speed")
	_check("speed: twice as fast", is_equal_approx(_player._speed, _player.base_speed * 2.0), str(_player._speed))


func _invisibility() -> void:
	await _setup("invisibility", 10.0, true)
	_expect_model("invisibility")
	_check("invisible: gun hidden", not _player._view_model.visible)
	_check("invisible: halo hidden", not _player._power_halo.visible)
	var ammo_before: float = _player.ammo
	await _tap_fire()
	await _wait(0.3)
	_check("invisible: cannot shoot", is_equal_approx(_player.ammo, ammo_before) and _dummy.hits == 0)
	_player.set_network_power("invisibility", false)
	await _wait(0.1)
	_check("visible again: gun back", _player._view_model.visible)
	await _tap_fire()
	await _wait(0.4)
	_check("visible again: can shoot", _dummy.hits == 1, str(_dummy.hits))
	_player.set_network_power("", false)


func _shield() -> void:
	_player.restore_full_vitals()
	_player.take_damage(30.0, null)
	_check("shield soaks damage first", is_equal_approx(_player.shield, 70.0) and is_equal_approx(_player.health, 100.0),
		"%.0f shield, %.0f health" % [_player.shield, _player.health])
	_player.take_damage(90.0, null)
	_check("then health", is_equal_approx(_player.shield, 0.0) and is_equal_approx(_player.health, 80.0),
		"%.0f shield, %.0f health" % [_player.shield, _player.health])
