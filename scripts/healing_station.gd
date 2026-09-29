extends Node3D

## Reusable healing pedestal. It reads the shared `interact` action and accepts
## only nodes in the existing `player` group.

signal station_state_changed(state: StringName)
## Emitted after a real power system confirms and consumes a power. The Snitch
## Ball System should connect here and spawn the surrendered `power_type`.
signal power_traded(power_type: Variant, player: Node3D, station: Node3D)

enum StationState { READY, INTERACTING, COOLDOWN }

@export_range(0.1, 10.0, 0.1) var interaction_duration: float = 1.5
@export_range(0.1, 60.0, 0.1) var cooldown_duration: float = 5.0
@export_range(0.5, 10.0, 0.1) var interaction_range: float = 2.5
## Keep false while the Player Power System is being implemented. Set true
## once it is connected if a player must carry a power to use this station.
@export var require_power_to_trade: bool = false

const READY_COLOR := Color("#36E6D2")
const COOLDOWN_COLOR := Color("#536C70")

var _state: StationState = StationState.READY
var _nearby_players: Array[Node3D] = []
var _active_player: Node3D
var _start_position: Vector3
var _interaction_elapsed: float = 0.0
var _cooldown_elapsed: float = 0.0
var _ring: MeshInstance3D
var _status: Label3D
var _core_material: StandardMaterial3D


func _ready() -> void:
	_build_visuals()
	var area := Area3D.new()
	area.name = "InteractionArea"
	area.collision_layer = 0
	area.collision_mask = 2
	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = interaction_range
	shape_node.shape = sphere
	area.add_child(shape_node)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	_set_state(StationState.READY)


func _process(delta: float) -> void:
	match _state:
		StationState.COOLDOWN:
			_cooldown_elapsed -= delta
			_status.text = "COOLDOWN  %.1f" % maxf(_cooldown_elapsed, 0.0)
			if _cooldown_elapsed <= 0.0:
				_set_state(StationState.READY)
		StationState.INTERACTING:
			if not is_instance_valid(_active_player):
				_cancel_interaction()
				return
			if not Input.is_action_pressed("interact"):
				_cancel_interaction()
				return
			if _active_player.global_position.distance_to(_start_position) > 0.08:
				_cancel_interaction()
				return
			if not _nearby_players.has(_active_player):
				_cancel_interaction()
				return
			_interaction_elapsed += delta
			var progress := clampf(_interaction_elapsed / interaction_duration, 0.0, 1.0)
			_ring.scale = Vector3.ONE * (0.35 + progress * 0.65)
			_status.text = "HEALING  %d%%" % int(progress * 100.0)
			if progress >= 1.0:
				_complete_interaction()
		StationState.READY:
			if Input.is_action_just_pressed("interact"):
				var player := _nearest_player()
				if player != null:
					_begin_interaction(player)


func _build_visuals() -> void:
	var base_material := _material(Color("#E9EDF0"))
	_core_material = _material(READY_COLOR)
	_add_box("Base", Vector3(1.0, 0.18, 1.0), Vector3(0.0, 0.09, 0.0), base_material)
	_add_box("Pedestal", Vector3(0.48, 0.78, 0.48), Vector3(0.0, 0.57, 0.0), base_material)
	_add_box("HealingCore", Vector3(0.62, 0.16, 0.62), Vector3(0.0, 0.87, 0.0), _core_material)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.42
	ring_mesh.outer_radius = 0.48
	_ring = MeshInstance3D.new()
	_ring.name = "ProgressRing"
	_ring.mesh = ring_mesh
	_ring.position.y = 1.25
	_ring.material_override = _material(Color("#F5A9CF"))
	add_child(_ring)
	_status = Label3D.new()
	_status.name = "StationStatus"
	_status.position = Vector3(0.0, 1.65, 0.0)
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.font_size = 32
	_status.pixel_size = 0.004
	_status.modulate = Color("#24353B")
	add_child(_status)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.12
	material.roughness = 0.38
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.45
	return material


func _add_box(node_name: String, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	mesh_node.position = at
	mesh_node.material_override = material
	add_child(mesh_node)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not _nearby_players.has(body):
		_nearby_players.append(body)


func _on_body_exited(body: Node3D) -> void:
	_nearby_players.erase(body)
	if body == _active_player:
		_cancel_interaction()


func _nearest_player() -> Node3D:
	var nearest: Node3D
	var nearest_distance := interaction_range
	for player in _nearby_players:
		if not is_instance_valid(player):
			continue
		var distance := global_position.distance_to(player.global_position)
		if distance <= nearest_distance:
			nearest = player
			nearest_distance = distance
	return nearest


func _begin_interaction(player: Node3D) -> void:
	if _state != StationState.READY:
		return
	_active_player = player
	_start_position = player.global_position
	_interaction_elapsed = 0.0
	if player.has_signal("hurt"):
		player.hurt.connect(_on_active_player_hurt, CONNECT_ONE_SHOT)
	_set_state(StationState.INTERACTING)


func _on_active_player_hurt() -> void:
	_cancel_interaction()


func _cancel_interaction() -> void:
	if _state != StationState.INTERACTING:
		return
	_disconnect_hurt_listener()
	_active_player = null
	_interaction_elapsed = 0.0
	_ring.scale = Vector3.ONE
	_set_state(StationState.READY)


func _complete_interaction() -> void:
	var player := _active_player
	if not _player_can_trade(player):
		_cancel_interaction()
		return
	var trade := _consume_player_power(player)
	if require_power_to_trade and not bool(trade.get("consumed", false)):
		_cancel_interaction()
		return

	# Use the player's existing health API. `heal(max_health)` fills health and
	# keeps the HUD in sync through the existing stats_changed signal.
	player.call("heal", float(player.get("max_health")))
	if bool(trade.get("consumed", false)):
		power_traded.emit(trade.get("power_type"), player, self)
	_disconnect_hurt_listener()
	_active_player = null
	_interaction_elapsed = 0.0
	_cooldown_elapsed = cooldown_duration
	_set_state(StationState.COOLDOWN)


func _disconnect_hurt_listener() -> void:
	if is_instance_valid(_active_player) and _active_player.has_signal("hurt"):
		var callback := Callable(self, "_on_active_player_hurt")
		if _active_player.is_connected("hurt", callback):
			_active_player.disconnect("hurt", callback)


func _player_can_trade(player: Node3D) -> bool:
	if not is_instance_valid(player):
		return false
	var has_power_api := player.has_method("has_current_power")
	if not has_power_api:
		# This is waiting for the Player Power System to connect. Healing-only
		# mode remains testable until that system supplies the methods below.
		return not require_power_to_trade
	if not bool(player.call("has_current_power")):
		return false
	if not player.has_method("get_current_power_type"):
		return false
	if not player.has_method("can_trade_power_at_station"):
		return false
	if not player.has_method("try_consume_power_for_station"):
		return false
	return bool(player.call("can_trade_power_at_station"))


func _consume_player_power(player: Node3D) -> Dictionary:
	# This is waiting for the Player Power System to connect. Implement
	# `has_current_power()`, `get_current_power_type()`,
	# `can_trade_power_at_station()`, and `try_consume_power_for_station()` on the
	# player. The final method returns true only if it consumed that current
	# power; this station never stores power.
	if not player.has_method("try_consume_power_for_station"):
		return {"consumed": false, "power_type": null}
	var power_type = player.call("get_current_power_type")
	var consumed := bool(player.call("try_consume_power_for_station"))
	return {"consumed": consumed, "power_type": power_type}


func _set_state(new_state: StationState) -> void:
	_state = new_state
	var state_name: StringName
	match _state:
		StationState.READY:
			state_name = &"ready"
			_core_material.albedo_color = READY_COLOR
			_core_material.emission = READY_COLOR
			_status.text = "READY  [E] HOLD"
			_ring.visible = false
		StationState.INTERACTING:
			state_name = &"interacting"
			_status.text = "HEALING  0%"
			_ring.visible = true
			_ring.scale = Vector3.ONE * 0.35
		StationState.COOLDOWN:
			state_name = &"cooldown"
			_core_material.albedo_color = COOLDOWN_COLOR
			_core_material.emission = COOLDOWN_COLOR
			_status.text = "COOLDOWN  %.1f" % cooldown_duration
			_ring.visible = false
	station_state_changed.emit(state_name)
