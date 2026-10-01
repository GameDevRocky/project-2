extends SceneTree

## ============================================================================
## PERF PROBE - a development tool, not part of the game.
## ============================================================================
##
## Runs a full 2x10 TDM match in a real window (all 19 bots, the busiest scene
## in the game) and reports frames per second and the slowest frame, so a
## visual change can be checked for cost. Uncapped: v-sync is switched off for
## the measurement so the number shows real headroom, not the monitor's rate.
##
##   godot --path . --script res://tools/tests/perf_probe.gd [-- --seconds=20]
##
## Switches for finding what costs frame time (each turns one thing OFF after
## the match starts): --no-ssao, --no-visuals (hide combatant models),
## --remove-visuals (delete them outright), --mute-hud (HUD stops listening to the player), --no-dressing (hide props), --plain-surfaces (arena boxes back to plain
## materials), --no-shadows (sun shadows off). It also counts hitches: frames
## slower than 33 ms (below 30 fps).

var _elapsed := 0.0
var _seconds := 20.0
var _frames := 0
var _worst := 0.0
var _started := false
var _hitches := 0
var _draw_calls := 0.0
var _objects := 0.0
var _script_ms := 0.0
var _physics_ms := 0.0
var _flags: PackedStringArray = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			_seconds = float(a.substr(10))
		else:
			_flags.append(a)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var m = load("res://scenes/match.tscn").instantiate()
	m.game_mode = "TEAM_DEATH_MATCH"
	m.session_team = "BLUE"
	var records: Array[Dictionary] = []
	records.append({"id": "local", "name": "Player", "team": "BLUE", "source": "local", "customization": {}})
	for i in 19:
		records.append({"id": "sim_%02d" % i, "name": "Bot%02d" % i, "team": "RED" if i < 10 else "BLUE", "source": "local_simulation", "customization": {}})
	m.lobby_players = records
	root.add_child(m)
	current_scene = m


func _process(delta: float) -> bool:
	_elapsed += delta
	# Skip the first 3 s: loading and shader compilation are not gameplay.
	if _elapsed < 3.0:
		return false
	if not _started:
		_started = true
		var player = current_scene.get_node_or_null("Player")
		if player != null:
			player.rotation.y = PI * 0.5   # look toward the enemy spawn
		_apply_flags()
		return false
	_frames += 1
	_worst = maxf(_worst, delta)
	if delta > 0.0333:
		_hitches += 1
		print("[perf]   hitch %.0f ms at t=%.1f s" % [delta * 1000.0, _elapsed])
	# Steady measures that do not wobble with the GPU's clock speed.
	_draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_script_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	if "--no-visuals" in _flags:
		for n in current_scene.find_children("Visual", "Node3D", true, false):
			(n as Node3D).visible = false
	if "--remove-visuals" in _flags:
		for n in current_scene.find_children("Visual", "Node3D", true, false):
			n.get_parent().set("_visual", null)
			n.queue_free()
	if _elapsed >= 3.0 + _seconds:
		print("[perf] %s %s: %.0f fps average over %.0f s, slowest frame %.1f ms, %d hitches" % [
			RenderingServer.get_current_rendering_method(), " ".join(_flags), _frames / _seconds, _seconds,
			_worst * 1000.0, _hitches])
		print("[perf]   per frame: %.0f draw calls, %.0f objects drawn, %.2f ms process, %.2f ms physics" % [
			_draw_calls / _frames, _objects / _frames, _script_ms / _frames, _physics_ms / _frames])
		quit()
	return false


func _apply_flags() -> void:
	var scene := current_scene
	if "--no-ssao" in _flags:
		for w in scene.find_children("*", "WorldEnvironment", true, false):
			(w as WorldEnvironment).environment.ssao_enabled = false
	if "--mute-hud" in _flags:
		# Stop the HUD hearing the player's stats_changed signal.
		var player = scene.get_node_or_null("Player")
		for connection in player.stats_changed.get_connections():
			player.stats_changed.disconnect(connection["callable"])
	if "--remove-dressing" in _flags:
		var dressing := scene.find_child("Dressing", true, false)
		if dressing != null:
			dressing.queue_free()
	if "--no-dressing" in _flags:
		var d := scene.find_child("Dressing", true, false)
		if d != null:
			(d as Node3D).visible = false
	if "--no-shadows" in _flags:
		for l in scene.find_children("*", "DirectionalLight3D", true, false):
			(l as DirectionalLight3D).shadow_enabled = false
	if "--plain-surfaces" in _flags:
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.material_override is ShaderMaterial:
				var plain := StandardMaterial3D.new()
				plain.albedo_color = (m.material_override as ShaderMaterial).get_shader_parameter("albedo")
				m.material_override = plain
