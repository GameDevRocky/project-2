extends Control

## ============================================================================
## DEATH SCREEN - shown over the spectator view while you wait to respawn.
## ============================================================================
##
## Part of the TDM HUD (scripts/ui/tdm_hud.gd builds it and shows it while you
## are painted out). Three blocks:
##
##   top     PAINTED OUT, who did it, and the respawn countdown
##   bottom  the spectate bar: whose view you are watching, and buttons to
##           switch teammate (Q / E) or first/third person (V)
##   left    the LOADOUT: one card per gun (keys 1-5). The gun you pick is the
##           one you respawn with. It sits down the left side so the middle of
##           the screen (the teammate you watch) and the bottom right (their
##           gun, in first person) stay clear.
##
## Like every HUD script it only DRAWS and reports clicks. It never decides
## anything: the buttons emit signals, and the match controller (which owns the
## spectate target and the picked gun) does the work and tells this screen
## what to show.

signal weapon_picked(index: int)
signal spectate_step(direction: int)
signal view_toggled

const UITheme = preload("res://scripts/ui/ui_theme.gd")
const Weapons = preload("res://scripts/weapons.gd")

const CARD_SIZE := Vector2(300, 66)
const BAR_NAMES := ["DMG", "RATE", "RANGE"]

var _killer: Label
var _countdown: Label
var _spectating: Label
var _view_button: Button
var _prev_button: Button
var _next_button: Button
var _blurb: Label
var _cards: Array[Button] = []
var _selected := -1
var _shown_second := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_top()
	_build_spectate_bar()
	_build_loadout()


# ============================================================================
# CONSTRUCTION
# ============================================================================

func _build_top() -> void:
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 0)
	stack.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Below the score pill and its "YOU ARE TEAM" caption.
	stack.offset_top = 104.0
	add_child(stack)
	var title := Label.new()
	title.theme_type_variation = &"HudNumber"
	title.add_theme_font_size_override("font_size", 40)
	title.text = "PAINTED OUT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	_killer = Label.new()
	_killer.theme_type_variation = &"HudLabel"
	_killer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_killer)
	_countdown = Label.new()
	_countdown.theme_type_variation = &"HudNumber"
	_countdown.add_theme_font_size_override("font_size", 26)
	_countdown.add_theme_color_override("font_color", UITheme.WARN)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_countdown)


func _build_spectate_bar() -> void:
	var bar_holder := CenterContainer.new()
	bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar_holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar_holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar_holder.offset_bottom = -24.0
	add_child(bar_holder)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.09, 0.82),
		Color(UITheme.LINE, 0.9), 1, 10, 12.0, 6.0))
	bar_holder.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	_prev_button = _small_button(row, "◀  Q", func(): spectate_step.emit(-1))
	_spectating = Label.new()
	_spectating.theme_type_variation = &"HudLabel"
	_spectating.custom_minimum_size = Vector2(250, 0)
	_spectating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectating.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_spectating.size_flags_vertical = Control.SIZE_FILL
	_spectating.clip_text = true
	_spectating.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_spectating)
	_next_button = _small_button(row, "E  ▶", func(): spectate_step.emit(1))
	_view_button = _small_button(row, "V  THIRD PERSON", func(): view_toggled.emit())
	_view_button.custom_minimum_size = Vector2(190, 0)


func _build_loadout() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.09, 0.88),
		Color(UITheme.LINE, 0.9), 1, 12, 12.0, 12.0))
	# Pinned to the left edge, below the top of the screen.
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 24.0
	panel.offset_top = 96.0
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := Label.new()
	title.theme_type_variation = &"HudLabel"
	title.add_theme_font_override("font", UITheme.bold())
	title.text = "LOADOUT"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var keys := Label.new()
	keys.theme_type_variation = &"HudCaption"
	keys.text = "CLICK OR PRESS 1-5"
	keys.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	keys.size_flags_vertical = Control.SIZE_FILL
	heading.add_child(keys)
	for index in Weapons.count():
		_cards.append(_build_card(column, index))
	_blurb = Label.new()
	_blurb.theme_type_variation = &"BodyLabel"
	_blurb.add_theme_font_size_override("font_size", 13)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size = Vector2(CARD_SIZE.x, 54)
	column.add_child(_blurb)
	var hint := Label.new()
	hint.theme_type_variation = &"HudCaption"
	hint.text = "YOU RESPAWN WITH THE PICKED GUN"
	column.add_child(hint)


func _small_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(76, 38)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## One gun's card: key number, name and role on top, three small rating
## bars below, all drawn INSIDE a button (ignoring the mouse, so the click
## lands on the button).
func _build_card(parent: Control, index: int) -> Button:
	var weapon := Weapons.get_weapon(index)
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(func(): weapon_picked.emit(index))
	parent.add_child(card)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)
	var key := _card_label(top, str(index + 1), &"DimLabel")
	key.custom_minimum_size = Vector2(12, 0)
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.size_flags_vertical = Control.SIZE_FILL
	var name_label := _card_label(top, str(weapon.name), &"HeaderLabel")
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.name = "Name"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var role := _card_label(top, str(weapon.role), &"DimLabel")
	role.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	role.size_flags_vertical = Control.SIZE_FILL
	var bars := HBoxContainer.new()
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_theme_constant_override("separation", 12)
	column.add_child(bars)
	for bar_index in BAR_NAMES.size():
		_rating(bars, BAR_NAMES[bar_index], float(weapon.bars[bar_index]))
	return card


func _card_label(parent: Control, text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = variation
	label.text = text
	parent.add_child(label)
	return label


## A caption and a thin bar filled to `amount` (0..1).
func _rating(parent: Control, caption: String, amount: float) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var label := _card_label(row, caption, &"DimLabel")
	label.add_theme_font_size_override("font_size", 10)
	var track := Control.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.custom_minimum_size = Vector2(0, 6)
	row.add_child(track)
	var back := ColorRect.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.color = Color(1, 1, 1, 0.12)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.add_child(back)
	var fill := ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = UITheme.ACCENT
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(amount, 0.05, 1.0)
	track.add_child(fill)


# ============================================================================
# LIVE UPDATES (called by tdm_hud.gd with the controller's values)
# ============================================================================

func set_killer(killer_name: String, color: Color) -> void:
	_killer.text = "by %s" % killer_name if not killer_name.is_empty() else ""
	_killer.add_theme_color_override("font_color", color)


func set_countdown(seconds_left: float) -> void:
	var whole := int(ceil(seconds_left))
	if whole == _shown_second:
		return
	_shown_second = whole
	_countdown.text = "RESPAWN IN %d" % whole if whole > 0 else "RESPAWNING…"


## `who` empty = no living teammate to watch.
func set_spectating(who: String, color: Color, first_person: bool, can_switch: bool) -> void:
	var text := "SPECTATING  %s" % who if not who.is_empty() else "NO TEAMMATES TO SPECTATE"
	if _spectating.text != text:
		_spectating.text = text
	_spectating.add_theme_color_override("font_color", color if not who.is_empty() else UITheme.DIM)
	var view_text := "V  FIRST PERSON" if first_person else "V  THIRD PERSON"
	if _view_button.text != view_text:
		_view_button.text = view_text
	_view_button.disabled = who.is_empty()
	_prev_button.disabled = not can_switch
	_next_button.disabled = not can_switch


func set_selected(index: int, team_color: Color) -> void:
	if index == _selected:
		return
	_selected = index
	for i in _cards.size():
		var card := _cards[i]
		var on := i == index
		# The picked card gets a thick team-coloured border, like your own row
		# on the scoreboard.
		var style := UITheme.box(Color(team_color, 0.2) if on else Color(0.075, 0.085, 0.135, 0.9),
			team_color if on else UITheme.LINE, 3 if on else 1, 8, 0.0, 0.0)
		card.add_theme_stylebox_override("normal", style)
		var name_label := card.find_child("Name", true, false) as Label
		if name_label != null:
			name_label.add_theme_color_override("font_color", team_color if on else UITheme.TEXT)
	var weapon := Weapons.get_weapon(index)
	_blurb.text = str(weapon.blurb)
