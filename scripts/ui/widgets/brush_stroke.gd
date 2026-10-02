extends Control

## ============================================================================
## BRUSH STROKE - a painted swash drawn behind a heading.
## ============================================================================
##
## The menu's paint theme in one small piece: a ragged, tapering stroke of
## colour across the lower half of the heading, like a highlighter made with a
## dry brush. It is drawn behind the text at partial opacity, so the heading
## stays perfectly readable.
##
## Put it in the same container as the heading label, BEFORE the label. A
## MarginContainer gives every child the same rectangle, so the stroke fills
## exactly the heading's area and the label draws on top of it.

var color: Color = Color("#FF7391")
## Changes the stroke's raggedness so two headings never look identical.
var seed_value: int = 7


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	# Redraw when the heading changes size, so the stroke always fits it.
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var w := size.x
	var h := size.y
	if w < 4.0 or h < 4.0:
		return
	var top_line := PackedVector2Array()
	var bottom_line := PackedVector2Array()
	var steps := 28
	for i in steps + 1:
		var t := float(i) / steps
		var x := lerpf(-6.0, w * 0.96, t)
		# The stroke thins toward its right end, like a brush running dry.
		var thickness := h * 0.38 * (1.0 - 0.55 * pow(t, 2.2))
		var centre_y := h * 0.72 + sin(t * 3.1 + seed_value) * 2.0
		top_line.append(Vector2(x, centre_y - thickness * 0.5 + rng.randf_range(-1.6, 1.6)))
		bottom_line.append(Vector2(x, centre_y + thickness * 0.5 + rng.randf_range(-1.6, 1.6)))
	bottom_line.reverse()
	var shape := top_line + bottom_line
	draw_colored_polygon(shape, Color(color, 0.34))
	# Bristle streaks: thin darker lines along the stroke.
	for streak in 3:
		var y := h * 0.72 + (float(streak) - 1.0) * h * 0.09
		var length := w * rng.randf_range(0.45, 0.8)
		draw_line(Vector2(0.0, y), Vector2(length, y), Color(color, 0.22), 1.5)
	# A few flicked droplets past the end of the stroke.
	for drop in 4:
		var p := Vector2(w * rng.randf_range(0.82, 1.0), h * rng.randf_range(0.5, 0.95))
		draw_circle(p, rng.randf_range(1.2, 2.8), Color(color, 0.4))
