extends Node

## Local frontend/session flow. Lobby entries are generic records; `source` is
## only a replaceable tag for this offline simulation.
const MATCH_SCENE := preload("res://scenes/match.tscn")
const Data := preload("res://scripts/character_customization_data.gd")
const PreviewScript := preload("res://scripts/character_preview.gd")
const PortraitScript := preload("res://scripts/bean_portrait.gd")
const MAX_PER_TEAM := 10
const CATEGORIES := ["SKINS", "BODY COLORS", "HATS", "MASKS", "GUN SKINS", "BACK BLING"]
const ITEM_NAMES := {
	"HATS": Data.HATS,
	"MASKS": Data.MASKS,
	"GUN SKINS": Data.GUN_SKINS,
	"BACK BLING": Data.BACK_BLING,
}
const TEAM_RED := Color("#FF627E")
const TEAM_BLUE := Color("#58D7F2")

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
var lobby_dropdown: OptionButton
var lobby_refresh_accumulator := 0.0
var inspection_hide_nodes: Array[Node3D] = []


func _ready() -> void:
	if NetworkSession.is_dedicated_server():
		return
	NetworkSession.connection_state_changed.connect(_on_network_state_changed)
	NetworkSession.connection_failed.connect(_on_network_failed)
	NetworkSession.lobby_joined.connect(_on_lobby_joined)
	NetworkSession.lobby_changed.connect(_on_online_lobby_changed)
	NetworkSession.lobby_list_changed.connect(_on_lobby_list_changed)
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
	for i in 7:
		var panel := _box(Vector3(0.23, 2.0 + float(i % 3) * 0.55, 0.22), Color(Data.ACCENT_COLORS[i]), true)
		panel.position = Vector3(-4.4 + i * 1.42, panel.mesh.get_aabb().size.y * 0.5, -2.65 - float(i % 2) * 0.25)
		stage.add_child(panel)
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


func _label(parent: Control, text_value: String, at: Vector2, size: Vector2, font_size := 18, color := Color("#F8F5FF")) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = at
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _panel(parent: Control, at: Vector2, size: Vector2, tint: Color, border := 2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = at
	panel.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.11, 0.91)
	style.border_color = tint
	style.set_border_width_all(border)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _button(parent: Control, text_value: String, at: Vector2, size: Vector2, action: Callable, disabled := false, accent := Color("#8CEADF")) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = at
	button.size = size
	button.disabled = disabled
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("#FAF7FF"))
	button.add_theme_color_override("font_hover_color", accent)
	button.add_theme_color_override("font_disabled_color", Color("#747586"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.055, 0.065, 0.11, 0.78)
	normal.border_color = Color(accent, 0.4)
	normal.set_border_width_all(1)
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.corner_radius_bottom_left = 4
	normal.corner_radius_bottom_right = 4
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent, 0.19)
	hover.border_color = accent
	button.add_theme_stylebox_override("hover", hover)
	button.pressed.connect(action)
	var focus_first := parent.find_children("*", "Button", true, false).is_empty()
	parent.add_child(button)
	if focus_first and not disabled:
		button.call_deferred("grab_focus")
	return button


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
	var card := _panel(menu_content, Vector2(36, 40), Vector2(430, 625), Color("#70DED5"), 1)
	var content := Control.new()
	card.add_child(content)
	_label(content, "PAINT STRIKE:\nGLOWFALL", Vector2(12, 18), Vector2(390, 118), 39)
	_label(content, "TEAM DEATHMATCH  /  PAINT THE FUTURE", Vector2(14, 137), Vector2(390, 28), 13, Color("#93E7DD"))
	var user_label := _label(content, "LOCAL PILOT  •  %s" % _username(), Vector2(14, 174), Vector2(390, 25), 15, Color("#F49BC9"))
	_button(content, "PLAY", Vector2(12, 235), Vector2(374, 54), _begin_play, false, Color("#FF7391"))
	_button(content, "CUSTOMIZE CHARACTER", Vector2(12, 300), Vector2(374, 54), func(): _open_customization("main"))
	_button(content, "SETTINGS", Vector2(12, 365), Vector2(374, 54), _show_settings)
	_button(content, "QUIT", Vector2(12, 430), Vector2(374, 54), func(): get_tree().quit())
	_label(content, "LOCAL SESSION  •  GLOWFALL TEST BAY", Vector2(14, 568), Vector2(370, 22), 11, Color("#A7A7BC"))
	user_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_content.modulate.a = 0.0
	_create_tween().tween_property(menu_content, "modulate:a", 1.0, 0.28)


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
	var card := _panel(menu_content, Vector2(300, 92), Vector2(680, 540), Color("#5AD8EF"), 1)
	var content := Control.new()
	card.add_child(content)
	_label(content, "SELECT A GAME MODE", Vector2(24, 26), Vector2(620, 54), 32)
	_label(content, "CHOOSE YOUR GLOWFALL MATCH", Vector2(26, 81), Vector2(620, 24), 14, Color("#9FE9E1"))
	_button(content, "TEAM DEATH MATCH", Vector2(38, 142), Vector2(600, 110), _select_tdm, false, Color("#FF718A"))
	_label(content, "Human players. Red versus Blue. Most eliminations wins.", Vector2(58, 220), Vector2(560, 24), 15, Color("#DDE7F3"))
	_button(content, "SURVIVAL", Vector2(38, 286), Vector2(600, 110), func(): _launch_survival(), false, Color("#65E2D2"))
	_label(content, "Human free-for-all. One life. Last player standing wins.", Vector2(58, 364), Vector2(560, 24), 15, Color("#DDE7F3"))
	_button(content, "BACK", Vector2(38, 446), Vector2(180, 48), func(): _fade_transition(_show_main, false))
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
	var card := _panel(menu_content, Vector2(300, 66), Vector2(680, 610), Color("#65E2D2"), 1)
	var content := Control.new()
	card.add_child(content)
	var mode_title := "SURVIVAL" if selected_game_mode == "SURVIVAL" else "TEAM DEATHMATCH"
	_label(content, mode_title + "  /  ONLINE", Vector2(24, 16), Vector2(620, 48), 30)
	status_label = _label(content, "Create a lobby or choose an available room.", Vector2(26, 66), Vector2(620, 28), 15, Color("#B4EEE7"))
	_button(content, "CREATE LOBBY", Vector2(38, 108), Vector2(604, 56), _create_online_lobby, false, Color("#FF718A"))
	_label(content, "AVAILABLE LOBBIES", Vector2(40, 187), Vector2(300, 24), 13, Color("#DDE7F3"))
	lobby_dropdown = OptionButton.new()
	lobby_dropdown.position = Vector2(38, 215)
	lobby_dropdown.size = Vector2(604, 50)
	lobby_dropdown.add_theme_font_size_override("font_size", 16)
	lobby_dropdown.item_selected.connect(_on_lobby_selected)
	content.add_child(lobby_dropdown)
	_label(content, "FILTER OR ENTER ROOM CODE", Vector2(40, 292), Vector2(330, 24), 13, Color("#DDE7F3"))
	join_code_edit = LineEdit.new()
	join_code_edit.placeholder_text = "ABCDE"
	join_code_edit.max_length = 6
	join_code_edit.position = Vector2(38, 320)
	join_code_edit.size = Vector2(380, 52)
	join_code_edit.add_theme_font_size_override("font_size", 22)
	join_code_edit.text_changed.connect(func(_value): _render_lobby_dropdown())
	content.add_child(join_code_edit)
	_button(content, "JOIN", Vector2(432, 320), Vector2(210, 52), _join_online_lobby)
	_button(content, "REFRESH", Vector2(38, 404), Vector2(210, 48), _refresh_lobby_list)
	_button(content, "BACK", Vector2(432, 404), Vector2(210, 48), func(): _fade_transition(_show_mode_select, false))
	_render_lobby_dropdown()
	lobby_refresh_accumulator = 0.0
	_refresh_lobby_list()


func _create_online_lobby() -> void:
	NetworkSession.configure_local_player(_username(), customization)
	status_label.text = "CONNECTING TO ONLINE SERVER..."
	NetworkSession.create_lobby(selected_game_mode)


func _join_online_lobby() -> void:
	var code := join_code_edit.text.strip_edges().to_upper()
	if code.is_empty() and is_instance_valid(lobby_dropdown) and lobby_dropdown.selected >= 0:
		code = str(lobby_dropdown.get_item_metadata(lobby_dropdown.selected))
	NetworkSession.configure_local_player(_username(), customization)
	status_label.text = "CONNECTING TO LOBBY..."
	NetworkSession.join_lobby(code)


func _refresh_lobby_list() -> void:
	if current_screen == "online_setup":
		NetworkSession.request_lobby_list()


func _on_lobby_list_changed(_lobbies: Array[Dictionary]) -> void:
	if current_screen == "online_setup":
		_render_lobby_dropdown()


func _render_lobby_dropdown() -> void:
	if not is_instance_valid(lobby_dropdown):
		return
	lobby_dropdown.clear()
	var filter_code := ""
	if is_instance_valid(join_code_edit):
		filter_code = join_code_edit.text.strip_edges().to_upper()
	for lobby in NetworkSession.public_lobbies:
		var code := str(lobby.get("code", ""))
		if str(lobby.get("mode", "")) != selected_game_mode:
			continue
		if not filter_code.is_empty() and not code.contains(filter_code):
			continue
		var row := "%s  •  %d/%d PLAYERS  •  CODE %s" % [
			str(lobby.get("host_name", "Player")),
			int(lobby.get("player_count", 0)),
			int(lobby.get("max_players", 20)), code]
		lobby_dropdown.add_item(row)
		lobby_dropdown.set_item_metadata(lobby_dropdown.item_count - 1, code)
	if lobby_dropdown.item_count == 0:
		lobby_dropdown.add_item("NO JOINABLE LOBBIES FOUND")
		lobby_dropdown.set_item_metadata(0, "")
		lobby_dropdown.disabled = true
	else:
		lobby_dropdown.disabled = false
		lobby_dropdown.select(0)


func _on_lobby_selected(index: int) -> void:
	if not is_instance_valid(join_code_edit):
		return
	var code := str(lobby_dropdown.get_item_metadata(index))
	if not code.is_empty():
		join_code_edit.text = code
		join_code_edit.caret_column = code.length()


func _on_network_state_changed(_state: int, detail: String) -> void:
	if current_screen == "online_setup" and is_instance_valid(status_label):
		status_label.text = detail.to_upper()


func _on_network_failed(detail: String) -> void:
	if (current_screen == "online_setup" or current_screen == "lobby") and is_instance_valid(status_label):
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
	var mode_title := "SURVIVAL FREE-FOR-ALL" if selected_game_mode == "SURVIVAL" else "TEAM DEATHMATCH"
	var title := _label(menu_content, mode_title, Vector2(0, 26), Vector2(1280, 48), 31)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lobby_status := "%s  •  CODE %s" % [status, NetworkSession.current_lobby_code]
	status_label = _label(menu_content, "MATCH STARTING" if match_starting else lobby_status, Vector2(0, 78), Vector2(1280, 26), 16, Color("#B4EEE7"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label = _label(menu_content, "", Vector2(0, 105), Vector2(1280, 38), 27, Color("#FFE28D"))
	if match_starting:
		countdown_label.text = str(countdown_remaining)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if selected_game_mode == "SURVIVAL":
		var players_panel := _panel(menu_content, Vector2(290, 154), Vector2(700, 474), TEAM_BLUE)
		red_rows = _team_column(players_panel, "HUMAN PLAYERS", TEAM_BLUE)
		blue_rows = null
		fill_label = _label(menu_content, "%d / %d PLAYERS" % [lobby_players.size(), MAX_PER_TEAM * 2], Vector2(0, 638), Vector2(1280, 28), 17)
	else:
		var red_panel := _panel(menu_content, Vector2(54, 154), Vector2(564, 474), TEAM_RED)
		var blue_panel := _panel(menu_content, Vector2(662, 154), Vector2(564, 474), TEAM_BLUE)
		red_rows = _team_column(red_panel, "TEAM RED", TEAM_RED)
		blue_rows = _team_column(blue_panel, "TEAM BLUE", TEAM_BLUE)
		fill_label = _label(menu_content, "RED  0 / 10          BLUE  0 / 10", Vector2(0, 638), Vector2(1280, 28), 17)
	fill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(menu_content, "CUSTOMIZE CHARACTER", Vector2(42, 674), Vector2(258, 38), func(): _open_customization("lobby"))
	_button(menu_content, "LEAVE QUEUE", Vector2(980, 674), Vector2(252, 38), _leave_lobby, false, Color("#FFA2B4"))
	_button(menu_content, "START MATCH", Vector2(514, 674), Vector2(252, 38), NetworkSession.start_match, not NetworkSession.is_host(), Color("#FFE28D"))
	_render_team_rows()


func _team_column(panel: PanelContainer, heading: String, accent: Color) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var title := Label.new()
	title.text = heading
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", accent)
	column.add_child(title)
	var note := Label.new()
	note.text = "10 PLAYER SLOTS"
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color("#B2B5C7"))
	column.add_child(note)
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
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(520, 34)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#292333" if team == "RED" else "#1F2F3A", 0.92)
		var is_local := int(player_record.get("peer_id", -1)) == NetworkSession.local_peer_id()
		style.border_color = Color(_team_color(team), 0.95) if is_local else Color("#56596B")
		style.set_border_width_all(2 if is_local else 1)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 1
		style.content_margin_bottom = 1
		row.add_theme_stylebox_override("panel", style)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		row.add_child(line)
		var icon := PortraitScript.new()
		icon.custom_minimum_size = Vector2(26, 27)
		icon.team_color = _team_color(team)
		line.add_child(icon)
		var name_label := Label.new()
		name_label.text = str(player_record.name) + ("  •  YOU" if is_local else "")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.add_theme_color_override("font_color", Color("#FFFFFF") if is_local else Color("#D5D8E4"))
		line.add_child(name_label)
		var position_label := Label.new()
		position_label.text = "%02d" % (ordinal + 1)
		position_label.add_theme_font_size_override("font_size", 10)
		position_label.add_theme_color_override("font_color", Color("#AEB3C5"))
		line.add_child(position_label)
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
	slot.custom_minimum_size = Vector2(520, 34)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#181B29", 0.64)
	style.border_color = Color(tint, 0.18)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	slot.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = "OPEN SLOT"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("#74788C"))
	slot.add_child(label)
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


func _show_customization() -> void:
	current_screen = "customize"
	_clear_screen()
	var panel := _panel(menu_content, Vector2(24, 14), Vector2(430, 692), Color("#77EBDD"), 1)
	var content := Control.new()
	panel.add_child(content)
	_label(content, "CHARACTER\nINSPECTION", Vector2(8, 4), Vector2(390, 78), 28)
	_label(content, "DRAG TO ROTATE  •  ← / → TO INSPECT", Vector2(10, 82), Vector2(390, 23), 10, Color("#91E4DC"))
	username_edit = LineEdit.new()
	username_edit.position = Vector2(8, 112)
	username_edit.size = Vector2(385, 38)
	username_edit.max_length = 16
	username_edit.placeholder_text = "Enter username"
	username_edit.text = _username()
	username_edit.text_submitted.connect(_commit_username)
	username_edit.focus_exited.connect(func(): _commit_username(username_edit.text))
	content.add_child(username_edit)
	_label(content, "LOADOUT CATEGORY", Vector2(10, 160), Vector2(350, 20), 12, Color("#E9B4DB"))
	for index in CATEGORIES.size():
		var category: String = CATEGORIES[index]
		var allowed := Data.category_allows(customization, category)
		var tab_text := ("›  " if selected_category == category else "") + category
		var tab := _button(content, tab_text, Vector2(8, 184 + index * 38), Vector2(180, 33), func(): selected_category = category; _show_customization(), false, Color("#8CEADF"))
		if not allowed:
			tab.add_theme_color_override("font_color", Color("#A2A3AF"))
		elif selected_category == category:
			tab.add_theme_color_override("font_color", Color("#9AF4E6"))
	var category_title := _label(content, selected_category, Vector2(200, 160), Vector2(220, 22), 12, Color("#E9B4DB"))
	category_title.clip_text = true
	var allowed := Data.category_allows(customization, selected_category)
	if not allowed:
		var reason := "BODY COLOR IS FOR THE DEFAULT BEAN ONLY" if selected_category == "BODY COLORS" else "THIS COMPLETE SKIN DOES NOT SUPPORT THIS ACCESSORY"
		_label(content, reason, Vector2(200, 185), Vector2(220, 58), 10, Color("#A0A2B0"))
	else:
		var items := _options_for(selected_category)
		for index in items.size():
			var option_index := index
			var col := index % 2
			var row := index / 2
			var item_text := str(items[index])
			var item_button := _button(content, item_text, Vector2(200 + col * 98, 198 + row * 55), Vector2(94, 47), func(): _select_option(selected_category, option_index), false, Color("#8CEADF"))
			item_button.add_theme_font_size_override("font_size", 9)
			if _selected_option(selected_category) == option_index:
				item_button.add_theme_color_override("font_color", Color("#9AF4E6"))
				item_button.text = "✓ " + item_text
	_label(content, "GUN SKIN IS A SEPARATE PAINT GUN PRESET", Vector2(10, 540), Vector2(400, 21), 10, Color("#A9B0C4"))
	_button(content, "BACK", Vector2(10, 580), Vector2(374, 46), _return_from_customization, false, Color("#FF90BB"))
	_label(content, "CURRENT SESSION ONLY", Vector2(10, 636), Vector2(370, 18), 10, Color("#858A9E"))
	preview.set_customization(customization)
	menu_content.modulate.a = 0.0
	_create_tween().tween_property(menu_content, "modulate:a", 1.0, 0.28)


func _options_for(category: String) -> Array:
	match category:
		"SKINS":
			var result: Array = ["DEFAULT BEAN"]
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
	_show_customization()


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
	var card := _panel(menu_content, Vector2(36, 40), Vector2(430, 625), Color("#70DED5"), 1)
	var content := Control.new()
	card.add_child(content)
	_label(content, "SETTINGS", Vector2(12, 22), Vector2(380, 58), 36)
	_label(content, "MASTER VOLUME", Vector2(12, 112), Vector2(380, 24), 16)
	var volume := HSlider.new()
	volume.position = Vector2(12, 143)
	volume.size = Vector2(365, 32)
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.01
	volume.value = volume_value
	volume.value_changed.connect(func(value): volume_value = value; AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value, 0.001))))
	content.add_child(volume)
	_label(content, "MOUSE SENSITIVITY", Vector2(12, 205), Vector2(380, 24), 16)
	var sensitivity := HSlider.new()
	sensitivity.position = Vector2(12, 236)
	sensitivity.size = Vector2(365, 32)
	sensitivity.min_value = 0.0005
	sensitivity.max_value = 0.006
	sensitivity.step = 0.0001
	sensitivity.value = sensitivity_value
	sensitivity.value_changed.connect(func(value): sensitivity_value = value)
	content.add_child(sensitivity)
	_button(content, "FULLSCREEN  %s" % ("ON" if fullscreen else "OFF"), Vector2(12, 310), Vector2(365, 48), func(): fullscreen = not fullscreen; DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED); _show_settings())
	_button(content, "BACK", Vector2(12, 388), Vector2(365, 48), _show_main)


func _team_color(team: String) -> Color:
	return TEAM_RED if team == "RED" else TEAM_BLUE


func _unhandled_input(event: InputEvent) -> void:
	if current_screen == "customize":
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging_character = event.pressed and event.position.x > 450
		elif event is InputEventMouseMotion and dragging_character:
			rotation_target += event.relative.x * 0.009
		elif event.is_action_pressed("ui_left"):
			rotation_target -= 0.65
		elif event.is_action_pressed("ui_right"):
			rotation_target += 0.65
	if event.is_action_pressed("ui_cancel"):
		if current_screen == "customize":
			_return_from_customization()
		elif current_screen == "settings":
			_show_main()
		elif current_screen == "lobby":
			_leave_lobby()


func _process(delta: float) -> void:
	if not is_instance_valid(preview_mount):
		return
	if current_screen == "online_setup":
		lobby_refresh_accumulator += delta
		if lobby_refresh_accumulator >= 2.0:
			lobby_refresh_accumulator = 0.0
			_refresh_lobby_list()
	if current_screen == "customize":
		if Input.is_action_just_pressed("ui_left"):
			rotation_target -= 0.65
		if Input.is_action_just_pressed("ui_right"):
			rotation_target += 0.65
		preview_mount.rotation.y = lerp_angle(preview_mount.rotation.y, rotation_target, 1.0 - exp(-delta * 8.0))
	else:
		preview_mount.rotation.y += delta * 0.08
		preview_mount.position.y = 0.23 + sin(Time.get_ticks_msec() * 0.0012) * 0.035
