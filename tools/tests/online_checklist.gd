extends SceneTree

## ============================================================================
## ONLINE CHECKLIST - a development tool, not part of the game.
## ============================================================================
##
## Plays a real online match on THIS computer: a local copy of the dedicated
## server plus test clients, each driving the real menu (mode select -> online
## setup -> lobby) and the real match. Each client prints PASS/FAIL lines.
## tools/tests/run_online_checklist.sh starts everything:
##
##   godot --headless --path . -- --server                       (the server)
##   godot --headless --path . --script res://tools/tests/online_checklist.gd -- --role=host  --run=ID
##   godot --headless --path . --script res://tools/tests/online_checklist.gd -- --role=guest --run=ID
##   godot --headless --path . --script res://tools/tests/online_checklist.gd -- --role=mate  --run=ID
##   (add --mode=survival to all of them, and skip mate, for Survival)
##
## TEAM DEATHMATCH (three clients)
##   host  = RED. Creates the lobby, starts the match, paints out the guest
##           with the Brush Rifle, tests the pause menu, gets painted out,
##           spectates the mate (third and first person), picks the Fine
##           Liner, respawns with it and paints the guest out with the scope.
##   guest = BLUE. Gets painted out with no teammate to watch, picks the Splat
##           Bucket, respawns with it and paints the host out at close range.
##   mate  = RED. Stands at spawn as the teammate the host spectates, checks it
##           sees the others' new guns, then leaves through the pause menu.
##
## SURVIVAL (host + guest): the Survival HUD and pause menu, and the match
## ending when only one player is left standing.
##
## TEST-ONLY shortcuts: the clients connect to ws://127.0.0.1:9080 instead of
## the live server (by handing NetworkSession a socket before the menu asks for
## one), players are teleported to fixed spots, aim is set directly before the
## real fire button is pressed, and keys are sent as real key events.

const LOCAL_URL := "ws://127.0.0.1:9080"
const CODE_FILE := "user://online_checklist_code.txt"
const Weapons = preload("res://scripts/weapons.gd")

const HOST_SPOT := Vector3(0, 1.2, -6)
const GUEST_SPOT := Vector3(0, 1.2, 6)
const GUEST_CLOSE_SPOT := Vector3(0, 1.2, -3)

var role := "host"
var mode := "tdm"
var run_id := "0"
var players_expected := 3
## --shots=DIR (a Windows or res:// path): save screenshots of each screen
## there. Only useful for a client run WITHOUT --headless.
var shots_dir := ""
var ns
var menu
var game
var controller
var player
var _passed := 0
var _failed := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--run="):
			run_id = arg.trim_prefix("--run=")
		elif arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
	players_expected = 2 if mode == "survival" else 3
	# A watchdog: if a script error stops _run part-way, quit anyway instead of
	# leaving a headless Godot running forever.
	create_timer(200.0).timeout.connect(func():
		print("[%s] TIMEOUT - the run stopped early (look for a SCRIPT ERROR above)" % role)
		quit(2))
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[%s] %s  %s  %s" % [role, "PASS" if ok else "FAIL", label, detail])


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## Waits until `condition` returns true, up to `seconds`. Returns whether it did.
func _until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return bool(condition.call())


## Presses and releases a key as a real key event (so _input and
## _unhandled_input see it exactly as they would from the keyboard).
func _key(keycode: Key) -> void:
	await physics_frame
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame


## Saves what is on screen right now as DIR/<role>_<label>.png.
func _shot(label: String) -> void:
	if shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := shots_dir.path_join("%s_%s.png" % [role, label])
	root.get_texture().get_image().save_png(path)
	print("[%s] shot %s" % [role, path])


func _run() -> void:
	ns = root.get_node("NetworkSession")
	if not shots_dir.is_empty():
		# A windowed test client would otherwise grab the real mouse whenever
		# the game captures it. The game keeps its own "captured" flag and
		# never reads the mouse mode back, so handing the mouse back every
		# frame changes nothing about how it plays.
		process_frame.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
	if role == "host":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CODE_FILE))

	# --- Connect to the LOCAL server ------------------------------------------
	var peer := WebSocketMultiplayerPeer.new()
	_check("socket created", peer.create_client(LOCAL_URL) == OK)
	ns.multiplayer.multiplayer_peer = peer
	var local := await _until(func(): return ns.is_connected_to_server(), 20.0)
	_check("connected to local server", local)
	if not local:
		# Never fall through to the menu: it would connect to the LIVE server.
		_finish()
		return

	# --- The real menu ---------------------------------------------------------
	change_scene_to_file("res://scenes/main.tscn")
	await _until(func(): return current_scene != null and current_scene.has_method("_select_tdm"), 10.0)
	menu = current_scene
	await _wait(0.5)
	if mode == "survival":
		menu._launch_survival()
	else:
		menu._select_tdm()
	await process_frame
	_check("online setup page", menu.current_screen == "online_setup" and is_instance_valid(menu.join_code_edit))
	await _wait(0.6)
	await _shot("online_setup")

	if role == "host":
		await _host_lobby()
	else:
		await _join_lobby()

	# --- The match -------------------------------------------------------------
	var started := await _until(func():
		return current_scene != null and current_scene.has_node("OnlineMatchController"), 20.0)
	_check("match scene loaded", started)
	if not started:
		_finish()
		return
	game = current_scene
	controller = game.get_node("OnlineMatchController")
	player = game.get_node("Player")
	await _wait(1.0)
	_check_match_basics()
	await _shot("match_start")

	if mode == "survival":
		if role == "host":
			await _survival_host()
		else:
			await _survival_guest()
	else:
		match role:
			"host":
				await _host_script()
			"guest":
				await _guest_script()
			"mate":
				await _mate_script()
	_finish()


func _host_lobby() -> void:
	menu._create_online_lobby()
	var joined := await _until(func(): return menu.current_screen == "lobby" and not ns.current_lobby_code.is_empty(), 10.0)
	_check("lobby created", joined, ns.current_lobby_code)
	_check("lobby shows code", menu.status_label.text.contains(ns.current_lobby_code), menu.status_label.text)
	var file := FileAccess.open(CODE_FILE, FileAccess.WRITE)
	file.store_string("%s %s" % [run_id, ns.current_lobby_code])
	file.close()
	var full := await _until(func(): return ns.lobby_roster().size() >= players_expected, 30.0)
	_check("all players joined", full, str(ns.lobby_roster().size()))
	await _wait(0.5)
	if mode == "tdm":
		_check("fill label counts teams", menu.fill_label.text.contains("RED  2") and menu.fill_label.text.contains("BLUE  1"), menu.fill_label.text)
	else:
		_check("fill label counts players", menu.fill_label.text.contains("2 / 20"), menu.fill_label.text)
	_check("host is host", ns.is_host())
	await _shot("lobby")
	ns.start_match()


func _join_lobby() -> void:
	var code := ""
	var deadline := Time.get_ticks_msec() + 30000
	while code.is_empty() and Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(CODE_FILE):
			var parts := FileAccess.get_file_as_string(CODE_FILE).split(" ")
			if parts.size() == 2 and parts[0] == run_id:
				code = parts[1]
		await _wait(0.2)
	_check("read lobby code", not code.is_empty(), code)
	# Join one after the other (guest first, then mate), so the server's team
	# balancing gives guest BLUE and mate RED every time.
	if role == "mate":
		await _until(func(): return false, 1.5)
	menu.join_code_edit.text = code
	menu._join_online_lobby()
	var joined := await _until(func(): return menu.current_screen == "lobby", 10.0)
	_check("joined lobby", joined)
	_check("not host", not ns.is_host())
	await _wait(0.8)
	await _shot("lobby")


func _check_match_basics() -> void:
	var remotes := get_nodes_in_group("remote_players")
	_check("remote players", remotes.size() == players_expected - 1, str(remotes.size()))
	for remote in remotes:
		var visual = remote.get_node_or_null("Visual")
		var blaster = remote.get_node_or_null("AimPivot/Blaster")
		_check("remote dressed as runner", visual != null and visual.model != null, remote.name)
		_check("remote gun on aim pivot", blaster != null, remote.name)
	_check("pause menu built", game.has_node("PauseMenu") and not game.get_node("PauseMenu").is_open())
	if mode == "survival":
		_check("survival HUD", game.has_node("OnlineHUD"))
		return
	var expected_team := "BLUE" if role == "guest" else "RED"
	_check("team", controller.session_team == expected_team, controller.session_team)
	_check("TDM HUD", game.has_node("TDMHud"))
	_check("starts with the Brush Rifle", int(player.weapon_index) == Weapons.BRUSH_RIFLE)
	var mine := 0
	for record in controller.players:
		if bool(record.get("is_local", false)):
			mine += 1
	_check("one local scoreboard record", mine == 1)


## Puts the local player at `at`, facing `facing`.
func _place(at: Vector3, facing: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.look_at(Vector3(facing.x, at.y, facing.z), Vector3.UP)


## Aims the real camera at a remote player's chest and holds the real fire
## button (and right mouse, if `scoped`) until `done` is true or time is up.
func _shoot_at(target: Node3D, done: Callable, seconds: float, scoped := false) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var camera: Camera3D = player.get_node("Camera")
	if scoped:
		await physics_frame
		Input.action_press("aim")
		await _wait(0.5)
	while Time.get_ticks_msec() < deadline and not done.call():
		var chest := target.global_position + Vector3(0, 1.0, 0)
		player.look_at(Vector3(chest.x, player.global_position.y, chest.z), Vector3.UP)
		var eye := camera.global_position
		var flat := Vector2(chest.x - eye.x, chest.z - eye.z).length()
		camera.rotation.x = atan2(chest.y - eye.y, flat)
		await physics_frame
		Input.action_press("fire")
	await physics_frame
	Input.action_release("fire")
	Input.action_release("aim")
	return bool(done.call())


func _aim_camera_at(target: Node3D) -> void:
	var camera: Camera3D = player.get_node("Camera")
	var chest := target.global_position + Vector3(0, 1.0, 0)
	player.look_at(Vector3(chest.x, player.global_position.y, chest.z), Vector3.UP)
	var eye := camera.global_position
	camera.rotation.x = atan2(chest.y - eye.y, Vector2(chest.x - eye.x, chest.z - eye.z).length())


## The remote player on `team` standing nearest `spot`.
func _remote_near(team: String, spot: Vector3) -> Node3D:
	var best: Node3D = null
	for remote in get_nodes_in_group("remote_players"):
		if str(remote.get("tdm_team")) != team:
			continue
		if best == null or remote.global_position.distance_to(spot) < best.global_position.distance_to(spot):
			best = remote
	return best


func _current_camera() -> Camera3D:
	return root.get_viewport().get_camera_3d()


# ============================================================================
# TEAM DEATHMATCH
# ============================================================================

## HOST (RED).
func _host_script() -> void:
	# 1. Paint out the guest with the Brush Rifle.
	_place(HOST_SPOT, GUEST_SPOT)
	await _wait(2.0)
	var guest := _remote_near("BLUE", GUEST_SPOT)
	var killed := await _shoot_at(guest, func(): return not guest.alive, 8.0)
	var guest_down_at := Time.get_ticks_msec()
	_check("rifle paints out the guest", killed)
	await _wait(0.5)
	_check("RED scored", int(controller.scores.get("RED", 0)) == 1, str(controller.scores))
	_check("host kill counted", controller._local_stat("kills") == 1)
	_check("feed shows the elimination", controller.hud._feed.get_child_count() >= 1)

	# 2. The pause menu, while the guest waits to respawn.
	var pause = game.get_node("PauseMenu")
	await _key(KEY_ESCAPE)
	_check("Esc opens the pause menu", pause.is_open())
	await _wait(0.3)
	await _shot("pause_menu")
	_check("paused: player ignores input", player.is_paused() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	var ammo_before: float = player.ammo
	await physics_frame
	Input.action_press("fire")
	await _wait(0.5)
	Input.action_release("fire")
	_check("paused: fire does nothing", is_equal_approx(player.ammo, ammo_before) or player.ammo >= ammo_before,
		"%.1f -> %.1f" % [ammo_before, player.ammo])
	await _key(KEY_ESCAPE)
	_check("Esc again resumes", not pause.is_open() and not player.is_paused())
	await _key(KEY_ESCAPE)
	pause._resume.pressed.emit()
	_check("RESUME button resumes", not pause.is_open() and not player.is_paused())

	# 3. The guest respawns after the full 10 seconds.
	var back := await _until(func(): return guest.alive and guest.visible, NetworkSession.RESPAWN_SECONDS + 4.0)
	var waited := (Time.get_ticks_msec() - guest_down_at) / 1000.0
	_check("guest respawns after ~10 s", back and waited >= NetworkSession.RESPAWN_SECONDS - 1.0, "%.1f s" % waited)

	# 4. Stand still and get painted out by the guest's Splat Bucket.
	_place(HOST_SPOT, GUEST_CLOSE_SPOT)
	player.set_physics_process(false)
	var died := await _until(func(): return player.is_dead(), 25.0)
	_check("host painted out by the guest", died)
	player.set_physics_process(true)
	await _wait(0.5)
	_check("guest is seen holding the Splat Bucket", int(guest.get_meta("weapon", -1)) == Weapons.SPLAT_BUCKET,
		str(guest.get_meta("weapon", -1)))
	var hud = controller.hud
	_check("death screen shown", hud._respawn.visible)
	var left: float = controller.local_respawn_time_left()
	_check("10 second countdown", left > 8.0 and left <= NetworkSession.RESPAWN_SECONDS, "%.1f" % left)
	_check("death screen names the killer", controller.killed_by_name == guest.display_name, controller.killed_by_name)
	_check("loadout hidden HUD corners", not hud._bottom_left.visible and not hud._paint.visible)

	# 5. Spectate the mate: third person, then first person.
	var mate := _remote_near("RED", Vector3(-34, 1.2, 0))
	var cam := _current_camera()
	_check("spectator camera is current", cam != null and cam.name == "SpectatorCamera")
	_check("spectating the teammate", controller.spectate_name() == mate.display_name, controller.spectate_name())
	_check("starts in third person", not controller.spectate_first_person())
	await _wait(0.4)
	var head := mate.global_position + Vector3(0, 1.55, 0)
	var distance := cam.global_position.distance_to(head)
	_check("third person sits behind the teammate", distance > 1.0 and distance < 5.0, "%.2f m" % distance)
	_check("third person shows the teammate", mate.get_node("Visual").visible)
	await _shot("death_third_person")
	await _key(KEY_V)
	await _wait(0.3)
	_check("V switches to first person", controller.spectate_first_person())
	var eye := mate.global_position + Vector3(0, 1.6, 0)
	_check("first person at the teammate's eyes", cam.global_position.distance_to(eye) < 0.25,
		"%.2f m" % cam.global_position.distance_to(eye))
	_check("first person hides the teammate's body", not mate.get_node("Visual").visible)
	_check("first person shows their gun", cam.get_child_count() > 0)
	await _shot("death_first_person")
	await _key(KEY_E)
	_check("only one teammate to cycle", controller.spectate_name() == mate.display_name)

	# 6. Loadout: click the Prism Beam card, then change mind with key 2.
	hud._respawn._cards[Weapons.PRISM_BEAM].pressed.emit()
	_check("clicking a card picks it", controller.chosen_weapon == Weapons.PRISM_BEAM)
	await _key(KEY_2)
	_check("key 2 picks the Fine Liner", controller.chosen_weapon == Weapons.FINE_LINER)
	_check("still holding the rifle until respawn", int(player.weapon_index) == Weapons.BRUSH_RIFLE)

	var respawned := await _until(func(): return not player.is_dead(), NetworkSession.RESPAWN_SECONDS + 4.0)
	_check("host respawned", respawned)
	await _wait(0.3)
	_check("respawned with the Fine Liner", int(player.weapon_index) == Weapons.FINE_LINER)
	_check("paint caption shows the gun", hud._paint._caption.text == "FINE LINER", hud._paint._caption.text)
	_check("own camera is current again", _current_camera() == player.get_node("Camera"))
	_check("teammate's body visible again", mate.get_node("Visual").visible)
	_check("death screen hidden", not hud._respawn.visible and hud._bottom_left.visible)
	await _shot("respawn_fine_liner")

	# 7. Scope in and paint out the guest with the Fine Liner.
	_place(HOST_SPOT, GUEST_CLOSE_SPOT)
	await _wait(0.5)
	guest = _remote_near("BLUE", GUEST_CLOSE_SPOT)
	if not shots_dir.is_empty():
		_aim_camera_at(guest)
		await physics_frame
		Input.action_press("aim")
		await _wait(0.6)
		await _shot("scope")
		Input.action_release("aim")
	var sniped := await _shoot_at(guest, func(): return not guest.alive, 8.0, true)
	_check("Fine Liner paints out the guest", sniped)
	await _wait(NetworkSession.RESPAWN_SECONDS + 2.0)


## GUEST (BLUE).
func _guest_script() -> void:
	# 1. Stand still and get painted out by the host.
	_place(GUEST_SPOT, HOST_SPOT)
	player.set_physics_process(false)
	var died := await _until(func(): return player.is_dead(), 25.0)
	_check("guest painted out by the host", died)
	player.set_physics_process(true)
	await _wait(0.3)
	var cam := _current_camera()
	_check("no teammate: overview camera", cam != null and cam.name == "SpectatorCamera" and controller.spectate_name() == "")
	_check("death screen says nobody to watch", controller.hud._respawn._spectating.text.begins_with("NO TEAMMATES"),
		controller.hud._respawn._spectating.text)
	await _shot("death_no_teammates")
	await _key(KEY_4)
	_check("key 4 picks the Splat Bucket", controller.chosen_weapon == Weapons.SPLAT_BUCKET)
	var respawned := await _until(func(): return not player.is_dead(), NetworkSession.RESPAWN_SECONDS + 4.0)
	_check("guest respawned", respawned)
	await _wait(0.3)
	_check("respawned with the Splat Bucket", int(player.weapon_index) == Weapons.SPLAT_BUCKET
		and is_equal_approx(player.ammo, 6.0), "%d / %.1f" % [player.weapon_index, player.ammo])
	await _shot("respawn_splat_bucket")

	# 2. Walk up close and paint out the host with the bucket.
	await _wait(1.0)
	_place(GUEST_CLOSE_SPOT, HOST_SPOT)
	await _wait(0.6)
	var host := _remote_near("RED", HOST_SPOT)
	var killed := await _shoot_at(host, func(): return not host.alive, 10.0)
	_check("Splat Bucket paints out the host", killed)
	await _wait(0.5)
	_check("BLUE scored", int(controller.scores.get("BLUE", 0)) == 1, str(controller.scores))

	# 3. Stand still for the host's Fine Liner.
	_place(GUEST_CLOSE_SPOT, HOST_SPOT)
	player.set_physics_process(false)
	var sniped := await _until(func(): return player.is_dead(), NetworkSession.RESPAWN_SECONDS + 15.0)
	_check("painted out by the Fine Liner", sniped)
	_check("host is seen holding the Fine Liner", int(host.get_meta("weapon", -1)) == Weapons.FINE_LINER,
		str(host.get_meta("weapon", -1)))
	await _shot("death_by_fine_liner")
	player.set_physics_process(true)
	await _wait(1.0)


## MATE (RED): the teammate the host spectates, then leaves via the pause menu.
func _mate_script() -> void:
	player.set_physics_process(false)
	var guest := _remote_near("BLUE", GUEST_SPOT)
	var saw_bucket := await _until(func(): return int(guest.get_meta("weapon", -1)) == Weapons.SPLAT_BUCKET, 45.0)
	_check("sees the guest's Splat Bucket", saw_bucket)
	if not shots_dir.is_empty():
		# Look at the guest to see the bucket in their hands.
		await _wait(1.5)
		_place(player.global_position, guest.global_position)
		_aim_camera_at(guest)
		await _wait(0.3)
		await _shot("guest_with_bucket")
	var host := _remote_near("RED", HOST_SPOT)
	var saw_liner := await _until(func(): return int(host.get_meta("weapon", -1)) == Weapons.FINE_LINER, 45.0)
	_check("sees the host's Fine Liner", saw_liner)
	_check("mate saw three eliminations", await _until(func():
		return int(controller.scores.get("RED", 0)) + int(controller.scores.get("BLUE", 0)) == 3, 10.0),
		str(controller.scores))
	_check("mate never died", not player.is_dead())
	# Leave through the pause menu.
	player.set_physics_process(true)
	await _key(KEY_ESCAPE)
	var pause = game.get_node("PauseMenu")
	_check("mate opens pause", pause.is_open())
	pause._leave()
	var at_menu := await _until(func(): return current_scene != null and current_scene.has_method("_select_tdm"), 10.0)
	_check("LEAVE MATCH returns to the main menu", at_menu)
	_check("left the online session", not ns.is_online())


# ============================================================================
# SURVIVAL
# ============================================================================

func _survival_host() -> void:
	var hud = controller.hud
	_check("status shows players alive", hud._enemies_label.text.begins_with("2 ALIVE"), hud._enemies_label.text)
	var pause = game.get_node("PauseMenu")
	await _key(KEY_ESCAPE)
	_check("Esc opens the pause menu", pause.is_open() and player.is_paused())
	await _key(KEY_ESCAPE)
	_check("Esc again resumes", not pause.is_open() and not player.is_paused())
	_place(HOST_SPOT, GUEST_SPOT)
	await _wait(1.5)
	var guest := get_nodes_in_group("remote_players")[0] as Node3D
	await _shot("survival_hud")
	var killed := await _shoot_at(guest, func(): return not guest.alive, 10.0)
	_check("paints out the last opponent", killed)
	var ended := await _until(func(): return controller.ended, 5.0)
	_check("match ends with one player standing", ended)
	_check("ending says who won", hud._end_title.text.ends_with("WINS"), hud._end_title.text)
	await _wait(0.4)
	await _shot("survival_end")
	_check("pause menu disabled after the end", not pause._enabled)


func _survival_guest() -> void:
	_place(GUEST_SPOT, HOST_SPOT)
	player.set_physics_process(false)
	var died := await _until(func(): return player.is_dead(), 25.0)
	_check("painted out", died)
	var ended := await _until(func(): return controller.ended, 5.0)
	_check("match ends for the loser too", ended)
	await _wait(1.0)


func _finish() -> void:
	print("[%s] RESULT %d passed, %d failed" % [role, _passed, _failed])
	ns.disconnect_game()
	await _wait(0.3)
	quit(1 if _failed > 0 else 0)
