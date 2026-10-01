extends SceneTree

## ============================================================================
## MENU FLOW PROBE - a development tool, not part of the game.
## ============================================================================
##
## Drives the REAL menu path - the same functions the buttons call - into a
## match and reports which HUD exists, so a change to the menu or to either
## mode can be checked end to end without a mouse. Headless is fine:
##
##   godot --headless --path . --script res://tools/tests/menu_flow_probe.gd -- --mode=tdm
##   godot --headless --path . --script res://tools/tests/menu_flow_probe.gd -- --mode=survival
##
## TDM takes about a minute: the simulated lobby fills one player every 1.8 s,
## then counts down.

var _mode := "tdm"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			_mode = a.substr(7)
	_run.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	var menu = load("res://scenes/main.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await _wait(0.6)
	menu._begin_play()                      # the PLAY button
	await _wait(0.9)
	print("[flow] screen after PLAY: ", menu.current_screen)
	if _mode == "tdm":
		menu._select_tdm()                  # the TEAM DEATH MATCH button
		var waited := 0.0
		while is_instance_valid(menu) and menu.is_inside_tree() and waited < 60.0:
			await _wait(2.0)
			waited += 2.0
			if is_instance_valid(menu) and menu.is_inside_tree() and menu.match_starting:
				print("[flow] t=%.0f lobby=%d countdown='%s'" % [waited, menu.lobby_players.size(),
					menu.countdown_label.text if is_instance_valid(menu.countdown_label) else "-"])
	else:
		menu._launch_survival()             # the SURVIVAL button
	await _wait(4.0)
	var match_node = current_scene
	print("[flow] current scene: ", match_node.name, " mode=", match_node.get("game_mode"))
	print("[flow] has TDMMatchController=", match_node.has_node("TDMMatchController"),
		" has TDMHud=", match_node.has_node("TDMHud"), " has Survival HUD=", match_node.has_node("HUD"))
	print("[flow] tdm_combatants=", get_nodes_in_group("tdm_combatants").size(),
		" enemies=", get_nodes_in_group("enemies").size())
	if match_node.has_node("TDMMatchController"):
		var c = match_node.get_node("TDMMatchController")
		var teams := {"RED": 0, "BLUE": 0}
		for r in c.players:
			teams[str(r.team)] += 1
		print("[flow] roster RED=%d BLUE=%d remaining=%.0f" % [teams.RED, teams.BLUE, c.remaining])
	quit()
