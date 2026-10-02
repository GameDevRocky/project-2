extends StaticBody3D

## Client representation of a server-owned flying power ball. The server sends
## positions and health; this node only smooths motion and reports local hits.

const Powers = preload("res://scripts/power_abilities.gd")

var ball_id := 0
var power_id := ""
var health := 35.0
var target_position := Vector3.ZERO
var _core: MeshInstance3D
var _left_wing: MeshInstance3D
var _right_wing: MeshInstance3D
var _flight_time := 0.0


func setup(record: Dictionary) -> void:
	ball_id = int(record.get("id", 0))
	power_id = str(record.get("power", ""))
	health = float(record.get("health", 35.0))
	target_position = record.get("position", Vector3.ZERO)
	position = target_position


func _ready() -> void:
	add_to_group("snitch_balls")
	collision_layer = 4
	collision_mask = 0

	var shape_node := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.55
	shape_node.shape = shape
	add_child(shape_node)

	_core = MeshInstance3D.new()
	_core.name = "PowerCore"
	var sphere := SphereMesh.new()
	sphere.radius = 0.34
	sphere.height = 0.68
	sphere.radial_segments = 12
	sphere.rings = 6
	_core.mesh = sphere
	_core.material_override = _glow_material(Powers.color_for(power_id), 3.4)
	add_child(_core)

	_left_wing = _build_wing(-1.0)
	_right_wing = _build_wing(1.0)
	add_child(_left_wing)
	add_child(_right_wing)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.54
	ring.mesh = torus
	ring.rotation.x = PI * 0.5
	ring.material_override = _glow_material(Powers.color_for(power_id), 2.2)
	add_child(ring)

	var label := Label3D.new()
	label.text = str(Powers.get_power(power_id).get("name", "POWER"))
	label.position.y = 0.95
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 30
	label.pixel_size = 0.004
	label.modulate = Powers.color_for(power_id)
	label.outline_size = 6
	add_child(label)


func _physics_process(delta: float) -> void:
	_flight_time += delta
	global_position = global_position.lerp(target_position, clampf(delta * 9.0, 0.0, 1.0))
	rotate_y(delta * 2.4)
	var flap := sin(_flight_time * 16.0) * 0.65
	_left_wing.rotation.z = -0.25 - flap
	_right_wing.rotation.z = 0.25 + flap


func receive_snapshot(record: Dictionary) -> void:
	health = float(record.get("health", health))
	target_position = record.get("position", target_position)


func take_damage(amount: float, _attacker = null) -> void:
	NetworkSession.report_snitch_hit(ball_id, amount)
	if is_instance_valid(_core):
		_core.scale = Vector3.ONE * 1.25
		var tween := _core.create_tween()
		tween.tween_property(_core, "scale", Vector3.ONE, 0.12)


func _build_wing(side: float) -> MeshInstance3D:
	var wing := MeshInstance3D.new()
	wing.name = "Wing"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.72, 0.035, 0.26)
	wing.mesh = mesh
	wing.position.x = side * 0.58
	wing.material_override = _glow_material(Color("#FFF6C7"), 1.2)
	return wing


func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.roughness = 0.25
	return material
