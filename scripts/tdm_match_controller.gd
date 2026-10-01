extends Node

## Human-only online match controller used by both Team Deathmatch and
## Survival. NetworkSession remains alive across scenes and owns match truth;
## this controller turns network events into visible actors and HUD updates.

const Projectile = preload("res://scripts/projectile.gd")
const RemotePlayer = preload("res://scripts/net/remote_player.gd")
const HudScript = preload("res://scripts/hud.gd")
const MATCH_SECONDS := 600.0
const RED := Color("#FF627E")
const BLUE := Color("#58D7F2")

var game
var local_player
var game_mode := "TEAM_DEATH_MATCH"
var players: Array[Dictionary] = []
var actors: Dictionary = {}
var scores := {"RED": 0, "BLUE": 0}
var stats: Dictionary = {}
var alive: Dictionary = {}
var remaining := MATCH_SECONDS
var ended := false
var hud
var mode_label: Label
var score_label: Label
var timer_label: Label
var _send_accumulator := 0.0


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
	NetworkSession.health_changed.connect(_on_health_changed)
	NetworkSession.player_eliminated.connect(_on_player_eliminated)
	NetworkSession.player_respawned.connect(_on_player_respawned)
	NetworkSession.score_changed.connect(_on_score_changed)
	NetworkSession.match_finished.connect(_on_match_finished)
	NetworkSession.server_left.connect(_on_server_left)
	_build_hud()


func _process(delta: float) -> void:
	if ended:
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
	glob.speed = float(shot_data.get("speed", 60.0))
	glob.splash_radius = float(shot_data.get("splash_radius", 0.0))
	glob.splash_mult = float(shot_data.get("splash_mult", 0.0))
	glob.color = shot_data.get("color", Color.WHITE)
	glob.can_deal_damage = false
	glob.configure_tdm(shooter, str(shooter.get("tdm_team")))
	game.add_child(glob)
	glob.setup(origin, direction, true)


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
	if victim_peer_id != NetworkSession.local_peer_id() and is_instance_valid(victim):
		victim.eliminate()
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
	else:
		actor.respawn(at)
	alive[peer_id] = true
	_refresh_score_label()


func _on_score_changed(next_scores: Dictionary, next_stats: Dictionary) -> void:
	scores = next_scores.duplicate(true)
	stats = next_stats.duplicate(true)
	_refresh_score_label()


func _on_match_finished(title: String, detail: String) -> void:
	ended = true
	local_player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_ending(title, detail + "\n\nPress R to return to the main menu.", Color.WHITE)


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
		score_label.text = "RED %d    BLUE %d" % [int(scores.get("RED", 0)), int(scores.get("BLUE", 0))]
	else:
		var alive_count := 0
		for value in alive.values():
			if bool(value):
				alive_count += 1
		score_label.text = "%d ALIVE" % alive_count


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


func _format_time(seconds: float) -> String:
	var whole := int(ceil(seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]
