extends Node

## Local frontend/session flow. Lobby entries are generic records; `source` is
## only a replaceable tag for this offline simulation.
const MATCH_SCENE := preload("res://scenes/match.tscn")
const Data := preload("res://scripts/character_customization_data.gd")
const PreviewScript := preload("res://scripts/character_preview.gd")
const PortraitScript := preload("res://scripts/bean_portrait.gd")
const UITheme = preload("res://scripts/ui/ui_theme.gd")
const BrushStroke = preload("res://scripts/ui/widgets/brush_stroke.gd")
const PaintKit = preload("res://scripts/visual/paint_kit.gd")
const MAX_PER_TEAM := 10
const CATEGORIES := ["SKINS", "BODY COLORS", "HATS", "MASKS", "GUN SKINS", "BACK BLING"]
## On-screen names for the categories (the keys stay the data's names).
const CATEGORY_LABELS := {"SKINS": "OUTFITS", "BODY COLORS": "SUIT COLORS"}
const ITEM_NAMES := {
	"HATS": Data.HATS,
	"MASKS": Data.MASKS,
	"GUN SKINS": Data.GUN_SKINS,
	"BACK BLING": Data.BACK_BLING,
}
const TEAM_RED := UITheme.TEAM_RED
const TEAM_BLUE := UITheme.TEAM_BLUE

var customization: Dictionary = Data.create_session_data()
var lobby_players: Array[Dictionary] = []
var local_team := "BLUE"
var selected_game_mode := "SURVIVAL"
var current_screen := "main"
var selected_category := "SKINS"
var customize_return := "main"
var match_starting := false
var countdown_remaining := 0
var queue_generation := 0
var preview: Node3D
var preview_mount: Node3D
var menu_camera: Camera3D
var menu_content: Control
var screen_root: Control
var fade_overlay: ColorRect
var status_label: Label
var count_label: Label
var countdown_label: Label
var username_edit: LineEdit
var volume_value := 0.8
var sensitivity_value := 0.0022
var fullscreen := false
var dragging_character := false
var rotation_target := 0.0
var red_rows: VBoxContainer
var blue_rows: VBoxContainer
var fill_label: Label
var join_code_edit: LineEdit
var inspection_hide_nodes: Array[Node3D] = []
## The customize page's card, so drag-to-rotate can start at its real edge.
var customize_panel: Control
var fullscreen_toggle: Button


func _ready() -> void:
	if NetworkSession.is_dedicated_server():
		return
	NetworkSession.connection_state_changed.connect(_on_network_state_changed)
	NetworkSession.connection_failed.connect(_on_network_failed)
	NetworkSession.lobby_joined.connect(_on_lobby_joined)
	NetworkSession.lobby_changed.connect(_on_online_lobby_changed)
	NetworkSession.match_started.connect(_on_online_match_started)
	NetworkSession.server_left.connect(_on_server_left)
	randomize()
	_build_showcase()
	_build_ui()
	_show_main()


func _build_showcase() -> void:
	var stage := Node3D.new()
	stage.name = "GlowfallShowcase"
	add_child(stage)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#111421")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#AAA7D2")
	environment.ambient_light_energy = 0.66
	environment.glow_enabled = true
	environment.glow_intensity = 0.85
	environment.glow_bloom = 0.08
	world.environment = environment
	stage.add_child(world)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38, -25, 0)
	key_light.light_color = Color("#FFE8F3")
	key_light.light_energy = 1.35
	stage.add_child(key_light)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-22, 155, 12)
	rim.light_color = Color("#55EBDD")
	rim.light_energy = 1.0
	stage.add_child(rim)
	var magenta_light := OmniLight3D.new()
	magenta_light.position = Vector3(2.8, 2.3, -1.6)
	magenta_light.light_color = Color("#FF5DB6")
	magenta_light.light_energy = 2.8
	magenta_light.omni_range = 7.0
	stage.add_child(magenta_light)
	var teal_light := OmniLight3D.new()
	teal_light.position = Vector3(-3.1, 1.8, -1.0)
	teal_light.light_color = Color("#50DDEB")
	teal_light.light_energy = 2.0
	teal_light.omni_range = 6.0
	stage.add_child(teal_light)
	menu_camera = Camera3D.new()
	menu_camera.position = Vector3(0.15, 2.05, 5.4)
	menu_camera.fov = 48.0
	stage.add_child(menu_camera)
	menu_camera.look_at(Vector3(0, 1.05, 0), Vector3.UP)
	menu_camera.current = true
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(24, 24)
	floor.mesh = floor_mesh
	floor.position.y = -0.03
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#242638")
	floor_mat.roughness = 0.72
	floor.material_override = floor_mat
	stage.add_child(floor)
	# Original Glowfall stage: floating paint slats and a halo frame keep the
	# silhouette dramatic while leaving the left side open for menu controls.
	# The uprights are giant paint brushes (models/generated/prop_giant_brush),
	# standing where the original glowing slats stood, their tips dipped in
	# glowing paint in the same accent colours. Falls back to the slats if the
	# model is missing.
	for i in 7:
		var height := 2.0 + float(i % 3) * 0.55
		var accent := Color(Data.ACCENT_COLORS[i])
		var brush := PaintKit.instance("prop_giant_brush")
		if brush == null:
			var panel := _box(Vector3(0.23, height, 0.22), accent, true)
			panel.position = Vector3(-4.4 + i * 1.42, height * 0.5, -2.65 - float(i % 2) * 0.25)
			stage.add_child(panel)
			continue
		var glow := StandardMaterial3D.new()
		glow.albedo_color = accent
		glow.emission_enabled = true
		glow.emission = accent
		glow.emission_energy_multiplier = 1.4
		PaintKit.paint(brush, accent, Color.WHITE, false,
			{"PK_Dry1": glow, "PK_Dry2": glow, "PK_Dry3": glow, "PK_Dry4": glow})
		brush.scale = Vector3.ONE * (height / 4.0)
		brush.position = Vector3(-4.4 + i * 1.42, 0.0, -2.65 - float(i % 2) * 0.25)
		brush.rotation.y = deg_to_rad(-12.0 + float(i % 3) * 12.0)
		stage.add_child(brush)
	var halo := MeshInstance3D.new()
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 1.05
	halo_mesh.outer_radius = 1.13
	halo.mesh = halo_mesh
	halo.position = Vector3(1.55, 1.14, -1.5)
	halo.rotation.x = deg_to_rad(73)
	var halo_mat := StandardMaterial3D.new()
	halo_mat.albedo_color = Color("#5479A3")
	halo_mat.emission_enabled = true
	halo_mat.emission = Color("#3DE5DA")
	halo_mat.emission_energy_multiplier = 0.85
	halo.material_override = halo_mat
	stage.add_child(halo)
	inspection_hide_nodes.append(halo)
	var seat := MeshInstance3D.new()
	var seat_mesh := CylinderMesh.new()
	seat_mesh.top_radius = 0.48
	seat_mesh.bottom_radius = 0.54
	seat_mesh.height = 0.16
	seat.mesh = seat_mesh
	seat.position = Vector3(1.42, 0.28, 0.12)
	seat.material_override = _mat(Color("#43445D"), 0.45, 0.28)
	stage.add_child(seat)
	inspection_hide_nodes.append(seat)
	for x in [-0.31, 0.31]:
		var leg := _box(Vector3(0.09, 0.28, 0.09), Color("#5ADFD5"), true)
		leg.position = seat.position + Vector3(x, -0.2, 0)
		stage.add_child(leg)
		inspection_hide_nodes.append(leg)
	var orb := _orb(Vector3(2.72, 1.9, -0.25), Color("#75FFF0"), 0.34)
	stage.add_child(orb)
	var pink_orb := _orb(Vector3(-1.6, 2.75, -1.65), Color("#FF72BD"), 0.12)
	stage.add_child(pink_orb)
	var anim = load("res://scripts/menu_orb.gd").new()
	anim.targets = [orb, pink_orb]
	stage.add_child(anim)
	preview_mount = Node3D.new()
	preview_mount.name = "CharacterInspectionModel"
	preview_mount.position = Vector3(1.42, 0.23, 0)
	stage.add_child(preview_mount)
	preview = PreviewScript.new()
	preview_mount.add_child(preview)
	preview.set_customization(customization)
	preview.rotation.z = deg_to_rad(-3.0)
	var motes: Array[Node3D] = []
	for i in 16:
		var mote := _orb(Vector3(
			-3.0 + fmod(float(i) * 1.91, 6.0),
			0.35 + fmod(float(i) * 0.73, 2.7),
			-0.55 - fmod(float(i) * 0.27, 2.0)),
			Color(Data.ACCENT_COLORS[i % Data.ACCENT_COLORS.size()]), 0.025)
		stage.add_child(mote)
		motes.append(mote)
	var mote_anim = load("res://scripts/menu_orb.gd").new()
	mote_anim.targets = motes
	stage.add_child(mote_anim)


func _mat(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _box(size: Vector3, color: Color, emissive := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := _mat(color, 0.72)
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.55
	node.material_override = material
	return node


func _orb(at: Vector3, color: Color, radius: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	node.mesh = mesh
	node.position = at
	var material := _mat(color, 0.2)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.8
	node.material_override = material
	return node


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	screen_root = Control.new()
	screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.mouse_filter = Control.MOUSE_FILTER_PASS
	# One shared theme for every page (scripts/ui/ui_theme.gd): button padding,
	# hover/focus styles, panel boxes and heading sizes are inherited by every
	# Control built under this root.
	screen_root.theme = UITheme.build()
	layer.add_child(screen_root)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.03, 0.08, 0.34)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_root.add_child(shade)
	menu_content = Control.new()
	menu_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_content.mouse_filter = Control.MOUSE_FILTER_PASS
	screen_root.add_child(menu_content)
	fade_overlay = ColorRect.new()
	fade_overlay.color = Color.BLACK
	fade_overlay.modulate.a = 0.0
	fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_root.add_child(fade_overlay)


func _clear_screen() -> void:
	for child in menu_content.get_children():
		menu_content.remove_child(child)
		child.queue_free()


## A Label styled by one of the shared theme's type variations (TitleLabel,
## HeaderLabel, SubLabel, BodyLabel, DimLabel). It takes no position or size:
## the container it is added to lays it out.
func _label(parent: Control, text_value: String, variation: StringName = &"BodyLabel", color: Variant = null) -> Label:
	var label := Label.new()
	label.text = text_value
	label.theme_type_variation = variation
	if color != null:
		label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## A themed PanelContainer with a coloured border. The caller decides where it
## goes (pinned to an edge, or inside a CenterContainer).
func _panel(tint: Color, border := 1) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel(tint, border))
	return panel


## A themed button. Padding, hover and focus styles come from the shared theme
## (so text never touches the border); `accent` tints this button's hover edge
## and text. Its width comes from the container it is in.
func _button(parent: Control, text_value: String, action: Callable, accent := Color("#8CEADF"), disabled := false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.disabled = disabled
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 50)
	UITheme.accent_button(button, accent)
	button.pressed.connect(action)
	# A little motion on hover/focus and on press, so the menu feels
	# responsive. Visual only - the click itself is unchanged.
	button.mouse_entered.connect(func(): _hover_motion(button, true))
	button.mouse_exited.connect(func(): _hover_motion(button, false))
	button.focus_entered.connect(func(): _hover_motion(button, true))
	button.focus_exited.connect(func(): _hover_motion(button, false))
	button.button_down.connect(func(): _press_motion(button))
	parent.add_child(button)
	return button


## Grows a button 2% while hovered or focused. It grows from its LEFT edge
## (pivot on the left), so a full-width button never pushes into the card's
## left margin; the right side has padding to spare.
func _hover_motion(button: Button, on: bool) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	button.pivot_offset = Vector2(0.0, button.size.y * 0.5)
	var tween := button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * (1.02 if on else 1.0), 0.12).set_trans(Tween.TRANS_CUBIC)


## A quick squash on press.
func _press_motion(button: Button) -> void:
	if not is_instance_valid(button):
		return
	button.pivot_offset = Vector2(0.0, button.size.y * 0.5)
	var tween := button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * 0.97, 0.05)
	tween.tween_property(button, "scale", Vector2.ONE * 1.02, 0.1)


func _show_main() -> void:
	current_screen = "main"
	menu_camera.position = Vector3(0.15, 2.05, 6.7)
	menu_camera.look_at(Vector3(0, 1.05, 0), Vector3.UP)
	preview_mount.position = Vector3(1.42, 0.23, 0)
	preview_mount.rotation.y = PI + 0.2
	rotation_target = preview_mount.rotation.y
	for decor in inspection_hide_nodes:
		decor.visible = true
	_clear_screen()
	var column := _side_card(Color("#70DED5"))
	_title(column, "PAINT STRIKE:\nGLOWFALL", Color("#FF7391"), 39)
	_label(column, "TEAM DEATHMATCH  /  PAINT THE FUTURE", &"SubLabel")
	_label(column, "LOCAL PILOT  •  %s" % _username(), &"BodyLabel", Color("#F49BC9"))
	_spacer(column, 22.0)
	var play := _button(column, "PLAY", _begin_play, Color("#FF7391"))
	_button(column, "CUSTOMIZE CHARACTER", func(): _open_customization("main"))
	_button(column, "SETTINGS", _show_settings)
	_button(column, "QUIT", func(): get_tree().quit())
	_spacer(column)
	_label(column, "LOCAL SESSION  •  GLOWFALL TEST BAY", &"DimLabel")
	_focus_later(play)
	menu_content.modulate.a = 0.0
	_create_tween().tween_property(menu_content, "modulate:a", 1.0, 0.28)


## Gives a button keyboard focus once the page has finished building. If the
## page was rebuilt again in the meantime, the old button is gone and this
## quietly does nothing.
func _focus_later(button: Control) -> void:
	var focus := func():
		if is_instance_valid(button) and button.is_inside_tree():
			button.grab_focus()
	focus.call_deferred()


func _create_tween() -> Tween:
	return create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _fade_transition(callback: Callable, inspection: bool) -> void:
	var tween := _create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 1.0, 0.2)
	await tween.finished
	callback.call()
	for decor in inspection_hide_nodes:
		decor.visible = not inspection
	var destination := Vector3(0.0, 1.72, 4.15) if inspection else Vector3(0.15, 2.05, 5.4)
	var target := Vector3(0, 0.98, 0) if inspection else Vector3(0, 1.05, 0)
	var camera_tween := _create_tween()
	camera_tween.set_parallel(true)
	camera_tween.tween_property(menu_camera, "position", destination, 0.38)
	camera_tween.tween_property(preview_mount, "position", Vector3(0, 0, 0) if inspection else Vector3(1.42, 0.23, 0), 0.38)
	camera_tween.tween_property(menu_content, "modulate:a", 1.0, 0.28)
	menu_camera.look_at(target, Vector3.UP)
	await camera_tween.finished
	var out := _create_tween()
	out.tween_property(fade_overlay, "modulate:a", 0.0, 0.2)


func _username() -> String:
	var value := str(customization.get("username", "Player")).strip_edges()
	return "Player" if value.is_empty() else value


func _begin_play() -> void:
	current_screen = "mode_select"
	_fade_transition(_show_mode_select, false)


func _show_mode_select() -> void:
	current_screen = "mode_select"
	_clear_screen()
	# CenterContainer keeps the card in the middle of the window at any size.
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_content.add_child(centre)
	var card := _panel(Color("#5AD8EF"), 1)
	card.custom_minimum_size = Vector2(680, 0)
	centre.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	_title(column, "SELECT A GAME MODE", Color("#5AD8EF"), 32)
	_label(column, "CHOOSE YOUR GLOWFALL MATCH", &"SubLabel")
	_spacer(column, 6.0)
	var tdm := _mode_button(column, "TEAM DEATH MATCH", "Human players. Red versus Blue. Most eliminations wins.",
		"ONLINE", _select_tdm, Color("#FF718A"))
	_mode_button(column, "SURVIVAL", "Human free-for-all. One life. Last player standing wins.",
		"ONLINE", func(): _launch_survival(), Color("#65E2D2"))
	_spacer(column, 6.0)
	var back := _button(column, "BACK", func(): _fade_transition(_show_main, false))
	back.custom_minimum_size = Vector2(180, 48)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_focus_later(tdm)
	menu_content.modulate.a = 0.0
	_create_tween().tween_property(menu_content, "modulate:a", 1.0, 0.22)


func _launch_survival() -> void:
	selected_game_mode = "SURVIVAL"
	_show_online_setup()


func _select_tdm() -> void:
	selected_game_mode = "TEAM_DEATH_MATCH"
	_show_online_setup()


func _show_online_setup() -> void:
	current_screen = "online_setup"
	_clear_screen()
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_content.add_child(centre)
	var card := _panel(Color("#65E2D2"), 1)
	card.custom_minimum_size = Vector2(620, 0)
	centre.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	var mode_title := "SURVIVAL" if selected_game_mode == "SURVIVAL" else "TEAM DEATHMATCH"
	_title(column, mode_title + "  /  ONLINE", Color("#65E2D2"), 30)
	status_label = _label(column, "Create a lobby or enter a friend's code.", &"SubLabel")
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spacer(column, 4.0)
	var create := _button(column, "CREATE LOBBY", _create_online_lobby, Color("#FF718A"))
	create.custom_minimum_size = Vector2(0, 60)
	_spacer(column, 6.0)
	_label(column, "JOIN WITH LOBBY CODE", &"DimLabel")
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	column.add_child(join_row)
	join_code_edit = LineEdit.new()
	join_code_edit.placeholder_text = "ABCDE"
	join_code_edit.max_length = 6
	join_code_edit.custom_minimum_size = Vector2(0, 54)
	join_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_code_edit.add_theme_font_size_override("font_size", 22)
	join_row.add_child(join_code_edit)
	var join := _button(join_row, "JOIN", _join_online_lobby)
	join.custom_minimum_size = Vector2(180, 54)
	_spacer(column, 10.0)
	var back := _button(column, "BACK", func(): _fade_transition(_show_mode_select, false))
	back.custom_minimum_size = Vector2(180, 48)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_focus_later(create)


func _create_online_lobby() -> void:
	NetworkSession.configure_local_player(_username(), customization)
	status_label.text = "CONNECTING TO ONLINE SERVER..."
	NetworkSession.create_lobby(selected_game_mode)


func _join_online_lobby() -> void:
	NetworkSession.configure_local_player(_username(), customization)
	status_label.text = "CONNECTING TO LOBBY..."
	NetworkSession.join_lobby(join_code_edit.text)


func _on_network_state_changed(_state: int, detail: String) -> void:
	if current_screen == "online_setup" and is_instance_valid(status_label):
		status_label.text = detail.to_upper()


func _on_network_failed(detail: String) -> void:
	if current_screen == "online_setup" and is_instance_valid(status_label):
		status_label.text = detail.to_upper()


func _on_lobby_joined(_code: String, mode: String) -> void:
	selected_game_mode = mode
	lobby_players = NetworkSession.lobby_roster()
	var local_record := NetworkSession.players.get(NetworkSession.local_peer_id(), {}) as Dictionary
	local_team = str(local_record.get("team", "FFA"))
	_build_lobby_screen("LOBBY CONNECTED")


func _on_online_lobby_changed(roster: Array[Dictionary]) -> void:
	lobby_players = roster.duplicate(true)
	if current_screen == "lobby":
		var local_record := NetworkSession.players.get(NetworkSession.local_peer_id(), {}) as Dictionary
		local_team = str(local_record.get("team", local_team))
		_render_team_rows()


func _on_online_match_started(mode: String, roster: Array[Dictionary]) -> void:
	selected_game_mode = mode
	lobby_players = roster.duplicate(true)
	var local_record := NetworkSession.players.get(NetworkSession.local_peer_id(), {}) as Dictionary
	local_team = str(local_record.get("team", "FFA"))
	_lobby_to_match()


func _on_server_left() -> void:
	if current_screen == "lobby":
		_show_online_setup()
		status_label.text = "SERVER DISCONNECTED. TRY AGAIN."


func _begin_tdm_queue() -> void:
	_show_online_setup()


func _lobby_to_match() -> void:
	var cover_tween := _create_tween()
	cover_tween.tween_property(fade_overlay, "modulate:a", 1.0, 0.24)
	await cover_tween.finished
	var match_node = MATCH_SCENE.instantiate()
	match_node.game_mode = selected_game_mode
	match_node.session_team = local_team
	match_node.customization = customization.duplicate(true)
	match_node.session_mouse_sensitivity = sensitivity_value
	match_node.lobby_players = lobby_players.duplicate(true)
	get_tree().root.add_child(match_node)
	var curtain_layer := CanvasLayer.new()
	curtain_layer.layer = 100
	get_tree().root.add_child(curtain_layer)
	var curtain := ColorRect.new()
	curtain.color = Color.BLACK
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain_layer.add_child(curtain)
	get_tree().current_scene.queue_free()
	get_tree().current_scene = match_node
	var reveal := curtain.create_tween()
	reveal.tween_property(curtain, "modulate:a", 0.0, 0.35)
	reveal.tween_callback(curtain_layer.queue_free)


func _build_lobby_screen(status: String) -> void:
	current_screen = "lobby"
	_clear_screen()
	# A MarginContainer keeps an even border round the whole page and a VBox
	# stacks header, teams and footer. The team panels EXPAND to fill whatever
	# height is left, so the footer buttons always sit at the bottom of the
	# window instead of at a fixed y of 674.
	var page := MarginContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("margin_left", 40)
	page.add_theme_constant_override("margin_right", 40)
	page.add_theme_constant_override("margin_top", 20)
	page.add_theme_constant_override("margin_bottom", 22)
	menu_content.add_child(page)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	page.add_child(column)
	var survival := selected_game_mode == "SURVIVAL"
	_title(column, "SURVIVAL FREE-FOR-ALL" if survival else "TEAM DEATHMATCH",
		Color("#65E2D2") if survival else Color("#58D7F2"), 32, true)
	var lobby_status := "%s  •  CODE %s" % [status, NetworkSession.current_lobby_code]
	status_label = _label(column, "MATCH STARTING" if match_starting else lobby_status, &"SubLabel")
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label = _label(column, "", &"TitleLabel", Color("#FFE28D"))
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Always reserve the countdown's height, so the team panels do not jump
	# down the moment the numbers start.
	countdown_label.custom_minimum_size = Vector2(0, 46)
	if match_starting:
		countdown_label.text = str(countdown_remaining)
	var teams := HBoxContainer.new()
	teams.mouse_filter = Control.MOUSE_FILTER_IGNORE
	teams.add_theme_constant_override("separation", 28)
	teams.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(teams)
	if survival:
		# Free-for-all: one list of everyone, kept to a readable width.
		var players_panel := _panel(TEAM_BLUE, 2)
		players_panel.custom_minimum_size = Vector2(700, 0)
		players_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
		teams.add_child(players_panel)
		red_rows = _team_column(players_panel, "PLAYERS", TEAM_BLUE, "%d PLAYER SLOTS" % (MAX_PER_TEAM * 2))
		blue_rows = null
	else:
		var red_panel := _panel(TEAM_RED, 2)
		var blue_panel := _panel(TEAM_BLUE, 2)
		for panel in [red_panel, blue_panel]:
			panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			teams.add_child(panel)
		red_rows = _team_column(red_panel, "TEAM RED", TEAM_RED)
		blue_rows = _team_column(blue_panel, "TEAM BLUE", TEAM_BLUE)
	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_theme_constant_override("separation", 16)
	column.add_child(footer)
	var customize := _button(footer, "CUSTOMIZE CHARACTER", func(): _open_customization("lobby"))
	customize.custom_minimum_size = Vector2(250, 46)
	fill_label = _label(footer, "", &"HeaderLabel")
	fill_label.add_theme_font_size_override("font_size", 18)
	fill_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill_label.size_flags_vertical = Control.SIZE_FILL
	fill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Only the lobby's host can start the match; everyone else waits for them.
	var host := NetworkSession.is_host()
	var start := _button(footer, "START MATCH" if host else "WAITING FOR HOST",
		NetworkSession.start_match, Color("#FFE28D"), not host)
	start.custom_minimum_size = Vector2(230, 46)
	var leave := _button(footer, "LEAVE LOBBY", _leave_lobby, Color("#FFA2B4"))
	leave.custom_minimum_size = Vector2(200, 46)
	_focus_later(start if host else customize)
	_render_team_rows()


func _team_column(panel: PanelContainer, heading: String, accent: Color,
		slots_note := "10 PLAYER SLOTS") -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label(header, heading, &"HeaderLabel", accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var note := _label(header, slots_note, &"DimLabel")
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.size_flags_vertical = Control.SIZE_FILL
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	column.add_child(rows)
	return rows


func _render_team_rows() -> void:
	if not is_instance_valid(red_rows):
		return
	var containers: Array[VBoxContainer] = [red_rows]
	if is_instance_valid(blue_rows):
		containers.append(blue_rows)
	for container in containers:
		for child in container.get_children():
			child.queue_free()
	var red_index := 0
	var blue_index := 0
	for player_record in lobby_players:
		var team := str(player_record.team)
		var target_rows := red_rows if selected_game_mode == "SURVIVAL" or team == "RED" else blue_rows
		var ordinal := red_index if selected_game_mode == "SURVIVAL" or team == "RED" else blue_index
		if selected_game_mode == "SURVIVAL" or team == "RED": red_index += 1
		else: blue_index += 1
		var is_local := int(player_record.get("peer_id", -1)) == NetworkSession.local_peer_id()
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(0, 34)
		row.add_theme_stylebox_override("panel", UITheme.box(
			Color("#292333" if team == "RED" else "#1F2F3A", 0.92),
			Color(_team_color(team), 0.95) if is_local else Color("#56596B"),
			2 if is_local else 1, 5, 10.0, 2.0))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		row.add_child(line)
		var icon := PortraitScript.new()
		icon.custom_minimum_size = Vector2(26, 27)
		icon.team_color = _team_color(team)
		line.add_child(icon)
		if is_local:
			line.add_child(_you_chip())
		var name_label := Label.new()
		name_label.text = str(player_record.name)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Long names are cut with "…" instead of pushing the slot number out.
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", Color("#FFFFFF") if is_local else Color("#D5D8E4"))
		if is_local:
			name_label.add_theme_font_override("font", UITheme.bold())
		line.add_child(name_label)
		var position_label := _label(line, "%02d" % (ordinal + 1), &"DimLabel", Color("#AEB3C5"))
		position_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		position_label.size_flags_vertical = Control.SIZE_FILL
		target_rows.add_child(row)
	if selected_game_mode != "SURVIVAL":
		for i in range(red_index, MAX_PER_TEAM): _empty_slot(red_rows, TEAM_RED)
		for i in range(blue_index, MAX_PER_TEAM): _empty_slot(blue_rows, TEAM_BLUE)
	if is_instance_valid(fill_label):
		if selected_game_mode == "SURVIVAL":
			fill_label.text = "%d / %d PLAYERS  •  LAST PLAYER STANDING" % [lobby_players.size(), MAX_PER_TEAM * 2]
		else:
			fill_label.text = "RED  %d / %d          BLUE  %d / %d" % [_team_count("RED"), MAX_PER_TEAM, _team_count("BLUE"), MAX_PER_TEAM]


func _empty_slot(rows: VBoxContainer, tint: Color) -> void:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(0, 34)
	# Padded like a filled row, so "OPEN SLOT" no longer sits against the edge.
	slot.add_theme_stylebox_override("panel", UITheme.box(Color("#181B29", 0.64),
		Color(tint, 0.18), 1, 5, 14.0, 2.0))
	var label := _label(slot, "OPEN SLOT", &"DimLabel", Color("#74788C"))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rows.add_child(slot)


func _fill_lobby(this_queue: int) -> void:
	# Kept as a compatibility entry point for older menu callbacks. Online
	# lobbies are populated only by NetworkSession roster updates.
	if this_queue < 0:
		return


func _team_count(team: String) -> int:
	var count := 0
	for player_record in lobby_players:
		if str(player_record.team) == team:
			count += 1
	return count


func _start_countdown(this_queue: int) -> void:
	if this_queue < 0:
		return
	NetworkSession.start_match()


func _leave_lobby() -> void:
	queue_generation += 1
	match_starting = false
	NetworkSession.leave_lobby()
	lobby_players.clear()
	_fade_transition(_show_main, false)


func _open_customization(return_to: String) -> void:
	customize_return = return_to
	current_screen = "customize"
	_fade_transition(_show_customization, true)


func _show_customization(animate := true) -> void:
	current_screen = "customize"
	_clear_screen()
	var column := _side_card(Color("#77EBDD"), 460.0, 14.0)
	customize_panel = column.get_parent() as Control
	column.add_theme_constant_override("separation", 8)
	_title(column, "CHARACTER INSPECTION", Color("#77EBDD"), 28)
	_label(column, "DRAG TO ROTATE  •  ← / → TO INSPECT", &"DimLabel", Color("#91E4DC"))
	username_edit = LineEdit.new()
	username_edit.custom_minimum_size = Vector2(0, 40)
	username_edit.max_length = 16
	username_edit.placeholder_text = "Enter username"
	username_edit.text = _username()
	username_edit.text_submitted.connect(_commit_username)
	username_edit.focus_exited.connect(func(): _commit_username(username_edit.text))
	column.add_child(username_edit)

	# Two columns side by side: the category list and that category's options.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var categories := VBoxContainer.new()
	categories.add_theme_constant_override("separation", 6)
	categories.custom_minimum_size = Vector2(150, 0)
	body.add_child(categories)
	_label(categories, "LOADOUT CATEGORY", &"DimLabel", Color("#E9B4DB"))
	var focus_tab: Button = null
	for index in CATEGORIES.size():
		var category: String = CATEGORIES[index]
		var allowed := Data.category_allows(customization, category)
		var tab := _button(categories, CATEGORY_LABELS.get(category, category), func(): _pick_category(category))
		tab.custom_minimum_size = Vector2(0, 36)
		tab.add_theme_font_size_override("font_size", 14)
		# Toggle mode draws the selected category in the theme's "pressed"
		# style, instead of the old "›" text prefix that shifted the word.
		tab.toggle_mode = true
		tab.set_pressed_no_signal(selected_category == category)
		if not allowed:
			tab.add_theme_color_override("font_color", Color("#A2A3AF"))
		if selected_category == category:
			focus_tab = tab

	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 6)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(options)
	var category_title := _label(options, CATEGORY_LABELS.get(selected_category, selected_category), &"DimLabel", Color("#E9B4DB"))
	category_title.clip_text = true
	var allowed := Data.category_allows(customization, selected_category)
	if not allowed:
		var reason := "SUIT COLORS ARE FOR THE PLAIN CANVAS RUNNER" if selected_category == "BODY COLORS" else "THIS OUTFIT HAS ITS OWN HEADGEAR"
		var reason_label := _label(options, reason, &"BodyLabel", Color("#A0A2B0"))
		reason_label.add_theme_font_size_override("font_size", 13)
		# Wrap inside the column instead of running off the panel.
		reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		# A 2-column grid. Each cell is an equal share of the column's width,
		# and each button WRAPS its text, so a long name like PAINTBALL
		# SPLATTER goes onto two lines instead of widening into its neighbour.
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		options.add_child(grid)
		var items := _options_for(selected_category)
		for index in items.size():
			var option_index := index
			var item_text := str(items[index])
			var chosen := _selected_option(selected_category) == option_index
			var item_button := _button(grid, ("✓ " if chosen else "") + item_text, func(): _select_option(selected_category, option_index))
			item_button.toggle_mode = true
			item_button.set_pressed_no_signal(chosen)
			item_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
			item_button.custom_minimum_size = Vector2(0, 44)
			item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			item_button.add_theme_font_size_override("font_size", 12)

	_label(column, "YOUR LOOK AND GUN SKIN CARRY INTO MATCHES", &"DimLabel")
	_button(column, "BACK", _return_from_customization, Color("#FF90BB"))
	_label(column, "CURRENT SESSION ONLY", &"DimLabel", Color("#858A9E"))
	preview.set_customization(customization)
	if focus_tab != null:
		_focus_later(focus_tab)
	# Fade in when arriving on the page, but not on every option click - that
	# made the whole panel flash each time.
	if animate:
		menu_content.modulate.a = 0.0
		_create_tween().tween_property(menu_content, "modulate:a", 1.0, 0.28)


## Switches the customize category. Opening BACK BLING turns the character
## round so you can see the pack; leaving it turns them back.
func _pick_category(category: String) -> void:
	if category == "BACK BLING" and selected_category != "BACK BLING":
		rotation_target += PI
	elif category != "BACK BLING" and selected_category == "BACK BLING":
		rotation_target -= PI
	selected_category = category
	_show_customization(false)


func _options_for(category: String) -> Array:
	match category:
		"SKINS":
			var result: Array = ["CANVAS RUNNER"]
			for skin in Data.SKINS:
				result.append(str(skin.name))
			return result
		"BODY COLORS":
			var result: Array = []
			for item in Data.BODY_COLORS: result.append(str(item.name))
			return result
		_: return ITEM_NAMES.get(category, [])


func _select_option(category: String, option: int) -> void:
	if not Data.category_allows(customization, category):
		return
	match category:
		"SKINS":
			customization["skin"] = "default" if option == 0 else str(Data.SKINS[option - 1].id)
		"BODY COLORS": customization["body_color"] = option
		"HATS": customization["hat"] = option
		"MASKS": customization["mask"] = option
		"GUN SKINS": customization["gun_skin"] = option
		"BACK BLING": customization["back_bling"] = option
	_commit_username(str(customization.get("username", "Player")))
	preview.set_customization(customization)
	_show_customization(false)


func _selected_option(category: String) -> int:
	match category:
		"SKINS":
			var skin_id := str(customization.get("skin", "default"))
			if skin_id == "default": return 0
			for index in Data.SKINS.size():
				if str(Data.SKINS[index].id) == skin_id: return index + 1
			return 0
		"BODY COLORS": return int(customization.get("body_color", 4))
		"HATS": return int(customization.get("hat", 0))
		"MASKS": return int(customization.get("mask", 0))
		"GUN SKINS": return int(customization.get("gun_skin", 0))
		"BACK BLING": return int(customization.get("back_bling", 0))
		_: return 0


func _commit_username(value: String) -> void:
	var clean := value.strip_edges().substr(0, 16)
	customization["username"] = "Player" if clean.is_empty() else clean
	_sync_local_player_record()
	if username_edit and is_instance_valid(username_edit) and username_edit.text != customization.username:
		username_edit.text = customization.username


func _sync_local_player_record() -> void:
	for player_record in lobby_players:
		if int(player_record.get("peer_id", -1)) == NetworkSession.local_peer_id():
			player_record["name"] = customization.username
			player_record["customization"] = customization.duplicate(true)
	if NetworkSession.is_online():
		NetworkSession.configure_local_player(_username(), customization)
	if current_screen == "lobby":
		_render_team_rows()


func _return_from_customization() -> void:
	_commit_username(username_edit.text if is_instance_valid(username_edit) else _username())
	preview.set_customization(customization)
	if customize_return == "lobby":
		_build_lobby_screen("LOBBY CONNECTED")
		menu_content.modulate.a = 0.0
		_create_tween().tween_property(menu_content, "modulate:a", 1.0, 0.25)
		_fade_camera_to_lobby()
	else:
		_fade_transition(_show_main, false)


func _fade_camera_to_lobby() -> void:
	var tween := _create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 1.0, 0.15)
	await tween.finished
	var camera_tween := _create_tween()
	camera_tween.set_parallel(true)
	camera_tween.tween_property(menu_camera, "position", Vector3(0.15, 2.05, 5.4), 0.32)
	camera_tween.tween_property(preview_mount, "position", Vector3(1.42, 0.23, 0), 0.32)
	await camera_tween.finished
	var out := _create_tween()
	out.tween_property(fade_overlay, "modulate:a", 0.0, 0.18)


func _show_settings() -> void:
	current_screen = "settings"
	_clear_screen()
	var column := _side_card(Color("#70DED5"))
	_title(column, "SETTINGS", Color("#70DED5"), 36)
	_spacer(column, 12.0)

	var volume_readout := _setting_row(column, "MASTER VOLUME")
	var volume := HSlider.new()
	volume.custom_minimum_size = Vector2(0, 28)
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.01
	volume.value = volume_value
	volume_readout.text = "%d%%" % int(round(volume_value * 100.0))
	volume.value_changed.connect(func(value):
		volume_value = value
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value, 0.001)))
		volume_readout.text = "%d%%" % int(round(value * 100.0)))
	column.add_child(volume)
	_spacer(column, 10.0)

	var sensitivity_readout := _setting_row(column, "MOUSE SENSITIVITY")
	var sensitivity := HSlider.new()
	sensitivity.custom_minimum_size = Vector2(0, 28)
	sensitivity.min_value = 0.0005
	sensitivity.max_value = 0.006
	sensitivity.step = 0.0001
	sensitivity.value = sensitivity_value
	sensitivity_readout.text = _sensitivity_text(sensitivity_value)
	sensitivity.value_changed.connect(func(value):
		sensitivity_value = value
		sensitivity_readout.text = _sensitivity_text(value))
	column.add_child(sensitivity)
	_spacer(column, 16.0)

	fullscreen_toggle = _button(column, _fullscreen_text(), _toggle_fullscreen)
	_spacer(column)
	_button(column, "BACK", _show_main)
	_focus_later(fullscreen_toggle)
	menu_content.modulate.a = 0.0
	_create_tween().tween_property(menu_content, "modulate:a", 1.0, 0.22)


func _team_color(team: String) -> Color:
	return TEAM_RED if team == "RED" else TEAM_BLUE


func _unhandled_input(event: InputEvent) -> void:
	if current_screen == "customize":
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging_character = event.pressed and event.position.x > _customize_edge()
		elif event is InputEventMouseMotion and dragging_character:
			rotation_target += event.relative.x * 0.009
		elif event.is_action_pressed("ui_left"):
			rotation_target -= 0.65
		elif event.is_action_pressed("ui_right"):
			rotation_target += 0.65
	# Esc means "back" on every page, the same as that page's BACK button.
	if event.is_action_pressed("ui_cancel"):
		if current_screen == "customize":
			_return_from_customization()
		elif current_screen == "settings":
			_show_main()
		elif current_screen == "mode_select":
			_fade_transition(_show_main, false)
		elif current_screen == "lobby":
			_leave_lobby()


func _process(delta: float) -> void:
	if not is_instance_valid(preview_mount):
		return
	if current_screen == "customize":
		if Input.is_action_just_pressed("ui_left"):
			rotation_target -= 0.65
		if Input.is_action_just_pressed("ui_right"):
			rotation_target += 0.65
		preview_mount.rotation.y = lerp_angle(preview_mount.rotation.y, rotation_target, 1.0 - exp(-delta * 8.0))
	else:
		preview_mount.rotation.y += delta * 0.08
		preview_mount.position.y = 0.23 + sin(Time.get_ticks_msec() * 0.0012) * 0.035


## The tall card that Main, Settings and Customize sit in. It is anchored to
## the left edge from the top of the window to the bottom, so it always spans
## the full height (minus a margin) at any window size, instead of stopping at
## a fixed 625px. Returns the VBox inside it; the card is its parent.
func _side_card(tint: Color, width := 430.0, margin := 40.0) -> VBoxContainer:
	var card := _panel(tint, 1)
	card.anchor_left = 0.0
	card.anchor_right = 0.0
	card.anchor_top = 0.0
	card.anchor_bottom = 1.0
	card.offset_left = 36.0
	card.offset_right = 36.0 + width
	card.offset_top = margin
	card.offset_bottom = -margin
	menu_content.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	return column


## A page heading with a painted brush stroke behind it. The stroke and the
## label share one MarginContainer, which gives both the same rectangle, and the
## label is added second so it draws on top.
func _title(parent: Control, text_value: String, stroke: Color, font_size := 38, centered := false) -> Label:
	var holder := MarginContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# SHRINK makes the holder only as wide as the heading's text, so the stroke
	# ends where the word ends instead of running across the whole card.
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if centered else Control.SIZE_SHRINK_BEGIN
	parent.add_child(holder)
	var swash := BrushStroke.new()
	swash.color = stroke
	swash.seed_value = text_value.length()
	holder.add_child(swash)
	var label := _label(holder, text_value, &"TitleLabel")
	label.add_theme_font_size_override("font_size", font_size)
	return label


## Empty space in a VBox. With no height it EXPANDS, pushing whatever follows
## to the bottom of the card.
func _spacer(parent: Control, height := 0.0) -> Control:
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size = Vector2(0, height)
	if height <= 0.0:
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(gap)
	return gap


## A big mode button with its title and description INSIDE it. The old page
## drew each description as a separate label on top of its button, so the two
## overlapped. Here both texts are children of the button, laid out by a
## container, so they cannot overlap; they ignore the mouse so clicks still
## land on the button.
func _mode_button(parent: Control, title_text: String, description: String, tag: String,
		action: Callable, accent: Color) -> Button:
	var button := _button(parent, "", action, accent)
	button.custom_minimum_size = Vector2(0, 96)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	button.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	var heading := _label(column, title_text, &"HeaderLabel", accent)
	heading.add_theme_font_size_override("font_size", 22)
	var body := _label(column, description, &"BodyLabel")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tag_label := _label(row, tag, &"DimLabel")
	tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag_label.size_flags_vertical = Control.SIZE_FILL
	return button


## The small yellow "YOU" tag, matching the one on the in-match scoreboard.
func _you_chip() -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.WARN, 0.9),
		Color(UITheme.WARN, 0.9), 0, 4, 6.0, 1.0))
	var text := Label.new()
	text.text = "YOU"
	text.add_theme_font_size_override("font_size", 11)
	text.add_theme_font_override("font", UITheme.heavy())
	text.add_theme_color_override("font_color", UITheme.INK)
	chip.add_child(text)
	return chip


## One settings heading with its current value shown on the right.
## Returns the value label so the slider can keep it up to date.
func _setting_row(parent: Control, caption: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := _label(row, caption, &"HeaderLabel")
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _label(row, "", &"SubLabel")


## Sensitivity shown relative to the game's default (0.0022 = ×1.00), which
## means something to a player, rather than as radians per pixel.
func _sensitivity_text(value: float) -> String:
	return "×%.2f" % (value / 0.0022)


func _fullscreen_text() -> String:
	return "FULLSCREEN  %s" % ("ON" if fullscreen else "OFF")


## Updates the button's own text in place instead of rebuilding the page, so
## toggling does not make the whole settings card flash.
func _toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if is_instance_valid(fullscreen_toggle):
		fullscreen_toggle.text = _fullscreen_text()


## Where the customize panel ends on screen. Drags to the right of it rotate
## the character; presses on the panel itself belong to the panel's controls.
func _customize_edge() -> float:
	if customize_panel != null and is_instance_valid(customize_panel):
		return customize_panel.get_global_rect().end.x
	return 450.0
