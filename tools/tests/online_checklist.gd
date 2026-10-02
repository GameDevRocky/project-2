extends SceneTree

## ============================================================================
## ONLINE CHECKLIST - a development tool, not part of the game.
## ============================================================================
##
## Plays a real online match on THIS computer: a local copy of the dedicated
## server plus two test clients, each driving the real menu (mode select ->
## online setup -> lobby browser -> lobby) and the real match, under Rocklyn's
## online rules. Each client prints PASS/FAIL lines.
## tools/tests/run_online_checklist.sh starts everything:
##
##   godot --headless --path . -- --server                       (the server)
##   godot --headless --path . --script res://tools/tests/online_checklist.gd -- --role=host  --run=ID
##   godot --headless --path . --script res://tools/tests/online_checklist.gd -- --role=guest --run=ID
##   (Survival: add --mode=survival to all three, plus a --role=mate client)
##
## TEAM DEATHMATCH (teams are random each round; two players are always one
## per team)
##   host   creates the lobby and starts the match; shoots down the 2 Shot power
##          ball (and must then hold the Fine Liner model), paints out the
##          guest, tests the pause menu, then trades the power at a station.
##   guest  finds the lobby in the LOBBY BROWSER and joins; stands still to be
##          painted out; checks the death screen, spectating its killer in
##          third and first person, and the 3 s respawn.
##
## SURVIVAL (three players: host, guest, mate): the host paints out the guest
## (whose death screen says OUT UNTIL THE NEXT ROUND and watches the host),
## then the mate, ending the round; the next round then starts by itself.
##
## TEST-ONLY shortcuts: the clients connect to ws://127.0.0.1:9080 instead of
## the live server (by handing NetworkSession a socket before the menu asks for
## one), players are teleported to fixed spots, aim is set directly before the
## real fire button is pressed, and keys are sent as real key events.

const LOCAL_URL := "ws://127.0.0.1:9080"
const CODE_FILE := "user://online_checklist_code.txt"
const Weapons = preload("res://scripts/weapons.gd")

const HOST_SPOT := Vector3(0, 1.2, -16)
const GUEST_SPOT := Vector3(0, 1.2, -26)
const MATE_SPOT := Vector3(10, 1.2, -16)

var role := "host"
var mode := "tdm"
var run_id := "0"
var players_expected := 2
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
	players_expected = 3 if mode == "survival" else 2
	# A watchdog: if a script error stops _run part-way, quit anyway instead of
	# leaving a headless Godot running forever.
	create_timer(240.0).timeout.connect(func():
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
	var path := shots_dir.path_join("%s_%s_%s.png" % [mode, role, label])
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
	_check("online setup page", menu.current_screen == "online_setup" and is_instance_valid(menu.lobby_list))

	if role == "host":
		await _host_lobby()
	else:
		await _join_lobby()

	# --- The match -------------------------------------------------------------
	if not await _enter_match():
		_finish()
		return
	if mode == "survival":
		match role:
			"host":
				await _survival_host()
			"guest":
				await _survival_guest()
			_:
				await _survival_mate()
	elif role == "host":
		await _host_script()
	else:
		await _guest_script()
	_finish()


## Waits for the match scene, then picks up its controller and player.
func _enter_match() -> bool:
	var started := await _until(func():
		return current_scene != null and current_scene.has_node("OnlineMatchController"), 20.0)
	_check("match scene loaded", started)
	if not started:
		return false
	game = current_scene
	controller = game.get_node("OnlineMatchController")
	player = game.get_node("Player")
	await _wait(1.0)
	_check_match_basics()
	await _shot("match_start")
	return true


func _host_lobby() -> void:
	menu._create_online_lobby()
	var joined := await _until(func(): return menu.current_screen == "lobby" and not ns.current_lobby_code.is_empty(), 10.0)
	_check("lobby created", joined, ns.current_lobby_code)
	_check("lobby shows code", menu.status_label.text.contains(ns.current_lobby_code), menu.status_label.text)
	var file := FileAccess.open(CODE_FILE, FileAccess.WRITE)
	file.store_string("%s %s" % [run_id, ns.current_lobby_code])
	file.close()
	var full := await _until(func(): return ns.lobby_roster().size() >= players_expected, 40.0)
	_check("everyone joined", full, str(ns.lobby_roster().size()))
	await _wait(0.5)
	_check("host is host", ns.is_host())
	await _shot("lobby")
	ns.start_match()


## The guest finds the host's lobby in the LOBBY BROWSER (the code file only
## says which row to expect).
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
	var listed := await _until(func(): return _lobby_row(code) != null, 10.0)
	_check("lobby browser lists the host's lobby", listed)
	await _shot("online_setup")
	var row := _lobby_row(code)
	if row != null:
		row.pressed.emit()
	_check("picking a row fills in the code", menu.join_code_edit.text == code, menu.join_code_edit.text)
	menu._join_online_lobby()
	var joined := await _until(func(): return menu.current_screen == "lobby", 10.0)
	_check("joined lobby", joined)
	_check("not host", not ns.is_host())


## The lobby browser row (a Button) whose code label says `code`.
func _lobby_row(code: String) -> Button:
	if not is_instance_valid(menu.lobby_list):
		return null
	for row in menu.lobby_list.get_children():
		if row is Button:
			for label in row.find_children("*", "Label", true, false):
				if (label as Label).text == code:
					return row
	return null


func _check_match_basics() -> void:
	var remotes := get_nodes_in_group("remote_players")
	_check("remote players", remotes.size() == players_expected - 1, str(remotes.size()))
	for remote in remotes:
		_check("remote dressed as runner", remote.get_node_or_null("Visual") != null, remote.name)
		_check("remote holds the Paint Blaster", str(remote.get_meta("gun_model", "")) == "paint_blaster")
		_check("remote halo kept", remote.get_node_or_null("PowerHalo") != null)
	_check("pause menu built", game.has_node("PauseMenu") and not game.get_node("PauseMenu").is_open())
	_check("power balls flying", controller.snitch_actors.size() == 5, str(controller.snitch_actors.size()))
	_check("shield and health full", is_equal_approx(player.health, 100.0) and is_equal_approx(player.shield, 100.0))
	_check("starts with no power", str(player.current_power).is_empty())
	if mode == "survival":
		_check("survival HUD", game.has_node("OnlineHUD"))
		return
	_check("TDM HUD", game.has_node("TDMHud"))
	_check("team assigned", controller.session_team in ["RED", "BLUE"], controller.session_team)
	var hud = controller.hud
	_check("both leaderboards", hud._boards.size() == 2)
	_check("leaderboard lists me", _board_has(hud, controller.session_team, "Player"))


func _board_has(hud, team: String, text: String) -> bool:
	for label in (hud._boards[team] as Node).find_children("*", "Label", true, false):
		if (label as Label).text.contains(text):
			return true
	return false


## Puts the local player at `at`, facing `facing`.
func _place(at: Vector3, facing: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	if Vector2(facing.x - at.x, facing.z - at.z).length() > 0.01:
		player.look_at(Vector3(facing.x, at.y, facing.z), Vector3.UP)


func _aim_camera_at(point: Vector3) -> void:
	var camera: Camera3D = player.get_node("Camera")
	player.look_at(Vector3(point.x, player.global_position.y, point.z), Vector3.UP)
	var eye := camera.global_position
	camera.rotation.x = atan2(point.y - eye.y, Vector2(point.x - eye.x, point.z - eye.z).length())


## Aims the real camera at `target` (`height` above its origin) and holds the
## real fire button until `done` is true or time is up. With `chase`, the
## player is moved to stay 8 m from the target (for flying power balls).
func _shoot_at(target: Node3D, done: Callable, seconds: float, height := 1.0, chase := false) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and not done.call() and is_instance_valid(target):
		if chase:
			var flat := Vector3(target.global_position.x, 0.0, target.global_position.z)
			player.global_position = flat + Vector3(0, 0.6, 8.0)
			player.velocity = Vector3.ZERO
		_aim_camera_at(target.global_position + Vector3(0, height, 0))
		await physics_frame
		Input.action_press("fire")
	await physics_frame
	Input.action_release("fire")
	return bool(done.call())


func _remote() -> Node3D:
	var remotes := get_nodes_in_group("remote_players")
	return remotes[0] if not remotes.is_empty() else null


## The remote player standing nearest `spot`.
func _remote_near(spot: Vector3) -> Node3D:
	var best: Node3D = null
	for remote in get_nodes_in_group("remote_players"):
		if best == null or remote.global_position.distance_to(spot) < best.global_position.distance_to(spot):
			best = remote
	return best


func _current_camera() -> Camera3D:
	return root.get_viewport().get_camera_3d()


func _gun_model() -> String:
	return player._gun.scene_file_path.get_file() if player._gun != null else "(none)"


## Shoots down the flying power ball carrying `power_id`.
func _claim_power(power_id: String) -> bool:
	var ball = null
	for candidate in controller.snitch_actors.values():
		if is_instance_valid(candidate) and str(candidate.power_id) == power_id:
			ball = candidate
	_check("found the %s ball" % power_id, ball != null)
	if ball == null:
		return false
	player.set_physics_process(true)
	var got := await _shoot_at(ball, func(): return str(player.current_power) == power_id, 25.0, 0.0, true)
	_check("shot down the %s ball" % power_id, got, str(player.current_power))
	return got


# ============================================================================
# TEAM DEATHMATCH
# ============================================================================

func _host_script() -> void:
	var hud = controller.hud
	# 1. A power: the 2 Shot, and the gun model that goes with it.
	if await _claim_power("two_shot"):
		await _wait(0.3)
		_check("2 Shot puts the Fine Liner in your hands", _gun_model() == "weapon_fine_liner.glb", _gun_model())
		_check("paint tank caption names the gun", hud._paint._caption.text == "FINE LINER", hud._paint._caption.text)
		_check("power card shows the power", hud._pair_card._name_label.text == "2 SHOT", hud._pair_card._name_label.text)
		_check("power halo on", player._power_halo.visible)
		_check("2 Shot hits for 100", is_equal_approx(player._damage, 100.0))
		await _shot("power_two_shot")

	# 2. Paint out the guest (two 2 Shot hits remove shield + health).
	_place(HOST_SPOT, GUEST_SPOT)
	await _wait(1.5)
	var guest := _remote()
	var killed := await _shoot_at(guest, func(): return not guest.alive, 10.0)
	_check("paints out the guest", killed)
	await _wait(0.5)
	_check("my team scored", int(controller.scores.get(controller.session_team, 0)) == 1, str(controller.scores))
	_check("kill counted on the leaderboard", controller._local_stat("kills") == 1 and _board_has(hud, controller.session_team, "1 / 0"))
	_check("kill feed shows it", hud._feed.get_child_count() >= 1)

	# 3. The pause menu, while the guest waits to respawn.
	var pause = game.get_node("PauseMenu")
	await _key(KEY_ESCAPE)
	_check("Esc opens the pause menu", pause.is_open())
	_check("paused: player ignores input", player.is_paused())
	await _wait(0.2)
	await _shot("pause_menu")
	var ammo_before: float = player.ammo
	await physics_frame
	Input.action_press("fire")
	await _wait(0.5)
	Input.action_release("fire")
	_check("paused: fire does nothing", player.ammo >= ammo_before - 0.01, "%.1f -> %.1f" % [ammo_before, player.ammo])
	await _key(KEY_ESCAPE)
	_check("Esc again resumes", not pause.is_open() and not player.is_paused())

	# 4. Trade the power at a station: full health + shield, power released.
	var back := await _until(func(): return guest.alive, NetworkSession.RESPAWN_SECONDS + 4.0)
	_check("guest respawns (3 s)", back)
	var station := Vector3(NetworkSession.STATION_POSITIONS[0]) + Vector3(0.0, 0.1, 0.0)
	_place(station, station + Vector3(0, 0, -1))
	await _wait(1.2)
	await physics_frame
	Input.action_press("interact")
	var traded := await _until(func(): return str(player.current_power).is_empty(), 6.0)
	Input.action_release("interact")
	_check("trading at a station removes the power", traded, str(player.current_power))
	await _wait(0.4)
	_check("gun back to the Paint Blaster", _gun_model() == "paint_blaster.glb", _gun_model())
	_check("full health and shield", is_equal_approx(player.health, 100.0) and is_equal_approx(player.shield, 100.0))
	_check("the traded power flies again", await _until(func(): return controller.snitch_actors.size() == 5, 3.0))
	await _shot("after_trade")
	await _wait(3.0)


func _guest_script() -> void:
	var host := _remote()
	# 1. The host picks up the 2 Shot: their gun turns into the Fine Liner.
	var saw := await _until(func(): return str(host.get_meta("gun_model", "")) == "weapon_fine_liner", 40.0)
	_check("sees the host holding the Fine Liner", saw)
	# 2. Stand still and get painted out.
	_place(GUEST_SPOT, HOST_SPOT)
	player.set_physics_process(false)
	var died := await _until(func(): return player.is_dead(), 25.0)
	_check("painted out by the host", died)
	player.set_physics_process(true)
	await _wait(0.4)
	var hud = controller.hud
	_check("death screen shown", hud._respawn.visible)
	var left: float = controller.local_respawn_time_left()
	_check("3 second countdown", left > 0.5 and left <= NetworkSession.RESPAWN_SECONDS, "%.1f" % left)
	_check("death screen names the killer", controller.killed_by_name == host.display_name, controller.killed_by_name)
	# 3. Spectating the killer, third person then first person.
	var cam := _current_camera()
	_check("spectator camera is current", cam != null and cam.name == "SpectatorCamera")
	_check("spectating the killer", controller.spectate_name() == host.display_name, controller.spectate_name())
	var head := host.global_position + Vector3(0, 1.55, 0)
	_check("third person behind the killer", cam.global_position.distance_to(head) > 1.0 and cam.global_position.distance_to(head) < 5.0,
		"%.2f m" % cam.global_position.distance_to(head))
	await _shot("death_third_person")
	await _key(KEY_V)
	await _wait(0.2)
	_check("V switches to first person", controller.spectate_first_person())
	var eye := host.global_position + Vector3(0, 1.6, 0)
	_check("first person at the killer's eyes", cam.global_position.distance_to(eye) < 0.25, "%.2f m" % cam.global_position.distance_to(eye))
	_check("first person hides their body", not host.get_node("Visual").visible)
	_check("first person shows their Fine Liner", cam._view_gun_power == "two_shot", str(cam._view_gun_power))
	await _shot("death_first_person")
	# 4. Respawn after 3 s: own camera back, body visible again.
	var respawned := await _until(func(): return not player.is_dead(), NetworkSession.RESPAWN_SECONDS + 4.0)
	_check("respawned", respawned)
	await _wait(0.3)
	_check("own camera current again", _current_camera() == player.get_node("Camera"))
	_check("death screen hidden", not hud._respawn.visible)
	_check("killer's body visible again", host.get_node("Visual").visible)
	_check("first person choice kept for next time", controller.spectate_first_person())
	# 5. The host trades the 2 Shot away: their gun goes back to the blaster.
	var traded := await _until(func(): return str(host.get_meta("gun_model", "")) == "paint_blaster", 25.0)
	_check("sees the host's gun go back after the trade", traded)
	await _wait(2.0)


# ============================================================================
# SURVIVAL
# ============================================================================

func _survival_host() -> void:
	var hud = controller.hud
	_check("status shows players alive", hud._enemies_label.text.begins_with("3 ALIVE"), hud._enemies_label.text)
	var pause = game.get_node("PauseMenu")
	await _key(KEY_ESCAPE)
	_check("Esc opens the pause menu", pause.is_open() and player.is_paused())
	await _key(KEY_ESCAPE)
	_check("Esc again resumes", not pause.is_open() and not player.is_paused())
	await _claim_power("two_shot")
	_place(HOST_SPOT, GUEST_SPOT)
	await _wait(1.5)
	await _shot("survival_hud")
	var guest := _remote_near(GUEST_SPOT)
	var killed := await _shoot_at(guest, func(): return not guest.alive, 12.0)
	_check("paints out the guest", killed)
	await _wait(0.4)
	_check("status counts down", hud._enemies_label.text.begins_with("2 ALIVE"), hud._enemies_label.text)
	# Give the guest time to look around its death screen, then end the round.
	await _wait(3.0)
	var mate := _remote_near(MATE_SPOT)
	_place(HOST_SPOT, mate.global_position)
	var last := await _shoot_at(mate, func(): return not mate.alive, 12.0)
	_check("paints out the last opponent", last)
	var ended := await _until(func(): return controller.ended, 5.0)
	_check("round ends with one player standing", ended)
	_check("ending says who won", hud._end_title.text.ends_with("WINS"), hud._end_title.text)
	await _wait(1.2)
	_check("next round countdown shown", hud._end_body.text.contains("NEXT ROUND"), hud._end_body.text)
	_check("pause menu disabled after the end", not pause._enabled)
	await _shot("survival_end")
	await _next_round()


func _survival_guest() -> void:
	_place(GUEST_SPOT, HOST_SPOT)
	player.set_physics_process(false)
	var died := await _until(func(): return player.is_dead(), 45.0)
	_check("painted out", died)
	player.set_physics_process(true)
	await _wait(0.4)
	var hud = controller.hud
	_check("survival death screen shown", hud._death.visible)
	_check("one life: no respawn countdown", hud._death._countdown.text == "OUT UNTIL THE NEXT ROUND", hud._death._countdown.text)
	var host := _remote_near(HOST_SPOT)
	_check("spectating the killer", controller.spectate_name() == host.display_name, controller.spectate_name())
	_check("crosshair hidden while spectating", not hud._crosshair.visible)
	await _key(KEY_V)
	await _wait(0.2)
	_check("V switches to first person", controller.spectate_first_person())
	await _shot("survival_death")
	var ended := await _until(func(): return controller.ended, 25.0)
	_check("round ends for the spectator too", ended)
	_check("death screen gives way to the ending", await _until(func(): return not hud._death.visible, 1.0))
	await _next_round()


func _survival_mate() -> void:
	_place(MATE_SPOT, HOST_SPOT)
	player.set_physics_process(false)
	var died := await _until(func(): return player.is_dead(), 60.0)
	_check("painted out last", died)
	var ended := await _until(func(): return controller.ended, 5.0)
	_check("round ends", ended)
	await _next_round()


## After the 10 s intermission the server starts the next round by itself and
## the match scene reloads.
func _next_round() -> void:
	# Compare by instance id: the old controller is freed when the scene
	# reloads, and a lambda must not hold on to a freed object.
	var old_id: int = controller.get_instance_id()
	var next := await _until(func():
		return current_scene != null and current_scene.has_node("OnlineMatchController") \
			and current_scene.get_node("OnlineMatchController").get_instance_id() != old_id, NetworkSession.INTERMISSION_SECONDS + 8.0)
	_check("next round starts by itself", next)
	if next:
		await _wait(1.0)
		controller = current_scene.get_node("OnlineMatchController")
		_check("next round: everyone alive again", not current_scene.get_node("Player").is_dead() and not controller.ended)


func _finish() -> void:
	print("[%s] RESULT %d passed, %d failed" % [role, _passed, _failed])
	ns.disconnect_game()
	await _wait(0.3)
	quit(1 if _failed > 0 else 0)
