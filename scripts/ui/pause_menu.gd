extends CanvasLayer

## ============================================================================
## PAUSE MENU - Esc during a Team Deathmatch or Survival match.
## ============================================================================
##
## Created by tdm_match_controller.gd for both online modes. Press Esc (the
## built-in "ui_cancel" action) to open it, and Esc again or RESUME to close.
##
## AN ONLINE MATCH CANNOT REALLY STOP
## Everyone else is still playing, so pausing does not freeze the world (that
## would be get_tree().paused, which only makes sense alone). Instead it frees
## your mouse and tells your player to ignore your keys and mouse until you
## resume (player.set_paused). The menu says so, so nobody is surprised to
## come back painted out.
##
## WHY _input AND NOT _unhandled_input
## Godot hands every key press to nodes in a fixed order: first every node's
## _input(), then the on-screen controls, then _unhandled_input(). The player
## script also listens for Esc in _unhandled_input (to free the mouse). Catching
## Esc here in _input and marking it handled means only the pause menu reacts.

const UITheme = preload("res://scripts/ui/ui_theme.gd")

## Untyped: set_paused() is this project's function, not CharacterBody3D's.
var _player = null
var _on_leave: Callable
var _enabled := true
var _root: Control
var _resume: Button


func _init() -> void:
	layer = 40
	visible = false


## Called once by the match controller after this node is in the tree.
## `on_leave` is the controller's own "leave the match" action.
func setup(player, on_leave: Callable) -> void:
	_player = player
	_on_leave = on_leave
	_build()


func _build() -> void:
	_root = Control.new()
	_root.theme = UITheme.build()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.05, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	var style := UITheme.panel(UITheme.ACCENT, 2)
	style.border_width_top = 6
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 26
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.text = "ONLINE MATCH  •  THE GAME KEEPS GOING"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(note)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	column.add_child(gap)

	_resume = _button(column, "RESUME", UITheme.ACCENT, close)
	_button(column, "LEAVE MATCH", Color("#FFA2B4"), _leave)
	var hint := Label.new()
	hint.theme_type_variation = &"DimLabel"
	hint.text = "ESC  to resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


func _button(parent: Control, text: String, accent: Color, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(0, 52)
	UITheme.accent_button(button, accent)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _input(event: InputEvent) -> void:
	if not _enabled or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if visible:
		close()
	else:
		open()


func open() -> void:
	if not _enabled or visible:
		return
	visible = true
	if _player != null and is_instance_valid(_player):
		_player.set_paused(true)
	# Focus RESUME once the menu has drawn - unless the menu (or the whole
	# match) is already gone by then.
	var focus := func():
		if is_instance_valid(_resume) and _resume.is_inside_tree() and visible:
			_resume.grab_focus()
	focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	if _player != null and is_instance_valid(_player):
		_player.set_paused(false)


func is_open() -> bool:
	return visible


## Off for good once the match has ended (the result screen takes over). The
## player is left as it was: the match is over, so its inputs no longer matter.
func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		visible = false


func _leave() -> void:
	visible = false
	_enabled = false
	_on_leave.call()
