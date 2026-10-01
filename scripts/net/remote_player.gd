extends CharacterBody3D

## A visible, collidable copy of another human player. The owning client sends
## transforms through NetworkSession; this node smooths toward those updates.

var peer_id := 0
var display_name := "Player"
var tdm_team := "FFA"
var health := 100.0
var alive := true
var target_position := Vector3.ZERO
var target_yaw := 0.0
var target_velocity := Vector3.ZERO
var _initialized_transform := false


func setup(record: Dictionary, spawn_position: Vector3, combat_team: String) -> void:
	peer_id = int(record.get("peer_id", 0))
	display_name = str(record.get("name", "Player"))
	tdm_team = combat_team
	position = spawn_position
	target_position = spawn_position


func _ready() -> void:
	add_to_group("tdm_combatants")
	add_to_group("remote_players")
	collision_layer = 4
	collision_mask = 1 | 2 | 4

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.42
	mesh.height = 1.8
	body.mesh = mesh
	body.position.y = 0.9
	var material := StandardMaterial3D.new()
	material.albedo_color = _team_color()
	material.roughness = 0.72
	material.emission_enabled = true
	material.emission = _team_color()
	material.emission_energy_multiplier = 0.18
	body.material_override = material
	add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.31
	head_mesh.height = 0.62
	head.mesh = head_mesh
	head.position.y = 1.82
	head.material_override = material
	add_child(head)


func receive_network_transform(next_position: Vector3, yaw: float, _pitch: float, next_velocity: Vector3) -> void:
	target_position = next_position
	target_yaw = yaw
	target_velocity = next_velocity
	if not _initialized_transform:
		global_position = next_position
		rotation.y = yaw
		_initialized_transform = true


func _physics_process(delta: float) -> void:
	if not alive:
		return
	global_position = global_position.lerp(target_position, clampf(delta * 14.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 16.0, 0.0, 1.0))


func take_damage(amount: float, _attacker = null) -> void:
	if alive:
		NetworkSession.report_hit(peer_id, amount)


func set_network_health(next_health: float) -> void:
	health = next_health
	if health <= 0.0:
		eliminate()


func eliminate() -> void:
	alive = false
	visible = false
	collision_layer = 0
	collision_mask = 0


func respawn(at: Vector3) -> void:
	health = 100.0
	alive = true
	visible = true
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	global_position = at
	target_position = at
	velocity = Vector3.ZERO


func _team_color() -> Color:
	if tdm_team == "RED":
		return Color("#FF627E")
	if tdm_team == "BLUE":
		return Color("#58D7F2")
	var hue := fmod(float(peer_id) * 0.173, 1.0)
	return Color.from_hsv(hue, 0.62, 1.0)
