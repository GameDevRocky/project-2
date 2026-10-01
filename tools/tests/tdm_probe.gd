extends SceneTree

## ============================================================================
## TDM PROBE - a development tool, not part of the game.
## ============================================================================
##
## TDM can only be started through the menu (game.gd needs lobby records), and
## game.gd never attaches the autoplay bot in TDM. This starts a 2x10 match
## directly, attaches tools/autoplay.gd, and prints the controller's live state
## every 5 seconds. Headless is fine:
##
##   godot --headless --path . --script res://tools/tests/tdm_probe.gd -- [--seconds=45] [--shorten=30] [--tab]
##
##   --shorten=N  set the match clock to N seconds, to reach the ending quickly
##   --tab        hold TAB from 8 s to 12 s and report the scoreboard's state
##
## One lobby name is deliberately very long, to exercise name clipping.

var _match
var _controller
var _elapsed := 0.0
var _next_report := 2.0
var _end_at := 45.0
var _shorten_to := -1.0
var _test_tab := false
var _tab_down := false
var _hits_confirmed := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			_end_at = float(a.split("=")[1])
		elif a.begins_with("--shorten="):
			_shorten_to = float(a.split("=")[1])
		elif a == "--tab":
			_test_tab = true
	_match = load("res://scenes/match.tscn").instantiate()
	_match.game_mode = "TEAM_DEATH_MATCH"
	_match.session_team = "BLUE"
	var records: Array[Dictionary] = []
	records.append({"id": "local", "name": "Player", "team": "BLUE", "source": "local", "customization": {}})
	for i in 19:
		var long_name := "ExtremelyLongPlayerNameThatBreaksThings" if i == 3 else "Bot%02d" % i
		records.append({"id": "sim_%02d" % i, "name": long_name, "team": "RED" if i < 10 else "BLUE", "source": "local_simulation", "customization": {}})
	_match.lobby_players = records
	root.add_child(_match)
	current_scene = _match
	print("[probe] TDM match added")


func _send_tab(down: bool) -> void:
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.physical_keycode = KEY_TAB
	tab.pressed = down
	Input.parse_input_event(tab)


func _process(delta: float) -> bool:
	_elapsed += delta
	if _controller == null and _match != null:
		_controller = _match.get_node_or_null("TDMMatchController")
		if _controller != null:
			var bot := Node.new()
			bot.set_script(load("res://tools/autoplay.gd"))
			_match.add_child(bot)
			if _shorten_to > 0.0:
				_controller.remaining = _shorten_to
			print("[probe] controller found, autoplay attached; survival HUD present=%s" % str(_match.has_node("HUD")))
			var p = _match.get_node("Player")
			p.hit_confirmed.connect(func(): _hits_confirmed += 1)
	if _controller != null and _elapsed >= _next_report:
		_next_report += 5.0
		var player = _match.get_node_or_null("Player")
		var local := {}
		for r in _controller.players:
			if str(r.get("id", "")) == "local":
				local = r
		print("[probe] t=%.0f remaining=%.0f RED=%d BLUE=%d  you K/D/A=%d/%d/%d  hp=%.0f paint=%.0f bots=%d ended=%s hits=%d" % [
			_elapsed, _controller.remaining, int(_controller.scores.RED), int(_controller.scores.BLUE),
			int(local.get("kills", 0)), int(local.get("deaths", 0)), int(local.get("assists", 0)),
			float(player.health) if player else -1.0, float(player.ammo) if player else -1.0,
			get_nodes_in_group("tdm_combatants").size(), str(_controller.ended), _hits_confirmed])
	if _test_tab and _controller != null and _controller.hud != null:
		var board = _controller.hud.get("_scoreboard")
		if _elapsed >= 8.0 and _elapsed < 12.0 and not _tab_down:
			_tab_down = true
			_send_tab(true)
		elif _elapsed >= 12.0 and _tab_down:
			_tab_down = false
			_send_tab(false)
		if board != null and _elapsed > 7.5 and _elapsed < 13.1 and int(_elapsed * 60.0) % 30 == 0:
			print("[probe] t=%.1f tab=%s scoreboard_visible=%s" % [_elapsed, str(_tab_down), str(board.visible)])
	if _elapsed >= _end_at:
		quit()
	return false
