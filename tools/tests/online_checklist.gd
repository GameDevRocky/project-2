extends SceneTree

## ============================================================================
## ONLINE CHECKLIST - a development tool, not part of the game.
## ============================================================================
##
## Plays a real online Team Deathmatch on THIS computer: a local copy of the
## dedicated server plus three test clients, each driving the real menu (mode
## select -> online setup -> lobby) and the real match. Each client prints
## PASS/FAIL lines. tools/tests/run_online_checklist.sh starts everything:
##
##   godot --headless --path . -- --server                       (the server)
##   godot --headless --path . --script res://tools/tests/online_checklist.gd -- --role=host  --run=ID
##   godot --headless --path . --script res://tools/tests/online_checklist.gd -- --role=guest --run=ID
##   godot --headless --path . --script res://tools/tests/online_checklist.gd -- --role=mate  --run=ID
##
## host  = RED, creates the lobby and starts the match.
## guest = BLUE, joins with the code the host writes to user://.
## mate  = RED, joins too, so RED has a teammate to spectate.
##
## TEST-ONLY shortcuts: the clients connect to ws://127.0.0.1:9080 instead of
## the live server (by handing NetworkSession a socket before the menu asks for
## one), players are teleported to fixed spots, and aim is set directly before
## the real fire button is pressed.

const LOCAL_URL := "ws://127.0.0.1:9080"
const CODE_FILE := "user://online_checklist_code.txt"
const PLAYERS := 3

var role := "host"
var run_id := "0"
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


func _run() -> void:
	ns = root.get_node("NetworkSession")
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
	menu._select_tdm()
	await process_frame
	_check("online setup page", menu.current_screen == "online_setup" and is_instance_valid(menu.join_code_edit))

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
	var full := await _until(func(): return ns.lobby_roster().size() >= PLAYERS, 30.0)
	_check("all players joined", full, str(ns.lobby_roster().size()))
	await _wait(0.5)
	_check("fill label counts teams", menu.fill_label.text.contains("RED  2") and menu.fill_label.text.contains("BLUE  1"), menu.fill_label.text)
	_check("host is host", ns.is_host())
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


func _check_match_basics() -> void:
	var expected_team := "BLUE" if role == "guest" else "RED"
	_check("team", controller.session_team == expected_team, controller.session_team)
	_check("TDM HUD", game.has_node("TDMHud"))
	var remotes := get_nodes_in_group("remote_players")
	_check("two remote players", remotes.size() == PLAYERS - 1, str(remotes.size()))
	for remote in remotes:
		var visual = remote.get_node_or_null("Visual")
		var blaster = remote.get_node_or_null("AimPivot/Blaster")
		_check("remote dressed as runner", visual != null and visual.model != null, remote.name)
		_check("remote gun on aim pivot", blaster != null, remote.name)
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
## button until `done` is true (or `seconds` pass).
func _shoot_at(target: Node3D, done: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var camera: Camera3D = player.get_node("Camera")
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
	return bool(done.call())


func _remote_for(team: String) -> Node3D:
	for remote in get_nodes_in_group("remote_players"):
		if str(remote.get("tdm_team")) == team:
			return remote
	return null


## HOST (RED): paint out the guest, then stand still and get painted out.
func _host_script() -> void:
	_place(Vector3(0, 1.2, -6), Vector3(0, 1.2, 6))
	await _wait(2.0)
	var guest := _remote_for("BLUE")
	var killed := await _shoot_at(guest, func(): return not guest.alive, 8.0)
	_check("shots eliminate the guest", killed)
	await _wait(0.5)
	_check("RED scored", int(controller.scores.get("RED", 0)) == 1, str(controller.scores))
	_check("host kill counted", controller._local_stat("kills") == 1)
	_check("feed shows the elimination", controller.hud._feed.get_child_count() >= 1)
	var back := await _until(func(): return guest.alive and guest.visible, NetworkSession.RESPAWN_SECONDS + 3.0)
	_check("guest respawns for everyone", back)
	# Now stand still in the open and wait to be painted out.
	_place(Vector3(0, 1.2, -6), Vector3(0, 1.2, 6))
	player.set_physics_process(false)
	var died := await _until(func(): return player.is_dead(), 20.0)
	_check("host painted out by guest", died)
	await _wait(0.3)
	var left: float = controller.local_respawn_time_left()
	_check("respawn countdown running", left > 0.0 and left <= NetworkSession.RESPAWN_SECONDS, "%.1f" % left)
	_check("respawn overlay shown", controller.hud._respawn.visible)
	player.set_physics_process(true)
	var respawned := await _until(func(): return not player.is_dead(), NetworkSession.RESPAWN_SECONDS + 3.0)
	_check("host respawned", respawned)
	_check("respawn overlay hidden", await _until(func(): return not controller.hud._respawn.visible, 1.0))


## GUEST (BLUE): stand still and get painted out, then paint out the host.
func _guest_script() -> void:
	_place(Vector3(0, 1.2, 6), Vector3(0, 1.2, -6))
	player.set_physics_process(false)
	var died := await _until(func(): return player.is_dead(), 20.0)
	_check("guest painted out by host", died)
	player.set_physics_process(true)
	var respawned := await _until(func(): return not player.is_dead(), NetworkSession.RESPAWN_SECONDS + 3.0)
	_check("guest respawned", respawned)
	await _wait(1.5)
	_place(Vector3(0, 1.2, 6), Vector3(0, 1.2, -6))
	var host := _remote_for("RED")
	for remote in get_nodes_in_group("remote_players"):
		if str(remote.get("tdm_team")) == "RED" and remote.global_position.distance_to(Vector3(0, 1.2, -6)) < 2.0:
			host = remote
	var killed := await _shoot_at(host, func(): return not host.alive, 10.0)
	_check("shots eliminate the host", killed)
	await _wait(0.5)
	_check("BLUE scored", int(controller.scores.get("BLUE", 0)) == 1, str(controller.scores))
	await _wait(NetworkSession.RESPAWN_SECONDS + 2.0)


## MATE (RED): stays at spawn as a teammate for the host.
func _mate_script() -> void:
	player.set_physics_process(false)
	await _wait(10.0 + NetworkSession.RESPAWN_SECONDS * 2.0)
	_check("mate saw both eliminations", int(controller.scores.get("RED", 0)) + int(controller.scores.get("BLUE", 0)) == 2,
		str(controller.scores))


func _finish() -> void:
	print("[%s] RESULT %d passed, %d failed" % [role, _passed, _failed])
	ns.disconnect_game()
	await _wait(0.3)
	quit(1 if _failed > 0 else 0)
