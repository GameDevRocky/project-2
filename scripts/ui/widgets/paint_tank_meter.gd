extends PanelContainer

## ============================================================================
## PAINT TANK METER - the paint reservoir drawn as a tank, not an ammo count.
## ============================================================================
##
## A rounded glass vessel with paint in it, graduation ticks every 10%, and the
## number beside it. It is fed the player's real `ammo` and `get_max_ammo()`
## through set_values(); it never keeps its own paint count.
##
## The one thing it remembers is the LAST value it was shown, purely so it can
## tell "going up" from "going down" and play the refill shimmer. That is a
## drawing detail, not game state - the player script still decides everything.

const UITheme = preload("res://scripts/ui/ui_theme.gd")

var _value_label: Label
var _max_label: Label
var _status: Label
var _caption: Label
var _tank: Tank
var _last_ammo: float = -1.0
## Seconds left to keep showing "REFILLING" after the last rise.
var _refill_hold: float = 0.0
## What the labels currently show, so they are only rewritten on a change.
var _shown_ammo := -1
var _shown_max := -1
var _shown_status := "-"


class Tank extends Control:
	var fraction: float = 1.0
	var fill: Color = Color.WHITE
	var shimmer: float = -1.0   # 0..1 position of the refill highlight, <0 = off

	func _draw() -> void:
		var radius := size.y * 0.5
		var shell := StyleBoxFlat.new()
		shell.bg_color = Color(0.02, 0.025, 0.04, 0.75)
		shell.border_color = Color(1.0, 1.0, 1.0, 0.28)
		shell.set_border_width_all(1)
		shell.set_corner_radius_all(int(radius))
		draw_style_box(shell, Rect2(Vector2.ZERO, size))

		var inner := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
		var width := inner.size.x * fraction
		if width > 0.5:
			var paint := StyleBoxFlat.new()
			paint.bg_color = fill
			# Round only as much as the fill is wide, so a nearly empty tank
			# still draws as a sliver of paint instead of a squashed pill.
			paint.set_corner_radius_all(int(minf(inner.size.y * 0.5, width * 0.5)))
			draw_style_box(paint, Rect2(inner.position, Vector2(width, inner.size.y)))
			# A bright meniscus line at the paint's surface.
			draw_line(Vector2(inner.position.x + width - 1.0, inner.position.y + 2.0),
				Vector2(inner.position.x + width - 1.0, inner.end.y - 2.0),
				Color(1, 1, 1, 0.55), 1.5)
			# A soft glossy stripe along the top, so it reads as liquid.
			draw_line(Vector2(inner.position.x + 4.0, inner.position.y + 2.5),
				Vector2(maxf(inner.position.x + 4.0, inner.position.x + width - 4.0), inner.position.y + 2.5),
				Color(1, 1, 1, 0.22), 1.5)
			if shimmer >= 0.0:
				var x := inner.position.x + width * shimmer
				draw_rect(Rect2(Vector2(x - 6.0, inner.position.y), Vector2(12.0, inner.size.y)),
					Color(1, 1, 1, 0.22))
		# Graduation ticks every 10% on the glass.
		for i in range(1, 10):
			var x := inner.position.x + inner.size.x * i / 10.0
			var tall := 5.0 if i == 5 else 3.0
			draw_line(Vector2(x, size.y - 1.0 - tall), Vector2(x, size.y - 1.0), Color(1, 1, 1, 0.35), 1.0)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.09, 0.72),
		Color(UITheme.LINE, 0.8), 1, 8, 14.0, 10.0))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(column)

	var caption_row := HBoxContainer.new()
	column.add_child(caption_row)
	_caption = Label.new()
	_caption.theme_type_variation = &"HudCaption"
	_caption.text = "PAINT"
	_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption_row.add_child(_caption)
	_status = Label.new()
	_status.theme_type_variation = &"HudCaption"
	caption_row.add_child(_status)

	_tank = Tank.new()
	_tank.custom_minimum_size = Vector2(210, 18)
	_tank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_tank)

	var numbers := HBoxContainer.new()
	numbers.add_theme_constant_override("separation", 2)
	row.add_child(numbers)
	_value_label = Label.new()
	_value_label.theme_type_variation = &"HudNumber"
	_value_label.custom_minimum_size = Vector2(44, 0)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	numbers.add_child(_value_label)
	_max_label = Label.new()
	_max_label.theme_type_variation = &"HudCaption"
	_max_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_max_label.size_flags_vertical = Control.SIZE_SHRINK_END
	numbers.add_child(_max_label)


func set_values(ammo: float, max_ammo: float) -> void:
	if _last_ammo >= 0.0 and ammo > _last_ammo + 0.001:
		_refill_hold = 0.25
	_last_ammo = ammo
	var fraction := clampf(ammo / maxf(max_ammo, 1.0), 0.0, 1.0)
	_tank.fraction = fraction
	_tank.fill = UITheme.PAINT if fraction > 0.2 else UITheme.PAINT_LOW
	_tank.queue_redraw()
	# The shot costs whole units, so show the whole units the player can spend.
	# Labels are only rewritten when the shown number changes: paint refills
	# every physics step, and rewriting a Label re-lays-out its containers.
	if int(ammo) != _shown_ammo:
		_shown_ammo = int(ammo)
		_value_label.text = str(_shown_ammo)
	if int(max_ammo) != _shown_max:
		_shown_max = int(max_ammo)
		_max_label.text = "/%d" % _shown_max
	_update_status(fraction)


## The caption over the tank: the name of the gun in your hands (it changes
## with your power online - scripts/weapons.gd).
func set_caption(text: String) -> void:
	if _caption.text != text:
		_caption.text = text


func _update_status(fraction: float) -> void:
	var text := ""
	var color := UITheme.DIM
	if _refill_hold > 0.0:
		text = "REFILLING"
		color = UITheme.PAINT
	elif _last_ammo < 1.0:
		text = "EMPTY"
		color = UITheme.HEALTH_FULL
	elif fraction <= 0.2:
		text = "LOW"
		color = UITheme.PAINT_LOW
	# Same rule: only touch the label (and its colour, which is a theme
	# change and even more expensive) when the status actually changes.
	if text == _shown_status:
		return
	_shown_status = text
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _process(delta: float) -> void:
	if _refill_hold > 0.0:
		_refill_hold -= delta
		_tank.shimmer = fmod(Time.get_ticks_msec() / 600.0, 1.0)
		_tank.queue_redraw()
		if _refill_hold <= 0.0:
			_tank.shimmer = -1.0
			_tank.queue_redraw()
			_update_status(_tank.fraction)
