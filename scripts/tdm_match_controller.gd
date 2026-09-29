extends Node

## Offline TDM authority. Lobby records remain the source of team/name identity;
## this controller owns the local match simulation and can later be replaced by
## an authoritative session implementation without changing the HUD contract.
const EnemyScript = preload("res://scripts/enemy.gd")
const MATCH_SECONDS := 600.0
const RESPAWN_SECONDS := 3.0
const ASSIST_WINDOW := 8.0
const RED := Color("#FF627E")
const BLUE := Color("#58D7F2")

var game
var local_player
var session_team := "BLUE"
var players: Array[Dictionary] = []
var actors: Dictionary = {}
var scores := {"RED": 0, "BLUE": 0}
var remaining := MATCH_SECONDS
var ended := false
var damage_log: Dictionary = {}
var hud: CanvasLayer
var red_score: Label
var blue_score: Label
var timer_label: Label
var scoreboard: Control
var result_layer: Control
var _refresh_timer := 0.0


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
	timer.timeout.connect(func():
		if not ended and is_instance_valid(local_player):
			local_player.tdm_respawn(_spawn_for_team(session_team, 0)))


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
	_refresh_timer += delta
	if _refresh_timer >= 0.25:
		_refresh_timer = 0.0
		timer_label.text = _format_time(remaining)
		if Input.is_key_pressed(KEY_TAB):
			scoreboard.visible = true
			_refresh_scoreboard()
		else:
			scoreboard.visible = false
	if remaining <= 0.0:
		_end_match()


func _format_time(seconds: float) -> String:
	var whole := int(ceil(seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 20
	game.add_child(hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	var bar := ColorRect.new()
	bar.color = Color(0.055, 0.07, 0.11, 0.82)
	bar.position = Vector2(0, 0)
	bar.size = Vector2(1280, 58)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	red_score = _label(root, "TEAM RED  0", Vector2(36, 10), Vector2(400, 38), 23, RED)
	blue_score = _label(root, "TEAM BLUE  0", Vector2(844, 10), Vector2(400, 38), 23, BLUE)
	blue_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_label = _label(root, "10:00", Vector2(560, 10), Vector2(160, 38), 24, Color.WHITE)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard = _build_scoreboard(root)
	scoreboard.visible = false
	_refresh_scoreboard()


func _label(parent: Control, text_value: String, at: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = at
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.08, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _build_scoreboard(parent: Control) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.035, 0.07, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	for side in 2:
		var panel := PanelContainer.new()
		panel.name = "TeamRedPanel" if side == 0 else "TeamBluePanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.position = Vector2(32 + side * 624, 86)
		panel.size = Vector2(592, 538)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.08, 0.12, 0.96)
		style.border_width_left = 3
		style.border_width_right = 1
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = RED if side == 0 else BLUE
		panel.add_theme_stylebox_override("panel", style)
		overlay.add_child(panel)
		var list := VBoxContainer.new()
		list.name = "RedList" if side == 0 else "BlueList"
		list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.add_theme_constant_override("separation", 7)
		panel.add_child(list)
		_label(list, "TEAM %s  |  %02d KILLS" % ["RED" if side == 0 else "BLUE", scores["RED" if side == 0 else "BLUE"]], Vector2.ZERO, Vector2(550, 38), 22, RED if side == 0 else BLUE)
		_label(list, "PLAYER                                      K      D      A", Vector2.ZERO, Vector2(550, 25), 13, Color("#D8E2EF"))
		for _row in 10:
			_label(list, "", Vector2.ZERO, Vector2(550, 32), 15, Color.WHITE)
	return overlay


func _refresh_scoreboard() -> void:
	if red_score == null:
		return
	red_score.text = "TEAM RED  %d" % int(scores.RED)
	blue_score.text = "TEAM BLUE  %d" % int(scores.BLUE)
	for team in ["RED", "BLUE"]:
		var list: VBoxContainer = scoreboard.get_node("TeamRedPanel/RedList" if team == "RED" else "TeamBluePanel/BlueList")
		var heading: Label = list.get_child(0)
		heading.text = "TEAM %s  |  %02d KILLS" % [team, int(scores[team])]
		var row_index := 0
		for record in players:
			if str(record.get("team", "")) != team:
				continue
			var row: Label = list.get_child(row_index + 2)
			var local_mark := "  • YOU" if str(record.get("id", "")) == "local" else ""
			row.text = "%-24s %3d %3d %3d%s" % [str(record.get("name", "Player")).left(22), int(record.get("kills", 0)), int(record.get("deaths", 0)), int(record.get("assists", 0)), local_mark]
			row.add_theme_color_override("font_color", Color("#FFE497") if not local_mark.is_empty() else Color("#F6F4FF"))
			row_index += 1
		while row_index < 10:
			list.get_child(row_index + 2).text = "—"
			row_index += 1


func _end_match() -> void:
	if ended:
		return
	ended = true
	timer_label.text = "00:00"
	local_player.set_physics_process(false)
	for actor in get_tree().get_nodes_in_group("tdm_combatants"):
		actor.set_physics_process(false)
	for glob in get_tree().get_nodes_in_group("projectiles"):
		glob.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var winner := "DRAW"
	if int(scores.RED) > int(scores.BLUE):
		winner = "TEAM RED WINS"
	elif int(scores.BLUE) > int(scores.RED):
		winner = "TEAM BLUE WINS"
	result_layer = Control.new()
	result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(result_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.035, 0.07, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_layer.add_child(dim)
	var title := _label(result_layer, winner, Vector2(100, 120), Vector2(1080, 78), 48, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var details := _label(result_layer, "TEAM RED  %d KILLS                       TEAM BLUE  %d KILLS\n\nYOUR STATS     %d KILLS    %d DEATHS    %d ASSISTS" % [int(scores.RED), int(scores.BLUE), _local_stat("kills"), _local_stat("deaths"), _local_stat("assists")], Vector2(160, 260), Vector2(960, 150), 24, Color("#DAE8F1"))
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var button := Button.new()
	button.text = "RETURN TO MAIN MENU"
	button.position = Vector2(470, 500)
	button.size = Vector2(340, 58)
	button.add_theme_font_size_override("font_size", 20)
	result_layer.add_child(button)
	button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))


func _local_stat(key: String) -> int:
	for record in players:
		if str(record.get("id", "")) == "local":
			return int(record.get(key, 0))
	return 0
