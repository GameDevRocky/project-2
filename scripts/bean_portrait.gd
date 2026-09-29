extends Control
class_name BeanPortrait

var team_color := Color("#56D9EB")


func _draw() -> void:
	var center := size * 0.5
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-7, -9), center + Vector2(7, -9), center + Vector2(10, -3),
		center + Vector2(9, 8), center + Vector2(4, 11), center + Vector2(-5, 11),
		center + Vector2(-10, 6), center + Vector2(-10, -3),
	]), team_color)
	draw_circle(center + Vector2(-3, -1), 1.2, Color("#202330"))
	draw_circle(center + Vector2(3, -1), 1.2, Color("#202330"))
