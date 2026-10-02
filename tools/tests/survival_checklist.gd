extends SceneTree

## ============================================================================
## SURVIVAL CHECKLIST - a development tool, not part of the game.
## ============================================================================
##
## Runs a real Survival match and checks the 15-point regression list from the
## visual-overhaul spec, printing PASS/FAIL per item and a total. Headless:
##
##   godot --headless --path . --script res://tools/tests/survival_checklist.gd
##
## TEST-ONLY shortcuts (nothing is saved, none reachable in play): the player
## is teleported next to cores / a healing station, globs are fired at an enemy
## directly instead of by aiming, and waves are cleared by calling each enemy's
## own take_damage() - so inheriting, healing, wave flow and the ending all run
## through the unchanged game code, without depending on the autoplay bot's
## aim or on enemies getting stuck in the arena.

const Traits = preload("res://scripts/traits.gd")

var _m
var _player
var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## Presses an action the way real input arrives: at the start of a frame, so
## every script's is_action_just_pressed() sees it in that same frame. (A
## press made from a timer callback lands after scripts have already run for
## the frame, and "just pressed" has expired by the next one.)
func _press(action: String) -> void:
	await physics_frame
	Input.action_press(action)


func _release(action: String) -> void:
	await physics_frame
	Input.action_release(action)


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[check] %s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _enemies() -> Array:
	return get_nodes_in_group("enemies")


func _run() -> void:
	_m = load("res://scenes/match.tscn").instantiate()
	root.add_child(_m)
	current_scene = _m
	await _wait(0.5)
	_player = _m.get_node("Player")
	var hud = _m.get_node_or_null("HUD")
	_check("1 Survival launches", str(_m.game_mode) == "SURVIVAL")
	_check("2 HUD appears", hud != null and hud.visible)
	_check("15 no TDM UI or controller in Survival",
		not _m.has_node("TDMMatchController") and not _m.has_node("TDMHud"))

	# Wave 1 starts after a 2.2 s intro; give it time to spawn.
	await _wait(3.6)
	_check("5 enemies spawn", _enemies().size() > 0, "%d alive" % _enemies().size())

	# 3 + 4: hold the real fire action.
	var ammo_before: float = _player.ammo
	var globs_seen := 0
	Input.action_press("fire")
	for i in 12:
		await _wait(0.05)
		globs_seen = maxi(globs_seen, get_nodes_in_group("projectiles").size())
	Input.action_release("fire")
	var ammo_after: float = _player.ammo
	_check("3 player fires", globs_seen > 0, "%d globs in flight" % globs_seen)
	_check("4a paint drains while firing", ammo_after < ammo_before,
		"%.1f -> %.1f" % [ammo_before, ammo_after])
	await _wait(1.6)
	_check("4b paint refills after the 0.6 s delay", _player.ammo > ammo_after,
		"%.1f -> %.1f" % [ammo_after, _player.ammo])

	# 6: a real player glob, fired straight at an enemy.
	var target = _enemies()[0]
	var hp_before: float = target.health
	var glob = Node3D.new()
	glob.set_script(load("res://scripts/projectile.gd"))
	glob.damage = 22.0
	glob.color = Color.WHITE
	_m.add_child(glob)
	var from: Vector3 = target.global_position + Vector3(0.0, 0.8, 2.5)
	glob.setup(from, (target.global_position + Vector3(0.0, 0.8, 0.0)) - from, true)
	await _wait(0.25)
	_check("6 enemies take damage", is_instance_valid(target) and target.health < hp_before,
		"%.0f -> %.0f" % [hp_before, target.health if is_instance_valid(target) else -1.0])

	# 7: kill one; it must drop its own core.
	var victim = _enemies()[0]
	var victim_type: String = victim.type_id
	victim.take_damage(9999.0)
	await _wait(0.1)
	var dropped = null
	for core in get_nodes_in_group("cores"):
		if core.pair_id == victim_type:
			dropped = core
	_check("7 defeated enemy drops a core", dropped != null, "type %s" % victim_type)

	# 8-10: stand on it and press the real interact action.
	var start_pair: String = _player.pair_id
	var start_name: String = _player.pair["name"]
	await _inherit(dropped)
	_check("8 E inherits the core's pair", _player.pair_id == victim_type,
		"%s -> %s" % [start_pair, _player.pair_id])
	var card = _m.get_node("HUD").get("_pair_card")
	var ability: String = str(_player.pair["ability_name"]).to_upper()
	var weakness: String = str(_player.pair["weakness_name"]).to_upper()
	_check("9 ability changes (and the HUD shows it)",
		_player.pair["ability_name"] != Traits.get_pair(start_pair)["ability_name"]
		and card.get("_benefit_name").text.contains(ability), ability)
	_check("10 weakness changes (and the HUD shows it)",
		_player.pair["weakness_name"] != Traits.get_pair(start_pair)["weakness_name"]
		and card.get("_cost_name").text.contains(weakness), weakness)

	# 11: a second, different pair replaces the first completely.
	var other_type := "monolith" if victim_type != "monolith" else "sprayer"
	var other = Node3D.new()
	other.set_script(load("res://scripts/core_pickup.gd"))
	other.pair_id = other_type
	other.color = Traits.get_pair(other_type)["color"]
	_m.add_child(other)
	other.global_position = Vector3(30.0, 0.7, 0.0)
	await _inherit(other)
	var expected_interval: float = _player.base_fire_interval / float(Traits.get_pair(other_type)["fire_rate_mult"])
	var expected_damage: float = _player.base_damage * float(Traits.get_pair(other_type)["damage_mult"])
	_check("11 new pair REPLACES the old one", _player.pair_id == other_type
		and is_equal_approx(_player._fire_interval, expected_interval)
		and is_equal_approx(_player._damage, expected_damage),
		"now %s; interval %.3f dmg %.1f" % [_player.pair_id, _player._fire_interval, _player._damage])

	# 12 + 13: clear wave 1, then use a healing station during the breather.
	await _clear_wave()
	var wave_after_clear: int = int(_m.get("_wave_index")) + 1
	_player.health = 30.0
	_player.stats_changed.emit()
	var station = _m.get_node("HealingStation1")
	_player.global_position = station.global_position + Vector3(1.2, 0.2, 0.0)
	_player.velocity = Vector3.ZERO
	await _wait(0.4)
	await _press("interact")
	await _wait(1.8)
	await _release("interact")
	_check("13 healing station heals to full", is_equal_approx(float(_player.health), float(_player.max_health)),
		"health %.0f" % float(_player.health))
	await _wait(5.5)
	_check("12 next wave starts after the breather", int(_m.get("_wave_index")) + 1 == wave_after_clear
		and _enemies().size() > 0, "wave %d, %d enemies" % [wave_after_clear, _enemies().size()])

	# 14: the full six-wave flow to the ending.
	for i in 6:
		if bool(_m.get("_run_over")):
			break
		await _clear_wave()
		await _wait(5.6)
	var end_panel = _m.get_node("HUD").get("_end_panel")
	var end_title = _m.get_node("HUD").get("_end_title")
	_check("14 six-wave flow reaches the win screen", bool(_m.get("_run_over"))
		and end_panel.visible and end_title.text == "CANVAS CLEAN",
		"run_over=%s title='%s'" % [str(_m.get("_run_over")), end_title.text])

	print("[check] TOTAL %d passed, %d failed" % [_passed, _failed])
	quit()


## Stands the player beside a core and presses interact (game.gd decides).
func _inherit(core) -> void:
	_player.global_position = Vector3(core.global_position.x, 0.2, core.global_position.z) + Vector3(0.6, 0.0, 0.0)
	_player.velocity = Vector3.ZERO
	await _wait(0.15)
	await _press("interact")
	await _wait(0.05)
	await _release("interact")
	await _wait(0.1)


## Waits for the current wave to finish spawning, then defeats every enemy
## through its own take_damage(), keeping the player alive meanwhile.
func _clear_wave() -> void:
	var waited := 0.0
	while bool(_m.get("_spawning")) and waited < 6.0:
		await _wait(0.1)
		waited += 0.1
	for i in 30:
		_player.health = float(_player.max_health)
		var alive := _enemies()
		if alive.is_empty() and not bool(_m.get("_spawning")):
			break
		for e in alive:
			e.take_damage(99999.0)
		await _wait(0.2)
