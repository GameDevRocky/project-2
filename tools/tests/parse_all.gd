extends SceneTree

## ============================================================================
## PARSE ALL - a development tool, not part of the game.
## ============================================================================
##
## Compiles every script under res://scripts with the project's autoloads
## loaded. `--check-only --script` cannot do this for scripts that use the
## NetworkSession autoload: it does not load autoloads, so it reports a false
## "Identifier not found: NetworkSession". Run:
##
##   godot --headless --path . --script res://tools/tests/parse_all.gd

func _initialize() -> void:
	var failed := 0
	var checked := 0
	for path in _scripts("res://scripts"):
		checked += 1
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			failed += 1
			print("[parse] FAIL  %s" % path)
	print("[parse] %d scripts, %d failed" % [checked, failed])
	quit(1 if failed > 0 else 0)


func _scripts(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file in dir.get_files():
		if file.ends_with(".gd"):
			found.append(dir_path + "/" + file)
	for sub in dir.get_directories():
		found.append_array(_scripts(dir_path + "/" + sub))
	return found
