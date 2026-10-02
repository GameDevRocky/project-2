extends PanelContainer

## ============================================================================
## INHERITANCE CARD - what you are carrying: one ability, one weakness.
## ============================================================================
##
## Reads a pair dictionary straight from traits.gd (via the player's `pair`).
## The benefit line is green with an up-arrow, the cost line red with a
## down-arrow, so the trade reads at a glance.
##
## Online, the same card shows the POWER you carry instead (set_power): Rocklyn's
## flying power balls replace the inheritance pickups there.
##
## The Apprentice Brush is special-cased on purpose. It has no ability and no
## weakness, and showing "▲ Nothing yet" in benefit-green made it look like a
## buff. It now says so plainly, in neutral grey.

const UITheme = preload("res://scripts/ui/ui_theme.gd")
const Traits = preload("res://scripts/traits.gd")
const Powers = preload("res://scripts/power_abilities.gd")

var _swatch: Swatch
var _name_label: Label
var _benefit_name: Label
var _benefit_desc: Label
var _cost_name: Label
var _cost_desc: Label
var _none_label: Label
var _hint_label: Label
var _style: StyleBoxFlat

## Optional line shown under the Apprentice state, e.g. how to inherit. Survival
## sets it; TDM leaves it empty because TDM never drops cores.
var apprentice_hint: String = ""


## A paint-drop swatch in the pair's colour, outlined so the charcoal Monolith
## pair and the white Ghost pair both stay visible on the dark card.
class Swatch extends Control:
	var color: Color = Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.36
		var drop := PackedVector2Array()
		for i in 20:
			var a := TAU * i / 20.0
			var p := Vector2(cos(a), sin(a)) * r
			# Pull the top point up into a droplet tip.
			if p.y < 0.0:
				p.y *= 1.0 + 0.55 * pow(absf(sin(a)), 6.0)
			drop.append(c + p + Vector2(0, r * 0.18))
		var outline := drop.duplicate()
		outline.append(drop[0])
		draw_colored_polygon(drop, color)
		draw_polyline(outline, Color(1, 1, 1, 0.75), 1.5, true)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(300, 0)
	_style = UITheme.box(Color(0.05, 0.055, 0.09, 0.72), Color(UITheme.LINE, 0.8), 1, 8, 14.0, 10.0)
	_style.border_width_left = 5
	add_theme_stylebox_override("panel", _style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	add_child(column)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	column.add_child(title_row)
	_swatch = Swatch.new()
	_swatch.custom_minimum_size = Vector2(22, 24)
	title_row.add_child(_swatch)
	_name_label = _make("HudLabel", 18, UITheme.TEXT, true)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_name_label)

	_benefit_name = _make("HudLabel", 15, UITheme.BENEFIT, true)
	column.add_child(_benefit_name)
	_benefit_desc = _make("HudLabel", 13, Color("#E6ECF2"), false)
	column.add_child(_benefit_desc)
	_cost_name = _make("HudLabel", 15, UITheme.COST, true)
	column.add_child(_cost_name)
	_cost_desc = _make("HudLabel", 13, Color("#E6ECF2"), false)
	column.add_child(_cost_desc)
	_none_label = _make("HudLabel", 14, UITheme.NEUTRAL, true)
	_none_label.text = "NO ABILITY  ·  NO WEAKNESS"
	column.add_child(_none_label)
	_hint_label = _make("HudCaption", 12, UITheme.DIM, false)
	column.add_child(_hint_label)


func _make(variation: StringName, font_size: int, color: Color, is_bold: bool) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if is_bold:
		label.add_theme_font_override("font", UITheme.bold())
	# Descriptions wrap rather than stretch the card off the screen.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A brief bright flash of the whole card when a new pair is taken, so the
## change of loadout catches the eye.
func flash() -> void:
	modulate = Color(1.8, 1.8, 1.8)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.45).set_ease(Tween.EASE_OUT)


func set_pair(pair: Dictionary, pair_id: String) -> void:
	if pair.is_empty():
		return
	var color: Color = pair["color"]
	_swatch.color = color
	_swatch.queue_redraw()
	# The left edge carries the pair colour. The charcoal pair would vanish
	# against the dark card, so very dark colours get a lighter edge instead.
	_style.border_color = color if color.get_luminance() > 0.25 else Color("#8A8DA8")
	_name_label.text = str(pair["name"]).to_upper()

	var apprentice := pair_id == Traits.starting_id()
	_benefit_name.visible = not apprentice
	_benefit_desc.visible = not apprentice
	_cost_name.visible = not apprentice
	_cost_desc.visible = not apprentice
	_none_label.visible = apprentice
	_hint_label.visible = apprentice and not apprentice_hint.is_empty()
	_hint_label.text = apprentice_hint
	if not apprentice:
		_benefit_name.text = "▲  %s" % str(pair["ability_name"]).to_upper()
		_benefit_desc.text = "     %s" % pair["ability_desc"]
		_cost_name.text = "▼  %s" % str(pair["weakness_name"]).to_upper()
		_cost_desc.text = "     %s" % pair["weakness_desc"]


## Online: the power you carry (scripts/power_abilities.gd), or how to get one.
func set_power(power_id: String, invisible: bool) -> void:
	var power := Powers.get_power(power_id)
	var has_power := not power.is_empty()
	var color: Color = power.get("color", UITheme.NEUTRAL) if has_power else UITheme.NEUTRAL
	_swatch.color = color
	_swatch.queue_redraw()
	_style.border_color = color
	_name_label.text = str(power.get("name", "POWER")) if has_power else "NO POWER"
	_benefit_name.visible = false
	_benefit_desc.visible = has_power
	_benefit_desc.text = str(power.get("description", ""))
	_cost_name.visible = has_power and invisible
	_cost_name.text = "▼  HIDDEN - YOU CANNOT SHOOT"
	_cost_desc.visible = false
	_none_label.visible = false
	_hint_label.visible = true
	_hint_label.text = ("TRADE IT AT A GREEN STATION (HOLD E) FOR FULL HEALTH + SHIELD" if has_power
		else "SHOOT DOWN A FLYING POWER BALL TO CLAIM ITS ABILITY")
