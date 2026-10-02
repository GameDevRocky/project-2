extends SceneTree

## ============================================================================
## ARENA VIEWS - a development tool, not part of the game.
## ============================================================================
##
## Builds the arena (scripts/arena.gd) and the two trade stations on their own -
## no match, no server - then saves a screenshot from each viewpoint below.
## Windowed only (headless draws nothing):
##
##   godot --path . --script res://tools/tests/arena_views.gd -- --out=<dir>
##   (add --rendering-method gl_compatibility to see the web renderer)
##
## Matches are online-only now, so tools that load scenes/match.tscn go back
## to the menu; this one does not need a match at all.

const VIEWS := [
	["01_overview", Vector3(62.0, 42.0, 62.0), Vector3(0.0, 0.0, 0.0)],
	["02_top_down", Vector3(0.0, 120.0, 12.0), Vector3(0.0, 0.0, 0.0)],
	["03_hub", Vector3(16.0, 2.2, 17.0), Vector3(0.0, 1.5, 0.0)],
	["04_se_building", Vector3(28.0, 2.2, 28.0), Vector3(45.0, 2.0, 44.0)],
	["05_west_lanes", Vector3(-38.0, 1.7, 2.0), Vector3(-56.0, 1.5, -24.0)],
	["06_north_wall", Vector3(0.0, 1.7, -42.0), Vector3(0.0, 4.0, -67.5)],
	["07_corner", Vector3(52.0, 1.7, -52.0), Vector3(66.0, 2.0, -66.0)],
	["08_red_spawn", Vector3(-44.0, 3.0, 9.0), Vector3(-55.0, 0.0, 0.0)],
	["09_station", Vector3(-20.0, 1.7, -20.0), Vector3(-28.0, 2.0, -28.0)],
	["10_look_north", Vector3(0.0, 1.7, 30.0), Vector3(0.0, 18.0, -114.0)],
	["11_look_south", Vector3(0.0, 1.7, -30.0), Vector3(0.0, 18.0, 111.0)],
	["12_look_east", Vector3(-30.0, 1.7, 0.0), Vector3(102.0, 18.0, 9.0)],
	["13_look_west", Vector3(30.0, 1.7, 0.0), Vector3(-114.0, 18.0, -6.0)],
]

var _out := "user://arena_views"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var arena := Node3D.new()
	arena.set_script(load("res://scripts/arena.gd"))
	world.add_child(arena)
	var positions: Array = root.get_node("NetworkSession").STATION_POSITIONS
	for index in positions.size():
		var station := Node3D.new()
		station.set_script(load("res://scripts/healing_station.gd"))
		station.station_id = index
		world.add_child(station)
		station.global_position = positions[index]
	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.far = 400.0
	world.add_child(camera)
	camera.make_current()
	await create_timer(1.5).timeout
	for view in VIEWS:
		camera.global_position = view[1]
		var target: Vector3 = view[2]
		var up := Vector3.UP if absf((target - camera.global_position).normalized().y) < 0.98 else Vector3.FORWARD
		camera.look_at(target, up)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := _out.path_join("arena_%s.png" % view[0])
		root.get_texture().get_image().save_png(path)
		print("[arena] %s" % path)
	quit()
