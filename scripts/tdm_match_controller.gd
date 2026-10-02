extends Node

## Human-only online match controller used by both Team Deathmatch and
## Survival. NetworkSession remains alive across scenes and owns match truth;
## this controller turns network events into visible actors and HUD updates.

const Projectile = preload("res://scripts/projectile.gd")
const RemotePlayer = preload("res://scripts/net/remote_player.gd")
const FlyingPowerBall = preload("res://scripts/flying_power_ball.gd")
const HudScript = preload("res://scripts/hud.gd")
const MATCH_SECONDS := 600.0
const INTERMISSION_SECONDS := 10.0
const TDM_KILL_LIMIT := 25
const RED := Color("#FF627E")
const BLUE := Color("#58D7F2")
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
var players: Array[Dictionary] = []
var actors: Dictionary = {}
var snitch_actors: Dictionary = {}
var scores := {"RED": 0, "BLUE": 0}
var stats: Dictionary = {}
var alive: Dictionary = {}
var remaining := MATCH_SECONDS
var ended := false
var hud
var mode_label: Label
var score_label: Label
var timer_label: Label
var red_leaderboard: Label
var blue_leaderboard: Label
var spectate_label: Label
var _send_accumulator := 0.0
var _rematch_remaining := 0.0
var _killer_of: Dictionary = {}
var _spectated_peer_id := 0


func start_match(owner_game, local_actor, lobby_records: Array[Dictionary], _team: String) -> void:
	game = owner_game
	local_player = local_actor
	game_mode = NetworkSession.current_game_mode
	players = lobby_records.duplicate(true)
	var local_id := NetworkSession.local_peer_id()
	var local_record := _record_for(local_id)
	local_player.tdm_team = _combat_team(local_record)
	local_player.add_to_group("tdm_combatants")
	local_player.global_position = _spawn_for(local_record)
	local_player.apply_network_vitals(float(local_record.get("health", 100.0)), float(local_record.get("shield", 100.0)))
	local_player.set_network_power(str(local_record.get("power", "")), bool(local_record.get("invisible", false)))
	actors[local_id] = local_player

	for record in players:
		var peer_id := int(record.get("peer_id", 0))
		stats[peer_id] = {"kills": 0, "deaths": 0}
		alive[peer_id] = true
		if peer_id == local_id:
			continue
		var actor := CharacterBody3D.new()
		actor.set_script(RemotePlayer)
		actor.name = "RemotePlayer_%d" % peer_id
		actor.setup(record, _spawn_for(record), _combat_team(record))
		game.add_child(actor)
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
		_rematch_remaining = maxf(_rematch_remaining - delta, 0.0)
		timer_label.text = str(int(ceil(_rematch_remaining)))
		mode_label.text = "NEXT MATCH"
		if Input.is_action_just_pressed("restart"):
			NetworkSession.disconnect_game()
			get_tree().change_scene_to_file("res://scenes/main.tscn")
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
		timer_label.text = _format_time(remaining)


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
	glob.can_deal_damage = false
	glob.configure_tdm(shooter, str(shooter.get("tdm_team")))
	game.add_child(glob)
	glob.setup(origin, direction, true)


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
		_begin_spectating(attacker_peer_id)
	elif _spectated_peer_id == victim_peer_id:
		_begin_spectating(attacker_peer_id)
	var attacker_name := str(_record_for(attacker_peer_id).get("name", "Player"))
	var victim_name := str(_record_for(victim_peer_id).get("name", "Player"))
	hud.announce("%s ELIMINATED" % victim_name.to_upper(), "by %s" % attacker_name)
	_refresh_score_label()


func _on_player_respawned(peer_id: int) -> void:
	var actor = actors.get(peer_id)
	if not is_instance_valid(actor):
		return
	var at := _spawn_for(_record_for(peer_id))
	if peer_id == NetworkSession.local_peer_id():
		local_player.tdm_respawn(at)
		_spectated_peer_id = 0
		spectate_label.text = ""
		hud.set_spectating(false)
	else:
		actor.respawn(at)
	alive[peer_id] = true
	_refresh_score_label()


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
		else:
			local_player.stop_spectating()
			spectate_label.text = ""
			hud.set_spectating(false)
	_refresh_score_label()


func _on_score_changed(next_scores: Dictionary, next_stats: Dictionary) -> void:
	scores = next_scores.duplicate(true)
	stats = next_stats.duplicate(true)
	_refresh_score_label()


func _on_match_finished(title: String, detail: String) -> void:
	ended = true
	_rematch_remaining = INTERMISSION_SECONDS
	local_player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_ending(title, detail + "\n\nPress R to return to the main menu.", Color.WHITE)


func _on_next_round_started(_mode: String, _roster: Array[Dictionary]) -> void:
	if ended:
		get_tree().change_scene_to_file("res://scenes/match.tscn")


func _on_match_abandoned(_detail: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkSession.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_server_left() -> void:
	_on_match_finished("SERVER DISCONNECTED", "The online server stopped responding.")


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.set_script(HudScript)
	hud.name = "OnlineHUD"
	game.add_child(hud)
	hud.bind_player(local_player)
	hud.set_enemies_left(0)
	mode_label = _label("SURVIVAL  •  LAST PLAYER STANDING" if game_mode == "SURVIVAL" else "TEAM DEATHMATCH", Vector2(30, 18), Vector2(540, 34), 20)
	score_label = _label("", Vector2(770, 18), Vector2(480, 34), 20)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_label = _label("" if game_mode == "SURVIVAL" else "10:00", Vector2(565, 18), Vector2(150, 34), 22)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	red_leaderboard = _label("", Vector2(30, 62), Vector2(330, 230), 14)
	blue_leaderboard = _label("", Vector2(920, 62), Vector2(330, 230), 14)
	red_leaderboard.add_theme_color_override("font_color", RED)
	blue_leaderboard.add_theme_color_override("font_color", BLUE)
	blue_leaderboard.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spectate_label = _label("", Vector2(390, 650), Vector2(500, 34), 18)
	spectate_label.add_theme_color_override("font_color", Color("#FFE28D"))
	spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	red_leaderboard.visible = game_mode == "TEAM_DEATH_MATCH"
	blue_leaderboard.visible = game_mode == "TEAM_DEATH_MATCH"
	_refresh_score_label()


func _label(text_value: String, at: Vector2, label_size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = at
	label.size = label_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color("#171A27"))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(label)
	return label


func _refresh_score_label() -> void:
	if not is_instance_valid(score_label):
		return
	if game_mode == "TEAM_DEATH_MATCH":
		score_label.text = "RED %d/%d    BLUE %d/%d" % [int(scores.get("RED", 0)), TDM_KILL_LIMIT, int(scores.get("BLUE", 0)), TDM_KILL_LIMIT]
		mode_label.text = "TEAM DEATHMATCH  •  FIRST TO %d" % TDM_KILL_LIMIT
		red_leaderboard.text = _leaderboard_text("RED")
		blue_leaderboard.text = _leaderboard_text("BLUE")
	else:
		var alive_count := 0
		for value in alive.values():
			if bool(value):
				alive_count += 1
		score_label.text = "%d ALIVE" % alive_count


func _leaderboard_text(team: String) -> String:
	var members: Array[Dictionary] = []
	for record in players:
		if str(record.get("team", "")) == team:
			members.append(record)
	members.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_stats: Dictionary = stats.get(int(a.get("peer_id", 0)), {})
		var b_stats: Dictionary = stats.get(int(b.get("peer_id", 0)), {})
		var a_kills := int(a_stats.get("kills", 0))
		var b_kills := int(b_stats.get("kills", 0))
		if a_kills == b_kills:
			return str(a.get("name", "")) < str(b.get("name", ""))
		return a_kills > b_kills)
	var lines: Array[String] = ["%s LEADERBOARD" % team]
	for record in members:
		var record_stats: Dictionary = stats.get(int(record.get("peer_id", 0)), {})
		lines.append("%s   %d K / %d D" % [str(record.get("name", "Player")),
			int(record_stats.get("kills", 0)), int(record_stats.get("deaths", 0))])
	return "\n".join(lines)


func _begin_spectating(requested_peer_id: int) -> void:
	var target_id := _resolve_spectate_target(requested_peer_id)
	var target = actors.get(target_id)
	if target_id == 0 or target_id == NetworkSession.local_peer_id() or not is_instance_valid(target):
		return
	_spectated_peer_id = target_id
	local_player.start_spectating(target)
	var target_name := str(_record_for(target_id).get("name", "Player"))
	spectate_label.text = "SPECTATING  %s" % target_name.to_upper()
	hud.set_spectating(true)


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


func _record_for(peer_id: int) -> Dictionary:
	for record in players:
		if int(record.get("peer_id", 0)) == peer_id:
			return record
	return {}


func _combat_team(record: Dictionary) -> String:
	if game_mode == "SURVIVAL":
		return str(record.get("peer_id", 0))
	return str(record.get("team", "RED"))


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


func _format_time(seconds: float) -> String:
	var whole := int(ceil(seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]
