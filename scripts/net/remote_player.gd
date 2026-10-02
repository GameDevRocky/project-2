extends CharacterBody3D

const Powers = preload("res://scripts/power_abilities.gd")

## A visible, collidable copy of another human player. The owning client sends
## transforms through NetworkSession; this node smooths toward those updates.

var peer_id := 0
var display_name := "Player"
var tdm_team := "FFA"
var health := 100.0
var shield := 100.0
var current_power := ""
var power_invisible := false
var alive := true
var target_position := Vector3.ZERO
var target_yaw := 0.0
var target_pitch := 0.0
var target_velocity := Vector3.ZERO
var _initialized_transform := false
var _aim_pivot: Node3D
var _customization: Dictionary = {}
var _power_halo: MeshInstance3D


func setup(record: Dictionary, spawn_position: Vector3, combat_team: String) -> void:
	peer_id = int(record.get("peer_id", 0))
	display_name = str(record.get("name", "Player"))
	tdm_team = combat_team
	health = float(record.get("health", 100.0))
	shield = float(record.get("shield", 100.0))
	current_power = str(record.get("power", ""))
	power_invisible = bool(record.get("invisible", false))
	var customization_value = record.get("customization", {})
	if customization_value is Dictionary:
		_customization = customization_value.duplicate(true)
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

	_build_weapon(_customization)
	_build_power_halo()
	_refresh_power_visuals()


func _build_weapon(customization: Dictionary) -> void:
	# The pivot sits at shoulder height and inherits this player's body yaw.
	# Rotating only the pivot on X lets the rifle follow the owning player's
	# camera pitch without tipping the whole character capsule over.
	_aim_pivot = Node3D.new()
	_aim_pivot.name = "AimPivot"
	_aim_pivot.position = Vector3(0.46, 1.42, -0.08)
	add_child(_aim_pivot)

	var weapon := Node3D.new()
	weapon.name = "Weapon"
	# Move the rifle in front of the torso. Its first position overlapped the
	# capsule body, which allowed the body mesh to hide almost all of the gun.
	weapon.position.z = -0.26
	_aim_pivot.add_child(weapon)
	weapon.add_child(_make_weapon_box(
		Vector3(0.09, 0.1, 0.55), Vector3.ZERO, Color("#303342")))
	weapon.add_child(_make_weapon_box(
		Vector3(0.07, 0.2, 0.09), Vector3(0.0, -0.13, 0.14), Color("#303342")))

	var palette := [Color("#FF6FAE"), Color("#63D9C7"), Color("#54C9E8"), Color("#F5C45E"), Color("#A78BFA"), Color("#F5F4F0"), Color("#FF867C"), Color("#79C991"), Color("#70BCEB"), Color("#C18B67")]
	var gun_skin := int(customization.get("gun_skin", 0))
	weapon.add_child(_make_weapon_box(
		Vector3(0.1, 0.045, 0.12), Vector3(0.0, 0.035, -0.06), palette[gun_skin % palette.size()]))

	var muzzle := _make_weapon_box(
		Vector3(0.12, 0.13, 0.16), Vector3(0.0, 0.0, -0.36), Color.WHITE)
	var muzzle_material := muzzle.material_override as StandardMaterial3D
	muzzle_material.emission_enabled = true
	muzzle_material.emission = Color.WHITE
	muzzle_material.emission_energy_multiplier = 0.5
	weapon.add_child(muzzle)


func _make_weapon_box(box_size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	node.mesh = box
	node.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	node.material_override = material
	return node


func _build_power_halo() -> void:
	_power_halo = MeshInstance3D.new()
	_power_halo.name = "PowerHalo"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.43
	_power_halo.mesh = torus
	_power_halo.position = Vector3(0.0, 2.28, 0.0)
	var material := StandardMaterial3D.new()
	material.emission_enabled = true
	material.emission_energy_multiplier = 2.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_power_halo.material_override = material
	add_child(_power_halo)


func set_power_state(power_id: String, invisible: bool) -> void:
	current_power = power_id if Powers.is_valid(power_id) else ""
	power_invisible = invisible and current_power == "invisibility"
	_refresh_power_visuals()


func _refresh_power_visuals() -> void:
	visible = alive and not power_invisible
	if not is_instance_valid(_power_halo):
		return
	_power_halo.visible = alive and not current_power.is_empty() and not power_invisible
	var color := Powers.color_for(current_power)
	var material := _power_halo.material_override as StandardMaterial3D
	material.albedo_color = color
	material.emission = color


func receive_network_transform(next_position: Vector3, yaw: float, pitch: float, next_velocity: Vector3) -> void:
	target_position = next_position
	target_yaw = yaw
	target_pitch = clampf(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
	target_velocity = next_velocity
	if not _initialized_transform:
		global_position = next_position
		rotation.y = yaw
		if is_instance_valid(_aim_pivot):
			_aim_pivot.rotation.x = target_pitch
		_initialized_transform = true


func _physics_process(delta: float) -> void:
	if not alive:
		return
	global_position = global_position.lerp(target_position, clampf(delta * 14.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 16.0, 0.0, 1.0))
	if is_instance_valid(_aim_pivot):
		_aim_pivot.rotation.x = lerp_angle(
			_aim_pivot.rotation.x, target_pitch, clampf(delta * 16.0, 0.0, 1.0))


func take_damage(amount: float, _attacker = null) -> void:
	if alive:
		NetworkSession.report_hit(peer_id, amount)


func set_network_health(next_health: float) -> void:
	set_network_vitals(next_health, shield)


func set_network_vitals(next_health: float, next_shield: float) -> void:
	health = next_health
	shield = next_shield
	if health <= 0.0:
		eliminate()


func eliminate() -> void:
	alive = false
	visible = false
	collision_layer = 0
	collision_mask = 0


func respawn(at: Vector3) -> void:
	health = 100.0
	shield = 100.0
	alive = true
	visible = not power_invisible
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	global_position = at
	target_position = at
	velocity = Vector3.ZERO
	_refresh_power_visuals()


func _team_color() -> Color:
	if tdm_team == "RED":
		return Color("#FF627E")
	if tdm_team == "BLUE":
		return Color("#58D7F2")
	var hue := fmod(float(peer_id) * 0.173, 1.0)
	return Color.from_hsv(hue, 0.62, 1.0)
