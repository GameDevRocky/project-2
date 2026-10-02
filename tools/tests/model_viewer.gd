extends SceneTree

## ============================================================================
## MODEL VIEWER - a development tool, not part of the game.
## ============================================================================
##
## Builds the real arena (arena.gd: same sky, sun, ambient, fog, floor), places
## the generated models (models/generated/*.glb) in the open east lane and
## screenshots them under in-game lighting: a line-up of every combatant at true
## scale, then a front and 3/4 close-up of each model. Opens a game window.
##
##   godot --path . --script res://tools/tests/model_viewer.gd -- --out=<dir> [--only=lineup|closeups|all]

const MODELS := {
	"enemy_sprayer": Color("#FFB7C5"),
	"enemy_bounder": Color("#98FF98"),
	"enemy_blotter": Color("#00A896"),
	"enemy_monolith": Color("#2B2D42"),
	"enemy_ghost": Color("#FFFFFF"),
	"canvas_runner": Color("#58D7F2"),
}
const SINGLES := ["paint_blaster", "chromatic_reservoir", "core_pigment", "healing_station",
	"paint_glob", "paint_splat", "prop_paint_tube", "prop_giant_brush", "prop_can_stack",
	"prop_mixing_vat", "prop_frame", "prop_banner", "prop_pipe_run", "prop_palette_inlay",
	"prop_hub_mobile", "prop_splat_decor"]

var _out := ""
var _only := "all"
var _world: Node3D
var _cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--only="):
			_only = a.substr(7)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_run.call_deferred()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, name]
	root.get_texture().get_image().save_png(path)
	print("[view] ", name)


func _load(name: String) -> Node3D:
	var path := "res://models/generated/%s.glb" % name
	if not ResourceLoader.exists(path):
		print("[view] missing ", path)
		return null
	var scene: PackedScene = load(path)
	return scene.instantiate()


## Colour every gameplay-role material the way the game will, for a fair look.
func _tint(node: Node, accent: Color, team := Color("#58D7F2")) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(i)
			if m == null:
				continue
			var n := m.resource_name
			var c: Variant = null
			if n in ["PK_Accent", "PK_AccentGlow", "PK_Fill", "PK_Wet"]:
				c = accent
			elif n in ["PK_Team", "PK_TeamGlow"]:
				c = team
			if c != null:
				var dup := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				dup.albedo_color = Color(c.r, c.g, c.b, dup.albedo_color.a)
				if dup.emission_enabled:
					dup.emission = c
				mi.set_surface_override_material(i, dup)
	for child in node.get_children():
		_tint(child, accent, team)


func _aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var arena := Node3D.new()
	arena.set_script(load("res://scripts/arena.gd"))
	_world.add_child(arena)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_world.add_child(_cam)
	_cam.current = true
	await create_timer(0.5).timeout

	if _only in ["all", "lineup"]:
		var x := 18.0
		var placed: Array = []
		for name in MODELS:
			var m := _load(name)
			if m == null:
				continue
			_world.add_child(m)
			_tint(m, MODELS[name])
			m.global_position = Vector3(x, 0.0, 6.0)
			placed.append(m)
			x += 2.6
		_cam.global_position = Vector3(24.5, 1.6, 15.5)
		_cam.look_at(Vector3(24.5, 1.0, 6.0))
		await create_timer(0.3).timeout
		await _snap("lineup_front")
		_cam.global_position = Vector3(31.0, 2.4, 13.0)
		_cam.look_at(Vector3(24.0, 0.9, 6.0))
		await _snap("lineup_34")
		_cam.global_position = Vector3(24.5, 1.8, -3.0)
		_cam.look_at(Vector3(24.5, 1.0, 6.0))
		await _snap("lineup_back")
		for m in placed:
			m.queue_free()
		await create_timer(0.2).timeout

	if _only in ["all", "closeups"]:
		for name in MODELS.keys() + SINGLES:
			var m := _load(name)
			if m == null:
				continue
			_world.add_child(m)
			_tint(m, MODELS.get(name, Color("#FFB7C5")))
			var base := Vector3(26.0, 0.0, 6.0)
			if name == "core_pigment":
				base.y = 0.7
			m.global_position = base
			await create_timer(0.1).timeout
			var box := _aabb(m)
			# Lift anything that pokes below the floor (the view-model gun's
			# pivot is its centre, so its grip would sink).
			if box.position.y < -0.02 and name != "core_pigment":
				m.global_position.y -= box.position.y
				box = _aabb(m)
			var centre := box.get_center()
			var r := maxf(box.size.length() * 0.5, 0.25)
			var dist := r / tan(deg_to_rad(_cam.fov * 0.5)) * 1.15
			_cam.global_position = centre + Vector3(0.0, r * 0.25, dist)
			_cam.look_at(centre)
			await _snap("close_%s_front" % name)
			_cam.global_position = centre + Vector3(dist * 0.7, r * 0.45, dist * 0.7)
			_cam.look_at(centre)
			await _snap("close_%s_34" % name)
			m.queue_free()
			await create_timer(0.1).timeout
	quit()
