extends Node3D

## Tall, walk-in healing station. It reads the shared `interact` action and
## accepts only nodes in the existing `player` group.

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
@export var station_id: int = 0

const READY_COLOR := Color("#4DFF88")
const READY_SOFT := Color("#B8FFD1")
const STATION_GREEN := Color("#237A4B")
const STATION_DARK := Color("#123E2C")
const COOLDOWN_COLOR := Color("#456557")

var _state: StationState = StationState.READY
var _nearby_players: Array[Node3D] = []
var _active_player: Node3D
var _start_position: Vector3
var _interaction_elapsed: float = 0.0
var _cooldown_elapsed: float = 0.0
var _ring: MeshInstance3D
var _status: Label3D
var _core_material: StandardMaterial3D
var _trim_material: StandardMaterial3D
var _energy_material: StandardMaterial3D
var _station_light: OmniLight3D
var _beacon: MeshInstance3D
var _pulse_time: float = 0.0


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
	_animate_station(delta)
	match _state:
		StationState.COOLDOWN:
			_cooldown_elapsed -= delta
			_status.text = "RECHARGING\n%.1f" % maxf(_cooldown_elapsed, 0.0)
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
			_status.text = "RESTORING\n%d%%" % int(progress * 100.0)
			if progress >= 1.0:
				_complete_interaction()
		StationState.READY:
			if Input.is_action_just_pressed("interact"):
				var player := _nearest_player()
				if player != null:
					_begin_interaction(player)


func _build_visuals() -> void:
	var base_material := _material(STATION_GREEN, 0.08)
	var dark_material := _material(STATION_DARK, 0.12)
	_core_material = _material(READY_COLOR)
	_trim_material = _material(READY_COLOR, 1.8)
	_energy_material = _transparent_material(Color(0.18, 1.0, 0.46, 0.2), 1.25)

	# The 5 metre frame makes the station visible over nearby cover. Its open
	# +Z side is the entrance; both stations face the southern doors of their
	# buildings in game.gd.
	_add_box("FloorBay", Vector3(3.6, 0.16, 3.4), Vector3(0.0, 0.08, 0.0), dark_material)
	_add_box("FloorInset", Vector3(2.9, 0.06, 2.75), Vector3(0.0, 0.18, 0.12), base_material)
	_add_box("HealingCore", Vector3(2.35, 0.035, 2.2), Vector3(0.0, 0.22, 0.12), _core_material)
	_add_box("LeftPillar", Vector3(0.42, 4.45, 0.5), Vector3(-1.55, 2.3, 0.0), base_material)
	_add_box("RightPillar", Vector3(0.42, 4.45, 0.5), Vector3(1.55, 2.3, 0.0), base_material)
	_add_box("Canopy", Vector3(3.52, 0.62, 0.72), Vector3(0.0, 4.48, 0.0), dark_material)
	_add_box("LeftLightRail", Vector3(0.10, 3.75, 0.56), Vector3(-1.55, 2.35, 0.03), _trim_material)
	_add_box("RightLightRail", Vector3(0.10, 3.75, 0.56), Vector3(1.55, 2.35, 0.03), _trim_material)
	_add_box("CanopyLightRail", Vector3(2.65, 0.11, 0.78), Vector3(0.0, 4.48, 0.04), _trim_material)
	_add_box("EnergyBackdrop", Vector3(2.75, 3.15, 0.08), Vector3(0.0, 1.78, -1.48), _energy_material)
	_add_box("BackTop", Vector3(3.1, 0.28, 0.36), Vector3(0.0, 3.55, -1.47), base_material)

	# A green medical cross reinforces the purpose even when the text is too far
	# away to read.
	_add_box("MedicalCrossVertical", Vector3(0.28, 1.1, 0.08), Vector3(0.0, 2.0, -1.41), _core_material)
	_add_box("MedicalCrossHorizontal", Vector3(1.1, 0.28, 0.08), Vector3(0.0, 2.0, -1.40), _core_material)

	for side in [-1.0, 1.0]:
		_add_box("FloorRail", Vector3(0.10, 0.08, 2.65), Vector3(side * 1.45, 0.22, 0.15), _trim_material)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.02
	ring_mesh.outer_radius = 1.12
	_ring = MeshInstance3D.new()
	_ring.name = "ProgressRing"
	_ring.mesh = ring_mesh
	_ring.position.y = 0.26
	_ring.material_override = _trim_material
	add_child(_ring)

	var beacon_mesh := TorusMesh.new()
	beacon_mesh.inner_radius = 0.34
	beacon_mesh.outer_radius = 0.43
	_beacon = MeshInstance3D.new()
	_beacon.name = "HealingBeacon"
	_beacon.mesh = beacon_mesh
	_beacon.position = Vector3(0.0, 3.82, -0.15)
	_beacon.rotation_degrees.x = 90.0
	_beacon.material_override = _trim_material
	add_child(_beacon)

	var title := Label3D.new()
	title.name = "StationTitle"
	title.text = "HEALING STATION"
	title.position = Vector3(0.0, 4.48, 0.39)
	title.font_size = 52
	title.pixel_size = 0.006
	title.modulate = READY_SOFT
	title.outline_size = 10
	title.outline_modulate = STATION_DARK
	add_child(title)

	_status = Label3D.new()
	_status.name = "StationStatus"
	# This is physical world UI mounted in the entrance instead of screen HUD.
	# It stays within the arch and remains legible from either approach.
	_status.position = Vector3(0.0, 3.05, -1.37)
	_status.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_status.font_size = 38
	_status.pixel_size = 0.0045
	_status.modulate = READY_SOFT
	_status.outline_size = 12
	_status.outline_modulate = STATION_DARK
	add_child(_status)

	_station_light = OmniLight3D.new()
	_station_light.name = "HealingGlow"
	_station_light.position = Vector3(0.0, 2.65, -0.25)
	_station_light.light_color = READY_COLOR
	_station_light.light_energy = 0.72
	_station_light.omni_range = 5.5
	_station_light.shadow_enabled = false
	add_child(_station_light)


func _material(color: Color, emission_energy: float = 0.45) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.12
	material.roughness = 0.38
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	return material


func _transparent_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := _material(color, emission_energy)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
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


func _animate_station(delta: float) -> void:
	_pulse_time += delta
	var pulse := (sin(_pulse_time * 2.4) + 1.0) * 0.5
	if is_instance_valid(_beacon):
		_beacon.rotation_degrees.z += delta * 70.0
		_beacon.position.y = 3.82 + sin(_pulse_time * 1.8) * 0.08
	if is_instance_valid(_station_light):
		var base_energy := 0.2 if _state == StationState.COOLDOWN else 0.62
		_station_light.light_energy = base_energy + pulse * 0.2
	if is_instance_valid(_energy_material):
		var energy := 0.35 if _state == StationState.COOLDOWN else 1.0 + pulse * 0.45
		_energy_material.emission_energy_multiplier = energy


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
	if NetworkSession.is_in_match():
		NetworkSession.request_power_trade(station_id)
		_play_restore_burst()
		_disconnect_hurt_listener()
		_active_player = null
		_interaction_elapsed = 0.0
		_cooldown_elapsed = cooldown_duration
		_set_state(StationState.COOLDOWN)
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
	_play_restore_burst()
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
			_status.text = "TRADE POWER\nHOLD [E] / [WEST BUTTON]\nFULL HEALTH + SHIELD"
			_status.modulate = READY_SOFT
			_ring.visible = false
		StationState.INTERACTING:
			state_name = &"interacting"
			_status.text = "RESTORING  0%"
			_status.modulate = Color.WHITE
			_ring.visible = true
			_ring.scale = Vector3.ONE * 0.35
		StationState.COOLDOWN:
			state_name = &"cooldown"
			_core_material.albedo_color = COOLDOWN_COLOR
			_core_material.emission = COOLDOWN_COLOR
			_status.text = "RECHARGING\n%.1f" % cooldown_duration
			_status.modulate = Color("#9FB8A9")
			_ring.visible = false
	station_state_changed.emit(state_name)


func _play_restore_burst() -> void:
	# Three expanding rings make a successful trade readable without moving the
	# camera or stealing control from the player.
	for index in 3:
		var burst_mesh := TorusMesh.new()
		burst_mesh.inner_radius = 0.78
		burst_mesh.outer_radius = 0.86
		var burst := MeshInstance3D.new()
		burst.mesh = burst_mesh
		burst.position = Vector3(0.0, 0.35, 0.0)
		burst.material_override = _transparent_material(Color(0.3, 1.0, 0.55, 0.8), 2.2)
		add_child(burst)
		var delay := float(index) * 0.09
		var tween := burst.create_tween()
		tween.set_parallel(true)
		tween.tween_property(burst, "scale", Vector3.ONE * 2.6, 0.5).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(burst, "position:y", 2.8, 0.5).set_delay(delay)
		var burst_material := burst.material_override as StandardMaterial3D
		tween.tween_property(burst_material, "albedo_color:a", 0.0, 0.42).set_delay(delay + 0.08)
		tween.chain().tween_callback(burst.queue_free)
