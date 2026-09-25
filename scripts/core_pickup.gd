extends Node3D

## ============================================================================
## CORE PICKUP - the dropped pair a defeated enemy leaves behind.
## ============================================================================
##
## WHY INHERITING IS A BUTTON PRESS AND NOT A WALK-OVER
## The first version of this was automatic: touch the core, take the pair. It
## was a mistake. Because inheriting REPLACES your pair rather than adding to
## it, an accidental pickup can strip the ability you were relying on in the
## middle of a fight - and in a game where you are constantly moving, accidental
## is the normal case. So a core does nothing until you deliberately press the
## interact key while standing near it, and the HUD spells out exactly what you
## would gain and lose first. The mechanic is a decision, so it needs a moment
## where you actually decide.
##
## This script is intentionally passive. It floats, it spins, it fades, and it
## knows which pair it holds. The proximity check, the prompt and the key press
## all live in game.gd, because deciding WHEN an offer is available is game
## logic, not the business of a decoration on the floor.

const Traits = preload("res://scripts/traits.gd")


## Which pair this core carries, e.g. "monolith". Set by the dying enemy.
var pair_id: String = "sprayer"

## Matches the archetype that dropped it, so you can tell across the arena what
## is on offer without walking over to read the prompt.
var color: Color = Color.WHITE

## Seconds before the core disappears. Deliberately short. A core that lingered
## forever would turn inheritance into shopping - kill everything, then stroll
## around picking the best pair at leisure. A timer means committing to a pair
## while the fight is still going on, which is where the tension lives.
@export var lifetime: float = 14.0

## Metres from the core the player must be within for it to be offered.
@export var pickup_range: float = 2.6

var _age: float = 0.0
var _taken: bool = false

var _mesh: MeshInstance3D
var _halo: MeshInstance3D


func _ready() -> void:
	# Tagged so game.gd can find every core on the floor without tracking them.
	add_to_group("cores")
	_build_visuals()


func _build_visuals() -> void:
	# The core itself: a small faceted crystal in the pair's colour.
	_mesh = MeshInstance3D.new()
	var body := SphereMesh.new()
	body.radius = 0.3
	body.height = 0.75
	body.radial_segments = 6
	body.rings = 3
	_mesh.mesh = body

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	# Bright enough to catch your eye across the arena mid-fight, which is the
	# entire job of a pickup in a game this busy.
	mat.emission_energy_multiplier = 1.6
	mat.roughness = 0.4
	_mesh.material_override = mat
	add_child(_mesh)

	# A soft shell around it, so the core reads as "collectable thing" rather
	# than "another enemy". Drawing only the inside faces makes it look like a
	# glow you can see into instead of a solid ball.
	_halo = MeshInstance3D.new()
	var shell := SphereMesh.new()
	shell.radius = 0.62
	shell.height = 1.24
	shell.radial_segments = 10
	shell.rings = 5
	_halo.mesh = shell

	var halo_mat := StandardMaterial3D.new()
	halo_mat.albedo_color = Color(color.r, color.g, color.b, 0.22)
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_halo.material_override = halo_mat
	add_child(_halo)


## _process runs once per DRAWN frame, unlike _physics_process which runs on the
## fixed physics clock. Purely visual motion like this belongs here, so it stays
## smooth on a high-refresh monitor instead of being locked to 60 steps.
func _process(delta: float) -> void:
	if _taken:
		return

	_age += delta

	# Spin and bob, so the core is obviously interactive rather than scenery.
	_mesh.rotate_y(delta * 1.8)
	_mesh.position.y = sin(_age * 2.4) * 0.12
	_halo.position.y = _mesh.position.y
	# Breathe the halo slightly out of step with the bob, which reads as a pulse.
	var pulse: float = 1.0 + sin(_age * 3.1) * 0.07
	_halo.scale = Vector3.ONE * pulse

	# Warn that it is about to vanish by flashing over the last three seconds.
	# The flash gets faster as the time runs out, so urgency is something you
	# feel out of the corner of your eye rather than something you have to read.
	var remaining: float = lifetime - _age
	if remaining <= 3.0:
		var blink_rate: float = lerpf(4.0, 14.0, 1.0 - clampf(remaining / 3.0, 0.0, 1.0))
		var visible_now: bool = sin(_age * blink_rate) > -0.35
		_mesh.visible = visible_now
		_halo.visible = visible_now

	if _age >= lifetime:
		queue_free()


## How far the player is from this core, measured flat along the ground.
## Ignoring height means a core sitting at your feet still counts while you are
## mid-jump, rather than the prompt flickering off every time you leave the
## floor.
func distance_to_player(player_position: Vector3) -> float:
	var offset: Vector3 = global_position - player_position
	offset.y = 0.0
	return offset.length()


## The pair data this core is offering, so the HUD can show what is at stake.
func get_pair() -> Dictionary:
	return Traits.get_pair(pair_id)


## Called by game.gd when the player presses interact in range. Returns whether
## the swap actually happened - it does not if the player already has this pair,
## in which case the core is left on the ground rather than wasted.
##
## `player` is untyped on purpose: inherit_pair() is a function this project
## added to player.gd, and calling a project-added function on a variable typed
## as an engine class is a parse-time error in GDScript.
func collect(player) -> bool:
	if _taken:
		return false

	var swapped: bool = player.inherit_pair(pair_id)
	if not swapped:
		return false

	_taken = true
	remove_from_group("cores")

	# Suck the core upward and shrink it away, so taking a pair has a beat of
	# its own rather than the core just blinking out of existence.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.28)
	tween.tween_property(self, "position:y", position.y + 1.4, 0.28)
	tween.chain().tween_callback(queue_free)

	return true
