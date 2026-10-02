extends Control

## ============================================================================
## TDM SCOREBOARD - the live roster shown while TAB is held.
## ============================================================================
##
## Two team panels side by side, each with its total, a column-title row and
## ten player rows. Everything is laid out by containers; nothing is placed at
## a hand-typed pixel position, so it stays centred at any window size.
##
## It owns NO match data. refresh() is handed the controller's live `players`,
## `scores` and `remaining` and simply redraws them. tdm_match_controller.gd is
## still the only place kills, deaths, assists and scores are counted.

const UITheme = preload("res://scripts/ui/ui_theme.gd")
const RowScript = preload("res://scripts/ui/scoreboard_row.gd")
const ROWS_PER_TEAM := 10

var _timer_label: Label
var _team_score: Dictionary = {}     # "RED"/"BLUE" -> Label
var _team_rows: Dictionary = {}      # "RED"/"BLUE" -> Array of rows


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.05, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# CenterContainer keeps its one child in the middle of the screen at its
	# natural size, whatever the window shape.
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	centre.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "TEAM DEATHMATCH"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var time_caption := Label.new()
	time_caption.theme_type_variation = &"DimLabel"
	time_caption.text = "TIME LEFT"
	time_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_caption.size_flags_vertical = Control.SIZE_FILL
	header.add_child(time_caption)
	_timer_label = Label.new()
	_timer_label.theme_type_variation = &"HeaderLabel"
	_timer_label.custom_minimum_size = Vector2(80, 0)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_timer_label)

	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 24)
	column.add_child(teams)
	teams.add_child(_build_team_panel("RED"))
	teams.add_child(_build_team_panel("BLUE"))

	var hint := Label.new()
	hint.theme_type_variation = &"DimLabel"
	hint.text = "RELEASE  TAB  TO CLOSE"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


func _build_team_panel(team: String) -> PanelContainer:
	var color := UITheme.team_color(team)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(540, 0)
	var style := UITheme.panel(Color(color, 0.85), 2)
	style.border_width_top = 5
	style.content_margin_left = 16
	style.content_margin_right = 16
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var name_label := Label.new()
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.text = "TEAM %s" % team
	name_label.add_theme_color_override("font_color", color)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(name_label)
	var score := Label.new()
	score.theme_type_variation = &"TitleLabel"
	score.add_theme_color_override("font_color", color)
	score.text = "0"
	header.add_child(score)
	_team_score[team] = score

	var column_titles := RowScript.new()
	column.add_child(column_titles)
	column_titles.set_header()

	var rule := ColorRect.new()
	rule.color = Color(color, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

	var rows: Array = []
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	column.add_child(list)
	for i in ROWS_PER_TEAM:
		var row := RowScript.new()
		list.add_child(row)
		rows.append(row)
	_team_rows[team] = rows
	return panel


## Redraws every row from the controller's live records. Called by the
## controller four times a second while TAB is held, and on every death.
func refresh(players: Array, scores: Dictionary, remaining: float) -> void:
	_timer_label.text = format_time(remaining)
	for team in ["RED", "BLUE"]:
		(_team_score[team] as Label).text = str(int(scores.get(team, 0)))
		var members: Array = []
		for record in players:
			if str(record.get("team", "")) == team:
				members.append(record)
		# Display order only: most kills first, then fewest deaths, then name.
		members.sort_custom(_ranks_before)
		var rows: Array = _team_rows[team]
		for i in rows.size():
			var row = rows[i]
			if i < members.size():
				var record: Dictionary = members[i]
				row.set_record(i + 1, str(record.get("name", "Player")),
					int(record.get("kills", 0)), int(record.get("deaths", 0)),
					int(record.get("assists", 0)),
					bool(record.get("is_local", false)) or str(record.get("id", "")) == "local",
					UITheme.team_color(team))
			else:
				row.set_empty(i + 1)


func _ranks_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("kills", 0)) != int(b.get("kills", 0)):
		return int(a.get("kills", 0)) > int(b.get("kills", 0))
	if int(a.get("deaths", 0)) != int(b.get("deaths", 0)):
		return int(a.get("deaths", 0)) < int(b.get("deaths", 0))
	return str(a.get("name", "")) < str(b.get("name", ""))


## Same rounding as the controller always used: 9:59.2 shows as 10:00 until the
## whole second has passed, so the clock reaches 00:00 exactly at the end.
static func format_time(seconds: float) -> String:
	var whole := int(ceil(seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]
