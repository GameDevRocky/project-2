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
signal player_eliminated(victim_peer_id: int, attacker_peer_id: int)
signal player_respawned(peer_id: int)
signal score_changed(scores: Dictionary, stats: Dictionary)
signal match_finished(title: String, detail: String)

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

var connection_state := ConnectionState.OFFLINE
var players: Dictionary = {}
var current_lobby_code := ""
var current_game_mode := ""
var current_host_id := 0
var match_active := false
var public_lobbies: Array[Dictionary] = []
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


func _process(_delta: float) -> void:
	if not _dedicated_server:
		return
	var now := Time.get_ticks_msec()
	for code_value in _server_lobbies.keys():
		var code := str(code_value)
		var lobby: Dictionary = _server_lobbies[code]
		var state := str(lobby.get("state", ""))
		if state == "match" and str(lobby.get("mode", "")) == "TEAM_DEATH_MATCH":
			if int(lobby.get("ends_at", 0)) > 0 and now >= int(lobby.ends_at):
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
		"health": {}, "alive": {}, "scores": {TEAM_RED: 0, TEAM_BLUE: 0}, "stats": {}, "ends_at": 0,
		"next_match_at": 0, "round_number": 0,
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
	lobby_players[peer_id] = _make_player_record(peer_id, requested_info, str(previous.team))
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
	if (lobby.players as Dictionary).is_empty():
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
	var alive := {}
	var stats := {}
	for member_value in lobby_players.keys():
		var member := int(member_value)
		health[member] = 100.0
		alive[member] = true
		stats[member] = {"kills": 0, "deaths": 0}
	lobby.health = health
	lobby.alive = alive
	lobby.stats = stats
	lobby.scores = {TEAM_RED: 0, TEAM_BLUE: 0}
	lobby.state = "match"
	lobby.ends_at = Time.get_ticks_msec() + int(MATCH_SECONDS * 1000.0)
	lobby.next_match_at = 0
	lobby.round_number = int(lobby.get("round_number", 0)) + 1
	lobby.players = lobby_players
	_server_lobbies[code] = lobby
	for member_value in lobby_players.keys():
		_client_match_started.rpc_id(int(member_value), str(lobby.mode), lobby_players.duplicate(true))
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
	var safe_data := {
		"damage": clampf(float(shot_data.get("damage", 0.0)), 0.0, 100.0),
		"speed": clampf(float(shot_data.get("speed", 90.0)), 1.0, 120.0),
		"splash_radius": clampf(float(shot_data.get("splash_radius", 0.0)), 0.0, 10.0),
		"splash_mult": clampf(float(shot_data.get("splash_mult", 0.0)), 0.0, 1.0),
		"color": shot_data.get("color", Color.WHITE),
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
	var health: Dictionary = lobby.health
	health[victim_peer_id] = maxf(0.0, float(health.get(victim_peer_id, 100.0)) - clampf(damage, 0.0, 100.0))
	lobby.health = health
	_server_lobbies[code] = lobby
	_broadcast_health(code, victim_peer_id, float(health[victim_peer_id]))
	if float(health[victim_peer_id]) <= 0.0:
		_server_eliminate(code, victim_peer_id, attacker)


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


@rpc("authority", "call_remote", "reliable")
func _client_eliminated(victim_peer_id: int, attacker_peer_id: int) -> void:
	player_eliminated.emit(victim_peer_id, attacker_peer_id)


@rpc("authority", "call_remote", "reliable")
func _client_respawned(peer_id: int) -> void:
	player_respawned.emit(peer_id)


@rpc("authority", "call_remote", "reliable")
func _client_score_changed(scores: Dictionary, stats: Dictionary) -> void:
	score_changed.emit(scores.duplicate(true), stats.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func _client_match_finished(title: String, detail: String) -> void:
	match_active = false
	match_finished.emit(title, detail)


func _server_eliminate(code: String, victim: int, attacker: int) -> void:
	if not _server_lobbies.has(code):
		return
	var lobby: Dictionary = _server_lobbies[code]
	var alive: Dictionary = lobby.alive
	alive[victim] = false
	lobby.alive = alive
	var stats: Dictionary = lobby.stats
	var attacker_stats: Dictionary = stats.get(attacker, {"kills": 0, "deaths": 0})
	attacker_stats.kills = int(attacker_stats.kills) + 1
	stats[attacker] = attacker_stats
	var victim_stats: Dictionary = stats.get(victim, {"kills": 0, "deaths": 0})
	victim_stats.deaths = int(victim_stats.deaths) + 1
	stats[victim] = victim_stats
	lobby.stats = stats
	var reached_kill_limit := false
	var scoring_team := ""
	if str(lobby.mode) == "TEAM_DEATH_MATCH":
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
	var alive: Dictionary = lobby.alive
	health[peer_id] = 100.0
	alive[peer_id] = true
	lobby.health = health
	lobby.alive = alive
	_server_lobbies[code] = lobby
	for member_value in (lobby.players as Dictionary).keys():
		_client_health.rpc_id(int(member_value), peer_id, 100.0)
		_client_respawned.rpc_id(int(member_value), peer_id)


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
	var lobby_players: Dictionary = lobby.players
	lobby_players.erase(peer_id)
	(lobby.health as Dictionary).erase(peer_id)
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
	_server_lobbies[code] = lobby
	if str(lobby.state) == "lobby":
		_broadcast_lobby(code)
	elif str(lobby.mode) == "SURVIVAL":
		_check_survival_winner(code)
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
	current_lobby_code = ""
	current_game_mode = ""
	current_host_id = 0
	match_active = false
	lobby_changed.emit([])


func _set_state(next_state: int, detail: String) -> void:
	connection_state = next_state
	connection_state_changed.emit(connection_state, detail)


func _on_smoke_lobby_joined(code: String, mode: String) -> void:
	print("[network-smoke] joined %s mode=%s peer=%d" % [code, mode, local_peer_id()])
