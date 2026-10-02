extends Node

## Human-only online match controller used by both Team Deathmatch and
## Survival. NetworkSession remains alive across scenes and owns match truth;
## this controller turns network events into visible actors and HUD updates.
##
## The HUD is drawn by the overhaul's screens: Team Deathmatch uses
## scripts/ui/tdm_hud.gd (score pill, Tab scoreboard, death screen, result
## screen) and Survival uses scripts/hud.gd. Both only DRAW; every number they
## show comes from this controller or from the local player. Both modes get the
## Esc pause menu (scripts/ui/pause_menu.gd).
##
## WHILE YOU WAIT TO RESPAWN (TDM)
## The server brings you back NetworkSession.RESPAWN_SECONDS after you are
## painted out. Meanwhile this controller:
##   - points a spectator camera (scripts/spectator_camera.gd) at a living
##     teammate, first or third person (Q / E to switch teammate, V to switch
##     view - or the death screen's buttons);
##   - remembers which gun you pick on the death screen's loadout (keys 1-5),
##     and hands it to the player when the server respawns you.

const Projectile = preload("res://scripts/projectile.gd")
const RemotePlayer = preload("res://scripts/net/remote_player.gd")
const RemoteLook = preload("res://scripts/visual/remote_look.gd")
const UITheme = preload("res://scripts/ui/ui_theme.gd")
const SurvivalHudScript = preload("res://scripts/hud.gd")
const TdmHudScript = preload("res://scripts/ui/tdm_hud.gd")
const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")
const SpectatorCameraScript = preload("res://scripts/spectator_camera.gd")
const Weapons = preload("res://scripts/weapons.gd")
const MATCH_SECONDS := 600.0
const RED := UITheme.TEAM_RED
const BLUE := UITheme.TEAM_BLUE

var game
var local_player
var game_mode := "TEAM_DEATH_MATCH"
## The local player's team: "RED"/"BLUE" in TDM, their peer id in Survival.
var session_team := ""
## Lobby records. The TDM scoreboard reads name, team, kills, deaths and
## assists from these, and `is_local` marks your own row.
var players: Array[Dictionary] = []
var actors: Dictionary = {}
var scores := {"RED": 0, "BLUE": 0}
var stats: Dictionary = {}
var alive: Dictionary = {}
var remaining := MATCH_SECONDS
var ended := false
## The HUD node: tdm_hud.gd or hud.gd. Untyped because update_clock() and
## friends are this project's functions, not CanvasLayer's.
var hud = null
var _send_accumulator := 0.0
var _refresh_timer := 0.0
## Time (in Time.get_ticks_msec() milliseconds) the server will respawn the
## local player, so the HUD can count down. 0 while alive.
var _local_respawn_at := 0
var pause_menu = null

## The gun picked on the death screen; equipped at the next respawn. Everyone
## starts with the Brush Rifle.
var chosen_weapon := Weapons.BRUSH_RIFLE
## Who painted you out last, for the death screen.
var killed_by_name := ""
var killed_by_color := Color.WHITE
## The spectator camera while you are dead in TDM, otherwise null.
var _spectator = null
## First or third person. Kept between deaths, so your choice sticks.
var _spectate_mode := SpectatorCameraScript.THIRD_PERSON


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
		# Dress the remote player as a Canvas Runner in their own outfit.
		RemoteLook.dress(actor, record, _team_color_for(record))
		actors[peer_id] = actor

	NetworkSession.remote_transform_received.connect(_on_remote_transform)
	NetworkSession.remote_shot_received.connect(_on_remote_shot)
	NetworkSession.health_changed.connect(_on_health_changed)
	NetworkSession.player_eliminated.connect(_on_player_eliminated)
	NetworkSession.player_respawned.connect(_on_player_respawned)
	NetworkSession.score_changed.connect(_on_score_changed)
	NetworkSession.match_finished.connect(_on_match_finished)
	NetworkSession.server_left.connect(_on_server_left)
	_build_hud()


func _process(delta: float) -> void:
	if ended:
		if game_mode == "SURVIVAL" and Input.is_action_just_pressed("restart"):
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
	# Which gun fired it, so the copy flies and looks the same as on the
	# shooter's screen (pellets, arc, bolt size). A server that does not pass
	# the gun along yet sends no "weapon" key: that reads as the Brush Rifle.
	var weapon_index := int(shot_data.get("weapon", Weapons.BRUSH_RIFLE))
	var weapon := Weapons.get_weapon(weapon_index)
	RemoteLook.set_weapon(shooter, weapon_index)
	var pellets := maxi(int(weapon.pellets), 1)
	for i in pellets:
		var glob := Node3D.new()
		glob.set_script(Projectile)
		glob.damage = float(shot_data.get("damage", 22.0))
		glob.speed = float(shot_data.get("speed", 90.0))
		glob.splash_radius = float(shot_data.get("splash_radius", 0.0))
		glob.splash_mult = float(shot_data.get("splash_mult", 0.0))
		glob.color = shot_data.get("color", Color.WHITE)
		Weapons.apply_to_shot(glob, weapon)
		# Only a picture of their shot: the shooter's own game reports its hits.
		glob.can_deal_damage = false
		glob.configure_tdm(shooter, str(shooter.get("tdm_team")))
		game.add_child(glob)
		var shot_direction := direction
		if pellets > 1:
			shot_direction = Weapons.spread_direction(direction, float(weapon.spread))
		glob.setup(origin, shot_direction, true)
	RemoteLook.on_fire(shooter)
	if _spectator != null and _spectator.target == shooter:
		_spectator.on_target_fired()


func _on_health_changed(peer_id: int, next_health: float) -> void:
	var actor = actors.get(peer_id)
	if not is_instance_valid(actor):
		return
	if peer_id == NetworkSession.local_peer_id():
		local_player.apply_network_health(next_health)
	else:
		actor.set_network_health(next_health)


func _on_player_eliminated(victim_peer_id: int, attacker_peer_id: int) -> void:
	alive[victim_peer_id] = false
	var victim = actors.get(victim_peer_id)
	if victim_peer_id == NetworkSession.local_peer_id():
		_local_respawn_at = Time.get_ticks_msec() + int(NetworkSession.RESPAWN_SECONDS * 1000.0)
		var killer := _record_for(attacker_peer_id)
		killed_by_name = str(killer.get("name", ""))
		killed_by_color = _team_color_for(killer)
		if game_mode == "TEAM_DEATH_MATCH" and not ended:
			_start_spectating()
	elif is_instance_valid(victim):
		victim.eliminate()
		# The teammate you were watching was painted out: move on to another.
		if _spectator != null and _spectator.target == victim:
			spectate_step(1)
	var attacker_name := str(_record_for(attacker_peer_id).get("name", "Player"))
	var victim_name := str(_record_for(victim_peer_id).get("name", "Player"))
	if game_mode == "TEAM_DEATH_MATCH":
		hud.add_feed_entry(attacker_name, _team_color_for(_record_for(attacker_peer_id)),
			victim_name, _team_color_for(_record_for(victim_peer_id)))
	else:
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
		# Equip the gun picked on the death screen, if it changed.
		if int(local_player.weapon_index) != chosen_weapon:
			local_player.set_weapon(chosen_weapon)
		local_player.tdm_respawn(at)
	else:
		actor.respawn(at)
	alive[peer_id] = true
	_refresh_scores()


func _on_score_changed(next_scores: Dictionary, next_stats: Dictionary) -> void:
	scores = next_scores.duplicate(true)
	stats = next_stats.duplicate(true)
	# Copy the server's kills/deaths into the lobby records the scoreboard
	# reads. The server does not track assists, so those stay 0.
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
	pause_menu = PauseMenuScript.new()
	pause_menu.name = "PauseMenu"
	game.add_child(pause_menu)
	pause_menu.setup(local_player, _return_to_menu)
	_refresh_scores()


## Pushes the live scores into the HUD: the score pill (and the scoreboard, if
## it is open) in TDM, the players-alive count in Survival.
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
# SPECTATING AND LOADOUT (TDM, while you wait to respawn)
# ============================================================================

## Keys while you are painted out: Q / E switch teammate, V switches first /
## third person, 1-5 pick a gun. _unhandled_input only sees keys nothing else
## used (the pause menu takes Esc first).
func _unhandled_input(event: InputEvent) -> void:
	if ended or game_mode != "TEAM_DEATH_MATCH" or not local_player.is_dead():
		return
	if pause_menu != null and pause_menu.is_open():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).physical_keycode
	match key:
		KEY_Q:
			spectate_step(-1)
		KEY_E:
			spectate_step(1)
		KEY_V:
			toggle_spectate_view()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			pick_weapon(key - KEY_1)
		_:
			return
	get_viewport().set_input_as_handled()


## The gun to respawn with. Nothing changes until the respawn.
func pick_weapon(index: int) -> void:
	chosen_weapon = posmod(index, Weapons.count())


## Living teammates you can watch, in lobby order.
func _spectate_candidates() -> Array:
	var found: Array = []
	for record in players:
		var actor = actors.get(int(record.get("peer_id", 0)))
		if actor == null or actor == local_player or not is_instance_valid(actor):
			continue
		if str(actor.get("tdm_team")) == session_team and bool(actor.get("alive")):
			found.append(actor)
	return found


func spectate_choices() -> int:
	return _spectate_candidates().size()


func _start_spectating() -> void:
	if _spectator == null:
		_spectator = Camera3D.new()
		_spectator.set_script(SpectatorCameraScript)
		_spectator.name = "SpectatorCamera"
		_spectator.death_spot = local_player.global_position
		game.add_child(_spectator)
	var choices := _spectate_candidates()
	_spectator.follow(choices[0] if not choices.is_empty() else null, _spectate_mode)


func _stop_spectating() -> void:
	if _spectator != null:
		_spectator.queue_free()
		_spectator = null


## Watch the next (+1) or previous (-1) living teammate.
func spectate_step(direction: int) -> void:
	if _spectator == null:
		return
	var choices := _spectate_candidates()
	if choices.is_empty():
		_spectator.follow(null, _spectate_mode)
		return
	var at := choices.find(_spectator.target)
	var next := 0 if at < 0 else posmod(at + direction, choices.size())
	_spectator.follow(choices[next], _spectate_mode)


func toggle_spectate_view() -> void:
	_spectate_mode = SpectatorCameraScript.FIRST_PERSON if _spectate_mode == SpectatorCameraScript.THIRD_PERSON else SpectatorCameraScript.THIRD_PERSON
	if _spectator != null:
		_spectator.set_mode(_spectate_mode)


## What the death screen shows: the watched teammate's name ("" if nobody).
func spectate_name() -> String:
	if _spectator == null or _spectator.target == null or not is_instance_valid(_spectator.target):
		return ""
	if not bool(_spectator.target.get("alive")):
		return ""
	return str(_spectator.target.get("display_name"))


func spectate_color() -> Color:
	return UITheme.team_color(session_team)


func spectate_first_person() -> bool:
	return _spectate_mode == SpectatorCameraScript.FIRST_PERSON


## Seconds until the local player respawns, or 0 when no respawn is pending.
## Read by the TDM HUD's respawn overlay.
func local_respawn_time_left() -> float:
	if _local_respawn_at == 0:
		return 0.0
	return maxf(float(_local_respawn_at - Time.get_ticks_msec()) / 1000.0, 0.0)


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
		var angle := TAU * float(index) / float(maxi(players.size(), 1))
		return Vector3(cos(angle) * 28.0, 1.2, sin(angle) * 28.0)
	var team := str(record.get("team", "RED"))
	var team_index := 0
	for entry in players:
		if str(entry.get("team", "")) == team:
			if int(entry.get("peer_id", 0)) == peer_id:
				break
			team_index += 1
	var x := -34.0 if team == "RED" else 34.0
	return Vector3(x, 1.2, float((team_index % 5) - 2) * 3.0)
