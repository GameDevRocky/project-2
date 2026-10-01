extends PanelContainer

## ============================================================================
## SCOREBOARD ROW - one line of the TDM scoreboard.
## ============================================================================
##
## WHY THE OLD COLUMNS DID NOT LINE UP
## The old board built each row as one string padded with spaces ("%-24s %3d").
## That only lines up in a typewriter-style font where every letter is equally
## wide. The game's font is proportional - an "i" is much narrower than a "W" -
## so the numbers drifted, and a long name shoved its stats to the right.
##
## THE FIX
## Each stat gets its own Label with a FIXED minimum width, and the name gets
## the leftover space (SIZE_EXPAND_FILL). Every row uses the same widths, so K,
## D and A sit in the same columns on every row, whatever the name. A long name
## is cut off with "…" (text_overrun_behavior) instead of pushing anything.

const UITheme = preload("res://scripts/ui/ui_theme.gd")

const RANK_WIDTH := 30.0
const STAT_WIDTH := 46.0

var _rank: Label
var _you_chip: PanelContainer
var _name: Label
var _kills: Label
var _deaths: Label
var _assists: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 30)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	add_child(line)

	_rank = _cell(line, RANK_WIDTH, HORIZONTAL_ALIGNMENT_CENTER)

	_you_chip = PanelContainer.new()
	_you_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_you_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_you_chip.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.WARN, 0.9),
		Color(UITheme.WARN, 0.9), 0, 4, 6.0, 1.0))
	var chip_text := Label.new()
	chip_text.text = "YOU"
	chip_text.add_theme_font_size_override("font_size", 11)
	chip_text.add_theme_font_override("font", UITheme.heavy())
	chip_text.add_theme_color_override("font_color", UITheme.INK)
	_you_chip.add_child(chip_text)
	_you_chip.visible = false
	line.add_child(_you_chip)

	_name = Label.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A small minimum so the name column can shrink, rather than a long name
	# forcing the whole panel wider.
	_name.custom_minimum_size = Vector2(60, 0)
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", 15)
	line.add_child(_name)

	_kills = _cell(line, STAT_WIDTH, HORIZONTAL_ALIGNMENT_CENTER)
	_kills.add_theme_font_override("font", UITheme.bold())
	_deaths = _cell(line, STAT_WIDTH, HORIZONTAL_ALIGNMENT_CENTER)
	_assists = _cell(line, STAT_WIDTH, HORIZONTAL_ALIGNMENT_CENTER)
	_set_style(false, Color.WHITE)


func _cell(parent: Control, width: float, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	parent.add_child(label)
	return label


## Turns this row into the column-title row ("#  PLAYER  K  D  A").
func set_header() -> void:
	add_theme_stylebox_override("panel", UITheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 10.0, 2.0))
	custom_minimum_size = Vector2(0, 22)
	_rank.text = "#"
	_name.text = "PLAYER"
	_kills.text = "K"
	_deaths.text = "D"
	_assists.text = "A"
	for label in [_rank, _name, _kills, _deaths, _assists]:
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", UITheme.DIM)
		label.add_theme_font_override("font", UITheme.bold())


func set_record(rank: int, player_name: String, kills: int, deaths: int, assists: int,
		is_local: bool, team_color: Color) -> void:
	_rank.text = str(rank)
	_name.text = player_name
	_kills.text = str(kills)
	_deaths.text = str(deaths)
	_assists.text = str(assists)
	_you_chip.visible = is_local
	var text_color := Color.WHITE if is_local else Color("#E4E6F0")
	for label in [_name, _kills, _deaths, _assists]:
		label.add_theme_color_override("font_color", text_color)
	_rank.add_theme_color_override("font_color", UITheme.DIM)
	if is_local:
		_name.add_theme_font_override("font", UITheme.bold())
	else:
		_name.remove_theme_font_override("font")
	_set_style(is_local, team_color)


## An unfilled slot (the team has fewer than ten players).
func set_empty(rank: int) -> void:
	_rank.text = str(rank)
	_name.text = "—"
	_kills.text = ""
	_deaths.text = ""
	_assists.text = ""
	_you_chip.visible = false
	_name.add_theme_color_override("font_color", UITheme.FAINT)
	_set_style(false, Color.WHITE)


func _set_style(is_local: bool, team_color: Color) -> void:
	var style: StyleBoxFlat
	if is_local:
		# The local player's row: a team-tinted background and a thick team
		# edge. Noticeable at a glance, but no flashing or animation.
		style = UITheme.box(Color(team_color, 0.2), Color(team_color, 0.9), 0, 5, 10.0, 3.0)
		style.border_width_left = 4
	else:
		style = UITheme.box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 0, 5, 10.0, 3.0)
	add_theme_stylebox_override("panel", style)
