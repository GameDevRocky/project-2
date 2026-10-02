extends RefCounted

## ============================================================================
## RUNNER DRESSER - turns a customization dictionary into a dressed runner.
## ============================================================================
##
## One place that knows how to dress the Canvas Runner (models/generated/
## canvas_runner.glb) from the customization data the menu writes:
##
##   skin        "default" = the plain Canvas Runner, or an outfit id
##               (skeleton, astronaut ... and the bot-only ones)
##   body_color  suit colour of the plain runner (CharacterCustomizationData)
##   hat / mask  index into HATS / MASKS (0 = none)
##   back_bling  index into BACK_BLING (0 = the standard Chromatic Tank)
##   gun_skin    index into GUN_SKINS (restyles the held Paint Blaster)
##
## Used by the menu's character preview AND by TDM bots, so what you see in
## the customize screen is exactly what a runner looks like in a match. It
## only builds visuals: no collision, no gameplay values.
##
## Team marks (armbands, chest chevron, visor strip, pack paint) are always
## drawn in `team` - in a match that is RED or BLUE, so teams stay readable
## whatever anyone is wearing.

const Data = preload("res://scripts/character_customization_data.gd")
const PaintKit = preload("res://scripts/visual/paint_kit.gd")
const GunSkins = preload("res://scripts/visual/gun_skins.gd")
const SuitShader = preload("res://scripts/visual/suit_pattern.gdshader")

const DEFAULT_HELMET := Color("#F2EEE6")
const OUTFIT_MODELS := ["cosmetic_outfits_a", "cosmetic_outfits_b"]

## Suit materials, shared between every runner wearing the same suit.
static var _suits: Dictionary = {}


## Builds a dressed runner. Returns null if the runner model is missing.
## `with_gun` false leaves the hands empty, for an online player whose gun is
## carried separately so it can follow their aim (scripts/visual/remote_look.gd).
static func build(customization: Dictionary, team: Color, fogless := true, with_gun := true) -> Node3D:
	var runner := PaintKit.instance("canvas_runner")
	if runner == null:
		return null
	dress(runner, customization, team, fogless, with_gun)
	return runner


## Dresses a runner instance that is NOT yet wearing anything.
static func dress(runner: Node3D, customization: Dictionary, team: Color, fogless := true,
		with_gun := true) -> void:
	var skin := Data.skin_by_id(str(customization.get("skin", "default")))
	var is_default := str(skin.get("id", "default")) == "default"

	# --- 1. The runner's own suit, helmet and team marks ----------------------
	var helmet_color: Color = DEFAULT_HELMET if is_default else Color(str(skin.get("helmet", "#F2EEE6")))
	var helmet := _plain("helmet", helmet_color, 0.45, 0.0, fogless)
	var suit_body := _suit(customization, skin, is_default, 0.0, fogless)
	var suit_leg := _suit(customization, skin, is_default, 0.78, fogless)
	PaintKit.paint(runner, team, team, fogless, {"PK_Canvas": suit_body, "PK_Body": helmet})
	for leg_name in ["Leg_L", "Leg_R"]:
		var leg := PaintKit.part(runner, leg_name)
		if leg != null:
			PaintKit.paint(leg, team, team, fogless, {"PK_Canvas": suit_leg, "PK_Body": helmet})

	# --- 2. A full outfit, if one is chosen -----------------------------------
	if not is_default:
		var outfit_id := "Outfit_" + str(skin.id).to_upper()
		var outfit: Node3D = null
		for model in OUTFIT_MODELS:
			outfit = PaintKit.variant(model, outfit_id)
			if outfit != null:
				break
		if outfit != null:
			_wear_outfit(runner, outfit, team, fogless)
		if bool(skin.get("hides_head", false)) and outfit != null:
			var head := PaintKit.part(runner, "Head")
			if head != null:
				head.visible = false

	# --- 3. Hat and mask (plain runner only) ----------------------------------
	if bool(skin.get("allows_hat", false)):
		_attach(runner, "Socket_Head", "cosmetic_hats",
			Data.cosmetic_node("HATS", int(customization.get("hat", 0))), team, fogless)
	if bool(skin.get("allows_mask", false)):
		_attach(runner, "Socket_Face", "cosmetic_masks",
			Data.cosmetic_node("MASKS", int(customization.get("mask", 0))), team, fogless)

	# --- 4. Back bling: everyone carries their paint ---------------------------
	var back_index := int(customization.get("back_bling", 0))
	var back_name := Data.cosmetic_node("BACK BLING", back_index)
	var pack: Node3D = PaintKit.variant("cosmetic_backbling", back_name) if not back_name.is_empty() else null
	if pack == null:
		pack = PaintKit.instance("chromatic_reservoir")
	_mount(runner, "Socket_Back", pack, team, fogless)

	# --- 5. The Paint Blaster in the right hand, in the chosen gun skin --------
	if not with_gun:
		return
	var gun := PaintKit.instance("paint_blaster_prop")
	if gun != null:
		_mount(runner, "Socket_Hand_R", gun, team, fogless)
		GunSkins.apply(gun, int(customization.get("gun_skin", 0)), fogless)


## Lays an outfit over the runner. Parts under the outfit's OnLeg_L / OnLeg_R
## empties ride on the runner's real legs (both pivot at the same hip point);
## everything else is placed in the runner's own space.
static func _wear_outfit(runner: Node3D, outfit: Node3D, team: Color, fogless: bool) -> void:
	for child in outfit.get_children():
		var target: Node = runner
		var parts: Array = [child]
		# Godot makes node names unique across one imported file, so the leg
		# holders may arrive as OnLeg_L2, OnLeg_R3... - match on the start.
		var child_name := str(child.name)
		if child_name.begins_with("OnLeg_L") or child_name.begins_with("OnLeg_R"):
			target = PaintKit.part(runner, "Leg_L" if child_name.begins_with("OnLeg_L") else "Leg_R")
			parts = child.get_children()
			if target == null:
				continue
		for part in parts:
			var keep: Transform3D = (part as Node3D).transform
			part.get_parent().remove_child(part)
			target.add_child(part)
			(part as Node3D).transform = keep
			PaintKit.paint(part, team, team, fogless)
	outfit.free()


## Puts one cosmetic part (hat or mask) on a socket. The part's origin was
## modelled exactly at the socket, so it is placed with no offset.
static func _attach(runner: Node3D, socket: String, model: String, part_name: String,
		team: Color, fogless: bool) -> void:
	if part_name.is_empty():
		return
	_mount(runner, socket, PaintKit.variant(model, part_name), team, fogless)


static func _mount(runner: Node3D, socket: String, item: Node3D, team: Color, fogless: bool) -> void:
	var anchor := PaintKit.part(runner, socket)
	if anchor == null or item == null:
		if item != null:
			item.free()
		return
	anchor.add_child(item)
	item.transform = Transform3D.IDENTITY
	# Paint in the pack / on the gun shows the team colour.
	PaintKit.paint(item, team, team, fogless)
	# Small parts on a moving character: their shadows are too small to see but
	# would be drawn again for every shadow pass.
	PaintKit.set_shadows(item, false)


## The suit material: a plain colour, gold metal, or a pattern (rainbow, camo).
static func _suit(customization: Dictionary, skin: Dictionary, is_default: bool,
		height_offset: float, fogless: bool) -> Material:
	if not is_default:
		return _plain("suit", Color(str(skin.get("suit", "#E9E1D2"))), 0.9, 0.0, fogless)
	var index := posmod(int(customization.get("body_color", 4)), Data.BODY_COLORS.size())
	var choice: Dictionary = Data.BODY_COLORS[index]
	var color := Color(str(choice.color))
	if bool(choice.get("rainbow", false)) or bool(choice.get("camo", false)):
		var key := "pattern|%d|%s" % [index, str(height_offset)]
		if not _suits.has(key):
			var shader := ShaderMaterial.new()
			shader.shader = SuitShader
			shader.set_shader_parameter("mode", 1 if bool(choice.get("rainbow", false)) else 2)
			shader.set_shader_parameter("base_color", color)
			shader.set_shader_parameter("height_offset", height_offset)
			_suits[key] = shader
		return _suits[key]
	if bool(choice.get("metallic", false)):
		return _plain("suit", color, 0.3, 0.75, fogless)
	return _plain("suit", color, 0.9, 0.0, fogless)


static func _plain(kind: String, color: Color, roughness: float, metallic: float,
		fogless: bool) -> StandardMaterial3D:
	var key := "%s|%s|%.2f|%.2f|%s" % [kind, color.to_html(), roughness, metallic, str(fogless)]
	if not _suits.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		m.metallic = metallic
		m.disable_fog = fogless
		if fogless:
			m.rim_enabled = true
			m.rim = 0.35
			m.rim_tint = 0.35
		_suits[key] = m
	return _suits[key]
