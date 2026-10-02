extends Control

## ============================================================================
## CROSSHAIR - four short arms around a gap, plus a centre dot.
## ============================================================================
##
## Drawn in code with _draw() rather than built from ColorRects. _draw() is a
## function Godot calls whenever this Control needs repainting; inside it the
## draw_* functions paint straight onto the screen. queue_redraw() asks Godot to
## call it again on the next frame.
##
## Every stroke is painted twice: a wider dark stroke underneath and the white
## stroke on top. That dark edge is what keeps the crosshair visible on the
## pale canvas floor as well as against the dark violet walls.
##
## The gap matters: a solid dot would hide exactly the thing you are aiming at,
## which is a real problem against the small, fast Bounders.

const ARM := 8.0
const GAP := 5.0
const THICK := 2.0
const COLOR := Color(1.0, 1.0, 1.0, 0.95)
const OUTLINE := Color(0.07, 0.08, 0.12, 0.75)

## Extra gap, pushed out briefly on each shot and eased back to zero. Purely
## visual: it does not change where the shot goes.
var _spread: float = 0.0
## 1 the moment a shot lands, fading to 0: draws the four diagonal hit ticks.
var _hit: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(48, 48)
	size = custom_minimum_size
	# PRESET_CENTER pins the control's middle to the middle of the screen and
	# KEEP_SIZE keeps it 48x48, so it stays perfectly centred at any window size.
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)


func _draw() -> void:
	var centre := (size * 0.5).floor()
	var gap := GAP + _spread
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var from: Vector2 = centre + direction * gap
		var to: Vector2 = from + direction * ARM
		draw_line(from - direction, to + direction, OUTLINE, THICK + 2.0)
		draw_line(from, to, COLOR, THICK)
	draw_circle(centre, 2.2, OUTLINE)
	draw_circle(centre, 1.2, COLOR)
	# Hit marker: four short diagonal ticks just outside the arms, so you know
	# a glob connected without looking away from the target.
	if _hit > 0.0:
		var tick_color := Color(1.0, 1.0, 1.0, _hit)
		var outline := Color(OUTLINE, OUTLINE.a * _hit)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var direction: Vector2 = d.normalized()
			var from: Vector2 = centre + direction * 9.0
			var to: Vector2 = centre + direction * 15.0
			draw_line(from - direction, to + direction, outline, 4.0)
			draw_line(from, to, tick_color, 2.0)


## A small outward kick of the arms when the player fires.
func pulse() -> void:
	var tween := create_tween()
	tween.tween_method(_set_spread, 4.0, 0.0, 0.14).set_ease(Tween.EASE_OUT)


func _set_spread(value: float) -> void:
	_spread = value
	queue_redraw()


## Shows the hit marker. Called when one of the player's globs lands.
func show_hit() -> void:
	_hit = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if _hit > 0.0:
		_hit = maxf(0.0, _hit - delta / 0.22)
		queue_redraw()
