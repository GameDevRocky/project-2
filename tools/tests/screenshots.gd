extends SceneTree

## ============================================================================
## SCREENSHOTS - a development tool, not part of the game.
## ============================================================================
##
## Walks every reachable menu page, a TDM match (HUD, held-Tab scoreboard,
## respawn, result) and a Survival match (HUD, a pair, the inherit offer, the
## end panel), saving a PNG of each. Headless runs render nothing, so this is
## how visual changes get checked. It opens a real game window for a minute.
##
## Run (from the project folder, with the Godot console exe):
##   godot --path . --script res://tools/tests/screenshots.gd -- --out=<dir> [--res=1280x720] [--only=menu|tdm|survival|showcase|arena|wardrobe]
##
## "showcase" is not a normal game state: it builds a Survival arena with no
## waves, then places one of each enemy (frozen), a core of every pair colour,
## a healing station and a few paint splats in front of the camera, so the
## generated models can be judged in the real game with the real scripts.
## "wardrobe" lines up dressed Canvas Runners (every outfit incl. bot-only,
## every hat, mask, back bling and gun skin) under in-game lighting.
## "arena" flies a free camera to seven viewpoints (hub, the three buildings,
## the south lane, a corner, an overview) and prints the average brightness
## of a patch of sunlit floor, to compare lighting between changes.
## Add --rendering-method gl_compatibility BEFORE --script to check the web
## renderer.
##
## Some steps inject TEST-ONLY state (a pair in TDM, fake K/D/A numbers, a
## killing blow) purely so the screenshot shows that state. None of it is saved
## or reachable from normal play.

var _out := ""
var _res := Vector2i(1280, 720)
var _tag := "1280x720"
var _only := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--res="):
			var parts := a.substr(6).split("x")
			_res = Vector2i(int(parts[0]), int(parts[1]))
			_tag = a.substr(6)
		elif a.begins_with("--only="):
			_only = a.substr(7)
	DisplayServer.window_set_size(_res)
	root.size = _res
	_run.call_deferred()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [_out, _tag, name]
	img.save_png(path)
	print("[shot] ", path.get_file())


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	await _wait(0.5)
	if _only == "" or _only == "menu":
		await _menu_pass()
	if _only == "" or _only == "tdm":
		await _tdm_pass()
	if _only == "" or _only == "survival":
		await _survival_pass()
	if _only == "" or _only == "showcase":
		await _showcase_pass()
	if _only == "" or _only == "arena":
		await _arena_pass()
	if _only == "wardrobe":
		await _wardrobe_pass()
	quit()


func _menu_pass() -> void:
	var menu = load("res://scenes/main.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await _wait(1.0)
	await _snap("menu_01_main")
	menu._begin_play()
	await _wait(1.2)
	await _snap("menu_02_mode_select")
	menu.selected_game_mode = "TEAM_DEATH_MATCH"
	menu.queue_generation += 1
	menu.local_team = "BLUE"
	menu.lobby_players.clear()
	menu.lobby_players.append({"id": "local", "name": "Player", "team": "BLUE", "source": "local", "customization": {}})
	for i in 13:
		menu.lobby_players.append({"id": "sim_%02d" % i, "name": ("ExtremelyLongPlayerName" if i == 2 else menu.SIM_NAMES[i]), "team": "RED" if i % 2 == 0 else "BLUE", "source": "local_simulation", "customization": {}})
	menu._build_lobby_screen("WAITING FOR PLAYERS  •  TEAM BLUE ASSIGNED")
	menu.menu_content.modulate.a = 1.0
	await _wait(0.4)
	await _snap("menu_03_lobby")
	menu.match_starting = true
	menu.countdown_remaining = 3
	menu._build_lobby_screen("MATCH STARTING")
	menu.menu_content.modulate.a = 1.0
	await _wait(0.3)
	await _snap("menu_04_lobby_countdown")
	menu._open_customization("main")
	await _wait(1.3)
	await _snap("menu_05_customize_skins")
	# Test-only picks, made through the same function the buttons call.
	menu._pick_category("HATS")
	menu._select_option("HATS", 2)
	menu._pick_category("MASKS")
	menu._select_option("MASKS", 3)
	await _wait(0.6)
	await _snap("menu_05b_customize_hat_mask")
	menu._pick_category("BACK BLING")
	menu._select_option("BACK BLING", 4)
	menu.menu_content.modulate.a = 1.0
	await _wait(1.0)
	await _snap("menu_06_customize_backbling")
	menu._pick_category("GUN SKINS")
	menu._select_option("GUN SKINS", 9)
	await _wait(1.0)
	await _snap("menu_06b_customize_gun")
	menu._pick_category("SKINS")
	menu._select_option("SKINS", 6)
	await _wait(0.6)
	await _snap("menu_06c_customize_outfit")
	menu.customization["skin"] = "ninja"
	menu.selected_category = "HATS"
	menu._show_customization()
	menu.menu_content.modulate.a = 1.0
	await _wait(0.4)
	await _snap("menu_07_customize_locked")
	menu._return_from_customization()
	await _wait(1.2)
	menu._show_settings()
	menu.menu_content.modulate.a = 1.0
	await _wait(0.4)
	await _snap("menu_08_settings")
	menu.queue_free()
	await _wait(0.3)


func _tdm_pass() -> void:
	var m = load("res://scenes/match.tscn").instantiate()
	m.game_mode = "TEAM_DEATH_MATCH"
	m.session_team = "BLUE"
	var records: Array[Dictionary] = []
	records.append({"id": "local", "name": "Player", "team": "BLUE", "source": "local", "customization": {}})
	for i in 19:
		var n := "ExtremelyLongPlayerNameThatBreaksThings" if i == 3 else "Bot%02d" % i
		records.append({"id": "sim_%02d" % i, "name": n, "team": "RED" if i < 10 else "BLUE", "source": "local_simulation", "customization": {}})
	m.lobby_players = records
	root.add_child(m)
	current_scene = m
	await _wait(4.0)
	await _snap("tdm_01_hud")
	var controller = m.get_node("TDMMatchController")
	var player = m.get_node("Player")
	# Test-only: turn to face the enemy spawn, so bots are in view.
	player.rotation.y = PI * 0.5
	await _wait(1.5)
	await _snap("tdm_01a_facing_bots")
	# Test-only: show a real pair on the card (TDM never drops cores).
	player.inherit_pair("blotter")
	player.ammo = 5.0
	player.stats_changed.emit()
	await _wait(0.3)
	await _snap("tdm_01b_hud_pair")
	# Test-only: numbers on the board so sorting/alignment is visible.
	for r in controller.players:
		var seed_value := int(str(r.get("id")).hash()) & 0xff
		r["kills"] = seed_value % 13
		r["deaths"] = (seed_value / 13) % 9
		r["assists"] = (seed_value / 7) % 6
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	Input.parse_input_event(tab)
	await _wait(0.6)
	await _snap("tdm_02_scoreboard")
	tab = tab.duplicate()
	tab.pressed = false
	Input.parse_input_event(tab)
	await _wait(0.2)
	player.take_damage(999.0)
	await _wait(0.8)
	await _snap("tdm_02b_respawning")
	await _wait(3.0)
	await _snap("tdm_02c_after_respawn")
	controller.remaining = 0.3
	await _wait(1.0)
	await _snap("tdm_03_result")
	m.queue_free()
	await _wait(0.3)


func _survival_pass() -> void:
	var m = load("res://scenes/match.tscn").instantiate()
	# The look the menu would hand over; gun skin 3 = SUNBURST.
	var custom: Dictionary = load("res://scripts/character_customization_data.gd").create_session_data()
	custom["gun_skin"] = 3
	m.customization = custom
	root.add_child(m)
	current_scene = m
	await _wait(3.5)
	await _snap("survival_01_hud")
	var player = m.get_node("Player")
	# Test-only: face the middle of the arena, where the first wave comes from.
	player.rotation.y = PI * 0.5
	await _wait(3.0)
	await _snap("survival_01b_wave")
	# Stage 7: one shot (muzzle puff) and a hit marker.
	Input.action_press("fire")
	await _wait(0.05)
	Input.action_release("fire")
	player.confirm_hit()
	await _wait(0.03)
	await _snap("survival_01c_fire_hit")
	player.inherit_pair("monolith")
	await _wait(0.4)
	# A real core next to the player, so game.gd's own offer logic shows it.
	var core = Node3D.new()
	core.set_script(load("res://scripts/core_pickup.gd"))
	core.pair_id = "ghost"
	core.color = Color.WHITE
	m.add_child(core)
	core.global_position = player.global_position + (-player.global_transform.basis.z * 2.0) + Vector3(0.0, 0.7, 0.0)
	await _wait(0.5)
	await _snap("survival_02_offer")
	core.queue_free()
	# Test-only: put the player at low health (wave enemies may already have
	# hurt them, so a fixed amount of damage could kill instead).
	player.health = 18.0
	player.stats_changed.emit()
	await _wait(0.45)
	await _snap("survival_03_lowhp")
	m.get_node("HUD").show_ending("PAINTED OVER", "You fell on wave 1 of 6, carrying the Monolith's Pair.\n\nPress R to start a new run.", Color("#FF6B81"))
	await _wait(0.3)
	await _snap("survival_04_end")
	m.queue_free()
	await _wait(0.3)


func _showcase_pass() -> void:
	var m = load("res://scenes/match.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	m._run_over = true            # no waves: nothing will spawn on its own
	await _wait(0.5)
	var player = m.get_node("Player")
	player.set_physics_process(false)
	var cam: Camera3D = player.get_node("Camera")
	var view_model: Node3D = cam.get_child(0)
	view_model.visible = false
	var hud = m.get_node("HUD")
	hud.visible = false

	# --- Enemies, spawned through the real enemy.gd, then frozen -------------
	var enemy_script = load("res://scripts/enemy.gd")
	# Open ground in the east of the arena (no cover between here and x=40).
	var x := 27.0
	for type_id in ["sprayer", "bounder", "blotter", "monolith", "ghost"]:
		var e = CharacterBody3D.new()
		e.set_script(enemy_script)
		e.setup(type_id, 1.0)
		m.add_child(e)
		e.global_position = Vector3(x, 0.0, 0.0)
		e.rotation.y = 0.0          # face +Z, toward the camera
		e.set_physics_process(false)
		x += 2.6
	player.global_position = Vector3(32.2, 0.0, 7.0)
	player.rotation.y = 0.0
	cam.rotation.x = deg_to_rad(-8.0)
	await _wait(1.0)
	await _snap("show_01_enemies")
	# One enemy hit, to see the flash.
	for e in get_nodes_in_group("enemies"):
		if e.type_id == "blotter":
			e._visual.on_fire()
			e._flash()
	await _wait(0.05)
	await _snap("show_02_flash_fire")
	# Stage 7: a death burst (test-only kill of the Bounder).
	for e in get_nodes_in_group("enemies"):
		if e.type_id == "bounder":
			e.take_damage(9999.0)
	await _wait(0.1)
	await _snap("show_02a_death_burst")
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	await _wait(0.2)

	# --- Two TDM runners (one per team), frozen, close up --------------------
	for i in 2:
		var bot = CharacterBody3D.new()
		bot.set_script(enemy_script)
		bot.setup_tdm("RED" if i == 0 else "BLUE", null)
		m.add_child(bot)
		bot.global_position = Vector3(31.0 + i * 1.6, 0.0, 1.0)
		bot.rotation.y = 0.35 - i * 0.7
		bot.set_physics_process(false)
	player.global_position = Vector3(31.8, 0.0, 4.6)
	cam.rotation.x = deg_to_rad(-10.0)
	await _wait(0.6)
	await _snap("show_02b_runners")
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	player.global_position = Vector3(32.2, 0.0, 7.0)
	cam.rotation.x = deg_to_rad(-8.0)
	await _wait(0.2)

	# --- Cores in every pair colour ------------------------------------------
	var traits = load("res://scripts/traits.gd")
	x = 28.4
	for pair_id in ["sprayer", "bounder", "blotter", "monolith", "ghost"]:
		var core = Node3D.new()
		core.set_script(load("res://scripts/core_pickup.gd"))
		core.pair_id = pair_id
		core.color = traits.get_pair(pair_id)["color"]
		m.add_child(core)
		core.global_position = Vector3(x, 0.7, 0.0)
		x += 1.9
	player.global_position = Vector3(32.2, 0.0, 4.2)
	await _wait(0.8)
	await _snap("show_03_cores_fresh")
	for core in get_nodes_in_group("cores"):
		core._age = 9.0   # test-only: fast-forward to show the draining ticks
	await _wait(0.3)
	await _snap("show_04_cores_aged")
	# Stage 7: the pickup burst (test-only: collect the Blotter core).
	for core in get_nodes_in_group("cores"):
		if core.pair_id == "blotter":
			core.collect(player)
	await _wait(0.08)
	await _snap("show_04b_pickup_burst")
	for core in get_nodes_in_group("cores"):
		core.queue_free()

	# --- A healing station (NW building) -------------------------------------
	player.global_position = Vector3(-27.0, 0.0, -24.2)
	player.rotation.y = 0.35
	cam.rotation.x = deg_to_rad(-14.0)
	await _wait(0.8)
	await _snap("show_05_station")

	# --- Paint splats on a wall and the floor --------------------------------
	player.global_position = Vector3(38.0, 0.0, 0.0)
	player.rotation.y = -PI * 0.5      # face +X, the east wall
	cam.rotation.x = deg_to_rad(-12.0)
	var projectile_script = load("res://scripts/projectile.gd")
	var colors := [Color("#FFB7C5"), Color("#98FF98"), Color("#00A896"), Color("#58D7F2"), Color("#FF627E")]
	for i in 12:
		var glob = Node3D.new()
		glob.set_script(projectile_script)
		glob.color = colors[i % colors.size()]
		m.add_child(glob)
		var target := Vector3(45.0, randf_range(0.4, 3.0), randf_range(-3.0, 3.0))
		if i % 3 == 0:
			target = Vector3(randf_range(40.0, 43.0), 0.0, randf_range(-2.5, 2.5))
		var from := Vector3(39.0, 1.4, randf_range(-1.0, 1.0))
		glob.setup(from, target - from, true)
	await _wait(0.9)
	await _snap("show_06_splats")
	m.queue_free()
	await _wait(0.3)


func _arena_pass() -> void:
	var m = load("res://scenes/match.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	m._run_over = true
	await _wait(0.5)
	m.get_node("HUD").visible = false
	m.get_node("Player").visible = false
	var cam := Camera3D.new()
	cam.fov = 75.0
	m.add_child(cam)
	cam.current = true
	var views := [
		["arena_01_hub", Vector3(16.0, 2.2, 17.0), Vector3(0.0, 1.5, 0.0)],
		["arena_02_nw_storage", Vector3(-24.5, 1.7, -24.5), Vector3(-32.0, 2.4, -30.5)],
		["arena_03_ne_mixing", Vector3(21.0, 1.7, -22.0), Vector3(31.0, 3.0, -33.0)],
		["arena_04_sw_gallery", Vector3(-23.0, 5.1, 25.0), Vector3(-37.6, 3.4, 27.0)],
		["arena_05_south_lane", Vector3(0.0, -0.6, 19.5), Vector3(0.0, -1.6, 38.0)],
		["arena_06_corner", Vector3(38.5, 1.7, -30.0), Vector3(44.0, 2.2, -43.5)],
		["arena_07_overview", Vector3(34.0, 14.0, 34.0), Vector3(0.0, 0.0, 0.0)],
		["arena_08_books_close", Vector3(18.5, 1.6, 7.5), Vector3(15.0, 0.9, 3.0)],
		["arena_09_platform", Vector3(6.5, 4.5, 6.5), Vector3(0.0, 0.8, 0.0)],
		["arena_10_look_north", Vector3(0.0, 1.7, 15.0), Vector3(0.0, 10.0, -45.0)],
		["arena_11_look_south", Vector3(0.0, 1.7, -15.0), Vector3(0.0, 10.0, 45.0)],
		["arena_12_look_east", Vector3(-15.0, 1.7, 0.0), Vector3(45.0, 10.0, 0.0)],
		["arena_13_look_west", Vector3(15.0, 1.7, 0.0), Vector3(-45.0, 10.0, 0.0)],
	]
	for view in views:
		cam.global_position = view[1]
		cam.look_at(view[2])
		await _wait(0.4)
		await _snap(view[0])
	# Brightness probe: a patch of open, sunlit floor straight below the camera.
	cam.global_position = Vector3(30.0, 3.0, 4.0)
	cam.look_at(Vector3(30.0, 0.0, 0.0))
	await _wait(0.3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var total := 0.0
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	for x in range(cx - 20, cx + 20):
		for y in range(cy - 20, cy + 20):
			var c := img.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0
	print("[shot] sunlit floor average = %.0f / 255" % (total / 1600.0 * 255.0))
	m.queue_free()
	await _wait(0.3)


func _wardrobe_pass() -> void:
	var Data = load("res://scripts/character_customization_data.gd")
	var Dresser = load("res://scripts/visual/runner_dresser.gd")
	var m = load("res://scenes/match.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	m._run_over = true
	await _wait(0.5)
	m.get_node("HUD").visible = false
	m.get_node("Player").visible = false
	var cam := Camera3D.new()
	cam.fov = 50.0
	m.add_child(cam)
	cam.current = true
	# Each sheet: up to 7 runners in a row, each a {customization, team}.
	var sheets := {}
	var outfits: Array = []
	for skin in Data.SKINS + Data.BOT_SKINS:
		outfits.append({"skin": str(skin.id), "back_bling": outfits.size() % Data.BACK_BLING.size(), "gun_skin": outfits.size() % 10})
	sheets["wardrobe_outfits_1"] = outfits.slice(0, 7)
	sheets["wardrobe_outfits_2"] = outfits.slice(7, 14)
	var hats: Array = []
	for i in range(1, Data.HATS.size()):
		hats.append({"skin": "default", "body_color": i % 10, "hat": i, "mask": 0})
	sheets["wardrobe_hats_1"] = hats.slice(0, 5)
	sheets["wardrobe_hats_2"] = hats.slice(5, 9)
	var masks: Array = []
	for i in range(1, Data.MASKS.size()):
		masks.append({"skin": "default", "body_color": (i + 3) % 10, "mask": i})
	sheets["wardrobe_masks_1"] = masks.slice(0, 5)
	sheets["wardrobe_masks_2"] = masks.slice(5, 9)
	var backs: Array = []
	for i in Data.BACK_BLING.size():
		backs.append({"skin": "default", "body_color": i % 10, "back_bling": i, "gun_skin": i % 10})
	sheets["wardrobe_back_1"] = backs.slice(0, 6)
	sheets["wardrobe_back_2"] = backs.slice(6, 12)
	var guns: Array = []
	for i in 10:
		guns.append({"skin": "default", "body_color": 4, "gun_skin": i})
	sheets["wardrobe_guns_1"] = guns.slice(0, 5)
	sheets["wardrobe_guns_2"] = guns.slice(5, 10)
	for sheet_name in sheets:
		var row: Array = sheets[sheet_name]
		var built: Array = []
		for i in row.size():
			var custom: Dictionary = Data.create_session_data()
			custom.merge(row[i], true)
			var team := Color("#FF627E") if i % 2 == 0 else Color("#58D7F2")
			var runner = Dresser.build(custom, team)
			if runner == null:
				continue
			m.add_child(runner)
			runner.global_position = Vector3(26.0 + (i - (row.size() - 1) * 0.5) * 1.35, 0.0, 0.0)
			built.append(runner)
		var back_view: bool = sheet_name.begins_with("wardrobe_back")
		var close: bool = sheet_name.begins_with("wardrobe_hats") or sheet_name.begins_with("wardrobe_masks") or sheet_name.begins_with("wardrobe_guns")
		var width := maxf(row.size() * 1.35, 3.0)
		var dist := width * 0.95 if not close else width * 0.8
		var height := 1.0 if not close else 1.35
		var z := dist if not back_view else -dist
		for r in built:
			r.rotation.y = 0.0 if not back_view else 0.0
		cam.global_position = Vector3(26.0, height + 0.15, z)
		cam.look_at(Vector3(26.0, height, 0.0))
		await _wait(0.4)
		await _snap(sheet_name)
		if back_view:
			# Also a 3/4 view of the packs.
			cam.global_position = Vector3(26.0 + width * 0.55, height + 0.6, -dist * 0.8)
			cam.look_at(Vector3(26.0, height, 0.0))
			await _wait(0.2)
			await _snap(sheet_name + "_34")
		for r in built:
			r.queue_free()
		await _wait(0.1)
	m.queue_free()
	await _wait(0.3)
