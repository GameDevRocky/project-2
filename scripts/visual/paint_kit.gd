extends RefCounted

## ============================================================================
## PAINT KIT (Godot side) - loads the generated models and paints them.
## ============================================================================
##
## The models in models/generated/ are built by the Blender scripts in
## tools/blender/. Their materials are named by ROLE (PK_Accent, PK_Team,
## PK_Fill...) instead of by colour. This file swaps those role materials for
## ones made here, in code, from the game's own colours - the pair colours in
## traits.gd and the team colours in ui_theme.gd. So a Sprayer is pink because
## traits.gd says the Sprayer pair is pink, not because a model file says so.
##
## Used like traits.gd (no class_name, so no global name to collide with):
##
##     const PaintKit = preload("res://scripts/visual/paint_kit.gd")
##     var model := PaintKit.instance("enemy_sprayer")
##
## Every function tolerates a missing model file by returning null, and every
## caller keeps its old primitive-shape code as a fallback, so the game still
## runs if the Blender scripts have never been run on a machine.

const MODEL_PATH := "res://models/generated/%s.glb"

## Gameplay-coloured roles. Everything else in a model keeps the look it was
## exported with.
const ACCENT_ROLES := ["PK_Accent", "PK_AccentGlow", "PK_Fill", "PK_Wet"]
const TEAM_ROLES := ["PK_Team", "PK_TeamGlow"]

static var _scenes: Dictionary = {}       # model name -> PackedScene (or null)
static var _meshes: Dictionary = {}       # "model/node" -> Mesh
static var _role_cache: Dictionary = {}   # role + colour key -> material
static var _fogless: Dictionary = {}      # source material id -> fog-free copy


## A fresh instance of a generated model, or null if the file does not exist.
static func instance(model: String) -> Node3D:
	var scene := _scene(model)
	return scene.instantiate() as Node3D if scene != null else null


static func _scene(model: String) -> PackedScene:
	if not _scenes.has(model):
		var path := MODEL_PATH % model
		_scenes[model] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _scenes[model]


## A copy of ONE named part (with its children) from a model that holds many
## variants, e.g. variant("cosmetic_hats", "Hat_CROWN"). The model file is
## loaded once (cached as a PackedScene); each call builds the model, keeps the
## wanted part and frees the rest, so nothing is left lying around outside the
## game. The meshes are shared, so this is cheap. Returns null if the model or
## the part is missing.
static func variant(model: String, part_name: String) -> Node3D:
	var scene := _scene(model)
	if scene == null:
		return null
	var whole := scene.instantiate()
	var found := whole.find_child(part_name, true, false) as Node3D
	if found != null:
		found.get_parent().remove_child(found)
		# Everything in the file "belongs" (owner) to its root; cut those links
		# before the root is freed so nothing points at a deleted node.
		found.owner = null
		for child in found.find_children("*", "", true, false):
			child.owner = null
	whole.free()
	return found


## Just the Mesh of one named part, cached. For things spawned by the dozen
## (paint globs, splats) this avoids building a whole scene per shot.
static func mesh(model: String, part: String) -> Mesh:
	var key := model + "/" + part
	if not _meshes.has(key):
		var found: Mesh = null
		var scene := _scene(model)
		if scene != null:
			var root := scene.instantiate()
			var node := root.find_child(part, true, false) as MeshInstance3D
			if node != null:
				found = node.mesh
			root.free()
		_meshes[key] = found
	return _meshes[key]


## Loads the models that are spawned mid-fight (paint globs and splats) up
## front. Loading a model file takes ~35 ms the first time; left until the
## first shot, that was a visible stutter a few seconds into every match. The
## arena calls this while the match is still being set up.
static func warm_up() -> void:
	mesh("paint_glob", "Glob")
	for i in 4:
		mesh("paint_splat", "Splat_%d" % i)


## Finds a named part anywhere inside a model.
static func part(root: Node, name: String) -> Node3D:
	return root.find_child(name, true, false) as Node3D


## One gameplay-coloured material. Shared by every object that asks for the
## same role + colour, so twenty pink Sprayers use one pink material.
static func role_material(role: String, color: Color, fogless := true) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [role, color.to_html(), str(fogless)]
	if _role_cache.has(key):
		return _role_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.disable_fog = fogless
	if fogless:
		_add_rim(mat)
	match role:
		"PK_AccentGlow", "PK_TeamGlow":
			mat.roughness = 0.3
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 1.6
		"PK_Fill":
			mat.roughness = 0.15
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 0.6
		"PK_Wet":
			# Wet paint: glossy, and a faint glow so it reads as live paint
			# rather than the room's matte dried paint.
			mat.roughness = 0.1
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 0.35
		_:
			# Accent and team paint glow a little in their own colour (the same
			# 0.55-0.6 the old enemy spheres used), so a combatant's colour reads
			# at range against the room even though most of its body is neutral.
			mat.roughness = 0.4
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 0.55
	_role_cache[key] = mat
	return mat


## Repaints a model: accent roles in `accent`, team roles in `team`. Any other
## material is kept, but swapped for a fog-free copy when `fogless` is on -
## combatants ignore the arena's distance haze so they stay crisp at range
## (the same rule the old enemy spheres followed).
static func paint(root: Node, accent: Color, team: Color = Color.WHITE, fogless := true,
		extra: Dictionary = {}) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(i)
			if source == null:
				continue
			var role := source.resource_name
			var replacement: Material = null
			if extra.has(role):
				replacement = extra[role]
			elif role in ACCENT_ROLES:
				replacement = role_material(role, accent, fogless)
			elif role in TEAM_ROLES:
				replacement = role_material(role, team, fogless)
			elif fogless:
				replacement = _fog_free(source)
			if replacement != null:
				mi.set_surface_override_material(i, replacement)


static func _fog_free(source: Material) -> Material:
	var id := source.get_instance_id()
	if not _fogless.has(id):
		var copy: Material = source
		if source is BaseMaterial3D:
			copy = source.duplicate() as Material
			(copy as BaseMaterial3D).disable_fog = true
			_add_rim(copy as BaseMaterial3D)
		_fogless[id] = copy
	return _fogless[id]


## Rim lighting: a thin brightening along a model's outline where the surface
## turns away from the camera. It separates a combatant from the wall or floor
## behind it without making the whole model brighter. Cheap, and supported by
## both renderers. Only combatants and pickups (the fog-free materials) get it.
static func _add_rim(mat: BaseMaterial3D) -> void:
	mat.rim_enabled = true
	mat.rim = 0.35
	mat.rim_tint = 0.35


static func set_shadows(root: Node, on: bool) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


## A brief white flash over a whole multi-part model. The overlay material is
## only attached while the flash runs, so an idle model is not drawn twice.
## `owner_node` runs the tween, so it dies with the model.
## The additive white overlay used by flash(). Its own function so the shader
## warm-up can draw it once during loading.
static func flash_overlay_material() -> StandardMaterial3D:
	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	overlay.disable_fog = true
	overlay.albedo_color = Color(1, 1, 1, 0)
	return overlay


static func flash(owner_node: Node, root: Node, strength := 0.6, seconds := 0.18) -> void:
	# has_meta first: get_meta() with a null default still logs an error when
	# the key does not exist yet.
	var overlay: StandardMaterial3D = null
	if owner_node.has_meta("paint_flash"):
		overlay = owner_node.get_meta("paint_flash")
	if overlay == null:
		overlay = flash_overlay_material()
		owner_node.set_meta("paint_flash", overlay)
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	for node in meshes:
		(node as GeometryInstance3D).material_overlay = overlay
	overlay.albedo_color.a = strength
	if owner_node.has_meta("paint_flash_tween"):
		var previous: Tween = owner_node.get_meta("paint_flash_tween")
		if previous != null and previous.is_valid():
			previous.kill()
	var tween := owner_node.create_tween()
	tween.tween_property(overlay, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(func():
		for node in meshes:
			if is_instance_valid(node):
				(node as GeometryInstance3D).material_overlay = null)
	owner_node.set_meta("paint_flash_tween", tween)
