extends Node

## Persistent browser multiplayer session. Browser clients connect through
## Caddy to a dedicated Godot WebSocket server. The server owns lobbies, teams,
## health, scoring, eliminations, and respawns.

signal connection_state_changed(state: int, detail: String)
signal lobby_changed(roster: Array[Dictionary])
signal lobby_joined(code: String, mode: String)
signal lobby_list_changed(lobbies: Array[Dictionary])
signal connection_failed(detail: String)
signal server_left
signal match_started(mode: String, roster: Array[Dictionary])
signal remote_transform_received(peer_id: int, position: Vector3, yaw: float, pitch: float, velocity: Vector3)
signal remote_shot_received(peer_id: int, origin: Vector3, direction: Vector3, shot_data: Dictionary)
signal health_changed(peer_id: int, health: float)
signal vitals_changed(peer_id: int, health: float, shield: float)
signal power_changed(peer_id: int, power_id: String, invisible: bool)
signal snitch_snapshot_changed(snapshot: Dictionary)
signal player_eliminated(victim_peer_id: int, attacker_peer_id: int)
signal player_respawned(peer_id: int)
signal player_left_match(peer_id: int)
signal score_changed(scores: Dictionary, stats: Dictionary)
signal match_finished(title: String, detail: String)
signal match_abandoned(detail: String)

enum ConnectionState { OFFLINE, CONNECTING, CONNECTED }

const SERVER_URL := "wss://98.84.170.140.sslip.io/"
const SERVER_PORT := 9080
const MAX_CONNECTIONS := 64
const MAX_LOBBY_PLAYERS := 20
const MAX_NAME_LENGTH := 24
const MATCH_SECONDS := 600.0
const RESPAWN_SECONDS := 3.0
const INTERMISSION_SECONDS := 10.0
const TDM_KILL_LIMIT := 25
const TEAM_RED := "RED"
const TEAM_BLUE := "BLUE"
const TEAM_FFA := "FFA"
const MAX_HEALTH := 100.0
const MAX_SHIELD := 100.0
# Two ordinary 4.4-damage shots destroy a Snitch. High-damage abilities can
# still destroy one in a single hit as part of their normal advantage.
const SNITCH_HEALTH := 8.8
const SNITCH_SYNC_INTERVAL := 0.1
const Powers = preload("res://scripts/power_abilities.gd")
const STATION_POSITIONS := [Vector3(-28.0, 0.0, -28.0), Vector3(33.0, 0.0, -31.0)]
const SNITCH_ANCHORS := [
	Vector3(-42.0, 6.5, -8.0), Vector3(-12.0, 8.0, 36.0),
	Vector3(30.0, 6.0, 26.0), Vector3(42.0, 7.5, -24.0),
	Vector3(0.0, 9.0, -42.0),
]

var connection_state := ConnectionState.OFFLINE
var players: Dictionary = {}
var current_lobby_code := ""
var current_game_mode := ""
var current_host_id := 0
var match_active := false
var public_lobbies: Array[Dictionary] = []
var snitches: Dictionary = {}
var local_player_info: Dictionary = {"name": "Player", "customization": {}}

var _dedicated_server := false
var _pending_action: Dictionary = {}
var _server_lobbies: Dictionary = {}
var _peer_lobbies: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var args := OS.get_cmdline_user_args()
	_dedicated_server = args.has("--server") or OS.has_feature("dedicated_server")
	if _dedicated_server:
		start_dedicated_server()
	else:
		for argument in args:
			if argument.begins_with("--smoke-join="):
				var smoke_code := argument.trim_prefix("--smoke-join=")
				lobby_joined.connect(_on_smoke_lobby_joined, CONNECT_ONE_SHOT)
				connection_failed.connect(func(detail): print("[network-smoke] failed: %s" % detail), CONNECT_ONE_SHOT)
				configure_local_player("Smoke Client", {})
				join_lobby.call_deferred(smoke_code)


func _process(delta: float) -> void:
	if not _dedicated_server:
		return
	var now := Time.get_ticks_msec()
	for code_value in _server_lobbies.keys():
		var code := str(code_value)
		var lobby: Dictionary = _server_lobbies[code]
		var state := str(lobby.get("state", ""))
		if state == "match":
			_server_tick_snitches(code, delta)
			if (str(lobby.get("mode", "")) == "TEAM_DEATH_MATCH"
					and int(lobby.get("ends_at", 0)) > 0 and now >= int(lobby.ends_at)):
				_finish_tdm(code)
		elif state == "intermission" and now >= int(lobby.get("next_match_at", 0)):
			_server_begin_round(code)


func is_dedicated_server() -> bool:
	return _dedicated_server


func start_dedicated_server(port: int = SERVER_PORT) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var result := peer.create_server(port, "127.0.0.1")
	if result != OK:
		push_error("Could not start WebSocket server on port %d: %s" % [port, error_string(result)])
		return result
	multiplayer.multiplayer_peer = peer
	_set_state(ConnectionState.CONNECTED, "Dedicated server listening on port %d." % port)
	print("[network] dedicated WebSocket server listening on 127.0.0.1:%d" % port)
	return OK


func configure_local_player(display_name: String, customization: Dictionary) -> void:
	local_player_info = {"name": _clean_name(display_name), "customization": _clean_customization(customization)}
	if is_connected_to_server() and not current_lobby_code.is_empty():
		_request_profile_update.rpc_id(1, local_player_info)


func create_lobby(mode: String) -> Error:
	_pending_action = {"type": "create", "mode": _clean_mode(mode)}
	return _ensure_server_connection()


func join_lobby(code: String) -> Error:
	var clean_code := code.strip_edges().to_upper().left(6)
	if clean_code.is_empty():
		connection_failed.emit("Enter a lobby code.")
		return ERR_INVALID_PARAMETER
	_pending_action = {"type": "join", "code": clean_code}
	return _ensure_server_connection()


func request_lobby_list() -> Error:
	if is_connected_to_server():
		_request_lobby_list.rpc_id(1)
		return OK
	_pending_action = {"type": "list"}
	return _ensure_server_connection()


func start_match() -> void:
	if is_connected_to_server() and not current_lobby_code.is_empty():
		_request_start_match.rpc_id(1)


func leave_lobby() -> void:
	if is_connected_to_server() and not current_lobby_code.is_empty():
		_request_leave_lobby.rpc_id(1)
	_clear_client_lobby()


func disconnect_game() -> void:
	if multiplayer.multiplayer_peer is WebSocketMultiplayerPeer:
		(multiplayer.multiplayer_peer as WebSocketMultiplayerPeer).close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_pending_action.clear()
	_clear_client_lobby()
	_set_state(ConnectionState.OFFLINE, "Offline")


func is_connected_to_server() -> bool:
	return connection_state == ConnectionState.CONNECTED and not _dedicated_server


func is_online() -> bool:
	return is_connected_to_server() and not current_lobby_code.is_empty()


func is_host() -> bool:
	return is_online() and multiplayer.get_unique_id() == current_host_id


func is_in_match() -> bool:
	return is_online() and match_active


func local_peer_id() -> int:
	return multiplayer.get_unique_id()


func lobby_roster() -> Array[Dictionary]:
	var roster: Array[Dictionary] = []
	for peer_id in players:
		roster.append((players[peer_id] as Dictionary).duplicate(true))
	roster.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.peer_id) < int(b.peer_id))
	return roster


func report_local_transform(position: Vector3, yaw: float, pitch: float, velocity: Vector3) -> void:
	if is_in_match():
		_submit_transform.rpc_id(1, position, yaw, pitch, velocity)


func report_shot(origin: Vector3, direction: Vector3, shot_data: Dictionary) -> void:
	if is_in_match():
		_submit_shot.rpc_id(1, origin, direction.normalized(), shot_data)


func report_hit(victim_peer_id: int, damage: float) -> void:
	if is_in_match() and victim_peer_id != local_peer_id():
		_submit_hit.rpc_id(1, victim_peer_id, clampf(damage, 0.0, 100.0))


func report_self_damage(damage: float) -> void:
	if is_in_match():
		_submit_self_damage.rpc_id(1, clampf(damage, 0.0, 100.0))


func report_snitch_hit(ball_id: int, damage: float) -> void:
	if is_in_match():
		_submit_snitch_hit.rpc_id(1, ball_id, clampf(damage, 0.0, 100.0))


func request_invisibility(enabled: bool) -> void:
	if is_in_match():
		_request_invisibility.rpc_id(1, enabled)


func request_power_trade(station_id: int) -> void:
	if is_in_match():
		_request_power_trade.rpc_id(1, station_id)


func local_power() -> String:
	var record: Dictionary = players.get(local_peer_id(), {})
	return str(record.get("power", ""))


func _ensure_server_connection() -> Error:
	if is_connected_to_server():
		_run_pending_action()
		return OK
	if connection_state == ConnectionState.CONNECTING:
		return OK
	var peer := WebSocketMultiplayerPeer.new()
	var result := peer.create_client(SERVER_URL)
	if result != OK:
		_pending_action.clear()
		_set_state(ConnectionState.OFFLINE, "Could not connect to the game server.")
		connection_failed.emit(error_string(result))
		return result
	multiplayer.multiplayer_peer = peer
	_set_state(ConnectionState.CONNECTING, "Connecting to online server...")
	return OK


func _run_pending_action() -> void:
	if _pending_action.is_empty():
		return
	var action := _pending_action.duplicate(true)
	_pending_action.clear()
	if str(action.get("type", "")) == "create":
		_request_create_lobby.rpc_id(1, str(action.get("mode", "TEAM_DEATH_MATCH")), local_player_info)
	elif str(action.get("type", "")) == "join":
		_request_join_lobby.rpc_id(1, str(action.get("code", "")), local_player_info)
	elif str(action.get("type", "")) == "list":
		_request_lobby_list.rpc_id(1)


func _on_peer_connected(_peer_id: int) -> void:
	pass


func _on_peer_disconnected(peer_id: int) -> void:
	if _dedicated_server:
		_server_remove_peer(peer_id)


func _on_connected_to_server() -> void:
	_set_state(ConnectionState.CONNECTED, "Connected to online server.")
	_run_pending_action()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_pending_action.clear()
	_clear_client_lobby()
	_set_state(ConnectionState.OFFLINE, "Connection failed.")
	connection_failed.emit("The online server could not be reached.")


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_pending_action.clear()
	_clear_client_lobby()
	_set_state(ConnectionState.OFFLINE, "The online server disconnected.")
	server_left.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_create_lobby(requested_mode: String, requested_info: Dictionary) -> void:
	if not _dedicated_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_server_remove_peer(peer_id)
	var code := _new_lobby_code()
	var mode := _clean_mode(requested_mode)
	var record := _make_player_record(peer_id, requested_info, TEAM_RED if mode == "TEAM_DEATH_MATCH" else TEAM_FFA)
	_server_lobbies[code] = {
		"host_id": peer_id, "mode": mode, "state": "lobby", "players": {peer_id: record},
		"health": {}, "shield": {}, "alive": {}, "scores": {TEAM_RED: 0, TEAM_BLUE: 0}, "stats": {}, "ends_at": 0,
		"next_match_at": 0, "round_number": 0, "snitches": {}, "snitch_seq": 0,
		"snitch_sync_accum": 0.0,
	}
	_peer_lobbies[peer_id] = code
	_broadcast_lobby(code)
	_broadcast_public_lobbies()


@rpc("any_peer", "call_remote", "reliable")
func _request_join_lobby(requested_code: String, requested_info: Dictionary) -> void:
	if not _dedicated_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var code := requested_code.strip_edges().to_upper()
	if not _server_lobbies.has(code):
		_client_request_failed.rpc_id(peer_id, "Lobby %s was not found." % code)
		return
	var lobby: Dictionary = _server_lobbies[code]
	if str(lobby.get("state", "")) != "lobby":
		_client_request_failed.rpc_id(peer_id, "That match has already started.")
		return
	var lobby_players: Dictionary = lobby.players
	if lobby_players.size() >= MAX_LOBBY_PLAYERS:
		_client_request_failed.rpc_id(peer_id, "That lobby is full.")
		return
	_server_remove_peer(peer_id)
	var mode := str(lobby.mode)
	var team := _server_next_team(lobby_players) if mode == "TEAM_DEATH_MATCH" else TEAM_FFA
	lobby_players[peer_id] = _make_player_record(peer_id, requested_info, team)
	lobby.players = lobby_players
	_server_lobbies[code] = lobby
	_peer_lobbies[peer_id] = code
	_broadcast_lobby(code)
	_broadcast_public_lobbies()


@rpc("any_peer", "call_remote", "reliable")
func _request_lobby_list() -> void:
	if not _dedicated_server:
		return
	_client_lobby_list.rpc_id(multiplayer.get_remote_sender_id(), _public_lobby_summaries())


@rpc("any_peer", "call_remote", "reliable")
func _request_profile_update(requested_info: Dictionary) -> void:
	if not _dedicated_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var code := str(_peer_lobbies.get(peer_id, ""))
	if code.is_empty() or not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var lobby_players: Dictionary = lobby.players
	if not lobby_players.has(peer_id):
		return
	var previous: Dictionary = lobby_players[peer_id]
	var replacement := _make_player_record(peer_id, requested_info, str(previous.team))
	replacement.power = str(previous.get("power", ""))
	replacement.invisible = bool(previous.get("invisible", false))
	lobby_players[peer_id] = replacement
	lobby.players = lobby_players
	_server_lobbies[code] = lobby
	_broadcast_lobby(code)


@rpc("any_peer", "call_remote", "reliable")
func _request_leave_lobby() -> void:
	if _dedicated_server:
		_server_remove_peer(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _request_start_match() -> void:
	if not _dedicated_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var code := str(_peer_lobbies.get(peer_id, ""))
	if code.is_empty() or not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	if int(lobby.host_id) != peer_id or str(lobby.state) != "lobby":
		return
	if (lobby.players as Dictionary).size() < 2:
		_client_request_failed.rpc_id(peer_id, "At least two players are required to start a match.")
		return
	_server_begin_round(code)


func _server_begin_round(code: String) -> void:
	if not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var lobby_players: Dictionary = lobby.players
	if lobby_players.is_empty():
		return
	if str(lobby.mode) == "TEAM_DEATH_MATCH":
		_assign_balanced_teams(lobby_players)
	else:
		for member_value in lobby_players.keys():
			var member := int(member_value)
			var record := (lobby_players[member] as Dictionary).duplicate(true)
			record.team = TEAM_FFA
			lobby_players[member] = record
	var health := {}
	var shield := {}
	var alive := {}
	var stats := {}
	for member_value in lobby_players.keys():
		var member := int(member_value)
		health[member] = MAX_HEALTH
		shield[member] = MAX_SHIELD
		alive[member] = true
		stats[member] = {"kills": 0, "deaths": 0}
		var record := (lobby_players[member] as Dictionary).duplicate(true)
		record.power = ""
		record.invisible = false
		record.health = MAX_HEALTH
		record.shield = MAX_SHIELD
		lobby_players[member] = record
	lobby.health = health
	lobby.shield = shield
	lobby.alive = alive
	lobby.stats = stats
	lobby.scores = {TEAM_RED: 0, TEAM_BLUE: 0}
	lobby.state = "match"
	lobby.ends_at = Time.get_ticks_msec() + int(MATCH_SECONDS * 1000.0)
	lobby.next_match_at = 0
	lobby.round_number = int(lobby.get("round_number", 0)) + 1
	lobby.players = lobby_players
	lobby.snitches = {}
	lobby.snitch_seq = 0
	lobby.snitch_sync_accum = 0.0
	for index in Powers.ORDER.size():
		_server_spawn_snitch(lobby, Powers.ORDER[index], SNITCH_ANCHORS[index])
	_server_lobbies[code] = lobby
	for member_value in lobby_players.keys():
		_client_match_started.rpc_id(int(member_value), str(lobby.mode), lobby_players.duplicate(true))
		_client_snitch_snapshot.rpc_id(int(member_value), (lobby.snitches as Dictionary).duplicate(true))
	_broadcast_public_lobbies()


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_transform(position: Vector3, yaw: float, pitch: float, velocity: Vector3) -> void:
	if not _dedicated_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	var code := str(_peer_lobbies.get(sender, ""))
	if not _server_match_has_peer(code, sender):
		return
	var lobby: Dictionary = _server_lobbies[code]
	if not bool((lobby.alive as Dictionary).get(sender, false)):
		return
	for member_value in (lobby.players as Dictionary).keys():
		var member := int(member_value)
		if member != sender:
			_client_transform.rpc_id(member, sender, position, yaw, pitch, velocity)


@rpc("any_peer", "call_remote", "reliable", 2)
func _submit_shot(origin: Vector3, direction: Vector3, shot_data: Dictionary) -> void:
	if not _dedicated_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	var code := str(_peer_lobbies.get(sender, ""))
	if not _server_match_has_peer(code, sender):
		return
	var lobby: Dictionary = _server_lobbies[code]
	if not bool((lobby.alive as Dictionary).get(sender, false)):
		return
	var record: Dictionary = (lobby.players as Dictionary).get(sender, {})
	var power_id := str(record.get("power", ""))
	if power_id == "invisibility" and bool(record.get("invisible", false)):
		return
	var power := Powers.get_power(power_id)
	if power.is_empty():
		power = {
			"damage": Powers.BASE_DAMAGE, "projectile_speed": 90.0,
			"splash_radius": 0.0, "splash_mult": 0.0,
			"projectile_kind": "bullet", "color": Color.WHITE,
		}
	var safe_data := {
		"damage": float(power.get("damage", Powers.BASE_DAMAGE)),
		"speed": float(power.get("projectile_speed", 90.0)),
		"splash_radius": float(power.get("splash_radius", 0.0)),
		"splash_mult": float(power.get("splash_mult", 0.0)),
		"projectile_kind": str(power.get("projectile_kind", "bullet")),
		"color": power.get("color", shot_data.get("color", Color.WHITE)),
	}
	for member_value in (lobby.players as Dictionary).keys():
		var member := int(member_value)
		if member != sender:
			_client_shot.rpc_id(member, sender, origin, direction.normalized(), safe_data)


@rpc("any_peer", "call_remote", "reliable", 3)
func _submit_hit(victim_peer_id: int, damage: float) -> void:
	if not _dedicated_server:
		return
	var attacker := multiplayer.get_remote_sender_id()
	var code := str(_peer_lobbies.get(attacker, ""))
	if not _server_match_has_peer(code, attacker) or not _server_match_has_peer(code, victim_peer_id) or attacker == victim_peer_id:
		return
	var lobby: Dictionary = _server_lobbies[code]
	var alive: Dictionary = lobby.alive
	if not bool(alive.get(attacker, false)) or not bool(alive.get(victim_peer_id, false)):
		return
	var lobby_players: Dictionary = lobby.players
	if str(lobby.mode) == "TEAM_DEATH_MATCH":
		if str((lobby_players[attacker] as Dictionary).team) == str((lobby_players[victim_peer_id] as Dictionary).team):
			return
	var max_damage := _server_power_damage(lobby_players, attacker)
	_server_apply_damage(code, victim_peer_id, attacker, minf(damage, max_damage))


@rpc("any_peer", "call_remote", "reliable", 4)
func _submit_self_damage(damage: float) -> void:
	if not _dedicated_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	var code := str(_peer_lobbies.get(sender, ""))
	if not _server_match_has_peer(code, sender):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var record: Dictionary = (lobby.players as Dictionary).get(sender, {})
	if str(record.get("power", "")) != "rocket_launcher":
		return
	_server_apply_damage(code, sender, sender, minf(damage, 90.0))


@rpc("any_peer", "call_remote", "reliable", 5)
func _submit_snitch_hit(ball_id: int, damage: float) -> void:
	if not _dedicated_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	var code := str(_peer_lobbies.get(sender, ""))
	if not _server_match_has_peer(code, sender):
		return
	var lobby: Dictionary = _server_lobbies[code]
	if not bool((lobby.alive as Dictionary).get(sender, false)):
		return
	var balls: Dictionary = lobby.snitches
	if not balls.has(ball_id):
		return
	var ball: Dictionary = (balls[ball_id] as Dictionary).duplicate(true)
	ball.health = maxf(0.0, float(ball.get("health", SNITCH_HEALTH)) - minf(damage, _server_power_damage(lobby.players, sender)))
	if float(ball.health) > 0.0:
		balls[ball_id] = ball
		lobby.snitches = balls
		_server_lobbies[code] = lobby
		_broadcast_snitches(code)
		return
	balls.erase(ball_id)
	lobby.snitches = balls
	var records: Dictionary = lobby.players
	var player_record := (records[sender] as Dictionary).duplicate(true)
	var previous_power := str(player_record.get("power", ""))
	player_record.power = str(ball.get("power", ""))
	player_record.invisible = false
	records[sender] = player_record
	lobby.players = records
	if not previous_power.is_empty():
		_server_spawn_snitch(lobby, previous_power, ball.get("position", Vector3.ZERO) + Vector3(0.0, 1.0, 0.0))
	_server_lobbies[code] = lobby
	_broadcast_power(code, sender)
	_broadcast_snitches(code)


@rpc("any_peer", "call_remote", "reliable")
func _request_invisibility(enabled: bool) -> void:
	if not _dedicated_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	var code := str(_peer_lobbies.get(sender, ""))
	if not _server_match_has_peer(code, sender):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var records: Dictionary = lobby.players
	var record: Dictionary = (records[sender] as Dictionary).duplicate(true)
	if str(record.get("power", "")) != "invisibility":
		return
	record.invisible = enabled
	records[sender] = record
	lobby.players = records
	_server_lobbies[code] = lobby
	_broadcast_power(code, sender)


@rpc("any_peer", "call_remote", "reliable")
func _request_power_trade(station_id: int) -> void:
	if not _dedicated_server or station_id < 0 or station_id >= STATION_POSITIONS.size():
		return
	var sender := multiplayer.get_remote_sender_id()
	var code := str(_peer_lobbies.get(sender, ""))
	if not _server_match_has_peer(code, sender):
		return
	var lobby: Dictionary = _server_lobbies[code]
	if not bool((lobby.alive as Dictionary).get(sender, false)):
		return
	var records: Dictionary = lobby.players
	var record: Dictionary = (records[sender] as Dictionary).duplicate(true)
	var traded_power := str(record.get("power", ""))
	if traded_power.is_empty():
		return
	record.power = ""
	record.invisible = false
	record.health = MAX_HEALTH
	record.shield = MAX_SHIELD
	records[sender] = record
	lobby.players = records
	var health: Dictionary = lobby.health
	var shield: Dictionary = lobby.shield
	health[sender] = MAX_HEALTH
	shield[sender] = MAX_SHIELD
	lobby.health = health
	lobby.shield = shield
	_server_spawn_snitch(lobby, traded_power, STATION_POSITIONS[station_id] + Vector3.UP * 3.0)
	_server_lobbies[code] = lobby
	_broadcast_power(code, sender)
	_broadcast_vitals(code, sender)
	_broadcast_snitches(code)


@rpc("authority", "call_remote", "reliable")
func _client_lobby_snapshot(snapshot: Dictionary, code: String, mode: String, host_id: int) -> void:
	var first_join := current_lobby_code != code
	players = snapshot.duplicate(true)
	current_lobby_code = code
	current_game_mode = mode
	current_host_id = host_id
	match_active = false
	if first_join:
		lobby_joined.emit(code, mode)
	lobby_changed.emit(lobby_roster())


@rpc("authority", "call_remote", "reliable")
func _client_lobby_list(snapshot: Array) -> void:
	public_lobbies.clear()
	for value in snapshot:
		if value is Dictionary:
			public_lobbies.append((value as Dictionary).duplicate(true))
	lobby_list_changed.emit(public_lobbies.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func _client_request_failed(detail: String) -> void:
	connection_failed.emit(detail)


@rpc("authority", "call_remote", "reliable")
func _client_match_started(mode: String, snapshot: Dictionary) -> void:
	players = snapshot.duplicate(true)
	current_game_mode = mode
	match_active = true
	match_started.emit(mode, lobby_roster())


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _client_transform(peer_id: int, position: Vector3, yaw: float, pitch: float, velocity: Vector3) -> void:
	remote_transform_received.emit(peer_id, position, yaw, pitch, velocity)


@rpc("authority", "call_remote", "reliable", 2)
func _client_shot(peer_id: int, origin: Vector3, direction: Vector3, shot_data: Dictionary) -> void:
	remote_shot_received.emit(peer_id, origin, direction, shot_data)


@rpc("authority", "call_remote", "reliable", 3)
func _client_health(peer_id: int, next_health: float) -> void:
	health_changed.emit(peer_id, next_health)
	var record: Dictionary = players.get(peer_id, {})
	var next_shield := float(record.get("shield", MAX_SHIELD))
	record.health = next_health
	players[peer_id] = record
	vitals_changed.emit(peer_id, next_health, next_shield)


@rpc("authority", "call_remote", "reliable", 4)
func _client_vitals(peer_id: int, next_health: float, next_shield: float) -> void:
	var record: Dictionary = players.get(peer_id, {})
	record.health = next_health
	record.shield = next_shield
	players[peer_id] = record
	health_changed.emit(peer_id, next_health)
	vitals_changed.emit(peer_id, next_health, next_shield)


@rpc("authority", "call_remote", "reliable", 5)
func _client_power(peer_id: int, power_id: String, invisible: bool) -> void:
	var record: Dictionary = players.get(peer_id, {})
	record.power = power_id
	record.invisible = invisible
	players[peer_id] = record
	power_changed.emit(peer_id, power_id, invisible)


@rpc("authority", "call_remote", "unreliable_ordered", 6)
func _client_snitch_snapshot(snapshot: Dictionary) -> void:
	snitches = snapshot.duplicate(true)
	snitch_snapshot_changed.emit(snitches.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func _client_eliminated(victim_peer_id: int, attacker_peer_id: int) -> void:
	player_eliminated.emit(victim_peer_id, attacker_peer_id)


@rpc("authority", "call_remote", "reliable")
func _client_respawned(peer_id: int) -> void:
	player_respawned.emit(peer_id)


@rpc("authority", "call_remote", "reliable")
func _client_player_left(peer_id: int) -> void:
	players.erase(peer_id)
	player_left_match.emit(peer_id)


@rpc("authority", "call_remote", "reliable")
func _client_score_changed(scores: Dictionary, stats: Dictionary) -> void:
	score_changed.emit(scores.duplicate(true), stats.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func _client_match_finished(title: String, detail: String) -> void:
	match_active = false
	match_finished.emit(title, detail)


@rpc("authority", "call_remote", "reliable")
func _client_match_abandoned(detail: String) -> void:
	_clear_client_lobby()
	match_abandoned.emit(detail)


func _server_eliminate(code: String, victim: int, attacker: int) -> void:
	if not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var alive: Dictionary = lobby.alive
	alive[victim] = false
	lobby.alive = alive
	var stats: Dictionary = lobby.stats
	var valid_kill := attacker != victim and (lobby.players as Dictionary).has(attacker)
	if valid_kill:
		var attacker_stats: Dictionary = stats.get(attacker, {"kills": 0, "deaths": 0})
		attacker_stats.kills = int(attacker_stats.kills) + 1
		stats[attacker] = attacker_stats
	var victim_stats: Dictionary = stats.get(victim, {"kills": 0, "deaths": 0})
	victim_stats.deaths = int(victim_stats.deaths) + 1
	stats[victim] = victim_stats
	lobby.stats = stats
	var reached_kill_limit := false
	var scoring_team := ""
	if str(lobby.mode) == "TEAM_DEATH_MATCH" and valid_kill:
		var scores: Dictionary = lobby.scores
		var attacker_team := str(((lobby.players as Dictionary)[attacker] as Dictionary).team)
		scores[attacker_team] = int(scores.get(attacker_team, 0)) + 1
		lobby.scores = scores
		scoring_team = attacker_team
		reached_kill_limit = int(scores[attacker_team]) >= TDM_KILL_LIMIT
	_server_lobbies[code] = lobby
	for member_value in (lobby.players as Dictionary).keys():
		var member := int(member_value)
		_client_eliminated.rpc_id(member, victim, attacker)
		_client_score_changed.rpc_id(member, (lobby.scores as Dictionary).duplicate(true), stats.duplicate(true))
	if str(lobby.mode) == "TEAM_DEATH_MATCH":
		if reached_kill_limit:
			_finish_match(code, "TEAM %s WINS" % scoring_team,
				"First to %d eliminations." % TDM_KILL_LIMIT)
		else:
			_server_respawn_later(code, victim)
	else:
		_check_survival_winner(code)


func _server_respawn_later(code: String, peer_id: int) -> void:
	await get_tree().create_timer(RESPAWN_SECONDS).timeout
	if not _server_match_has_peer(code, peer_id):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var health: Dictionary = lobby.health
	var shield: Dictionary = lobby.shield
	var alive: Dictionary = lobby.alive
	health[peer_id] = MAX_HEALTH
	shield[peer_id] = MAX_SHIELD
	alive[peer_id] = true
	lobby.health = health
	lobby.shield = shield
	lobby.alive = alive
	var records: Dictionary = lobby.players
	var record := (records[peer_id] as Dictionary).duplicate(true)
	record.health = MAX_HEALTH
	record.shield = MAX_SHIELD
	record.invisible = false
	records[peer_id] = record
	lobby.players = records
	_server_lobbies[code] = lobby
	for member_value in (lobby.players as Dictionary).keys():
		_client_vitals.rpc_id(int(member_value), peer_id, MAX_HEALTH, MAX_SHIELD)
		_client_power.rpc_id(int(member_value), peer_id, str(record.get("power", "")), false)
		_client_respawned.rpc_id(int(member_value), peer_id)


func _server_apply_damage(code: String, victim: int, attacker: int, amount: float) -> void:
	if not _server_match_has_peer(code, victim) or amount <= 0.0:
		return
	var lobby: Dictionary = _server_lobbies[code]
	if not bool((lobby.alive as Dictionary).get(victim, false)):
		return
	var health: Dictionary = lobby.health
	var shield: Dictionary = lobby.shield
	var remaining := amount
	var current_shield := float(shield.get(victim, MAX_SHIELD))
	var shield_damage := minf(current_shield, remaining)
	current_shield -= shield_damage
	remaining -= shield_damage
	var current_health := maxf(0.0, float(health.get(victim, MAX_HEALTH)) - remaining)
	shield[victim] = current_shield
	health[victim] = current_health
	lobby.health = health
	lobby.shield = shield
	var records: Dictionary = lobby.players
	var record := (records[victim] as Dictionary).duplicate(true)
	record.health = current_health
	record.shield = current_shield
	records[victim] = record
	lobby.players = records
	_server_lobbies[code] = lobby
	_broadcast_vitals(code, victim)
	if current_health <= 0.0:
		_server_eliminate(code, victim, attacker)


func _server_power_damage(lobby_players: Dictionary, peer_id: int) -> float:
	var record: Dictionary = lobby_players.get(peer_id, {})
	var power := Powers.get_power(str(record.get("power", "")))
	return float(power.get("damage", Powers.BASE_DAMAGE))


func _server_spawn_snitch(lobby: Dictionary, power_id: String, anchor: Vector3) -> void:
	if not Powers.is_valid(power_id):
		return
	var next_id := int(lobby.get("snitch_seq", 0)) + 1
	lobby.snitch_seq = next_id
	var balls: Dictionary = lobby.get("snitches", {})
	balls[next_id] = {
		"id": next_id,
		"power": power_id,
		"health": SNITCH_HEALTH,
		"anchor": anchor,
		"position": anchor,
		"phase": randf_range(0.0, TAU),
		"speed": randf_range(0.55, 0.9),
		"radius": randf_range(7.0, 12.0),
	}
	lobby.snitches = balls


func _server_tick_snitches(code: String, delta: float) -> void:
	if not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var balls: Dictionary = lobby.get("snitches", {})
	var time := float(Time.get_ticks_msec()) / 1000.0
	for id_value in balls.keys():
		var id := int(id_value)
		var ball := (balls[id] as Dictionary).duplicate(true)
		var anchor: Vector3 = ball.get("anchor", Vector3.ZERO)
		var phase := float(ball.get("phase", 0.0))
		var speed := float(ball.get("speed", 0.7))
		var radius := float(ball.get("radius", 8.0))
		var angle := time * speed + phase
		ball.position = anchor + Vector3(
			cos(angle) * radius,
			sin(time * speed * 2.3 + phase) * 2.4,
			sin(angle * 1.17) * radius * 0.72)
		balls[id] = ball
	lobby.snitches = balls
	lobby.snitch_sync_accum = float(lobby.get("snitch_sync_accum", 0.0)) + delta
	var should_sync := float(lobby.snitch_sync_accum) >= SNITCH_SYNC_INTERVAL
	if should_sync:
		lobby.snitch_sync_accum = 0.0
	_server_lobbies[code] = lobby
	if should_sync:
		_broadcast_snitches(code)


func _check_survival_winner(code: String) -> void:
	if not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var survivors: Array[int] = []
	for peer_value in (lobby.players as Dictionary).keys():
		var peer_id := int(peer_value)
		if bool((lobby.alive as Dictionary).get(peer_id, false)):
			survivors.append(peer_id)
	if survivors.size() > 1:
		return
	var title := "NO SURVIVORS"
	var detail := "The survival match ended."
	if survivors.size() == 1:
		var winner: Dictionary = (lobby.players as Dictionary)[survivors[0]]
		title = "%s WINS" % str(winner.name).to_upper()
		detail = "Last player standing."
	_finish_match(code, title, detail)


func _finish_tdm(code: String) -> void:
	if not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var scores: Dictionary = lobby.scores
	var title := "DRAW"
	if int(scores.get(TEAM_RED, 0)) > int(scores.get(TEAM_BLUE, 0)):
		title = "TEAM RED WINS"
	elif int(scores.get(TEAM_BLUE, 0)) > int(scores.get(TEAM_RED, 0)):
		title = "TEAM BLUE WINS"
	_finish_match(code, title, "RED %d   BLUE %d" % [int(scores.get(TEAM_RED, 0)), int(scores.get(TEAM_BLUE, 0))])


func _finish_match(code: String, title: String, detail: String) -> void:
	if not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	if str(lobby.get("state", "")) != "match":
		return
	lobby.state = "intermission"
	lobby.ends_at = 0
	lobby.next_match_at = Time.get_ticks_msec() + int(INTERMISSION_SECONDS * 1000.0)
	_server_lobbies[code] = lobby
	for member_value in (lobby.players as Dictionary).keys():
		_client_match_finished.rpc_id(int(member_value), title,
			"%s  Next match starts in %d seconds." % [detail, int(INTERMISSION_SECONDS)])


func _broadcast_lobby(code: String) -> void:
	if not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	for member_value in (lobby.players as Dictionary).keys():
		_client_lobby_snapshot.rpc_id(int(member_value), (lobby.players as Dictionary).duplicate(true), code, str(lobby.mode), int(lobby.host_id))


func _public_lobby_summaries() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for code_value in _server_lobbies.keys():
		var code := str(code_value)
		var lobby: Dictionary = _server_lobbies[code]
		if str(lobby.get("state", "")) != "lobby":
			continue
		var lobby_players: Dictionary = lobby.players
		if lobby_players.size() >= MAX_LOBBY_PLAYERS:
			continue
		var host_id := int(lobby.host_id)
		var host: Dictionary = lobby_players.get(host_id, {})
		summaries.append({
			"code": code,
			"mode": str(lobby.mode),
			"host_name": str(host.get("name", "Player")),
			"player_count": lobby_players.size(),
			"max_players": MAX_LOBBY_PLAYERS,
		})
	summaries.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.code) < str(b.code))
	return summaries


func _broadcast_public_lobbies() -> void:
	if not _dedicated_server:
		return
	var summaries := _public_lobby_summaries()
	for peer_id in multiplayer.get_peers():
		_client_lobby_list.rpc_id(int(peer_id), summaries)


func _broadcast_health(code: String, peer_id: int, next_health: float) -> void:
	var lobby: Dictionary = _server_lobbies[code]
	for member_value in (lobby.players as Dictionary).keys():
		_client_health.rpc_id(int(member_value), peer_id, next_health)


func _broadcast_vitals(code: String, peer_id: int) -> void:
	if not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var next_health := float((lobby.health as Dictionary).get(peer_id, MAX_HEALTH))
	var next_shield := float((lobby.shield as Dictionary).get(peer_id, MAX_SHIELD))
	for member_value in (lobby.players as Dictionary).keys():
		_client_vitals.rpc_id(int(member_value), peer_id, next_health, next_shield)


func _broadcast_power(code: String, peer_id: int) -> void:
	if not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var record: Dictionary = (lobby.players as Dictionary).get(peer_id, {})
	for member_value in (lobby.players as Dictionary).keys():
		_client_power.rpc_id(int(member_value), peer_id,
			str(record.get("power", "")), bool(record.get("invisible", false)))


func _broadcast_snitches(code: String) -> void:
	if not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var snapshot: Dictionary = (lobby.get("snitches", {}) as Dictionary).duplicate(true)
	for member_value in (lobby.players as Dictionary).keys():
		_client_snitch_snapshot.rpc_id(int(member_value), snapshot)


func _server_match_has_peer(code: String, peer_id: int) -> bool:
	return (not code.is_empty() and _server_lobbies.has(code)
		and str((_server_lobbies[code] as Dictionary).get("state", "")) == "match"
		and ((_server_lobbies[code] as Dictionary).players as Dictionary).has(peer_id))


func _server_remove_peer(peer_id: int) -> void:
	var code := str(_peer_lobbies.get(peer_id, ""))
	if code.is_empty() or not _server_lobbies.has(code):
		_peer_lobbies.erase(peer_id)
		return
	var lobby: Dictionary = _server_lobbies[code]
	var previous_state := str(lobby.get("state", ""))
	var lobby_players: Dictionary = lobby.players
	var leaving_record: Dictionary = lobby_players.get(peer_id, {})
	var dropped_power := str(leaving_record.get("power", ""))
	lobby_players.erase(peer_id)
	(lobby.health as Dictionary).erase(peer_id)
	(lobby.shield as Dictionary).erase(peer_id)
	(lobby.alive as Dictionary).erase(peer_id)
	(lobby.stats as Dictionary).erase(peer_id)
	_peer_lobbies.erase(peer_id)
	if lobby_players.is_empty():
		_server_lobbies.erase(code)
		_broadcast_public_lobbies()
		return
	if int(lobby.host_id) == peer_id:
		lobby.host_id = int(lobby_players.keys()[0])
	lobby.players = lobby_players
	if previous_state == "match" and not dropped_power.is_empty():
		_server_spawn_snitch(lobby, dropped_power, Vector3(0.0, 7.0, 0.0))
	_server_lobbies[code] = lobby
	if previous_state == "lobby":
		_broadcast_lobby(code)
	elif previous_state == "match" or previous_state == "intermission":
		for member_value in lobby_players.keys():
			_client_player_left.rpc_id(int(member_value), peer_id)
		if previous_state == "match" and not dropped_power.is_empty():
			_broadcast_snitches(code)
		if lobby_players.size() <= 1:
			_return_match_to_menu(code, "The match ended because too few players remain.")
			return
		if previous_state == "match":
			if str(lobby.mode) == "TEAM_DEATH_MATCH":
				var red_count := 0
				var blue_count := 0
				for record_value in lobby_players.values():
					var record: Dictionary = record_value
					if str(record.get("team", "")) == TEAM_RED:
						red_count += 1
					elif str(record.get("team", "")) == TEAM_BLUE:
						blue_count += 1
				if red_count == 0 or blue_count == 0:
					var remaining_team := TEAM_BLUE if red_count == 0 else TEAM_RED
					_finish_match(code, "TEAM %s REMAINS" % remaining_team,
						"The opposing team left the match.")
			else:
				_check_survival_winner(code)
	_broadcast_public_lobbies()


func _return_match_to_menu(code: String, detail: String) -> void:
	if not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var remaining_peers := (lobby.players as Dictionary).keys()
	_server_lobbies.erase(code)
	for member_value in remaining_peers:
		var member := int(member_value)
		_peer_lobbies.erase(member)
		_client_match_abandoned.rpc_id(member, detail)
	_broadcast_public_lobbies()


func _new_lobby_code() -> String:
	const LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	while true:
		var code := ""
		for _index in 5:
			code += LETTERS[randi_range(0, LETTERS.length() - 1)]
		if not _server_lobbies.has(code):
			return code
	return "ERROR"


func _server_next_team(lobby_players: Dictionary) -> String:
	var red_count := 0
	var blue_count := 0
	for record_value in lobby_players.values():
		var record := record_value as Dictionary
		if str(record.get("team", "")) == TEAM_RED:
			red_count += 1
		elif str(record.get("team", "")) == TEAM_BLUE:
			blue_count += 1
	return TEAM_RED if red_count <= blue_count else TEAM_BLUE


func _assign_balanced_teams(lobby_players: Dictionary) -> void:
	var peer_ids := lobby_players.keys()
	peer_ids.shuffle()
	var red_starts := randi_range(0, 1) == 0
	for index in peer_ids.size():
		var peer_id := int(peer_ids[index])
		var record := (lobby_players[peer_id] as Dictionary).duplicate(true)
		var even_slot := index % 2 == 0
		record.team = TEAM_RED if even_slot == red_starts else TEAM_BLUE
		lobby_players[peer_id] = record


func _make_player_record(peer_id: int, info: Dictionary, team: String) -> Dictionary:
	return {
		"peer_id": peer_id, "id": str(peer_id), "name": _clean_name(str(info.get("name", "Player"))),
		"team": team, "source": "human", "customization": _clean_customization(info.get("customization", {})),
		"health": MAX_HEALTH, "shield": MAX_SHIELD, "power": "", "invisible": false,
	}


func _clean_mode(value: String) -> String:
	return "SURVIVAL" if value.to_upper() == "SURVIVAL" else "TEAM_DEATH_MATCH"


func _clean_name(value: String) -> String:
	var clean := value.strip_edges()
	if clean.is_empty():
		clean = "Player"
	return clean.left(MAX_NAME_LENGTH)


func _clean_customization(value: Variant) -> Dictionary:
	var source: Dictionary = value if value is Dictionary else {}
	return {
		"username": _clean_name(str(source.get("username", local_player_info.get("name", "Player")))),
		"skin": str(source.get("skin", "default")).left(32),
		"body_color": clampi(int(source.get("body_color", 4)), 0, 9),
		"hat": clampi(int(source.get("hat", 0)), 0, 9),
		"mask": clampi(int(source.get("mask", 0)), 0, 9),
		"gun_skin": clampi(int(source.get("gun_skin", 0)), 0, 9),
		"back_bling": clampi(int(source.get("back_bling", 0)), 0, 9),
	}


func _clear_client_lobby() -> void:
	players.clear()
	snitches.clear()
	current_lobby_code = ""
	current_game_mode = ""
	current_host_id = 0
	match_active = false
	var empty_roster: Array[Dictionary] = []
	lobby_changed.emit(empty_roster)


func _set_state(next_state: int, detail: String) -> void:
	connection_state = next_state
	connection_state_changed.emit(connection_state, detail)


func _on_smoke_lobby_joined(code: String, mode: String) -> void:
	print("[network-smoke] joined %s mode=%s peer=%d" % [code, mode, local_peer_id()])
