extends Node3D

## ============================================================================
## COMBATANT VISUAL - the model an enemy or a TDM bot wears, and its motion.
## ============================================================================
##
## enemy.gd owns everything about how a combatant BEHAVES: its collision
## capsule, AI, attacks and health. This node is only what you SEE. It is added
## as a child of the enemy's CharacterBody3D, so it moves and turns with it,
## and it animates a few named parts of the generated model:
##
##   sprayer   legs stride, the nozzle crown spins when it fires
##   bounder   coil springs bounce, rollers spin, arms swing on a hit
##   blotter   paint sloshes, the mortar recoils and reloads its glob
##   monolith  the top slab slowly "breathes", the cannon recoils
##   ghost     floats and sways; eyes brighten while it regenerates
##   runner    (TDM bots) legs stride, body bobs, gun recoils
##
## Everything here READS the enemy (its velocity and health) or is told about
## an event (on_fire, on_melee). Nothing here can change what the enemy does.

const PaintKit = preload("res://scripts/visual/paint_kit.gd")
const RunnerDresser = preload("res://scripts/visual/runner_dresser.gd")
const Data = preload("res://scripts/character_customization_data.gd")

## Survival enemies' cosmetic extras (models/generated/enemy_accessories.glb).
## Small things on top or flat on the front: they never change an
## archetype's colour or outline, so a Sprayer always reads as a Sprayer.
const TOP_ACCESSORIES := ["Acc_BERET", "Acc_PARTY_HAT", "Acc_PROPELLER_CAP", "Acc_BOW", "Acc_TINY_CROWN", "Acc_SPROUT"]
const STICKERS := ["Sticker_STAR", "Sticker_SMILEY", "Sticker_BANDAGE", "Sticker_NUMBER7"]
## Which part of each enemy a hat sits on top of (it rides along with it), and
## how big a hat that part can wear.
const HAT_ANCHOR := {
	"sprayer": ["Body", 0.8], "bounder": ["Body", 0.8], "blotter": ["Lid", 0.95],
	"monolith": ["TopSlab", 1.6], "ghost": ["Body", 1.0],
}
## Stickers only where there is a flat-ish front to stick them to (on the
## others the front is a nozzle crown, a glass tank or a curved shell).
const STICKER_KINDS := ["monolith", "ghost"]

## The enemy this visual belongs to. Untyped for the project's usual reason:
## `health` is a variable this project added, which a CharacterBody3D-typed
## variable would reject at parse time.
var body = null
var kind := "sprayer"
var model: Node3D
var _parts: Dictionary = {}
var _rest: Dictionary = {}          # part name -> its starting Transform3D
var _time := 0.0
var _fire_kick := 0.0               # 1 at the moment of firing, eases to 0
var _melee_kick := 0.0
var _glob_reload := 1.0             # Blotter: 0 just fired, 1 glob fully back
var _last_health := -1.0
var _regen_glow := 0.0
var _eye_material: StandardMaterial3D


## Builds the model. Returns false (and builds nothing) if the model file is
## missing, so enemy.gd can fall back to its old sphere.
func setup(enemy, visual_kind: String, accent: Color, team: Color) -> bool:
	body = enemy
	kind = visual_kind
	name = "Visual"
	_time = randf() * 10.0   # so a pack does not animate in lock-step
	if kind == "runner":
		# The runner is dressed from the bot's own customization (outfit, suit,
		# hat, mask, back bling, gun skin) by the same code the menu preview
		# uses. Team marks are always drawn in the team colour.
		model = RunnerDresser.build(_runner_customization(enemy), team)
		if model == null:
			return false
		add_child(model)
	else:
		model = PaintKit.instance("enemy_" + kind)
		if model == null:
			return false
		add_child(model)
		PaintKit.paint(model, accent)
		_add_enemy_accessory()
	for part_name in ["Leg_L", "Leg_R", "NozzleFan", "Spring_L", "Spring_R", "Arm_L", "Arm_R",
			"Roller_L", "Roller_R", "Fill", "Mortar", "Glob", "TopSlab", "Cannon", "Shield",
			"Eyes", "Strip_0", "Strip_1", "Strip_2", "Strip_3", "Strip_4"]:
		var node := PaintKit.part(model, part_name)
		if node != null:
			_parts[part_name] = node
			_rest[part_name] = node.transform
	if kind == "ghost" and _parts.has("Eyes"):
		# The Ghost's eyes get their own material so one Ghost can glow brighter
		# while it heals without every other Ghost glowing with it.
		_eye_material = PaintKit.role_material("PK_AccentGlow", accent).duplicate() as StandardMaterial3D
		(_parts["Eyes"] as GeometryInstance3D).material_override = _eye_material
	return true


## The look of a TDM bot: from its lobby record when it has one, otherwise a
## random look seeded by its name, so the same bot keeps the same outfit every
## time it respawns.
func _runner_customization(enemy) -> Dictionary:
	var custom: Dictionary = enemy.get("customization") if enemy.get("customization") != null else {}
	if custom.has("skin"):
		return custom
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(enemy.name))
	return Data.random_bot_customization(rng, str(enemy.get("tdm_team")))


## Gives a Survival enemy a random small accessory: usually a little hat on top,
## sometimes a sticker on its front, sometimes nothing. Purely cosmetic.
func _add_enemy_accessory() -> void:
	if not HAT_ANCHOR.has(kind):
		return
	var roll := randf()
	if roll < 0.35:
		return
	var anchor_info: Array = HAT_ANCHOR[kind]
	var anchor := PaintKit.part(model, str(anchor_info[0]))
	if anchor == null:
		anchor = model
	var box := _local_aabb(anchor)
	if box.size == Vector3.ZERO:
		return
	if roll < 0.8 or not kind in STICKER_KINDS:
		var hat := PaintKit.variant("enemy_accessories", TOP_ACCESSORIES.pick_random())
		if hat == null:
			return
		anchor.add_child(hat)
		hat.transform = Transform3D(Basis(Vector3.UP, randf_range(-0.5, 0.5)) * float(anchor_info[1]),
			Vector3(box.get_center().x, box.end.y - 0.02, box.get_center().z))
		PaintKit.paint(hat, Color.WHITE, Color.WHITE, true)
	else:
		var sticker := PaintKit.variant("enemy_accessories", STICKERS.pick_random())
		if sticker == null:
			return
		anchor.add_child(sticker)
		# On the front (+Z, the way enemies face) at mid height, slightly tilted.
		sticker.transform = Transform3D(Basis(Vector3.FORWARD, randf_range(-0.4, 0.4)),
			Vector3(box.get_center().x, box.position.y + box.size.y * 0.55, box.end.z - 0.005))
		PaintKit.paint(sticker, Color.WHITE, Color.WHITE, true)


## The bounding box of a part's meshes, in that part's own space.
func _local_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var inverse := node.global_transform.affine_inverse() if node.is_inside_tree() else Transform3D.IDENTITY
	for mesh_node in [node] + node.find_children("*", "MeshInstance3D", true, false):
		if not mesh_node is MeshInstance3D:
			continue
		var mi := mesh_node as MeshInstance3D
		var to_local: Transform3D = inverse * mi.global_transform if node.is_inside_tree() else _relative(node, mi)
		var part_box: AABB = to_local * mi.get_aabb()
		box = part_box if first else box.merge(part_box)
		first = false
	return box


## Transform of `child` relative to `ancestor`, for nodes not yet in the tree.
func _relative(ancestor: Node3D, child: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = child
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


# ============================================================================
# EVENTS - called by enemy.gd
# ============================================================================

func on_fire() -> void:
	_fire_kick = 1.0
	_glob_reload = 0.0


func on_melee() -> void:
	_melee_kick = 1.0


func flash() -> void:
	PaintKit.flash(self, model)


# ============================================================================
# MOTION
# ============================================================================

func _process(delta: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	_time += delta
	_fire_kick = move_toward(_fire_kick, 0.0, delta * 4.0)
	_melee_kick = move_toward(_melee_kick, 0.0, delta * 2.5)
	_glob_reload = move_toward(_glob_reload, 1.0, delta * 0.8)
	var velocity: Vector3 = body.velocity
	var speed := Vector2(velocity.x, velocity.z).length()
	# 0 when standing, 1 at a brisk run. Drives stride size and bob.
	var move := clampf(speed / 5.0, 0.0, 1.0)
	match kind:
		"sprayer":
			_stride(12.0, 0.55 * move)
			model.position.y = absf(sin(_time * 12.0)) * 0.035 * move
			if _parts.has("NozzleFan"):
				(_parts["NozzleFan"] as Node3D).rotate_object_local(Vector3.FORWARD, delta * (0.8 + _fire_kick * 22.0))
		"bounder":
			# Squash both springs and lower the body by the same amount, so
			# the feet stay planted and the whole thing looks like it bounces.
			var bounce := absf(sin(_time * 8.0)) * (0.35 + 0.65 * move)
			var squash := 1.0 - 0.16 * bounce
			for spring in ["Spring_L", "Spring_R"]:
				if _parts.has(spring):
					(_parts[spring] as Node3D).scale.y = squash
			var spring_top: float = (_rest.get("Spring_L", Transform3D()) as Transform3D).origin.y
			model.position.y = -spring_top * (1.0 - squash)
			for arm in ["Arm_L", "Arm_R"]:
				if _parts.has(arm):
					var swing := -_melee_kick * 1.2 + sin(_time * 8.0 + (0.0 if arm == "Arm_L" else PI)) * 0.15 * move
					_pose(arm, Basis(Vector3.RIGHT, swing))
			for roller in ["Roller_L", "Roller_R"]:
				if _parts.has(roller):
					(_parts[roller] as Node3D).rotate_object_local(Vector3.RIGHT, delta * speed / 0.12)
		"blotter":
			if _parts.has("Fill"):
				_pose("Fill", Basis(Vector3.FORWARD, sin(_time * 3.1) * 0.05 * (0.3 + move)))
			if _parts.has("Mortar"):
				_pose("Mortar", Basis(Vector3.RIGHT, -_fire_kick * 0.35))
			if _parts.has("Glob"):
				var glob := _parts["Glob"] as Node3D
				glob.scale = Vector3.ONE * maxf(ease(_glob_reload, 2.4), 0.02)
			model.position.y = absf(sin(_time * 6.0)) * 0.02 * move
		"monolith":
			if _parts.has("TopSlab"):
				var slab := _parts["TopSlab"] as Node3D
				slab.position = (_rest["TopSlab"] as Transform3D).origin + Vector3(0.0, (sin(_time * 1.5) * 0.5 + 0.5) * 0.03, 0.0)
			if _parts.has("Cannon"):
				_pose("Cannon", Basis(Vector3.RIGHT, _fire_kick * 0.3))
			model.position.y = absf(sin(_time * 4.5)) * 0.03 * move
		"ghost":
			model.position.y = sin(_time * 1.8) * 0.07
			for i in 5:
				var strip := "Strip_%d" % i
				if _parts.has(strip):
					var trail := move * 0.35
					_pose(strip, Basis(Vector3.RIGHT, sin(_time * 2.3 + i) * 0.16 + trail)
						* Basis(Vector3.FORWARD, sin(_time * 1.7 + i * 1.3) * 0.09))
			_update_regen_glow(delta)
		"runner":
			_stride(10.0, 0.6 * move)
			model.position.y = absf(sin(_time * 10.0)) * 0.04 * move
			model.rotation.x = -_fire_kick * 0.04


func _stride(frequency: float, amplitude: float) -> void:
	var swing := sin(_time * frequency) * amplitude
	if _parts.has("Leg_L"):
		_pose("Leg_L", Basis(Vector3.RIGHT, swing))
	if _parts.has("Leg_R"):
		_pose("Leg_R", Basis(Vector3.RIGHT, -swing))


## Sets a part's rotation relative to the pose it was modelled in.
func _pose(part_name: String, rotation_basis: Basis) -> void:
	var node := _parts[part_name] as Node3D
	var rest := _rest[part_name] as Transform3D
	node.transform = Transform3D(rest.basis * rotation_basis, rest.origin)


## Ghost only: brighten the eyes while its health is going UP (Second Wind).
## This is how you see a Ghost healing without reading its health bar.
func _update_regen_glow(delta: float) -> void:
	var health := float(body.get("health"))
	if _last_health >= 0.0 and health > _last_health + 0.0001:
		_regen_glow = 1.0
	_last_health = health
	_regen_glow = move_toward(_regen_glow, 0.0, delta * 1.5)
	if _eye_material != null:
		_eye_material.emission_energy_multiplier = 1.6 + _regen_glow * (2.4 + sin(_time * 12.0) * 0.8)
