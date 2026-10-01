extends Node

## Offline TDM authority. Lobby records remain the source of team/name identity;
## this controller owns the local match simulation and can later be replaced by
## an authoritative session implementation without changing the HUD contract.
const EnemyScript = preload("res://scripts/enemy.gd")
const UITheme = preload("res://scripts/ui/ui_theme.gd")
const HudScript = preload("res://scripts/ui/tdm_hud.gd")
const MATCH_SECONDS := 600.0
const RESPAWN_SECONDS := 3.0
const ASSIST_WINDOW := 8.0
const RED := UITheme.TEAM_RED
const BLUE := UITheme.TEAM_BLUE

var game
var local_player
var session_team := "BLUE"
var players: Array[Dictionary] = []
var actors: Dictionary = {}
var scores := {"RED": 0, "BLUE": 0}
var remaining := MATCH_SECONDS
var ended := false
var damage_log: Dictionary = {}
## The TDM HUD (scripts/ui/tdm_hud.gd). It only draws: every number it shows is
## read from this controller or from the local player. Untyped for the usual
## parse-time reason: update_clock() etc. are this project's functions, not
## CanvasLayer's, so a CanvasLayer-typed variable would refuse to call them.
var hud = null
var _refresh_timer := 0.0
## The pending local respawn, kept so the HUD can show "Respawning in 2.4".
## The 3 second delay itself is unchanged.
var _local_respawn_timer: SceneTreeTimer


func start_match(owner_game, local_actor, lobby_records: Array[Dictionary], team: String) -> void:
	game = owner_game
	local_player = local_actor
	session_team = team
	players = lobby_records.duplicate(true)
	local_player.tdm_manager = self
	local_player.died.connect(_on_local_died)
	for index in players.size():
		var record := players[index]
		if str(record.get("id", "")) == "local":
			players[index]["kills"] = 0
			players[index]["deaths"] = 0
			players[index]["assists"] = 0
		else:
			players[index]["kills"] = 0
			players[index]["deaths"] = 0
			players[index]["assists"] = 0
			_spawn_bot(players[index])
	_build_hud()


func _spawn_for_team(team: String, index: int) -> Vector3:
	var x := -34.0 if team == "RED" else 34.0
	var z := float((index % 5) - 2) * 2.7
	return Vector3(x, 1.15, z + (4.0 if index >= 5 else -4.0))


func _spawn_bot(record: Dictionary) -> void:
	var bot := CharacterBody3D.new()
	bot.set_script(EnemyScript)
	bot.name = str(record.get("id", "Bot"))
	bot.setup_tdm(str(record.get("team", "RED")), self)
	game.add_child(bot)
	var team_index := 0
	for entry in players:
		if str(entry.get("team", "")) == str(record.get("team", "")):
			if str(entry.get("id", "")) == str(record.get("id", "")):
				break
			team_index += 1
	bot.global_position = _spawn_for_team(str(record.get("team", "RED")), team_index)
	actors[str(record.get("id", ""))] = bot


func find_enemy_for(actor):
	if ended:
		return null
	var best = null
	var best_distance := INF
	for candidate in get_tree().get_nodes_in_group("tdm_combatants"):
		if candidate == actor or str(candidate.get("tdm_team")) == str(actor.get("tdm_team")):
			continue
		if float(candidate.get("health")) <= 0.0:
			continue
		var distance: float = actor.global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func record_damage(attacker, victim) -> void:
	if ended or attacker == null or victim == null or not is_instance_valid(attacker) or not is_instance_valid(victim):
		return
	if str(attacker.get("tdm_team")) == str(victim.get("tdm_team")):
		return
	var victim_id: int = victim.get_instance_id()
	if not damage_log.has(victim_id):
		damage_log[victim_id] = []
	var recent: Array = damage_log[victim_id]
	var attacker_id: int = attacker.get_instance_id()
	var replaced := false
	for hit_index in recent.size():
		if int(recent[hit_index].id) == attacker_id:
			recent[hit_index] = {"id": attacker_id, "time": Time.get_ticks_msec()}
			replaced = true
			break
	if not replaced:
		recent.append({"id": attacker_id, "time": Time.get_ticks_msec()})
	damage_log[victim_id] = recent


func combatant_died(victim) -> void:
	if ended:
		return
	var killer = null
	if damage_log.has(victim.get_instance_id()):
		var recent: Array = damage_log[victim.get_instance_id()]
		var now := Time.get_ticks_msec()
		var latest := -1
		for hit in recent:
			if now - int(hit.time) <= ASSIST_WINDOW * 1000.0 and int(hit.time) > latest:
				latest = int(hit.time)
				killer = instance_from_id(int(hit.id))
		if latest >= 0:
			for hit in recent:
				if int(hit.time) < latest and now - int(hit.time) <= ASSIST_WINDOW * 1000.0:
					var assistant = instance_from_id(int(hit.id))
					if assistant != null and assistant != killer:
						_increment_stat(assistant, "assists")
	if killer != null and is_instance_valid(killer) and killer != victim:
		_increment_stat(killer, "kills")
		var team := str(killer.get("tdm_team"))
		scores[team] = int(scores.get(team, 0)) + 1
	_increment_stat(victim, "deaths")
	damage_log.erase(victim.get_instance_id())
	_refresh_scoreboard()
	if victim == local_player:
		_respawn_local()
	else:
		_respawn_bot(victim)


func _increment_stat(actor, stat: String) -> void:
	for index in players.size():
		var record := players[index]
		var matches: bool = (str(record.get("id", "")) == "local" and actor == local_player)
		if not matches and actor is Node:
			matches = str(record.get("id", "")) == str(actor.name)
		if matches:
			players[index][stat] = int(players[index].get(stat, 0)) + 1
			return


func _on_local_died() -> void:
	combatant_died(local_player)


func _respawn_local() -> void:
	var timer := get_tree().create_timer(RESPAWN_SECONDS)
	_local_respawn_timer = timer
	timer.timeout.connect(func():
		if not ended and is_instance_valid(local_player):
			local_player.tdm_respawn(_spawn_for_team(session_team, 0)))


## Seconds until the local player respawns, or 0 when no respawn is pending.
func local_respawn_time_left() -> float:
	if _local_respawn_timer == null:
		return 0.0
	return _local_respawn_timer.time_left


func _respawn_bot(old_bot) -> void:
	var bot_id := str(old_bot.name)
	var record: Dictionary = {}
	for entry in players:
		if str(entry.get("id", "")) == bot_id:
			record = entry.duplicate(true)
			break
	if record.is_empty():
		return
	var timer := get_tree().create_timer(RESPAWN_SECONDS)
	timer.timeout.connect(func():
		if not ended:
			_spawn_bot(record))


func _process(delta: float) -> void:
	if ended:
		return
	remaining = maxf(remaining - delta, 0.0)
	hud.update_clock(remaining)
	# TAB is still HELD, not toggled. It is now checked every frame, so the
	# board appears the instant the key goes down instead of up to 250 ms later;
	# its contents still refresh four times a second while it is open.
	var holding_tab := Input.is_key_pressed(KEY_TAB)
	hud.set_scoreboard_visible(holding_tab)
	_refresh_timer += delta
	if _refresh_timer >= 0.25:
		_refresh_timer = 0.0
		if holding_tab:
			_refresh_scoreboard()
	if remaining <= 0.0:
		_end_match()


func _build_hud() -> void:
	# HudScript.new() (rather than CanvasLayer.new() + set_script) so the HUD's
	# own _init() runs and builds its nodes.
	hud = HudScript.new()
	hud.name = "TDMHud"
	game.add_child(hud)
	hud.setup(self, local_player, session_team)
	_refresh_scoreboard()


## Pushes the live scores into the HUD's score pill and, if it is open, the
## scoreboard. combatant_died() calls this on every death.
func _refresh_scoreboard() -> void:
	if hud == null:
		return
	hud.refresh_scores()
	hud.refresh_scoreboard()


func _end_match() -> void:
	if ended:
		return
	ended = true
	local_player.set_physics_process(false)
	for actor in get_tree().get_nodes_in_group("tdm_combatants"):
		actor.set_physics_process(false)
	for glob in get_tree().get_nodes_in_group("projectiles"):
		glob.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var winner := "DRAW"
	var winner_color := Color.WHITE
	if int(scores.RED) > int(scores.BLUE):
		winner = "TEAM RED WINS"
		winner_color = RED
	elif int(scores.BLUE) > int(scores.RED):
		winner = "TEAM BLUE WINS"
		winner_color = BLUE
	hud.show_result(winner, winner_color, _local_stat("kills"), _local_stat("deaths"),
		_local_stat("assists"), func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))


func _local_stat(key: String) -> int:
	for record in players:
		if str(record.get("id", "")) == "local":
			return int(record.get(key, 0))
	return 0
