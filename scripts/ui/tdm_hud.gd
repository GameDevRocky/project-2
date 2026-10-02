extends CanvasLayer

## ============================================================================
## TDM HUD - everything drawn over a Team Death Match.
## ============================================================================
##
## Created and owned by tdm_match_controller.gd, which is still the TDM UX
## owner in MECHANICS.md. This file only DRAWS; it never counts anything:
##
##   health, paint, pair   read from the local player (its stats_changed and
##                         pair_inherited signals, and its health/ammo values)
##   scores, clock, K/D/A  read from the controller (scores, remaining, players)
##   respawn countdown     read from the controller's respawn timer
##
## WHAT A CanvasLayer IS
## A flat 2D sheet drawn on top of the finished 3D picture, in screen pixels,
## so HUD elements stay put and stay the same size wherever the camera points.
##
## ANCHORS
## Each block is pinned to a screen edge with anchors (top-centre, bottom-left,
## bottom-right) plus a margin, instead of a hand-typed pixel position. When
## the window changes shape the blocks stay in their corners.

const UITheme = preload("res://scripts/ui/ui_theme.gd")
const CrosshairScript = preload("res://scripts/ui/widgets/crosshair.gd")
const HealthMeterScript = preload("res://scripts/ui/widgets/health_meter.gd")
const PaintTankScript = preload("res://scripts/ui/widgets/paint_tank_meter.gd")
const InheritanceCardScript = preload("res://scripts/ui/widgets/inheritance_card.gd")
const ScreenFxScript = preload("res://scripts/ui/widgets/screen_fx.gd")
const ScoreboardScript = preload("res://scripts/ui/tdm_scoreboard.gd")
const DeathScreenScript = preload("res://scripts/ui/death_screen.gd")
const Powers = preload("res://scripts/power_abilities.gd")
const Weapons = preload("res://scripts/weapons.gd")

const SAFE_MARGIN := 24.0

## Untyped on purpose: the controller and player expose functions this project
## added (local_respawn_time_left, is_dead...), which a variable typed as an
## engine class would reject at parse time.
var _controller = null
var _player = null
var _team := "BLUE"

var _root: Control
var _fx
var _crosshair
var _health
var _paint
var _pair_card
var _red_score: Label
var _blue_score: Label
var _clock: Label
var _scoreboard
## The death screen (scripts/ui/death_screen.gd): countdown, spectate bar and
## loadout, shown while you wait to respawn.
var _respawn: Control
var _bottom_left: Control
var _feed: VBoxContainer
## Rocklyn's always-on team leaderboards (kills and deaths per player), RED in
## the top-left corner and BLUE in the top-right.
var _boards: Dictionary = {}
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
var _next_round: Label
var _result: Control
var _last_ammo: float = -1.0
var _shown_second: int = -1
var _scoreboard_tween: Tween
## Whether the board is meant to be up (it stays visible for 0.08 s while it
## fades out, so `visible` alone is not the answer).
var _scoreboard_wanted := false


func _init() -> void:
	layer = 20
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UITheme.build()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_fx = ScreenFxScript.new()
	_root.add_child(_fx)
	_crosshair = CrosshairScript.new()
	_root.add_child(_crosshair)


## Called once by the controller, after this node is in the tree.
func setup(controller, player, team: String) -> void:
	_controller = controller
	_player = player
	_team = team
	_build_score_pill()
	_build_bottom_left()
	_build_bottom_right()
	_build_respawn_overlay()
	_build_leaderboards()
	_build_banner()
	_scoreboard = ScoreboardScript.new()
	_scoreboard.visible = false
	_root.add_child(_scoreboard)

	# Connect to the player's announcements. The player keeps no idea this HUD
	# exists - it just emits, and whoever is listening redraws.
	player.stats_changed.connect(_on_stats_changed)
	player.hurt.connect(Callable(_fx, "flash_hurt"))
	player.pair_inherited.connect(_on_pair_inherited)
	if player.has_signal("hit_confirmed"):
		player.hit_confirmed.connect(_crosshair.show_hit)
	# Online (Rocklyn's branch): the card shows the power you carry, not a pair.
	if player.has_signal("power_changed"):
		player.power_changed.connect(_on_power_changed)
	_on_stats_changed()
	if NetworkSession.is_in_match():
		_show_power(str(player.current_power), bool(player.power_invisible))
	else:
		_pair_card.set_pair(player.pair, str(player.pair_id))
	refresh_scores()
	update_clock(float(controller.remaining))


# ============================================================================
# CONSTRUCTION
# ============================================================================

func _build_score_pill() -> void:
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 4)
	# Pinned to the top-centre. GROW_DIRECTION_BOTH makes it widen evenly to
	# both sides as its contents need room, so it stays centred.
	stack.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	stack.offset_top = 14.0
	_root.add_child(stack)

	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.09, 0.8),
		Color(UITheme.LINE, 0.9), 1, 10, 16.0, 4.0))
	stack.add_child(pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	pill.add_child(row)

	_red_score = _team_block(row, "RED", false)
	var divider_left := _divider()
	row.add_child(divider_left)
	_clock = Label.new()
	_clock.theme_type_variation = &"HudNumber"
	_clock.add_theme_font_size_override("font_size", 32)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Fixed width, so the pill does not twitch as the digits change.
	_clock.custom_minimum_size = Vector2(104, 0)
	row.add_child(_clock)
	row.add_child(_divider())
	_blue_score = _team_block(row, "BLUE", true)

	var you := Label.new()
	you.theme_type_variation = &"HudCaption"
	you.text = "FIRST TO %d  •  YOU ARE TEAM %s" % [NetworkSession.TDM_KILL_LIMIT, _team]
	you.add_theme_color_override("font_color", UITheme.team_color(_team))
	you.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(you)


## One side of the score pill: team name and score, with a team-coloured bar
## under it for YOUR team only.
func _team_block(parent: Control, team: String, score_first: bool) -> Label:
	var color := UITheme.team_color(team)
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 0)
	block.custom_minimum_size = Vector2(118, 0)
	parent.add_child(block)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 10)
	block.add_child(line)
	var name_label := Label.new()
	name_label.theme_type_variation = &"HudLabel"
	name_label.text = team
	name_label.add_theme_font_override("font", UITheme.bold())
	name_label.add_theme_color_override("font_color", color)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var score := Label.new()
	score.theme_type_variation = &"HudNumber"
	score.add_theme_font_size_override("font_size", 28)
	score.add_theme_color_override("font_color", color)
	score.custom_minimum_size = Vector2(42, 0)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if score_first:
		line.add_child(score)
		line.add_child(name_label)
	else:
		line.add_child(name_label)
		line.add_child(score)
	var underline := ColorRect.new()
	underline.color = color if team == _team else Color(0, 0, 0, 0)
	underline.custom_minimum_size = Vector2(0, 3)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(underline)
	return score


func _divider() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.18)
	rule.custom_minimum_size = Vector2(1, 30)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _build_bottom_left() -> void:
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 8)
	stack.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	# Grow UP from the bottom-left corner as the card gets taller.
	stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stack.offset_left = SAFE_MARGIN
	stack.offset_bottom = -SAFE_MARGIN
	_root.add_child(stack)
	_bottom_left = stack
	_pair_card = InheritanceCardScript.new()
	stack.add_child(_pair_card)
	_health = HealthMeterScript.new()
	stack.add_child(_health)


func _build_bottom_right() -> void:
	_paint = PaintTankScript.new()
	_paint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_paint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_paint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_paint.offset_right = -SAFE_MARGIN
	_paint.offset_bottom = -SAFE_MARGIN
	_root.add_child(_paint)


func _build_respawn_overlay() -> void:
	_respawn = DeathScreenScript.new()
	_respawn.visible = false
	_root.add_child(_respawn)
	# The screen only reports the click; the controller owns the spectator
	# camera and does the work.
	_respawn.view_toggled.connect(func(): _controller.toggle_spectate_view())


## RED's board in the top-left corner; BLUE's in the top-right, with the
## elimination feed under it.
func _build_leaderboards() -> void:
	for team in ["RED", "BLUE"]:
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 8)
		column.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT if team == "RED" else Control.PRESET_TOP_RIGHT)
		if team == "RED":
			column.offset_left = SAFE_MARGIN
		else:
			column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			column.offset_right = -SAFE_MARGIN
		column.offset_top = SAFE_MARGIN
		_root.add_child(column)
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.custom_minimum_size = Vector2(220, 0)
		var style := UITheme.box(Color(0.05, 0.055, 0.09, 0.66), Color(UITheme.LINE, 0.7), 1, 8, 12.0, 8.0)
		style.border_width_top = 3
		style.border_color = Color(UITheme.team_color(team), 0.9)
		panel.add_theme_stylebox_override("panel", style)
		column.add_child(panel)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 1)
		panel.add_child(rows)
		var header := HBoxContainer.new()
		rows.add_child(header)
		var title := Label.new()
		title.theme_type_variation = &"HudLabel"
		title.add_theme_font_override("font", UITheme.bold())
		title.add_theme_color_override("font_color", UITheme.team_color(team))
		title.text = "%s LEADERBOARD" % team
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		var caption := Label.new()
		caption.theme_type_variation = &"HudCaption"
		caption.text = "K / D"
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.size_flags_vertical = Control.SIZE_FILL
		header.add_child(caption)
		_boards[team] = rows
		if team == "BLUE":
			_feed = VBoxContainer.new()
			_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_feed.add_theme_constant_override("separation", 4)
			column.add_child(_feed)


## Rebuilds both leaderboards from the controller's records: most kills first,
## then fewest deaths, then name. Called when a score changes, never per frame.
func _refresh_leaderboards() -> void:
	for team in _boards.keys():
		var rows: VBoxContainer = _boards[team]
		# Keep the header (child 0); rebuild the player lines under it.
		for i in range(rows.get_child_count() - 1, 0, -1):
			var old := rows.get_child(i)
			rows.remove_child(old)
			old.queue_free()
		var members: Array = []
		for record in _controller.players:
			if str(record.get("team", "")) == team:
				members.append(record)
		members.sort_custom(func(a, b):
			if int(a.get("kills", 0)) != int(b.get("kills", 0)):
				return int(a.get("kills", 0)) > int(b.get("kills", 0))
			if int(a.get("deaths", 0)) != int(b.get("deaths", 0)):
				return int(a.get("deaths", 0)) < int(b.get("deaths", 0))
			return str(a.get("name", "")) < str(b.get("name", "")))
		for record in members:
			var line := HBoxContainer.new()
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rows.add_child(line)
			var is_local := bool(record.get("is_local", false))
			var name_label := Label.new()
			name_label.theme_type_variation = &"HudCaption"
			name_label.add_theme_font_size_override("font_size", 13)
			name_label.add_theme_color_override("font_color", UITheme.WARN if is_local else UITheme.TEXT)
			name_label.text = str(record.get("name", "Player"))
			name_label.clip_text = true
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(name_label)
			var stats_label := Label.new()
			stats_label.theme_type_variation = &"HudCaption"
			stats_label.add_theme_font_size_override("font_size", 13)
			stats_label.add_theme_color_override("font_color", UITheme.WARN if is_local else UITheme.TEXT)
			stats_label.text = "%d / %d" % [int(record.get("kills", 0)), int(record.get("deaths", 0))]
			line.add_child(stats_label)


## Big centred text that fades in and out on its own: a power picked up.
func _build_banner() -> void:
	_banner = VBoxContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = -170.0
	_banner.offset_bottom = -110.0
	_banner.modulate.a = 0.0
	_root.add_child(_banner)
	_banner_title = Label.new()
	_banner_title.theme_type_variation = &"HudNumber"
	_banner_title.add_theme_font_size_override("font_size", 34)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_title)
	_banner_sub = Label.new()
	_banner_sub.theme_type_variation = &"HudLabel"
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_sub)


func announce(title: String, subtitle: String = "", color: Color = UITheme.TEXT) -> void:
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", color)
	_banner_sub.text = subtitle
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.18)
	_banner_tween.tween_interval(1.6)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)


# ============================================================================
# LIVE UPDATES
# ============================================================================

## One line in the elimination feed: "ATTACKER  ✕  VICTIM", each name in its
## team colour. Only the last FEED_LINES stay; each fades out after a while.
const FEED_LINES := 4
const FEED_SECONDS := 5.0

func add_feed_entry(attacker: String, attacker_color: Color, victim: String, victim_color: Color) -> void:
	if _feed == null:
		return
	var line := PanelContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_SHRINK_END
	line.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.09, 0.72),
		Color(0, 0, 0, 0), 0, 6, 10.0, 3.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	line.add_child(row)
	for part in [[attacker, attacker_color], ["✕", UITheme.DIM], [victim, victim_color]]:
		var label := Label.new()
		label.theme_type_variation = &"HudCaption"
		label.add_theme_font_size_override("font_size", 15)
		label.text = str(part[0])
		label.add_theme_color_override("font_color", part[1])
		row.add_child(label)
	_feed.add_child(line)
	while _feed.get_child_count() > FEED_LINES:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
	var tween := line.create_tween()
	tween.tween_interval(FEED_SECONDS)
	tween.tween_property(line, "modulate:a", 0.0, 0.5)
	tween.tween_callback(line.queue_free)


func _on_stats_changed() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var ammo: float = _player.ammo
	var max_ammo: float = _player.get_max_ammo()
	_health.set_values(float(_player.health), float(_player.max_health))
	if NetworkSession.is_in_match():
		_health.set_shield(float(_player.shield), float(_player.max_shield))
	_fx.set_health_fraction(float(_player.health) / maxf(float(_player.max_health), 1.0))
	_paint.set_values(ammo, max_ammo)
	# A shot costs exactly one paint, so a drop of about one means "just fired".
	if _last_ammo >= 0.0 and ammo <= _last_ammo - 0.99:
		_crosshair.pulse()
	_last_ammo = ammo


## A power picked up, traded, or invisibility switched (online).
func _on_power_changed(power_id: String, invisible: bool) -> void:
	_show_power(power_id, invisible)
	_pair_card.flash()
	if not power_id.is_empty() and not invisible:
		var power := Powers.get_power(power_id)
		announce(str(power.get("name", "POWER")), str(power.get("description", "")),
			power.get("color", UITheme.TEXT))


## The power card, and the gun's name over the paint tank (the gun model in
## your hands changes with the power - scripts/weapons.gd).
func _show_power(power_id: String, invisible: bool) -> void:
	_pair_card.set_power(power_id, invisible)
	_paint.set_caption(str(Weapons.for_power(power_id).name))


func _on_pair_inherited(pair: Dictionary) -> void:
	_pair_card.set_pair(pair, str(_player.pair_id))
	_pair_card.flash()


func refresh_scores() -> void:
	if _controller == null:
		return
	_refresh_leaderboards()
	_red_score.text = str(int(_controller.scores.get("RED", 0)))
	_blue_score.text = str(int(_controller.scores.get("BLUE", 0)))


## Only while the board is OPEN. The controller calls this on every death, and
## rebuilding twenty hidden rows (about a hundred labels) inside the physics
## step cost ~3 ms per step for nothing. Opening the board refreshes it first.
func refresh_scoreboard() -> void:
	if _controller == null or _scoreboard == null or not _scoreboard_wanted:
		return
	_scoreboard.refresh(_controller.players, _controller.scores, float(_controller.remaining))


func update_clock(remaining: float) -> void:
	var whole := int(ceil(remaining))
	if whole == _shown_second:
		return
	_shown_second = whole
	_clock.text = ScoreboardScript.format_time(remaining)
	# The last 30 seconds turn the clock warm, so the end is noticed.
	_clock.add_theme_color_override("font_color", UITheme.WARN if whole <= 30 else UITheme.TEXT)


func set_scoreboard_visible(wanted: bool) -> void:
	if _scoreboard == null or _scoreboard_wanted == wanted:
		return
	_scoreboard_wanted = wanted
	if _scoreboard_tween != null and _scoreboard_tween.is_valid():
		_scoreboard_tween.kill()
	if wanted:
		# Fade in fast (0.1 s) so holding Tab still feels instant.
		_scoreboard.visible = true
		_scoreboard.modulate.a = 0.0
		refresh_scoreboard()
		_scoreboard_tween = create_tween()
		_scoreboard_tween.tween_property(_scoreboard, "modulate:a", 1.0, 0.1)
	else:
		_scoreboard_tween = create_tween()
		_scoreboard_tween.tween_property(_scoreboard, "modulate:a", 0.0, 0.08)
		_scoreboard_tween.tween_callback(func(): _scoreboard.visible = false)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _result != null:
		return
	var dead: bool = _player.is_dead()
	_respawn.visible = dead
	_crosshair.visible = not dead
	# While you watch someone, the corners showing your own health and paint
	# are hidden: they would only say zero.
	_bottom_left.visible = not dead
	_paint.visible = not dead
	if dead:
		_respawn.set_countdown(float(_controller.local_respawn_time_left()))
		_respawn.set_killer(_controller.killed_by_name, _controller.killed_by_color)
		_respawn.set_spectating(_controller.spectate_name(), _controller.spectate_color(),
			_controller.spectate_first_person())


# ============================================================================
# END OF MATCH
# ============================================================================

## Builds the result screen. The winner text and every number come from the
## controller; `on_return` is the controller's own "back to menu" action.
func show_result(winner: String, winner_color: Color, kills: int, deaths: int,
		assists: int, on_return: Callable) -> void:
	update_clock(0.0)
	if _scoreboard_tween != null and _scoreboard_tween.is_valid():
		_scoreboard_tween.kill()
	_scoreboard_wanted = false
	_scoreboard.visible = false
	_respawn.visible = false
	_crosshair.visible = false

	_result = Control.new()
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_result)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.05, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	var style := UITheme.panel(Color(winner_color, 0.9), 2)
	style.border_width_top = 6
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", winner_color)
	title.text = winner
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var caption := Label.new()
	caption.theme_type_variation = &"DimLabel"
	caption.text = "FINAL SCORE"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption)

	var scores := HBoxContainer.new()
	scores.alignment = BoxContainer.ALIGNMENT_CENTER
	scores.add_theme_constant_override("separation", 28)
	column.add_child(scores)
	_result_team(scores, "RED", int(_controller.scores.get("RED", 0)))
	var dash := Label.new()
	dash.theme_type_variation = &"HeaderLabel"
	dash.text = "—"
	dash.add_theme_color_override("font_color", UITheme.FAINT)
	dash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dash.size_flags_vertical = Control.SIZE_FILL
	scores.add_child(dash)
	_result_team(scores, "BLUE", int(_controller.scores.get("BLUE", 0)))

	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.12)
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)

	var mine := Label.new()
	mine.theme_type_variation = &"DimLabel"
	mine.text = "YOUR MATCH"
	mine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(mine)
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 40)
	column.add_child(stats)
	_result_stat(stats, "KILLS", kills)
	_result_stat(stats, "DEATHS", deaths)
	_result_stat(stats, "ASSISTS", assists)

	var button := Button.new()
	button.text = "RETURN TO MAIN MENU"
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(320, 52)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.accent_button(button, winner_color)
	button.pressed.connect(on_return)
	column.add_child(button)
	# Rocklyn's round format: the next round starts by itself after the
	# intermission. The controller counts it down through set_next_round().
	_next_round = Label.new()
	_next_round.theme_type_variation = &"DimLabel"
	_next_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_next_round)
	var focus := func():
		if is_instance_valid(button) and button.is_inside_tree():
			button.grab_focus()
	focus.call_deferred()


## "NEXT ROUND IN 7" under the result, while the intermission runs.
func set_next_round(seconds_left: float) -> void:
	if _next_round == null:
		return
	var text := "NEXT ROUND IN %d" % int(ceil(seconds_left)) if seconds_left > 0.0 else "NEXT ROUND STARTING…"
	if _next_round.text != text:
		_next_round.text = text


func _result_team(parent: Control, team: String, score: int) -> void:
	var block := VBoxContainer.new()
	parent.add_child(block)
	var number := Label.new()
	number.theme_type_variation = &"TitleLabel"
	number.add_theme_font_size_override("font_size", 44)
	number.add_theme_color_override("font_color", UITheme.team_color(team))
	number.text = str(score)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	block.add_child(number)
	var name_label := Label.new()
	name_label.theme_type_variation = &"SubLabel"
	name_label.add_theme_color_override("font_color", UITheme.team_color(team))
	name_label.text = "TEAM %s" % team
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	block.add_child(name_label)


func _result_stat(parent: Control, caption_text: String, value: int) -> void:
	var block := VBoxContainer.new()
	block.custom_minimum_size = Vector2(90, 0)
	parent.add_child(block)
	var number := Label.new()
	number.theme_type_variation = &"HeaderLabel"
	number.add_theme_font_size_override("font_size", 30)
	number.text = str(value)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	block.add_child(number)
	var caption := Label.new()
	caption.theme_type_variation = &"DimLabel"
	caption.text = caption_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	block.add_child(caption)
