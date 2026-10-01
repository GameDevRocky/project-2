extends CanvasLayer

## ============================================================================
## HUD - everything drawn on top of the 3D world in SURVIVAL. This is the UX
## system for that mode.
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
## SHARED PIECES
## The crosshair, health meter, paint tank, pair card and screen effects are
## shared widgets in scripts/ui/widgets/, also used by the TDM HUD, so both
## modes look like one game. Only the Survival-specific parts (wave readout,
## inherit offer, banner, end panel) are built here. The functions game.gd
## calls - bind_player, set_wave, set_enemies_left, set_offer, announce,
## show_ending - are unchanged.
##
## ANCHORS AND CONTAINERS
## Nothing below is placed at a hand-typed screen position. Each block is
## pinned to an edge or the centre with anchors, and its contents are lined up
## by containers, so the layout holds at any window size or shape.

const Traits = preload("res://scripts/traits.gd")
const UITheme = preload("res://scripts/ui/ui_theme.gd")
const CrosshairScript = preload("res://scripts/ui/widgets/crosshair.gd")
const HealthMeterScript = preload("res://scripts/ui/widgets/health_meter.gd")
const PaintTankScript = preload("res://scripts/ui/widgets/paint_tank_meter.gd")
const InheritanceCardScript = preload("res://scripts/ui/widgets/inheritance_card.gd")
const ScreenFxScript = preload("res://scripts/ui/widgets/screen_fx.gd")

const SAFE_MARGIN := 24.0

# --- Nodes, all created in _ready() ----------------------------------------
var _root: Control
var _fx
var _crosshair
var _health
var _paint
var _pair_card
var _wave_label: Label
var _enemies_label: Label
var _prompt: PanelContainer
var _prompt_title: Label
var _prompt_benefit: Label
var _prompt_cost: Label
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
var _end_panel: Control
var _end_title: Label
var _end_body: Label

## The player node. Untyped for the same parse-time reason explained in enemy.gd
## - this script calls get_max_ammo(), which GDScript would reject at parse time
## on a variable typed as an engine class.
var _player = null
var _last_ammo: float = -1.0


func _ready() -> void:
	# layer decides draw order between CanvasLayers. Anything above 0 sits on
	# top of the default layer.
	layer = 10

	_root = Control.new()
	_root.theme = UITheme.build()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_fx = ScreenFxScript.new()
	_root.add_child(_fx)
	_crosshair = CrosshairScript.new()
	_root.add_child(_crosshair)
	_build_wave_readout()
	_build_bottom_left()
	_build_bottom_right()
	_build_prompt()
	_build_banner()
	_build_end_panel()


# ============================================================================
# CONSTRUCTION
# ============================================================================

## Wave number and enemies left, in a pill at the top-centre.
func _build_wave_readout() -> void:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.09, 0.8),
		Color(UITheme.LINE, 0.9), 1, 10, 22.0, 6.0))
	# Pinned to the top-centre; GROW_DIRECTION_BOTH keeps it centred as the
	# text inside changes width.
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.offset_top = 14.0
	_root.add_child(pill)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	pill.add_child(column)
	_wave_label = Label.new()
	_wave_label.theme_type_variation = &"HudNumber"
	_wave_label.add_theme_font_size_override("font_size", 24)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.custom_minimum_size = Vector2(170, 0)
	column.add_child(_wave_label)
	_enemies_label = Label.new()
	_enemies_label.theme_type_variation = &"HudCaption"
	_enemies_label.add_theme_font_size_override("font_size", 13)
	_enemies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_enemies_label)


## The pair you are carrying, stacked above health, in the bottom-left corner.
## The pair card is the single most important readout in the game - the whole
## mechanic is meaningless if you cannot remember what you are carrying - so it
## is always on screen rather than hidden behind a key press.
func _build_bottom_left() -> void:
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 8)
	stack.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	# Grow UP from the corner as the card gets taller.
	stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stack.offset_left = SAFE_MARGIN
	stack.offset_bottom = -SAFE_MARGIN
	_root.add_child(stack)
	_pair_card = InheritanceCardScript.new()
	_pair_card.apprentice_hint = "Defeat an enemy, then press E on its paint core."
	stack.add_child(_pair_card)
	_health = HealthMeterScript.new()
	stack.add_child(_health)


func _build_bottom_right() -> void:
	_paint = PaintTankScript.new()
	_paint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_paint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_paint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_paint.offset_right = -SAFE_MARGIN
	_paint.offset_bottom = -SAFE_MARGIN
	_root.add_child(_paint)


## The "press E to inherit" offer. Sits below the crosshair rather than on it,
## so it never covers the enemy you are shooting while you decide.
func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.09, 0.82),
		Color(UITheme.LINE, 0.9), 1, 8, 18.0, 10.0))
	# Anchored to the screen centre, then pushed 80px down. It grows downward
	# and evenly to both sides as the text changes.
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 0.5
	_prompt.anchor_bottom = 0.5
	_prompt.offset_top = 80.0
	_prompt.offset_bottom = 80.0
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_END
	_prompt.visible = false
	_root.add_child(_prompt)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_prompt.add_child(column)
	_prompt_title = Label.new()
	_prompt_title.theme_type_variation = &"HudLabel"
	_prompt_title.add_theme_font_size_override("font_size", 19)
	_prompt_title.add_theme_font_override("font", UITheme.bold())
	_prompt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_prompt_title)
	# Spelling out BOTH halves is the point. The player has to be able to make
	# an informed trade, and the weakness is the half they would otherwise
	# forget to think about.
	var trade := HBoxContainer.new()
	trade.alignment = BoxContainer.ALIGNMENT_CENTER
	trade.add_theme_constant_override("separation", 28)
	column.add_child(trade)
	_prompt_benefit = Label.new()
	_prompt_benefit.theme_type_variation = &"HudLabel"
	_prompt_benefit.add_theme_color_override("font_color", UITheme.BENEFIT)
	trade.add_child(_prompt_benefit)
	_prompt_cost = Label.new()
	_prompt_cost.theme_type_variation = &"HudLabel"
	_prompt_cost.add_theme_color_override("font_color", UITheme.COST)
	trade.add_child(_prompt_cost)


## Big centred text for wave announcements. Fades itself out.
func _build_banner() -> void:
	_banner = VBoxContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.5
	_banner.anchor_bottom = 0.5
	_banner.offset_top = -170.0
	_banner.offset_bottom = -170.0
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_END
	_banner.modulate.a = 0.0
	_root.add_child(_banner)
	_banner_title = Label.new()
	_banner_title.theme_type_variation = &"HudNumber"
	_banner_title.add_theme_font_size_override("font_size", 52)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_title)
	_banner_sub = Label.new()
	_banner_sub.theme_type_variation = &"HudLabel"
	_banner_sub.add_theme_font_size_override("font_size", 21)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_sub)


func _build_end_panel() -> void:
	_end_panel = Control.new()
	_end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_panel.visible = false
	_root.add_child(_end_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.035, 0.06, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_panel.add_child(dim)

	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_panel.add_child(centre)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(640, 0)
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	_end_title = Label.new()
	_end_title.theme_type_variation = &"TitleLabel"
	_end_title.add_theme_font_size_override("font_size", 56)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_end_title)
	_end_body = Label.new()
	_end_body.theme_type_variation = &"BodyLabel"
	_end_body.add_theme_font_size_override("font_size", 20)
	_end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Wrap rather than run off the panel on a long pair name.
	_end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_end_body)


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
	if player.has_signal("hit_confirmed"):
		player.hit_confirmed.connect(_crosshair.show_hit)
	_on_stats_changed()
	_show_pair(player.pair)


func _on_stats_changed() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var ammo: float = _player.ammo
	_health.set_values(float(_player.health), float(_player.max_health))
	_fx.set_health_fraction(float(_player.health) / maxf(float(_player.max_health), 1.0))
	_paint.set_values(ammo, float(_player.get_max_ammo()))
	# A shot costs exactly one paint, so a drop of about one means "just fired".
	if _last_ammo >= 0.0 and ammo <= _last_ammo - 0.99:
		_crosshair.pulse()
	_last_ammo = ammo


func _on_hurt() -> void:
	_fx.flash_hurt()


func _on_pair_inherited(pair: Dictionary) -> void:
	_show_pair(pair)
	_pair_card.flash()
	announce(str(pair["name"]).to_upper(),
		"%s  ·  %s" % [pair["ability_name"], pair["weakness_name"]])


func _show_pair(pair: Dictionary) -> void:
	if pair.is_empty() or _player == null:
		return
	_pair_card.set_pair(pair, str(_player.pair_id))


# ============================================================================
# CALLED BY game.gd
# ============================================================================

func set_wave(wave: int, total: int) -> void:
	_wave_label.text = "WAVE %d / %d" % [wave, total]


func set_enemies_left(count: int) -> void:
	if count > 0:
		_enemies_label.text = "%d REMAINING" % count
	else:
		_enemies_label.text = ""


## Shows or hides the inherit offer. Passing an empty dictionary hides it.
func set_offer(pair: Dictionary, already_held: bool) -> void:
	if pair.is_empty():
		_prompt.visible = false
		return

	_prompt.visible = true

	if already_held:
		_prompt_title.text = "You already carry the %s." % pair["name"]
		_prompt_title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.65))
		_prompt_benefit.visible = false
		_prompt_cost.visible = false
		return

	_prompt_title.add_theme_color_override("font_color", Color.WHITE)
	_prompt_title.text = "[E]  Inherit the %s" % pair["name"]
	_prompt_benefit.visible = true
	_prompt_cost.visible = true
	_prompt_benefit.text = "▲ %s" % pair["ability_desc"]
	_prompt_cost.text = "▼ %s" % pair["weakness_desc"]


## Big centred text that fades in and out on its own.
func announce(title: String, subtitle: String = "") -> void:
	_banner_title.text = title
	_banner_sub.text = subtitle

	# kill() any animation still running from a previous announcement, so two
	# announcements close together do not fight over the same alpha value and
	# leave the text stuck half-faded.
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.18)
	_banner_tween.tween_interval(1.5)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)


func show_ending(title: String, body: String, title_color: Color) -> void:
	_end_panel.visible = true
	_end_title.text = title
	_end_title.add_theme_color_override("font_color", title_color)
	_end_body.text = body
	_prompt.visible = false
	_crosshair.visible = false
