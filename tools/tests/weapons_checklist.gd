extends SceneTree

## ============================================================================
## WEAPONS CHECKLIST - a development tool, not part of the game.
## ============================================================================
##
## Builds a bare test room (a floor, the real player, and a practice dummy in
## the "enemies" group), then equips each of the five loadout guns in turn and
## fires the REAL fire button at the dummy, printing PASS/FAIL per check:
##
##   godot --headless --path . --script res://tools/tests/weapons_checklist.gd
##
## No server: the player is not in an online match, so it fires exactly as it
## would online but does not report shots anywhere.
##
## Add `-- --shots=DIR` (and drop --headless) to build the real arena instead
## of the bare room, dress the dummy as a Canvas Runner, and save a first-person
## screenshot of every gun into DIR.

const Weapons = preload("res://scripts/weapons.gd")
const RunnerDresser = preload("res://scripts/visual/runner_dresser.gd")

var _passed := 0
var _failed := 0
var _world: Node3D
var _player
var _dummy: CharacterBody3D
var _shots_dir := ""
## Where the player stands, and which way "ahead" is. The bare room uses the
## world origin; the arena uses the RED spawn, looking at the centre.
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
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "interact", "restart"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
	if not InputMap.has_action("aim"):
		InputMap.add_action("aim")


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
	_dummy = _make_dummy()
	_world.add_child(_dummy)
	if not _shots_dir.is_empty():
		var look := RunnerDresser.build({"skin": "default", "body_color": 2, "hat": 3}, Color("#58D7F2"), true)
		if look != null:
			_dummy.add_child(look)
	await _wait(0.5)
	await _tests()


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


func _tests() -> void:
	_check("starts with the Brush Rifle", int(_player.weapon_index) == Weapons.BRUSH_RIFLE)
	_check("rifle numbers unchanged", is_equal_approx(float(_player._damage), 22.0)
		and is_equal_approx(float(_player._fire_interval), 0.28) and is_equal_approx(float(_player.get_max_ammo()), 30.0))

	await _brush_rifle()
	await _fine_liner()
	await _prism_beam()
	await _splat_bucket()
	await _blob_lobber()
	_report()


func _report() -> void:
	print("[weapons] RESULT %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Equips gun `index`, puts the dummy `distance` metres ahead, resets counters.
func _setup(index: int, distance: float) -> void:
	_player.set_weapon(index)
	_player.global_position = _origin
	_player.velocity = Vector3.ZERO
	_dummy.global_position = Vector3(_origin.x, 0.0, _origin.z) + _ahead * distance
	_dummy.taken = 0.0
	_dummy.hits = 0
	for glob in get_nodes_in_group("projectiles"):
		glob.queue_free()
	await _wait(0.2)
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


## The file the equipped gun model came from, e.g. "weapon_fine_liner.glb".
func _gun_model() -> String:
	return _player._gun.scene_file_path.get_file() if _player._gun != null else "(box gun)"


func _brush_rifle() -> void:
	await _setup(Weapons.BRUSH_RIFLE, 10.0)
	await _shot("brush_rifle")
	await _tap_fire()
	_check("rifle: one shot = one projectile", get_nodes_in_group("projectiles").size() == 1)
	await _wait(0.5)
	_check("rifle: 22 damage", is_equal_approx(_dummy.taken, 22.0), str(_dummy.taken))
	_check("rifle: costs 1 paint", is_equal_approx(_player.ammo, 29.0) or _player.ammo > 28.9, "%.2f" % _player.ammo)


func _fine_liner() -> void:
	await _setup(Weapons.FINE_LINER, 30.0)
	_check("liner: gun model swapped", _gun_model() == "weapon_fine_liner.glb", _gun_model())
	_check("liner: 5 shots", is_equal_approx(_player.get_max_ammo(), 5.0) and is_equal_approx(_player.ammo, 5.0))
	await _shot("fine_liner")
	await _press("aim", true)
	await _wait(0.6)
	var camera: Camera3D = _player.get_node("Camera")
	_check("liner: right mouse zooms", _player.is_zoomed() and camera.fov < 40.0, "fov %.1f" % camera.fov)
	_check("liner: gun hidden while scoped", not _player._view_model.visible)
	await _tap_fire()
	await _wait(0.6)
	_check("liner: 85 damage", is_equal_approx(_dummy.taken, 85.0), str(_dummy.taken))
	await _press("aim", false)
	await _wait(0.6)
	_check("liner: zoom releases", not _player.is_zoomed() and camera.fov > 100.0, "fov %.1f" % camera.fov)
	# Slow: a second tap straight away must not fire.
	await _tap_fire()
	await _tap_fire()
	_check("liner: slow fire interval", _player.ammo < 4.5 and _player.ammo > 2.5, "%.2f" % _player.ammo)


func _prism_beam() -> void:
	await _setup(Weapons.PRISM_BEAM, 12.0)
	_check("prism: gun model swapped", _gun_model() == "weapon_prism_beam.glb", _gun_model())
	await _shot("prism_beam")
	await _press("fire", true)
	await _wait(0.5)
	await _shot("prism_beam_firing")
	var early_hits: int = _dummy.hits
	_check("prism: rapid fire", early_hits >= 4, "%d hits in 0.5 s" % early_hits)
	var overheated := false
	for i in 120:
		await physics_frame
		if _player.is_overheated():
			overheated = true
			break
	_check("prism: overheats when the charge runs dry", overheated)
	var hits_at_lock: int = _dummy.hits
	await _wait(0.8)
	_check("prism: locked while overheated", _player.is_overheated() and get_nodes_in_group("projectiles").size() <= 3)
	await _press("fire", false)
	var recovered := false
	for i in 300:
		await physics_frame
		if not _player.is_overheated():
			recovered = true
			break
	_check("prism: unlocks once fully recharged", recovered and _player.ammo >= _player.get_max_ammo() - 0.01)
	_check("prism: 9 damage per bolt", is_equal_approx(_dummy.taken / maxf(float(_dummy.hits), 1.0), 9.0),
		"%.1f over %d hits (%d at lock)" % [_dummy.taken, _dummy.hits, hits_at_lock])


func _splat_bucket() -> void:
	await _setup(Weapons.SPLAT_BUCKET, 4.0)
	_check("bucket: gun model swapped", _gun_model() == "weapon_splat_bucket.glb", _gun_model())
	await _shot("splat_bucket")
	await _tap_fire()
	await _wait(0.5)
	# At 4 m the whole cone of droplets fits on the dummy, so every pellet hits.
	_check("bucket: 8 pellets per shot", _dummy.hits == 8, str(_dummy.hits))
	_check("bucket: close range hits hard", _dummy.taken >= 50.0, "%.0f damage from %d pellets" % [_dummy.taken, _dummy.hits])
	await _wait(1.0)
	await _setup(Weapons.SPLAT_BUCKET, 45.0)
	await _tap_fire()
	await _wait(1.0)
	_check("bucket: useless far away", is_equal_approx(_dummy.taken, 0.0), str(_dummy.taken))


func _blob_lobber() -> void:
	await _setup(Weapons.BLOB_LOBBER, 9.0)
	_check("lobber: gun model swapped", _gun_model() == "weapon_blob_lobber.glb", _gun_model())
	await _shot("blob_lobber")
	# Aim a little above the dummy's chest: the blob arcs down onto it.
	_aim_at(_dummy.global_position + Vector3(0, 1.6, 0))
	await _tap_fire()
	var globs := get_nodes_in_group("projectiles")
	_check("lobber: one blob", globs.size() == 1)
	await _wait(0.12)
	await _shot("blob_lobber_flight")
	if globs.size() == 1:
		var glob = globs[0]
		var start_dir: Vector3 = glob.direction
		await _wait(0.2)
		if is_instance_valid(glob):
			_check("lobber: blob arcs downward", glob.direction.y < start_dir.y - 0.05,
				"%.2f -> %.2f" % [start_dir.y, glob.direction.y])
	await _wait(1.0)
	_check("lobber: blob paints the dummy", _dummy.taken >= 40.0, str(_dummy.taken))
	# Splash: a blob landing on the floor next to the dummy still hurts it.
	_dummy.taken = 0.0
	await _wait(1.1)
	_aim_at(_dummy.global_position + _ahead.cross(Vector3.UP) * 1.6)
	await _tap_fire()
	await _wait(1.2)
	_check("lobber: splash hurts nearby", _dummy.taken > 5.0 and _dummy.taken < 50.0, str(_dummy.taken))
