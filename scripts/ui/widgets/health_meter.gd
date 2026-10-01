extends PanelContainer

## ============================================================================
## HEALTH METER - a big number plus a ten-segment bar.
## ============================================================================
##
## This widget stores nothing about the game. Whoever owns it (the Survival HUD
## or the TDM HUD) calls set_values() with the player's real health each time
## the player's stats_changed signal fires, and this only draws what it is told.
##
## Built from containers, not pixel positions: an HBoxContainer lines its
## children up left-to-right and a VBoxContainer top-to-bottom, sizing them
## automatically. That is what lets the HUD survive any window shape.

const UITheme = preload("res://scripts/ui/ui_theme.gd")

var _value_label: Label
var _max_label: Label
var _bar: SegmentBar
var _fraction: float = 1.0
var _time: float = 0.0


## An inner class: a tiny Control that only knows how to paint the bar. Kept
## inside this file because nothing else uses it.
class SegmentBar extends Control:
	const SEGMENTS := 10
	const GAP := 3.0
	var fraction: float = 1.0
	var fill: Color = Color.WHITE

	func _draw() -> void:
		var width := (size.x - GAP * (SEGMENTS - 1)) / SEGMENTS
		for i in SEGMENTS:
			var rect := Rect2(Vector2(i * (width + GAP), 0.0), Vector2(width, size.y))
			draw_rect(rect, Color(0.02, 0.025, 0.04, 0.7))
			# How much of THIS segment is filled, 0..1.
			var part := clampf(fraction * SEGMENTS - i, 0.0, 1.0)
			if part > 0.0:
				draw_rect(Rect2(rect.position, Vector2(width * part, size.y)), fill)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.09, 0.72),
		Color(UITheme.LINE, 0.8), 1, 8, 14.0, 10.0))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	_value_label = Label.new()
	_value_label.theme_type_variation = &"HudNumber"
	_value_label.custom_minimum_size = Vector2(62, 0)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_value_label)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(column)

	var caption_row := HBoxContainer.new()
	column.add_child(caption_row)
	var caption := Label.new()
	caption.theme_type_variation = &"HudCaption"
	caption.text = "HEALTH"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption_row.add_child(caption)
	_max_label = Label.new()
	_max_label.theme_type_variation = &"HudCaption"
	caption_row.add_child(_max_label)

	_bar = SegmentBar.new()
	_bar.custom_minimum_size = Vector2(210, 12)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_bar)


## The last numbers written to the labels. The player announces stats_changed
## up to 60 times a second (every physics step while Second Wind heals), and
## changing a Label's text makes Godot re-measure it and re-lay-out every
## container around it. So the labels are only touched when the number they
## SHOW actually changes. (Writing them every time cost ~7 ms per physics step.)
var _shown_health := -1
var _shown_max := -1


func set_values(health: float, max_health: float) -> void:
	_fraction = clampf(health / maxf(max_health, 1.0), 0.0, 1.0)
	# The player emits stats_changed BEFORE clamping a killing blow to zero, so
	# the raw value can briefly be negative. Never show less than 0.
	var shown := maxi(0, int(ceil(health)))
	if shown != _shown_health:
		_shown_health = shown
		_value_label.text = str(shown)
	if int(max_health) != _shown_max:
		_shown_max = int(max_health)
		_max_label.text = "/ %d" % _shown_max
	# Deeper red as it empties, so low health registers in peripheral vision
	# without reading the number. Redrawing the bar is cheap: no layout.
	_bar.fill = UITheme.HEALTH_LOW.lerp(UITheme.HEALTH_FULL, _fraction)
	_bar.fraction = _fraction
	_bar.queue_redraw()


func _process(delta: float) -> void:
	# Under 30% health the number gently pulses. Visual only.
	if _fraction > 0.0 and _fraction < 0.3:
		_time += delta
		_value_label.modulate = Color.WHITE.lerp(UITheme.HEALTH_FULL, 0.5 + 0.5 * sin(_time * 7.0))
	elif _value_label.modulate != Color.WHITE:
		_value_label.modulate = Color.WHITE
