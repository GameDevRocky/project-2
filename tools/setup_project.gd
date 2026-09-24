extends SceneTree

## ============================================================================
## SETUP PROJECT - a one-off maintenance script, not part of the game.
## ============================================================================
##
## Writes the game's input actions and window settings into project.godot, so
## they show up in Project > Project Settings > Input Map in the editor.
##
## WHY A SCRIPT INSTEAD OF JUST EDITING project.godot BY HAND
## Input actions are stored in that file in a dense generated format that is
## very easy to get subtly wrong - and a project.godot that fails to parse is a
## project that will not open at all. Letting Godot write its own settings file
## through ProjectSettings.save() means the format is correct by construction.
##
## The game does NOT depend on this having been run: game.gd registers the same
## actions at startup if they are missing. This is purely so the editor shows
## them.
##
## Run it with:
##     godot --headless --path <project> --script res://tools/setup_project.gd

func _initialize() -> void:
	var keys := {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
		"interact": KEY_E,
		"restart": KEY_R,
	}

	for action in keys:
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		ProjectSettings.set_setting("input/" + action, {
			"deadzone": 0.2,
			"events": [event],
		})

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	ProjectSettings.set_setting("input/fire", {
		"deadzone": 0.2,
		"events": [click],
	})

	ProjectSettings.set_setting("application/config/name", "Project 2: Inheritance")
	ProjectSettings.set_setting("display/window/size/viewport_width", 1280)
	ProjectSettings.set_setting("display/window/size/viewport_height", 720)

	var error := ProjectSettings.save()
	if error == OK:
		print("[setup] project.godot updated")
	else:
		print("[setup] FAILED to save, error code ", error)

	quit()
