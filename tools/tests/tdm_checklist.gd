extends SceneTree

## ============================================================================
## TDM CHECKLIST - a development tool, not part of the game.
## ============================================================================
##
## Enters Team Death Match through the REAL menu (PLAY -> TEAM DEATH MATCH ->
## lobby -> countdown), then checks the 26-point TDM regression list from the
## visual-overhaul spec, printing PASS/FAIL per item. A second, direct match
## checks that equal scores end in a draw. Headless, about 75 seconds:
##
##   godot --headless --path . --script res://tools/tests/tdm_checklist.gd
##
## TEST-ONLY shortcuts (nothing saved, none reachable in play): damage is dealt
## by calling the real take_damage() with a real attacker, globs are fired at a
## target directly instead of by aiming, a lobby name is lengthened to test
## clipping, and the clock is shortened to reach the ending.

var _passed := 0
var _failed := 0
var _m
var _c
var _hud
var _player


func _initialize() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[check] %s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _tab(down: bool) -> void:
	await physics_frame
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.physical_keycode = KEY_TAB
	key.pressed = down
	Input.parse_input_event(key)


func _record(id: String) -> Dictionary:
	for r in _c.players:
		if str(r.get("id", "")) == id:
			return r
	return {}


func _bots(team: String) -> Array:
	var out: Array = []
	for n in get_nodes_in_group("tdm_combatants"):
		if n != _player and str(n.get("tdm_team")) == team and float(n.get("health")) > 0.0:
			out.append(n)
	return out


func _run() -> void:
	# --- 1-4: the real menu route --------------------------------------------
	var menu = load("res://scenes/main.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await _wait(0.6)
	menu._begin_play()
	await _wait(0.9)
	menu._select_tdm()
	var countdown_seen: Dictionary = {}
	var lobby_names: Array = []
	var waited := 0.0
	while is_instance_valid(menu) and menu.is_inside_tree() and waited < 70.0:
		await _wait(0.2)
		waited += 0.2
		if is_instance_valid(menu) and menu.is_inside_tree():
			if is_instance_valid(menu.countdown_label) and not menu.countdown_label.text.is_empty():
				countdown_seen[menu.countdown_label.text] = true
			lobby_names = menu.lobby_players.map(func(r): return str(r.name))
	await _wait(1.5)
	_m = current_scene
	_c = _m.get_node_or_null("TDMMatchController")
	_check("1 PLAY -> TEAM DEATH MATCH reaches a TDM match",
		_c != null and str(_m.game_mode) == "TEAM_DEATH_MATCH")
	var match_names: Array = _c.players.map(func(r): return str(r.name))
	match_names.sort()
	lobby_names.sort()
	_check("2 lobby records load into the match", match_names == lobby_names and match_names.size() == 20,
		"%d records" % match_names.size())
	_check("3 lobby countdown runs", countdown_seen.has("5") and countdown_seen.has("1") and countdown_seen.has("GO!"),
		str(countdown_seen.keys()))
	var red := 0
	var blue := 0
	for r in _c.players:
		if str(r.team) == "RED":
			red += 1
		else:
			blue += 1
	_check("4 two teams populate", red == 10 and blue == 10
		and get_nodes_in_group("tdm_combatants").size() == 20, "RED %d BLUE %d" % [red, blue])

	_hud = _m.get_node("TDMHud")
	_player = _m.get_node("Player")
	var team: String = _c.session_team
	var enemy_team := "RED" if team == "BLUE" else "BLUE"

	# --- 26: Survival systems untouched in TDM ------------------------------
	_check("26a no Survival HUD, waves or cores in TDM", not _m.has_node("HUD")
		and int(_m.get("_wave_index")) == 0 and get_nodes_in_group("cores").is_empty())

	# --- 18, 19: crosshair and pair card -------------------------------------
	var crosshair = _hud.get("_crosshair")
	# Compare against the visible CANVAS, not the window: with the project's
	# canvas_items stretch mode the UI is laid out in canvas units, which only
	# equal window pixels at the base 1280x720 size.
	var centre_offset: Vector2 = crosshair.get_global_rect().get_center() - root.get_visible_rect().get_center()
	_check("18 crosshair visible and centred", crosshair.visible and centre_offset.length() < 1.0,
		"offset %s" % str(centre_offset))
	var card = _hud.get("_pair_card")
	_check("19 pair card is correct (Apprentice: no ability, no weakness)",
		card.get("_name_label").text == "APPRENTICE BRUSH" and card.get("_none_label").visible
		and not card.get("_benefit_name").visible)

	# --- 5, 14: bots fight, clock runs ---------------------------------------
	var clock_start: float = _c.remaining
	await _wait(9.0)
	var total_score: int = int(_c.scores.RED) + int(_c.scores.BLUE)
	_check("5 bots fight (team scores rise)", total_score > 0, "RED %d BLUE %d" % [int(_c.scores.RED), int(_c.scores.BLUE)])
	_check("14 timer counts down and the HUD shows it", _c.remaining < clock_start - 8.0
		and _hud.get("_clock").text == load("res://scripts/ui/tdm_scoreboard.gd").format_time(_c.remaining),
		"%.1f -> %.1f, HUD '%s'" % [clock_start, _c.remaining, _hud.get("_clock").text])

	# --- 6, 17: the player fires, paint HUD follows ---------------------------
	var ammo_before: float = _player.ammo
	await physics_frame
	Input.action_press("fire")
	await _wait(0.5)
	await physics_frame
	Input.action_release("fire")
	await _wait(0.05)
	_check("6 player fires (paint spent)", _player.ammo < ammo_before, "%.1f -> %.1f" % [ammo_before, _player.ammo])
	var paint_widget = _hud.get("_paint")
	_check("17 paint HUD matches the reservoir", paint_widget.get("_value_label").text == str(int(_player.ammo)),
		"HUD %s, ammo %.1f" % [paint_widget.get("_value_label").text, _player.ammo])

	# --- 7, 16: an enemy glob damages the player, health HUD follows ----------
	var shooter = _bots(enemy_team)[0]
	var hp_before: float = _player.health
	var glob = Node3D.new()
	glob.set_script(load("res://scripts/projectile.gd"))
	glob.damage = 13.0
	glob.speed = 40.0
	glob.color = Color.RED
	glob.configure_tdm(shooter, enemy_team)
	_m.add_child(glob)
	var from: Vector3 = _player.global_position + Vector3(0.0, 1.0, 3.0)
	glob.setup(from, (_player.global_position + Vector3(0.0, 1.0, 0.0)) - from, false)
	await _wait(0.3)
	_check("7 enemy paint damages the player", _player.health < hp_before, "%.0f -> %.0f" % [hp_before, _player.health])
	var health_widget = _hud.get("_health")
	_check("16 health HUD matches", health_widget.get("_value_label").text == str(int(ceil(_player.health))),
		"HUD %s, health %.1f" % [health_widget.get("_value_label").text, _player.health])

	# --- 8, 10, 11, 13: a kill, with credit ------------------------------------
	var killer = _bots(enemy_team)[0]
	var killer_before: int = int(_record(str(killer.name)).get("kills", 0))
	var my_deaths: int = int(_record("local").get("deaths", 0))
	var enemy_score: int = int(_c.scores[enemy_team])
	_player.take_damage(9999.0, killer)
	await _wait(0.05)
	_check("8 the player dies", _player.is_dead())
	_check("10 killer's kills +1", int(_record(str(killer.name)).get("kills", 0)) == killer_before + 1)
	_check("11 victim's deaths +1", int(_record("local").get("deaths", 0)) == my_deaths + 1)
	_check("13 killer's team score +1", int(_c.scores[enemy_team]) >= enemy_score + 1,
		"%d -> %d" % [enemy_score, int(_c.scores[enemy_team])])

	# --- 9, 15: three-second respawn, HUD back -------------------------------
	var died_at := Time.get_ticks_msec()
	var respawn_overlay = _hud.get("_respawn")
	await _wait(0.3)
	var overlay_while_dead: bool = respawn_overlay.visible
	while _player.is_dead() and Time.get_ticks_msec() - died_at < 6000:
		await process_frame
	var respawn_s := (Time.get_ticks_msec() - died_at) / 1000.0
	_check("9 respawn after 3 seconds", not _player.is_dead() and absf(respawn_s - 3.0) < 0.25,
		"%.2f s, 'PAINTED OUT' shown while dead: %s" % [respawn_s, str(overlay_while_dead)])
	await _wait(0.1)
	_check("15 HUD visible again after respawn", _hud.get("_root").visible and not respawn_overlay.visible
		and crosshair.visible and health_widget.get("_value_label").text == str(int(ceil(_player.health))))

	# --- 12: assists (8 s window) ---------------------------------------------
	# Freeze every bot for this check, so no third party can hit or kill the
	# target between the two test hits (the test, not the game, needs this).
	for n in get_nodes_in_group("tdm_combatants"):
		if n != _player:
			n.set_physics_process(false)
	var attackers := _bots(team)
	var victims := _bots(enemy_team).filter(func(b): return is_equal_approx(float(b.health), float(b.max_health)))
	var helper = attackers[0]
	var finisher = attackers[1]
	var target = victims[0]
	var helper_assists: int = int(_record(str(helper.name)).get("assists", 0))
	var finisher_kills: int = int(_record(str(finisher.name)).get("kills", 0))
	var finisher_assists: int = int(_record(str(finisher.name)).get("assists", 0))
	target.take_damage(10.0, helper)
	await _wait(0.1)
	target.take_damage(99999.0, finisher)
	await _wait(0.05)
	_check("12 assist credited to the earlier attacker (not the killer)",
		int(_record(str(helper.name)).get("assists", 0)) == helper_assists + 1
		and int(_record(str(finisher.name)).get("kills", 0)) == finisher_kills + 1
		and int(_record(str(finisher.name)).get("assists", 0)) == finisher_assists,
		"helper assists %d->%d, finisher kills %d->%d" % [helper_assists,
			int(_record(str(helper.name)).get("assists", 0)), finisher_kills,
			int(_record(str(finisher.name)).get("kills", 0))])
	for n in get_nodes_in_group("tdm_combatants"):
		n.set_physics_process(true)

	# --- 20-23: the Tab scoreboard ---------------------------------------------
	var board = _hud.get("_scoreboard")
	# Test-only: one very long name, to prove it is clipped and cannot push the
	# K/D/A columns.
	var long_record: Dictionary = _c.players[3]
	long_record["name"] = "AnExtremelyLongPlayerNameThatWouldBreakTheLayout"
	await _tab(true)
	await _wait(0.3)
	_check("20 holding Tab opens the scoreboard", board.visible and board.modulate.a > 0.9)
	var rows_ok := true
	var detail := ""
	for t in ["RED", "BLUE"]:
		var rows: Array = board.get("_team_rows")[t]
		var kills_x := -1.0
		var shown_kills := 0
		var row_width := -1.0
		for row in rows:
			var k_label = row.get("_kills")
			if k_label.text.is_empty():
				continue
			shown_kills += int(k_label.text)
			if kills_x < 0.0:
				kills_x = k_label.global_position.x
				row_width = row.size.x
			elif absf(k_label.global_position.x - kills_x) > 0.5 or absf(row.size.x - row_width) > 0.5:
				rows_ok = false
				detail = "column drift in %s" % t
		var record_kills := 0
		for r in _c.players:
			if str(r.team) == t:
				record_kills += int(r.get("kills", 0))
		if shown_kills != record_kills:
			rows_ok = false
			detail += " %s shows %d kills, records %d" % [t, shown_kills, record_kills]
	_check("22 scoreboard matches the controller after deaths/respawns", rows_ok, detail)
	var long_row_ok := false
	var team_rows: Array = board.get("_team_rows")[str(long_record.team)]
	var first_k_x := -1.0
	for row in team_rows:
		if row.get("_name").text == long_record["name"]:
			long_row_ok = row.get("_name").text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS
		if first_k_x < 0.0 and not row.get("_kills").text.is_empty():
			first_k_x = row.get("_kills").global_position.x
	var all_aligned := true
	for row in team_rows:
		if not row.get("_kills").text.is_empty() and absf(row.get("_kills").global_position.x - first_k_x) > 0.5:
			all_aligned = false
	_check("23 a long name is clipped and K/D/A stay aligned", long_row_ok and all_aligned)
	await _tab(false)
	await _wait(0.3)
	_check("21 releasing Tab closes it", not board.visible)

	# --- 24: the result screen -------------------------------------------------
	_c.remaining = 0.2
	await _wait(0.6)
	var result = _hud.get("_result")
	var expected := "DRAW"
	if int(_c.scores.RED) > int(_c.scores.BLUE):
		expected = "TEAM RED WINS"
	elif int(_c.scores.BLUE) > int(_c.scores.RED):
		expected = "TEAM BLUE WINS"
	var title_ok := false
	if result != null:
		for label in result.find_children("*", "Label", true, false):
			if (label as Label).text == expected:
				title_ok = true
	_check("24 final result screen shows the right winner", _c.ended and result != null and title_ok,
		"%s (RED %d BLUE %d)" % [expected, int(_c.scores.RED), int(_c.scores.BLUE)])
	_check("26b Survival end panel never appeared", not _m.has_node("HUD"))

	# --- 25: equal scores draw (a second, direct match) -----------------------
	_m.queue_free()
	await _wait(0.3)
	var m2 = load("res://scenes/match.tscn").instantiate()
	m2.game_mode = "TEAM_DEATH_MATCH"
	m2.session_team = "BLUE"
	var records: Array[Dictionary] = []
	records.append({"id": "local", "name": "Player", "team": "BLUE", "source": "local", "customization": {}})
	for i in 19:
		records.append({"id": "sim_%02d" % i, "name": "Bot%02d" % i, "team": "RED" if i < 10 else "BLUE", "source": "local_simulation", "customization": {}})
	m2.lobby_players = records
	root.add_child(m2)
	current_scene = m2
	await _wait(1.0)
	var c2 = m2.get_node("TDMMatchController")
	for n in get_nodes_in_group("tdm_combatants"):
		n.set_physics_process(false)
	c2.scores = {"RED": 7, "BLUE": 7}
	c2.remaining = 0.1
	await _wait(0.5)
	var draw_ok := false
	var r2 = m2.get_node("TDMHud").get("_result")
	if r2 != null:
		for label in r2.find_children("*", "Label", true, false):
			if (label as Label).text == "DRAW":
				draw_ok = true
	_check("25 equal scores end in a DRAW", c2.ended and draw_ok)

	print("[check] TOTAL %d passed, %d failed" % [_passed, _failed])
	quit()
