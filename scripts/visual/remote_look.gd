extends RefCounted

## ============================================================================
## REMOTE LOOK - dresses another online player as a Canvas Runner.
## ============================================================================
##
## scripts/net/remote_player.gd (Rocklyn's networking code) builds a plain
## capsule with a box rifle under an `AimPivot` that follows the owner's
## synced aim. This file only changes how that player LOOKS, from outside:
##
##   - the capsule and head are hidden and a Canvas Runner, dressed in that
##     player's own customization (from their lobby record), takes their place;
##   - the box rifle is hidden and the Paint Blaster, in their gun skin, is
##     mounted on the same AimPivot - moved to the runner's right hand - so it
##     still turns with their camera pitch, as remote-player-weapon-sync asks.
##
## Nothing here touches collision, health or networking. If the runner model
## is missing, the capsule stays as it was.

const CombatantVisual = preload("res://scripts/visual/combatant_visual.gd")
const PaintKit = preload("res://scripts/visual/paint_kit.gd")
const GunSkins = preload("res://scripts/visual/gun_skins.gd")
const Weapons = preload("res://scripts/weapons.gd")


## Call AFTER the remote player is in the scene tree (it needs real positions
## to find the runner's hand).
static func dress(actor: Node3D, record: Dictionary, team: Color) -> void:
	var custom_value = record.get("customization", {})
	var customization: Dictionary = custom_value if custom_value is Dictionary else {}
	var visual := Node3D.new()
	visual.set_script(CombatantVisual)
	if not visual.setup_remote(actor, customization, team):
		visual.free()
		return
	actor.add_child(visual)
	# The runner model faces +Z; a player looks down -Z. Turn it round.
	visual.rotation.y = PI
	for child in actor.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false

	var pivot := actor.get_node_or_null("AimPivot") as Node3D
	var socket := PaintKit.part(visual.model, "Socket_Hand_R")
	if pivot == null or socket == null:
		return
	# Move the aim pivot into the runner's right hand, so at level aim the gun
	# sits exactly where the runner's arms are posed to hold it.
	pivot.position = actor.to_local(socket.global_position)
	var old_weapon := pivot.get_node_or_null("Weapon") as Node3D
	if old_weapon != null:
		old_weapon.visible = false
	# Remembered so the gun can be rebuilt when they switch guns, and so the
	# spectator camera knows what to show in first person.
	actor.set_meta("gun_skin", int(customization.get("gun_skin", 0)))
	actor.set_meta("team_color", team)
	actor.set_meta("weapon", -1)
	set_weapon(actor, Weapons.BRUSH_RIFLE)
	if pivot.get_node_or_null("Blaster") == null and old_weapon != null:
		old_weapon.visible = true


## Puts gun `index` (scripts/weapons.gd) in this player's hands. Called when
## one of their shots arrives saying it came from a different gun.
static func set_weapon(actor: Node3D, index: int) -> void:
	if int(actor.get_meta("weapon", -1)) == index:
		return
	var pivot := actor.get_node_or_null("AimPivot") as Node3D
	if pivot == null or actor.get_node_or_null("Visual") == null:
		return
	var weapon := Weapons.get_weapon(index)
	# Other players' guns use the one-piece "_prop" copy of each model.
	var gun := PaintKit.instance(str(weapon.model) + "_prop")
	if gun == null:
		gun = PaintKit.instance("paint_blaster_prop")
	if gun == null:
		return
	var old := pivot.get_node_or_null("Blaster")
	if old != null:
		pivot.remove_child(old)
		old.queue_free()
	actor.set_meta("weapon", index)
	gun.name = "Blaster"
	pivot.add_child(gun)
	var team: Color = actor.get_meta("team_color", Color.WHITE)
	PaintKit.paint(gun, team, team, true)
	PaintKit.set_shadows(gun, false)
	GunSkins.apply(gun, int(actor.get_meta("gun_skin", 0)), true)
	# Hidden while someone spectates this player in first person.
	gun.visible = not bool(actor.get_meta("first_person_spectated", false))


## A small recoil when this player fires.
static func on_fire(actor: Node) -> void:
	var visual = actor.get_node_or_null("Visual")
	if visual != null and visual.has_method("on_fire"):
		visual.on_fire()
