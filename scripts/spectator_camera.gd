extends Camera3D

## ============================================================================
## SPECTATOR CAMERA - what you see while you wait to respawn in TDM.
## ============================================================================
##
## Created by tdm_match_controller.gd when you are painted out, and freed when
## you respawn. While it exists it is the CURRENT camera: a Viewport draws
## through exactly one Camera3D at a time, and calling make_current() on this
## one takes over from your own player's camera (which tdm_respawn() takes
## back later).
##
## It follows one living teammate (a scripts/net/remote_player.gd node):
##
##   FIRST PERSON  from their eyes, turning exactly as they turn and look up
##                 and down, with their gun drawn on screen like your own.
##                 Their body is hidden meanwhile, or you would be looking at
##                 the inside of their helmet.
##   THIRD PERSON  from behind and above their shoulder. A ray from their head
##                 to the camera's spot stops the camera in front of any wall,
##                 so it never ends up inside the scenery.
##
## With no teammate to follow, it circles slowly above where you fell.
##
## It only WATCHES: it reads the teammate's position, body yaw and aim pitch
## and never changes anything about them except hiding their model in first
## person (and showing it again afterwards).

const PaintKit = preload("res://scripts/visual/paint_kit.gd")
const GunSkins = preload("res://scripts/visual/gun_skins.gd")
const Weapons = preload("res://scripts/weapons.gd")

const FIRST_PERSON := 0
const THIRD_PERSON := 1

## Eye height above a player's feet (the same as the player's own camera).
const EYE_HEIGHT := 1.6
## Third person: how far behind and above the teammate's head the camera sits.
const BACK_DISTANCE := 2.7
const HEAD_HEIGHT := 1.55
const SHOULDER_OFFSET := 0.55
## Where the first-person gun sits on screen (the player's view-model spot).
const VIEW_GUN_HOME := Vector3(0.32, -0.26, -0.6)

var mode := THIRD_PERSON
## Untyped: target_pitch / alive are this project's variables on the remote
## player, not CharacterBody3D's.
var target = null
## Where you were painted out: the fallback view circles above it.
var death_spot := Vector3.ZERO

var _view_gun: Node3D
var _view_gun_weapon := -2
var _kick := 0.0
var _orbit := 0.0
var _hidden_target = null


func _ready() -> void:
	fov = 105.0
	make_current()


## Starts (or switches to) following `who` in `view_mode`.
func follow(who, view_mode: int) -> void:
	_show_target_body()
	target = who
	mode = view_mode
	_snap()


func set_mode(view_mode: int) -> void:
	mode = view_mode
	_show_target_body()
	_snap()


## The teammate fired: kick the first-person gun.
func on_target_fired() -> void:
	_kick = 1.0


func _has_target() -> bool:
	return target != null and is_instance_valid(target) and bool(target.get("alive"))


## Jumps straight to the new view instead of gliding across the map to it.
func _snap() -> void:
	_update_view(1.0)


func _process(delta: float) -> void:
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	_update_view(clampf(delta * 12.0, 0.0, 1.0))


func _update_view(blend: float) -> void:
	if not _has_target():
		_show_target_body()
		_set_view_gun(-2)
		_orbit += get_process_delta_time() * 0.25
		var spot := death_spot + Vector3(cos(_orbit) * 7.0, 6.0, sin(_orbit) * 7.0)
		global_position = global_position.lerp(spot, blend)
		look_at(death_spot + Vector3(0, 1.0, 0), Vector3.UP)
		return

	var yaw: float = target.rotation.y
	var pitch := _target_pitch()
	if mode == FIRST_PERSON:
		_hide_target_body()
		global_position = target.global_position + Vector3(0, EYE_HEIGHT, 0)
		rotation = Vector3(pitch, yaw, 0.0)
		_set_view_gun(int(target.get_meta("weapon", Weapons.BRUSH_RIFLE)))
		if _view_gun != null:
			_view_gun.position = VIEW_GUN_HOME + Vector3(0, -0.012, 0.05) * _kick
		return

	_show_target_body()
	_set_view_gun(-2)
	# Third person: start at the teammate's head, then go back (and a little
	# to the right, over the shoulder) along the direction they are facing,
	# tilted by half their aim pitch so looking down lifts the camera.
	var head: Vector3 = target.global_position + Vector3(0, HEAD_HEIGHT, 0)
	var facing := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, clampf(pitch * 0.5, -0.6, 0.45))
	var wanted := head + facing * Vector3(SHOULDER_OFFSET, 0.35, BACK_DISTANCE)
	# Stop in front of walls: a ray from the head to the wanted spot, against
	# the world only (layer 1), and sit just short of whatever it hits.
	var query := PhysicsRayQueryParameters3D.create(head, wanted, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		wanted = head + (hit["position"] - head) * 0.85
	global_position = global_position.lerp(wanted, blend)
	var look_ahead := head + facing * Vector3(0, 0, -8.0)
	if global_position.distance_to(look_ahead) > 0.1:
		look_at(look_ahead, Vector3.UP)


## The teammate's camera pitch, read from the aim pivot their gun rides on
## (remote_player.gd smooths it toward each network update).
func _target_pitch() -> float:
	var pivot := target.get_node_or_null("AimPivot") as Node3D
	return pivot.rotation.x if pivot != null else 0.0


func _hide_target_body() -> void:
	if _hidden_target == target:
		return
	_show_target_body()
	_hidden_target = target
	target.set_meta("first_person_spectated", true)
	_set_body_visible(target, false)


func _show_target_body() -> void:
	if _hidden_target != null and is_instance_valid(_hidden_target):
		_hidden_target.set_meta("first_person_spectated", false)
		_set_body_visible(_hidden_target, true)
	_hidden_target = null


static func _set_body_visible(actor, on: bool) -> void:
	var visual := actor.get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.visible = on
	var gun := actor.get_node_or_null("AimPivot/Blaster") as Node3D
	if gun != null:
		gun.visible = on


## The first-person gun: the teammate's gun model in their gun skin, with its
## paint in their team colour. -2 = none.
func _set_view_gun(index: int) -> void:
	if index == _view_gun_weapon:
		return
	_view_gun_weapon = index
	if _view_gun != null:
		_view_gun.queue_free()
		_view_gun = null
	if index < 0:
		return
	var weapon := Weapons.get_weapon(index)
	var gun := PaintKit.instance(str(weapon.model))
	if gun == null:
		gun = PaintKit.instance("paint_blaster")
	if gun == null:
		return
	var holder := Node3D.new()
	holder.position = VIEW_GUN_HOME
	add_child(holder)
	gun.scale = Vector3.ONE * 1.15
	if str(weapon.model) == "paint_blaster":
		gun.position = Vector3(0.0, 0.0, -0.36) * (1.0 - 1.15)
	else:
		gun.position = weapon.get("view_offset", Vector3.ZERO)
	holder.add_child(gun)
	var team: Color = target.get_meta("team_color", Color.WHITE)
	PaintKit.paint(gun, team, team, false)
	PaintKit.set_shadows(gun, false)
	GunSkins.apply(gun, int(target.get_meta("gun_skin", 0)), false)
	_view_gun = holder


func _exit_tree() -> void:
	_show_target_body()
