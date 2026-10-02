extends Node

## Human-only online match controller used by both Team Deathmatch and
## Survival. NetworkSession remains alive across scenes and owns match truth;
## this controller turns network events into visible actors and HUD updates.
##
## The rules are Rocklyn's online branch: TDM rounds to 25 eliminations with
## random balanced teams and a 3 second respawn, Survival as last player
## standing, 100 shield + 100 health, flying power balls, trade stations, and a
## 10 second intermission before the next round starts by itself.
##
## The look is the overhaul's: Team Deathmatch draws with
## scripts/ui/tdm_hud.gd (score pill, team leaderboards, kill feed, Tab
## scoreboard, death screen, result screen) and Survival with scripts/hud.gd.
## Both only DRAW; every number they show comes from this controller or from
## the local player. Other players are dressed as Canvas Runners
## (scripts/visual/remote_look.gd) holding the gun of the power they carry.
## Esc opens the pause menu (scripts/ui/pause_menu.gd) in both modes.
##
## WHILE YOU ARE PAINTED OUT
## You watch the player who painted you out; if they go down too, whoever got
## them (Rocklyn's killer chain). scripts/spectator_camera.gd draws it, from
## their eyes or over their shoulder - V switches, and the choice sticks.

const Projectile = preload("res://scripts/projectile.gd")
const RemotePlayer = preload("res://scripts/net/remote_player.gd")
const FlyingPowerBall = preload("res://scripts/flying_power_ball.gd")
const RemoteLook = preload("res://scripts/visual/remote_look.gd")
const UITheme = preload("res://scripts/ui/ui_theme.gd")
const SurvivalHudScript = preload("res://scripts/hud.gd")
const TdmHudScript = preload("res://scripts/ui/tdm_hud.gd")
const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")
const SpectatorCameraScript = preload("res://scripts/spectator_camera.gd")
const MATCH_SECONDS := 600.0
const INTERMISSION_SECONDS := 10.0
const TDM_KILL_LIMIT := 25
const RED := UITheme.TEAM_RED
const BLUE := UITheme.TEAM_BLUE
const SURVIVAL_SPAWNS := [
	Vector3(-58.0, 1.2, -58.0), Vector3(58.0, 1.2, 58.0),
	Vector3(58.0, 1.2, -58.0), Vector3(-58.0, 1.2, 58.0),
	Vector3(0.0, 1.2, -62.0), Vector3(0.0, 1.2, 62.0),
	Vector3(62.0, 1.2, 0.0), Vector3(-62.0, 1.2, 0.0),
	Vector3(58.0, 1.2, -12.0), Vector3(-58.0, 1.2, 12.0),
	Vector3(-58.0, 1.2, -12.0), Vector3(58.0, 1.2, 12.0),
	Vector3(38.0, 1.2, -58.0), Vector3(-38.0, 1.2, 58.0),
	Vector3(-38.0, 1.2, -58.0), Vector3(38.0, 1.2, 58.0),
	Vector3(58.0, 1.2, -48.0), Vector3(-58.0, 1.2, 48.0),
	Vector3(-58.0, 1.2, -48.0), Vector3(58.0, 1.2, 48.0),
]

var game
var local_player
var game_mode := "TEAM_DEATH_MATCH"
## The local player's team: "RED"/"BLUE" in TDM, their peer id in Survival.
var session_team := ""
## Lobby records. The leaderboards and Tab scoreboard read name, team, kills
## and deaths from these, and `is_local` marks your own row.
var players: Array[Dictionary] = []
var actors: Dictionary = {}
var snitch_actors: Dictionary = {}
var scores := {"RED": 0, "BLUE": 0}
var stats: Dictionary = {}
var alive: Dictionary = {}
var remaining := MATCH_SECONDS
var ended := false
## The HUD node: tdm_hud.gd or hud.gd. Untyped because update_clock() and
## friends are this project's functions, not CanvasLayer's.
var hud = null
var pause_menu = null
## Who painted you out last, for the death screen.
var killed_by_name := ""
var killed_by_color := Color.WHITE
var _send_accumulator := 0.0
var _refresh_timer := 0.0
var _rematch_remaining := 0.0
var _killer_of: Dictionary = {}
var _spectated_peer_id := 0
## The spectator camera while you are dead, otherwise null.
var _spectator = null
## First or third person. Kept between deaths, so your choice sticks.
var _spectate_mode := SpectatorCameraScript.THIRD_PERSON
## Time (in Time.get_ticks_msec() milliseconds) the server will respawn the
## local player in TDM, so the death screen can count down. 0 while alive.
var _local_respawn_at := 0


func start_match(owner_game, local_actor, lobby_records: Array[Dictionary], _team: String) -> void:
	game = owner_game
	local_player = local_actor
	game_mode = NetworkSession.current_game_mode
	players = lobby_records.duplicate(true)
	var local_id := NetworkSession.local_peer_id()
	var local_record := _record_for(local_id)
	session_team = _combat_team(local_record)
	local_player.tdm_team = session_team
	local_player.add_to_group("tdm_combatants")
	local_player.global_position = _spawn_for(local_record)
	local_player.apply_network_vitals(float(local_record.get("health", 100.0)), float(local_record.get("shield", 100.0)))
	local_player.set_network_power(str(local_record.get("power", "")), bool(local_record.get("invisible", false)))
	actors[local_id] = local_player

	for index in players.size():
		var record := players[index]
		var peer_id := int(record.get("peer_id", 0))
		players[index]["kills"] = 0
		players[index]["deaths"] = 0
		players[index]["assists"] = 0
		players[index]["is_local"] = peer_id == local_id
		stats[peer_id] = {"kills": 0, "deaths": 0}
		alive[peer_id] = true
		if peer_id == local_id:
			continue
		var actor := CharacterBody3D.new()
		actor.set_script(RemotePlayer)
		actor.name = "RemotePlayer_%d" % peer_id
		actor.setup(record, _spawn_for(record), _combat_team(record))
		game.add_child(actor)
		# Dress them as a Canvas Runner in their own outfit, holding the gun of
		# the power they carry.
		RemoteLook.dress(actor, record, _team_color_for(record))
		actors[peer_id] = actor

	NetworkSession.remote_transform_received.connect(_on_remote_transform)
	NetworkSession.remote_shot_received.connect(_on_remote_shot)
	NetworkSession.vitals_changed.connect(_on_vitals_changed)
	NetworkSession.power_changed.connect(_on_power_changed)
	NetworkSession.snitch_snapshot_changed.connect(_on_snitch_snapshot)
	NetworkSession.player_eliminated.connect(_on_player_eliminated)
	NetworkSession.player_respawned.connect(_on_player_respawned)
	NetworkSession.player_left_match.connect(_on_player_left_match)
	NetworkSession.score_changed.connect(_on_score_changed)
	NetworkSession.match_finished.connect(_on_match_finished)
	NetworkSession.match_abandoned.connect(_on_match_abandoned)
	NetworkSession.match_started.connect(_on_next_round_started)
	NetworkSession.server_left.connect(_on_server_left)
	_build_hud()
	_on_snitch_snapshot(NetworkSession.snitches)


func _process(delta: float) -> void:
	if ended:
		# Intermission: the next round starts by itself (the server sends
		# match_started again). R leaves for the main menu instead.
		_rematch_remaining = maxf(_rematch_remaining - delta, 0.0)
		hud.set_next_round(_rematch_remaining)
		if Input.is_action_just_pressed("restart"):
			_return_to_menu()
		return
	_send_accumulator += delta
	if _send_accumulator >= 0.05:
		_send_accumulator = 0.0
		NetworkSession.report_local_transform(
			local_player.global_position,
			local_player.rotation.y,
			local_player.network_pitch(),
			local_player.velocity)
	if game_mode == "TEAM_DEATH_MATCH":
		remaining = maxf(remaining - delta, 0.0)
		hud.update_clock(remaining)
		# TAB is HELD, not toggled, and checked every frame so the board
		# appears the instant the key goes down. Its rows refresh four times a
		# second while it is open.
		var holding_tab := Input.is_key_pressed(KEY_TAB)
		hud.set_scoreboard_visible(holding_tab)
		_refresh_timer += delta
		if _refresh_timer >= 0.25:
			_refresh_timer = 0.0
			if holding_tab:
				hud.refresh_scoreboard()


func _on_remote_transform(peer_id: int, position: Vector3, yaw: float, pitch: float, velocity: Vector3) -> void:
	var actor = actors.get(peer_id)
	if is_instance_valid(actor) and actor.has_method("receive_network_transform"):
		actor.receive_network_transform(position, yaw, pitch, velocity)


func _on_remote_shot(peer_id: int, origin: Vector3, direction: Vector3, shot_data: Dictionary) -> void:
	var shooter = actors.get(peer_id)
	if not is_instance_valid(shooter):
		return
	var glob := Node3D.new()
	glob.set_script(Projectile)
	glob.damage = float(shot_data.get("damage", 22.0))
	glob.speed = float(shot_data.get("speed", 90.0))
	glob.splash_radius = float(shot_data.get("splash_radius", 0.0))
	glob.splash_mult = float(shot_data.get("splash_mult", 0.0))
	glob.projectile_kind = str(shot_data.get("projectile_kind", "bullet"))
	glob.allow_self_damage = glob.projectile_kind == "rocket"
	glob.color = shot_data.get("color", Color.WHITE)
	# Only a picture of their shot: the shooter's own game reports its hits.
	glob.can_deal_damage = false
	glob.configure_tdm(shooter, str(shooter.get("tdm_team")))
	game.add_child(glob)
	glob.setup(origin, direction, true)
	RemoteLook.on_fire(shooter)
	if _spectator != null and _spectator.target == shooter:
		_spectator.on_target_fired()


func _on_vitals_changed(peer_id: int, next_health: float, next_shield: float) -> void:
	var actor = actors.get(peer_id)
	if not is_instance_valid(actor):
		return
	if peer_id == NetworkSession.local_peer_id():
		local_player.apply_network_vitals(next_health, next_shield)
	else:
		actor.set_network_vitals(next_health, next_shield)


func _on_power_changed(peer_id: int, power_id: String, invisible: bool) -> void:
	var actor = actors.get(peer_id)
	if not is_instance_valid(actor):
		return
	for index in players.size():
		if int(players[index].get("peer_id", 0)) == peer_id:
			var record := (players[index] as Dictionary).duplicate(true)
			record.power = power_id
			record.invisible = invisible
			players[index] = record
			break
	if peer_id == NetworkSession.local_peer_id():
		local_player.set_network_power(power_id, invisible)
	else:
		actor.set_power_state(power_id, invisible)
		# Their gun changes to the power's model, so everyone can see it.
		RemoteLook.set_power_gun(actor, str(actor.get("current_power")))


func _on_snitch_snapshot(snapshot: Dictionary) -> void:
	for id_value in snapshot.keys():
		var id := int(id_value)
		var record: Dictionary = snapshot[id_value]
		var ball = snitch_actors.get(id)
		if not is_instance_valid(ball):
			ball = StaticBody3D.new()
			ball.set_script(FlyingPowerBall)
			ball.name = "PowerBall_%d" % id
			ball.setup(record)
			game.add_child(ball)
			snitch_actors[id] = ball
		else:
			ball.receive_snapshot(record)
	for id_value in snitch_actors.keys():
		var id := int(id_value)
		if not snapshot.has(id) and not snapshot.has(str(id)):
			var stale = snitch_actors[id]
			if is_instance_valid(stale):
				stale.queue_free()
			snitch_actors.erase(id)


func _on_player_eliminated(victim_peer_id: int, attacker_peer_id: int) -> void:
	alive[victim_peer_id] = false
	_killer_of[victim_peer_id] = attacker_peer_id
	var victim = actors.get(victim_peer_id)
	var local_id := NetworkSession.local_peer_id()
	if victim_peer_id != local_id and is_instance_valid(victim):
		victim.eliminate()
	if victim_peer_id == local_id:
		var killer := _record_for(attacker_peer_id)
		killed_by_name = str(killer.get("name", ""))
		killed_by_color = _team_color_for(killer)
		if game_mode == "TEAM_DEATH_MATCH":
			_local_respawn_at = Time.get_ticks_msec() + int(NetworkSession.RESPAWN_SECONDS * 1000.0)
		_begin_spectating(attacker_peer_id)
	elif _spectated_peer_id == victim_peer_id:
		# The player you were watching went down: follow whoever got them.
		_begin_spectating(attacker_peer_id)
	var attacker_name := str(_record_for(attacker_peer_id).get("name", "Player"))
	var victim_name := str(_record_for(victim_peer_id).get("name", "Player"))
	if game_mode == "TEAM_DEATH_MATCH":
		hud.add_feed_entry(attacker_name, _team_color_for(_record_for(attacker_peer_id)),
			victim_name, _team_color_for(_record_for(victim_peer_id)))
	elif victim_peer_id != local_id:
		# (Your own elimination is on your death screen instead.)
		hud.announce("%s ELIMINATED" % victim_name.to_upper(), "by %s" % attacker_name)
	_refresh_scores()


func _on_player_respawned(peer_id: int) -> void:
	var actor = actors.get(peer_id)
	if not is_instance_valid(actor):
		return
	var at := _spawn_for(_record_for(peer_id))
	if peer_id == NetworkSession.local_peer_id():
		_local_respawn_at = 0
		_stop_spectating()
		local_player.tdm_respawn(at)
	else:
		actor.respawn(at)
	alive[peer_id] = true
	_refresh_scores()


func _on_player_left_match(peer_id: int) -> void:
	var actor = actors.get(peer_id)
	actors.erase(peer_id)
	alive.erase(peer_id)
	stats.erase(peer_id)
	_killer_of.erase(peer_id)
	for index in range(players.size() - 1, -1, -1):
		if int(players[index].get("peer_id", 0)) == peer_id:
			players.remove_at(index)
	if is_instance_valid(actor):
		actor.queue_free()
	if _spectated_peer_id == peer_id:
		_spectated_peer_id = 0
		var fallback_id := _first_alive_remote_peer()
		if fallback_id != 0:
			_begin_spectating(fallback_id)
		elif _spectator != null:
			_spectator.follow(null, _spectate_mode)
	_refresh_scores()


func _on_score_changed(next_scores: Dictionary, next_stats: Dictionary) -> void:
	scores = next_scores.duplicate(true)
	stats = next_stats.duplicate(true)
	# Copy the server's kills/deaths into the records the leaderboards read.
	# The server does not track assists, so those stay 0.
	for index in players.size():
		var peer_id := int(players[index].get("peer_id", 0))
		var line: Dictionary = stats.get(peer_id, {})
		players[index]["kills"] = int(line.get("kills", 0))
		players[index]["deaths"] = int(line.get("deaths", 0))
	_refresh_scores()


func _on_match_finished(title: String, detail: String) -> void:
	if ended:
		return
	ended = true
	_local_respawn_at = 0
	_rematch_remaining = INTERMISSION_SECONDS
	if pause_menu != null:
		pause_menu.set_enabled(false)
	local_player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if game_mode == "TEAM_DEATH_MATCH":
		var winner_color := Color.WHITE
		if title.contains("RED"):
			winner_color = RED
		elif title.contains("BLUE"):
			winner_color = BLUE
		hud.show_result(title, winner_color, _local_stat("kills"), _local_stat("deaths"),
			_local_stat("assists"), _return_to_menu)
	else:
		hud.show_ending(title, detail + "\n\nPress R to return to the main menu.", Color.WHITE)
	hud.set_next_round(_rematch_remaining)


func _on_next_round_started(_mode: String, _roster: Array[Dictionary]) -> void:
	if ended:
		get_tree().change_scene_to_file("res://scenes/match.tscn")


func _on_match_abandoned(_detail: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_return_to_menu()


func _on_server_left() -> void:
	_on_match_finished("SERVER DISCONNECTED", "The online server stopped responding.")


func _return_to_menu() -> void:
	NetworkSession.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _build_hud() -> void:
	if game_mode == "TEAM_DEATH_MATCH":
		# HudScript.new() (rather than CanvasLayer.new() + set_script) so the
		# HUD's own _init() runs and builds its nodes.
		hud = TdmHudScript.new()
		hud.name = "TDMHud"
		game.add_child(hud)
		hud.setup(self, local_player, session_team)
	else:
		hud = CanvasLayer.new()
		hud.set_script(SurvivalHudScript)
		hud.name = "OnlineHUD"
		game.add_child(hud)
		hud.bind_player(local_player)
		hud.attach_controller(self)
	pause_menu = PauseMenuScript.new()
	pause_menu.name = "PauseMenu"
	game.add_child(pause_menu)
	pause_menu.setup(local_player, _return_to_menu)
	_refresh_scores()


## Pushes the live scores into the HUD: the score pill and leaderboards (and
## the scoreboard, if it is open) in TDM, the players-alive pill in Survival.
func _refresh_scores() -> void:
	if hud == null:
		return
	if game_mode == "TEAM_DEATH_MATCH":
		hud.refresh_scores()
		hud.refresh_scoreboard()
	else:
		var alive_count := 0
		for value in alive.values():
			if bool(value):
				alive_count += 1
		hud.set_status("SURVIVAL", "%d ALIVE  ·  LAST PLAYER STANDING" % alive_count)


# ============================================================================
# SPECTATING (while you are painted out)
# ============================================================================

## V switches first / third person while you are dead. _unhandled_input only
## sees keys nothing else used (the pause menu takes Esc first).
func _unhandled_input(event: InputEvent) -> void:
	if ended or not local_player.is_dead():
		return
	if pause_menu != null and pause_menu.is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_V:
		toggle_spectate_view()
		get_viewport().set_input_as_handled()


## Watches `requested_peer_id`, or - if they are down too - whoever got them
## (Rocklyn's killer chain). With nobody to watch, the camera circles above
## where you fell.
func _begin_spectating(requested_peer_id: int) -> void:
	var target_id := _resolve_spectate_target(requested_peer_id)
	var target = actors.get(target_id)
	var local_id := NetworkSession.local_peer_id()
	if target_id == local_id or not is_instance_valid(target):
		target_id = 0
		target = null
	_spectated_peer_id = target_id
	local_player.start_spectating()
	if _spectator == null:
		_spectator = Camera3D.new()
		_spectator.set_script(SpectatorCameraScript)
		_spectator.name = "SpectatorCamera"
		_spectator.death_spot = local_player.global_position
		game.add_child(_spectator)
	_spectator.follow(target, _spectate_mode)
	if game_mode == "SURVIVAL":
		hud.set_spectating(true)


func _stop_spectating() -> void:
	_spectated_peer_id = 0
	if _spectator != null:
		_spectator.queue_free()
		_spectator = null
	if game_mode == "SURVIVAL":
		hud.set_spectating(false)


func toggle_spectate_view() -> void:
	_spectate_mode = SpectatorCameraScript.FIRST_PERSON if _spectate_mode == SpectatorCameraScript.THIRD_PERSON else SpectatorCameraScript.THIRD_PERSON
	if _spectator != null:
		_spectator.set_mode(_spectate_mode)


## What the death screen shows: the watched player's name ("" if nobody).
func spectate_name() -> String:
	var target = actors.get(_spectated_peer_id)
	if _spectated_peer_id == 0 or not is_instance_valid(target) or not bool(target.get("alive")):
		return ""
	return str(target.get("display_name"))


func spectate_color() -> Color:
	return _team_color_for(_record_for(_spectated_peer_id))


func spectate_first_person() -> bool:
	return _spectate_mode == SpectatorCameraScript.FIRST_PERSON


## Seconds until the local player respawns. 0 when no respawn is pending;
## -1 in Survival, where being painted out lasts until the round ends.
func local_respawn_time_left() -> float:
	if game_mode == "SURVIVAL":
		return -1.0
	if _local_respawn_at == 0:
		return 0.0
	return maxf(float(_local_respawn_at - Time.get_ticks_msec()) / 1000.0, 0.0)


func _resolve_spectate_target(requested_peer_id: int) -> int:
	var candidate := requested_peer_id
	var visited := {}
	while candidate != 0 and not bool(alive.get(candidate, false)):
		if visited.has(candidate) or not _killer_of.has(candidate):
			return 0
		visited[candidate] = true
		candidate = int(_killer_of[candidate])
	return candidate


func _first_alive_remote_peer() -> int:
	var local_id := NetworkSession.local_peer_id()
	for peer_value in actors.keys():
		var peer_id := int(peer_value)
		if peer_id != local_id and bool(alive.get(peer_id, false)):
			return peer_id
	return 0


func _local_stat(key: String) -> int:
	return int(_record_for(NetworkSession.local_peer_id()).get(key, 0))


func _record_for(peer_id: int) -> Dictionary:
	for record in players:
		if int(record.get("peer_id", 0)) == peer_id:
			return record
	return {}


func _combat_team(record: Dictionary) -> String:
	if game_mode == "SURVIVAL":
		return str(record.get("peer_id", 0))
	return str(record.get("team", "RED"))


## The colour a player's team marks are drawn in: red or blue in TDM, and in
## Survival (everyone for themselves) a colour of their own.
func _team_color_for(record: Dictionary) -> Color:
	if game_mode == "SURVIVAL":
		var hue := fmod(float(int(record.get("peer_id", 0))) * 0.173, 1.0)
		return Color.from_hsv(hue, 0.62, 1.0)
	return UITheme.team_color(str(record.get("team", "RED")))


func _spawn_for(record: Dictionary) -> Vector3:
	var peer_id := int(record.get("peer_id", 0))
	var index := 0
	for entry in players:
		if int(entry.get("peer_id", 0)) == peer_id:
			break
		index += 1
	if game_mode == "SURVIVAL":
		return SURVIVAL_SPAWNS[index % SURVIVAL_SPAWNS.size()]
	var team := str(record.get("team", "RED"))
	var team_index := 0
	for entry in players:
		if str(entry.get("team", "")) == team:
			if int(entry.get("peer_id", 0)) == peer_id:
				break
			team_index += 1
	var row := team_index / 5
	var x := (-55.0 + row * 4.0) if team == "RED" else (55.0 - row * 4.0)
	return Vector3(x, 1.2, float((team_index % 5) - 2) * 4.0)
