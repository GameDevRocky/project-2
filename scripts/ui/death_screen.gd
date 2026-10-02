extends Control

## ============================================================================
## DEATH SCREEN - shown over the spectator view while you are painted out.
## ============================================================================
##
## Built by both HUDs (scripts/ui/tdm_hud.gd and scripts/hud.gd) and shown
## while you are dead. Two blocks:
##
##   top     PAINTED OUT, who did it, and the respawn countdown (Team
##           Deathmatch) or "OUT UNTIL THE NEXT ROUND" (Survival, one life)
##   bottom  the spectate bar: whose view you are watching and a button to
##           switch first / third person (V)
##
## WHO you watch is Rocklyn's rule (the match controller): the player who
## painted you out, and if they go down too, whoever got them. HOW you watch -
## from their eyes or over their shoulder - is your choice, and it sticks
## between deaths.
##
## Like every HUD script it only DRAWS and reports clicks: the button emits a
## signal, and the match controller (which owns the spectator camera) does the
## work and tells this screen what to show.

signal view_toggled

const UITheme = preload("res://scripts/ui/ui_theme.gd")

var _killer: Label
var _countdown: Label
var _spectating: Label
var _view_button: Button
var _shown_second := -2


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_top()
	_build_spectate_bar()


# ============================================================================
# CONSTRUCTION
# ============================================================================

func _build_top() -> void:
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 0)
	stack.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Below the score pill and its caption.
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
	_spectating = Label.new()
	_spectating.theme_type_variation = &"HudLabel"
	_spectating.custom_minimum_size = Vector2(300, 0)
	_spectating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectating.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_spectating.size_flags_vertical = Control.SIZE_FILL
	_spectating.clip_text = true
	_spectating.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_spectating)
	_view_button = Button.new()
	_view_button.text = "V  THIRD PERSON"
	_view_button.focus_mode = Control.FOCUS_NONE
	_view_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_view_button.custom_minimum_size = Vector2(190, 38)
	_view_button.pressed.connect(func(): view_toggled.emit())
	row.add_child(_view_button)


# ============================================================================
# LIVE UPDATES (called by the HUD with the match controller's values)
# ============================================================================

func set_killer(killer_name: String, color: Color) -> void:
	var text := "by %s" % killer_name if not killer_name.is_empty() else ""
	if _killer.text != text:
		_killer.text = text
	_killer.add_theme_color_override("font_color", color)


## Seconds until you respawn; a negative number means you do not respawn this
## round (Survival is one life).
func set_countdown(seconds_left: float) -> void:
	var whole := -1 if seconds_left < 0.0 else int(ceil(seconds_left))
	if whole == _shown_second:
		return
	_shown_second = whole
	if whole < 0:
		_countdown.text = "OUT UNTIL THE NEXT ROUND"
	elif whole > 0:
		_countdown.text = "RESPAWN IN %d" % whole
	else:
		_countdown.text = "RESPAWNING…"


## `who` empty = nobody left to watch.
func set_spectating(who: String, color: Color, first_person: bool) -> void:
	var text := "SPECTATING  %s" % who if not who.is_empty() else "NOBODY LEFT TO SPECTATE"
	if _spectating.text != text:
		_spectating.text = text
	_spectating.add_theme_color_override("font_color", color if not who.is_empty() else UITheme.DIM)
	var view_text := "V  FIRST PERSON" if first_person else "V  THIRD PERSON"
	if _view_button.text != view_text:
		_view_button.text = view_text
	_view_button.disabled = who.is_empty()
