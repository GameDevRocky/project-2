extends CanvasLayer

## ============================================================================
## HUD - everything drawn on top of the 3D world. This is the UX system.
## ============================================================================
##
## WHAT A CanvasLayer IS
## The 3D world is drawn from the player's camera, so anything inside it moves
## and shrinks with perspective. A CanvasLayer is a separate 2D sheet drawn on
## top of the finished 3D image, in flat screen pixels. Health bars, text and
## the crosshair all live here so they stay put and stay the same size no matter
## where the camera is pointing.
##
## THE SEAM, AND WHY IT ONLY RUNS ONE WAY
## The GDD names UX-to-game-logic as one of the two seams. This file is the UX
## side of it, and it is deliberately built so that information only flows
## INWARD: the HUD reads from the player and from game.gd, and never writes back.
## It cannot damage you, spend your paint or start a wave. That means a bug in
## here can make the game look wrong but can never make it BEHAVE wrong, which
## is exactly the property you want from a seam you expect to be worked on by
## three people at once.
##
## Everything is built in code, for the same reason the arena is: the layout is
## then a readable list rather than generated scene data.

const Traits = preload("res://scripts/traits.gd")

# --- Colours used throughout the interface ---------------------------------
const INK := Color("#2B2D42")          ## Charcoal, for text on light panels
const PANEL := Color(1.0, 1.0, 1.0, 0.82)
const HEALTH_FULL := Color("#FF6B81")
const HEALTH_LOW := Color("#D62246")
const PAINT := Color("#00A896")

# --- Nodes, all created in _ready() ----------------------------------------
var _health_fill: ColorRect
var _health_label: Label
var _paint_fill: ColorRect
var _paint_label: Label
var _pair_title: Label
var _pair_ability: Label
var _pair_weakness: Label
var _wave_label: Label
var _enemies_label: Label
var _prompt: Label
var _banner: Label
var _banner_sub: Label
var _flash: ColorRect
var _crosshair: Control
var _end_panel: Control
var _end_title: Label
var _end_body: Label

## The player node. Untyped for the same parse-time reason explained in enemy.gd
## - this script calls get_max_ammo(), which GDScript would reject at parse time
## on a variable typed as an engine class.
var _player = null

## Full width of the two stat bars, in pixels. Stored so the fill can be sized
## as a fraction of it.
const BAR_WIDTH := 300.0
const BAR_HEIGHT := 20.0


func _ready() -> void:
	# layer decides draw order between CanvasLayers. Anything above 0 sits on
	# top of the default layer.
	layer = 10

	_build_vignette()
	_build_crosshair()
	_build_stat_bars()
	_build_pair_panel()
	_build_wave_readout()
	_build_prompt()
	_build_banner()
	_build_flash()
	_build_end_panel()


# ============================================================================
# CONSTRUCTION
# ============================================================================

## Small helper so the builders below read as layout rather than boilerplate.
func _make_label(text: String, size: int, text_color: Color,
		alignment: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	# add_theme_*_override changes this one node's styling without needing a
	# whole theme resource set up.
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", text_color)
	# An outline keeps white text legible against the arena's white floor, which
	# is otherwise a real problem with this palette.
	label.add_theme_color_override("font_outline_color", Color(0.17, 0.18, 0.26, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = alignment
	# Labels ignore the mouse, so they can never swallow a click meant for the
	# game underneath.
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_rect(rect_color: Color, rect_size: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = rect_color
	rect.size = rect_size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## The edge vignette the GDD's camera direction asks for by name: the screen
## corners darken slightly, which pulls your eye toward the middle where the
## crosshair and the action are.
##
## This is a SHADER - a tiny program that runs once per pixel on the graphics
## card. Doing it any other way would mean a hand-painted gradient image, and a
## shader is both sharper at every resolution and about eight lines long.
func _build_vignette() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec3 tint = vec3(0.17, 0.18, 0.26);
uniform float strength = 0.5;

void fragment() {
	// SCREEN_UV runs 0..1 across the screen. Shifting it by 0.5 puts the
	// origin in the middle, so `length()` is then the distance from centre.
	vec2 offset = SCREEN_UV - vec2(0.5);
	float dist = length(offset) * 1.414;
	// smoothstep ramps gently from 0 to 1 between the two thresholds, so the
	// darkening fades in instead of appearing as a hard ring.
	float amount = smoothstep(0.42, 1.0, dist) * strength;
	COLOR = vec4(tint, amount);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader

	var rect := ColorRect.new()
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# PRESET_FULL_RECT stretches the node to cover the whole screen and keeps it
	# covering the whole screen when the window is resized.
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)


## A four-armed crosshair with a gap in the middle. The gap matters: a solid dot
## hides the thing you are shooting at, which is a real problem against the
## small fast Bounders.
func _build_crosshair() -> void:
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	var arm_colour := Color(1.0, 1.0, 1.0, 0.92)
	var thickness := 2.0
	var length := 9.0
	var gap := 5.0

	# Each arm is positioned relative to the centre point.
	var arms := [
		{"size": Vector2(thickness, length), "pos": Vector2(-thickness * 0.5, -gap - length)},
		{"size": Vector2(thickness, length), "pos": Vector2(-thickness * 0.5, gap)},
		{"size": Vector2(length, thickness), "pos": Vector2(-gap - length, -thickness * 0.5)},
		{"size": Vector2(length, thickness), "pos": Vector2(gap, -thickness * 0.5)},
	]

	for arm in arms:
		var rect := _make_rect(arm_colour, arm["size"])
		rect.position = arm["pos"]
		_crosshair.add_child(rect)

	# A charcoal dot behind the arms, so the crosshair stays visible against a
	# bright white wall as well as against a dark pillar.
	var centre_dot := _make_rect(Color(0.17, 0.18, 0.26, 0.85), Vector2(3, 3))
	centre_dot.position = Vector2(-1.5, -1.5)
	_crosshair.add_child(centre_dot)


## Health and paint, stacked in the bottom-left corner.
func _build_stat_bars() -> void:
	var root := Control.new()
	# PRESET_BOTTOM_LEFT anchors to that corner, so the bars stay put when the
	# window is resized rather than drifting into the middle of the screen.
	root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	root.position = Vector2(40, -110)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Health ---
	_health_label = _make_label("HEALTH", 13, Color.WHITE)
	_health_label.position = Vector2(0, -20)
	root.add_child(_health_label)

	var health_bg := _make_rect(Color(0.17, 0.18, 0.26, 0.55), Vector2(BAR_WIDTH, BAR_HEIGHT))
	health_bg.position = Vector2(0, 0)
	root.add_child(health_bg)

	_health_fill = _make_rect(HEALTH_FULL, Vector2(BAR_WIDTH, BAR_HEIGHT))
	_health_fill.position = Vector2(0, 0)
	root.add_child(_health_fill)

	# --- Paint ---
	_paint_label = _make_label("PAINT", 13, Color.WHITE)
	_paint_label.position = Vector2(0, 28)
	root.add_child(_paint_label)

	var paint_bg := _make_rect(Color(0.17, 0.18, 0.26, 0.55), Vector2(BAR_WIDTH, BAR_HEIGHT * 0.7))
	paint_bg.position = Vector2(0, 48)
	root.add_child(paint_bg)

	_paint_fill = _make_rect(PAINT, Vector2(BAR_WIDTH, BAR_HEIGHT * 0.7))
	_paint_fill.position = Vector2(0, 48)
	root.add_child(_paint_fill)


## The panel showing what you have currently inherited. This is the single most
## important readout in the game - the whole mechanic is meaningless if you
## cannot remember what you are carrying - so it is always on screen rather than
## hidden behind a key press.
func _build_pair_panel() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2(40, 34)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_pair_title = _make_label("Apprentice Brush", 24, Color.WHITE)
	_pair_title.position = Vector2(0, 0)
	root.add_child(_pair_title)

	# Green for what you gained, red for what it cost. Colour-coding these two
	# lines means you can read your loadout at a glance mid-fight instead of
	# having to actually read the words.
	_pair_ability = _make_label("", 15, Color("#8CFF9E"))
	_pair_ability.position = Vector2(0, 32)
	root.add_child(_pair_ability)

	_pair_weakness = _make_label("", 15, Color("#FF8FA0"))
	_pair_weakness.position = Vector2(0, 54)
	root.add_child(_pair_weakness)


func _build_wave_readout() -> void:
	_wave_label = _make_label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_wave_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wave_label.position = Vector2(-150, 26)
	_wave_label.size = Vector2(300, 30)
	add_child(_wave_label)

	_enemies_label = _make_label("", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_enemies_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_enemies_label.position = Vector2(-150, 56)
	_enemies_label.size = Vector2(300, 24)
	add_child(_enemies_label)


## The "press E to inherit" offer. Sits below the crosshair rather than on it,
## so it never covers the enemy you are shooting while you decide.
func _build_prompt() -> void:
	_prompt = _make_label("", 19, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.position = Vector2(-380, 96)
	_prompt.size = Vector2(760, 90)
	# Let the text wrap rather than run off the sides on a narrow window.
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.visible = false
	add_child(_prompt)


## Big centred text for wave announcements. Fades itself out.
func _build_banner() -> void:
	_banner = _make_label("", 52, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.position = Vector2(-400, -140)
	_banner.size = Vector2(800, 70)
	_banner.modulate.a = 0.0
	add_child(_banner)

	_banner_sub = _make_label("", 21, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_sub.set_anchors_preset(Control.PRESET_CENTER)
	_banner_sub.position = Vector2(-400, -78)
	_banner_sub.size = Vector2(800, 34)
	_banner_sub.modulate.a = 0.0
	add_child(_banner_sub)


## A full-screen red wash, flashed briefly when you are hit. Kept at zero alpha
## the rest of the time.
func _build_flash() -> void:
	_flash = _make_rect(Color(0.84, 0.13, 0.27, 0.0), Vector2.ZERO)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)


func _build_end_panel() -> void:
	_end_panel = Control.new()
	_end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_panel.visible = false
	add_child(_end_panel)

	var dim := _make_rect(Color(0.17, 0.18, 0.26, 0.72), Vector2.ZERO)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_panel.add_child(dim)

	_end_title = _make_label("", 62, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_end_title.set_anchors_preset(Control.PRESET_CENTER)
	_end_title.position = Vector2(-400, -110)
	_end_title.size = Vector2(800, 80)
	_end_panel.add_child(_end_title)

	_end_body = _make_label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_end_body.set_anchors_preset(Control.PRESET_CENTER)
	_end_body.position = Vector2(-400, -20)
	_end_body.size = Vector2(800, 160)
	_end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_panel.add_child(_end_body)


# ============================================================================
# WIRING
# ============================================================================

## Connects to the player's signals. Called once by game.gd at startup.
##
## Connecting rather than checking the player's values every frame means the HUD
## only does work when something actually changed - and, more importantly, it
## means the player script has no idea the HUD exists.
func bind_player(player) -> void:
	_player = player
	player.stats_changed.connect(_on_stats_changed)
	player.hurt.connect(_on_hurt)
	player.pair_inherited.connect(_on_pair_inherited)
	_on_stats_changed()
	_show_pair(player.pair)


func _on_stats_changed() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var health: float = _player.health
	var max_health: float = _player.max_health
	var health_fraction: float = clampf(health / max_health, 0.0, 1.0)

	_health_fill.size.x = BAR_WIDTH * health_fraction
	# Shift the bar's colour toward a deeper red as it empties, so low health is
	# something you notice in peripheral vision without reading the number.
	_health_fill.color = HEALTH_LOW.lerp(HEALTH_FULL, health_fraction)
	_health_label.text = "HEALTH   %d" % int(ceil(health))

	var ammo: float = _player.ammo
	var max_ammo: float = _player.get_max_ammo()
	var ammo_fraction: float = clampf(ammo / max_ammo, 0.0, 1.0)

	_paint_fill.size.x = BAR_WIDTH * ammo_fraction
	# Fade the paint bar when the reservoir is nearly dry, which is the cue to
	# break off and let it refill.
	_paint_fill.color = PAINT if ammo_fraction > 0.2 else Color("#FFB7C5")
	_paint_label.text = "PAINT   %d / %d" % [int(ammo), int(max_ammo)]


func _on_hurt() -> void:
	# Snap to visible, then fade out. Re-creating the tween each time means
	# rapid hits keep the screen lit rather than each one cancelling the last.
	_flash.color.a = 0.32
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.35)


func _on_pair_inherited(pair: Dictionary) -> void:
	_show_pair(pair)
	announce(str(pair["name"]).to_upper(),
		"%s  ·  %s" % [pair["ability_name"], pair["weakness_name"]])


func _show_pair(pair: Dictionary) -> void:
	if pair.is_empty():
		return
	_pair_title.text = str(pair["name"])
	_pair_title.add_theme_color_override("font_color", pair["color"])
	_pair_ability.text = "▲  %s — %s" % [pair["ability_name"], pair["ability_desc"]]
	_pair_weakness.text = "▼  %s — %s" % [pair["weakness_name"], pair["weakness_desc"]]


# ============================================================================
# CALLED BY game.gd
# ============================================================================

func set_wave(wave: int, total: int) -> void:
	_wave_label.text = "WAVE %d / %d" % [wave, total]


func set_enemies_left(count: int) -> void:
	if count > 0:
		_enemies_label.text = "%d remaining" % count
	else:
		_enemies_label.text = ""


## Shows or hides the inherit offer. Passing an empty dictionary hides it.
func set_offer(pair: Dictionary, already_held: bool) -> void:
	if pair.is_empty():
		_prompt.visible = false
		return

	_prompt.visible = true

	if already_held:
		_prompt.text = "You already carry the %s." % pair["name"]
		_prompt.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.65))
		return

	_prompt.add_theme_color_override("font_color", Color.WHITE)
	# Spelling out BOTH halves is the point. The player has to be able to make
	# an informed trade, and the weakness is the half they would otherwise
	# forget to think about.
	_prompt.text = "[E]  Inherit the %s\n▲ %s        ▼ %s" % [
		pair["name"], pair["ability_desc"], pair["weakness_desc"]]


## Big centred text that fades in and out on its own.
func announce(title: String, subtitle: String = "") -> void:
	_banner.text = title
	_banner_sub.text = subtitle

	# kill() any animation still running from a previous announcement, so two
	# announcements close together do not fight over the same alpha value and
	# leave the text stuck half-faded.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_banner, "modulate:a", 1.0, 0.18)
	tween.tween_property(_banner_sub, "modulate:a", 1.0, 0.18)
	tween.chain().tween_interval(1.5)
	tween.chain().set_parallel(true)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.6)
	tween.tween_property(_banner_sub, "modulate:a", 0.0, 0.6)


func show_ending(title: String, body: String, title_color: Color) -> void:
	_end_panel.visible = true
	_end_title.text = title
	_end_title.add_theme_color_override("font_color", title_color)
	_end_body.text = body
	_prompt.visible = false
	_crosshair.visible = false
