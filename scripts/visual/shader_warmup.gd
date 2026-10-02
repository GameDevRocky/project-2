extends Node3D

## ============================================================================
## SHADER WARM-UP - draws every effect material once while the match loads.
## ============================================================================
##
## WHY
## The web build's renderer (Compatibility) compiles a material's shader the
## first time something using it is drawn, and the whole game waits while it
## does. Effects like the hit flash, paint puffs, splats and particle bursts
## first appear mid-fight, so that wait used to land a few seconds into every
## match as a ~140 ms freeze.
##
## WHAT IT DOES
## The player's camera adds this node once. For a fraction of a second it holds
## a tiny (1 cm) copy of each effect in front of the camera - too small to see
## - so each shader is compiled during loading instead. Then it deletes itself.
## It uses the SAME material functions as the real effects, so the warm-up can
## never drift out of date. Nothing here touches gameplay.

const Projectile = preload("res://scripts/projectile.gd")
const PaintKit = preload("res://scripts/visual/paint_kit.gd")
const PaintFx = preload("res://scripts/visual/paint_fx.gd")
const GunSkins = preload("res://scripts/visual/gun_skins.gd")
const Weapons = preload("res://scripts/weapons.gd")

var _age := 0.0


func _ready() -> void:
	position = Vector3(0.0, 0.0, -0.6)
	var sphere := SphereMesh.new()
	sphere.radial_segments = 6
	sphere.rings = 3
	_add(sphere, Projectile.glob_material(Color.WHITE), null)
	_add(sphere, Projectile.trail_material_for(Color.WHITE), null)
	_add(sphere, Projectile.burst_material(Color.WHITE), null)
	# Rocklyn's online effects: impact debris, rocket sparks, the power halo.
	_add(sphere, Projectile.debris_material(Color.WHITE), null)
	_add(sphere, Projectile.spark_material_for(), null)
	var halo := StandardMaterial3D.new()
	halo.emission_enabled = true
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add(sphere, halo, null)
	# A rocket's blast lights the area with a short-lived omni light; lit
	# materials need their "lit by an omni light" version compiled too.
	var flash := OmniLight3D.new()
	flash.omni_range = 0.5
	flash.light_energy = 0.01
	add_child(flash)
	var overlay := PaintKit.flash_overlay_material()
	overlay.albedo_color.a = 0.5
	_add(sphere, StandardMaterial3D.new(), overlay)
	var burst := PaintFx.make(Color.WHITE, 1, 0.0, 0.02, 0.3)
	add_child(burst)
	burst.emitting = true
	_warm_enemy_models()
	_warm_gun_models()
	_warm_scene.call_deferred()


## Picking up a power swaps the gun in your hands (and in other players'
## hands) for that power's model, mid-fight. Draw each one now.
func _warm_gun_models() -> void:
	for model_name in Weapons.all_models():
		for variant in [model_name, model_name + "_prop"]:
			var gun := PaintKit.instance(variant)
			if gun == null:
				continue
			PaintKit.paint(gun, Color.WHITE, Color.WHITE, variant.ends_with("_prop"))
			GunSkins.apply(gun, 0, variant.ends_with("_prop"))
			_add_copy(gun)


## Survival enemies (with their accessories) appear mid-wave, so draw one of
## each now.
func _warm_enemy_models() -> void:
	for kind in ["sprayer", "bounder", "blotter", "monolith", "ghost"]:
		var model := PaintKit.instance("enemy_" + kind)
		if model == null:
			continue
		PaintKit.paint(model, Color.WHITE)
		_add_copy(model)
	for accessory in ["Acc_BERET", "Sticker_STAR"]:
		var item := PaintKit.variant("enemy_accessories", accessory)
		if item != null:
			PaintKit.paint(item, Color.WHITE, Color.WHITE, true)
			_add_copy(item)


## Once everything in the match has been built (TDM bots spawn just after the
## player), draw one tiny copy of every distinct mesh + material combination in
## the match: the dressed runners' outfits, hats, packs and gun skins. Without
## this the web build froze for ~150 ms the first time the camera turned
## toward the other team.
func _warm_scene() -> void:
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	if player == null or player.get_parent() == null:
		return
	var seen := {}
	for node in player.get_parent().find_children("*", "MeshInstance3D", true, false):
		var source := node as MeshInstance3D
		if source.mesh == null or not source.is_visible_in_tree() or is_ancestor_of(source):
			continue
		var key := str(source.mesh.get_rid().get_id())
		var materials: Array = []
		for i in source.mesh.get_surface_count():
			var m := source.get_active_material(i)
			materials.append(m)
			key += "|" + (str(m.get_rid().get_id()) if m != null else "-")
		if source.material_overlay != null:
			key += "|o" + str(source.material_overlay.get_rid().get_id())
		if seen.has(key):
			continue
		seen[key] = true
		var copy := MeshInstance3D.new()
		copy.mesh = source.mesh
		for i in materials.size():
			copy.set_surface_override_material(i, materials[i])
		copy.material_overlay = source.material_overlay
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.scale = Vector3.ONE * 0.002
		add_child(copy)
	# Keep them for a few more frames so every shader is compiled and drawn.
	_age = 0.0


## Adds a tiny copy of a whole model in front of the camera.
func _add_copy(model: Node3D) -> void:
	model.scale = Vector3.ONE * 0.002
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(model)


func _add(mesh: Mesh, material: Material, overlay: Material) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.material_overlay = overlay
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.scale = Vector3.ONE * 0.01
	add_child(node)


func _process(delta: float) -> void:
	# A few frames is enough for every shader to be compiled and drawn.
	_age += delta
	if _age > 0.3:
		queue_free()
