extends RefCounted

## ============================================================================
## UI THEME - one shared look for the menu, the Survival HUD and the TDM HUD.
## ============================================================================
##
## WHAT A Theme IS
## Every Control node (Button, Label, Panel...) asks its Theme how to draw
## itself: which font size, which colours, which background box. A Theme set on
## one Control is inherited by all of its children. So instead of styling forty
## buttons one at a time, the menu hands this Theme to its root Control once and
## every button, label, slider and text box underneath picks it up.
##
## HOW OTHER SCRIPTS USE THIS FILE
## Like traits.gd, this has no class_name (so it cannot collide with a global
## name a teammate adds). Scripts write:
##
##     const UITheme = preload("res://scripts/ui/ui_theme.gd")
##     root.theme = UITheme.build()
##
## TYPE VARIATIONS
## A "type variation" is a named style that is still a Label (or Button...),
## just drawn differently. Setting `label.theme_type_variation = &"TitleLabel"`
## makes that one label big and bold without any per-node overrides.

# --- Team colours: the single source for red/blue across menu, HUD and bots.
const TEAM_RED := Color("#FF627E")
const TEAM_BLUE := Color("#58D7F2")

# --- Interface palette -------------------------------------------------------
const INK := Color("#12141F")            ## darkest panel / outline colour
const PANEL_BG := Color(0.07, 0.075, 0.115, 0.92)
const LINE := Color("#343952")          ## thin panel borders
const TEXT := Color("#F4F1FF")
const DIM := Color("#A7A9BC")
const FAINT := Color("#74788C")
const ACCENT := Color("#8CEADF")        ## default mint accent from the original menu
const WARN := Color("#FFE28D")          ## countdowns and "starting" states
const BENEFIT := Color("#8CFF9E")       ## the ability half of a pair
const COST := Color("#FF8FA0")          ## the weakness half of a pair
const NEUTRAL := Color("#C9CBD8")
const HEALTH_FULL := Color("#FF6B81")
const HEALTH_LOW := Color("#D62246")
const PAINT := Color("#39CDBD")
const PAINT_LOW := Color("#FFB45C")

## Built once and shared. `static var` keeps one copy for the whole game, so
## opening the menu five times does not build five identical themes.
static var _theme: Theme
static var _bold: FontVariation
static var _heavy: FontVariation


## A slightly heavier version of the default font, for headings. A
## FontVariation with no base_font wraps whatever the default font is.
static func bold() -> FontVariation:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.variation_embolden = 0.55
	return _bold


static func heavy() -> FontVariation:
	if _heavy == null:
		_heavy = FontVariation.new()
		_heavy.variation_embolden = 0.9
	return _heavy


static func team_color(team: String) -> Color:
	return TEAM_RED if team == "RED" else TEAM_BLUE


## A rounded box. Used for panels, buttons and rows. content_margin is the
## inner padding: it is what keeps button text off the button's border.
static func box(bg: Color, border: Color = LINE, border_width: int = 1,
		radius: int = 8, pad_x: float = 14.0, pad_y: float = 10.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	return style


## The standard dark panel, with a thin border in `accent`.
static func panel(accent: Color = LINE, border_width: int = 1) -> StyleBoxFlat:
	var style := box(PANEL_BG, accent, border_width, 10, 22.0, 18.0)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 10
	return style


static func build() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 16

	# --- Labels ------------------------------------------------------------
	t.set_color("font_color", "Label", TEXT)
	_label_variation(t, "TitleLabel", 38, TEXT, heavy())
	_label_variation(t, "HeaderLabel", 24, TEXT, bold())
	_label_variation(t, "SubLabel", 14, Color("#93E7DD"), bold())
	_label_variation(t, "BodyLabel", 15, Color("#DDE2EE"), null)
	_label_variation(t, "DimLabel", 12, DIM, null)
	# HUD text sits directly on the 3D world, so it gets a dark outline that
	# keeps it legible on the pale floor and the bright sky alike.
	_label_variation(t, "HudLabel", 15, TEXT, null)
	t.set_color("font_outline_color", "HudLabel", Color(INK, 0.9))
	t.set_constant("outline_size", "HudLabel", 5)
	_label_variation(t, "HudCaption", 12, DIM, bold())
	t.set_color("font_outline_color", "HudCaption", Color(INK, 0.9))
	t.set_constant("outline_size", "HudCaption", 4)
	_label_variation(t, "HudNumber", 30, TEXT, heavy())
	t.set_color("font_outline_color", "HudNumber", Color(INK, 0.9))
	t.set_constant("outline_size", "HudNumber", 6)

	# --- Buttons -----------------------------------------------------------
	var normal := box(Color(0.075, 0.085, 0.135, 0.9), LINE, 1, 6, 18.0, 10.0)
	var hover := box(Color(ACCENT, 0.16), ACCENT, 1, 6, 18.0, 10.0)
	hover.border_width_left = 4
	var pressed := box(Color(ACCENT, 0.26), ACCENT, 1, 6, 18.0, 10.0)
	pressed.border_width_left = 4
	var disabled := box(Color(0.06, 0.065, 0.1, 0.6), Color(LINE, 0.5), 1, 6, 18.0, 10.0)
	# The focus box is drawn ON TOP of the normal/hover box when the button has
	# keyboard focus, so it is border-only: no fill, just a brighter outline.
	var focus := box(Color(0, 0, 0, 0), Color(TEXT, 0.85), 2, 7, 18.0, 10.0)
	focus.draw_center = false
	focus.set_expand_margin_all(2.0)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_hover_pressed_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", FAINT)
	t.set_font("font", "Button", bold())
	t.set_font_size("font_size", "Button", 16)

	# --- Panels ------------------------------------------------------------
	t.set_stylebox("panel", "PanelContainer", panel())

	# --- Text entry --------------------------------------------------------
	var edit := box(Color(0.04, 0.045, 0.07, 0.95), LINE, 1, 6, 12.0, 8.0)
	var edit_focus := box(Color(0.04, 0.045, 0.07, 0.95), ACCENT, 2, 6, 12.0, 8.0)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", FAINT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_font_size("font_size", "LineEdit", 17)

	# --- Sliders -----------------------------------------------------------
	var track := box(Color(0.03, 0.035, 0.06, 1.0), LINE, 1, 4, 0.0, 3.0)
	var filled := box(Color(ACCENT, 0.85), Color(ACCENT, 0.85), 0, 4, 0.0, 3.0)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)

	_theme = t
	return t


static func _label_variation(t: Theme, name: StringName, size: int, color: Color,
		font: Font) -> void:
	t.set_type_variation(name, "Label")
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)
	if font != null:
		t.set_font("font", name, font)


## Gives one button its own accent colour (the original menu tinted PLAY pink,
## LEAVE QUEUE rose, and so on). Only the hover/pressed boxes change; the
## shared normal box stays so every button still sits in the same family.
static func accent_button(button: Button, accent: Color) -> void:
	var hover := box(Color(accent, 0.16), accent, 1, 6, 18.0, 10.0)
	hover.border_width_left = 4
	var pressed := box(Color(accent, 0.26), accent, 1, 6, 18.0, 10.0)
	pressed.border_width_left = 4
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_color_override("font_hover_color", accent)
	button.add_theme_color_override("font_pressed_color", accent)
	button.add_theme_color_override("font_hover_pressed_color", accent)
