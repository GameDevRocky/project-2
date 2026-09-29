extends Node

## A tiny shared motion driver for the showcase orbs and paint motes.
var targets: Array = []
var home_y: Array[float] = []
var phase := 0.0


func _ready() -> void:
	for value in targets:
		var target: Node3D = value as Node3D
		home_y.append(target.position.y)


func _process(delta: float) -> void:
	phase += delta
	for index in targets.size():
		var target: Node3D = targets[index] as Node3D
		if not is_instance_valid(target):
			continue
		target.position.y = home_y[index] + sin(phase * 1.1 + float(index)) * (0.025 if index > 1 else 0.14)
		target.rotation.y += delta * (0.35 + float(index % 4) * 0.08)
		if index < 2:
			target.scale = Vector3.ONE * (1.0 + sin(phase * 1.7 + index) * 0.04)
