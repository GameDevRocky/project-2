extends RefCounted

## ============================================================================
## PAINT FX - small one-shot paint effects (bursts of droplets).
## ============================================================================
##
## Pure decoration: nothing here touches health, paint, damage or timing.
##
## A burst is a CPUParticles3D - a node that throws a set number of tiny
## meshes outward once and then stops. CPU particles work in both of the game's
## renderers (desktop Forward+ and the web's Compatibility), unlike the GPU
## kind. Each burst frees itself when its last droplet has faded.
##
##     const PaintFx = preload("res://scripts/visual/paint_fx.gd")
##     PaintFx.burst(get_parent(), global_position, Color.PINK)

## One droplet mesh and one material, shared by every burst in the game.
static var _droplet: SphereMesh
static var _material: StandardMaterial3D


static func _shared() -> void:
	if _droplet != null:
		return
	_droplet = SphereMesh.new()
	_droplet.radius = 0.05
	_droplet.height = 0.1
	_droplet.radial_segments = 6
	_droplet.rings = 3
	_material = StandardMaterial3D.new()
	# Each particle carries its own colour; this makes the material use it.
	_material.vertex_color_use_as_albedo = true
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.disable_fog = true
	_droplet.material = _material


## Builds a burst node without starting it. `size` scales the droplets.
static func make(color: Color, amount: int = 14, speed: float = 3.5, size: float = 1.0,
		lifetime: float = 0.45) -> CPUParticles3D:
	_shared()
	var p := CPUParticles3D.new()
	p.mesh = _droplet
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0          # every droplet leaves at the same instant
	p.emitting = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -9.0, 0.0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.3 * size
	p.color = color
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Spawns a self-freeing burst of paint droplets at a world position.
static func burst(parent: Node, at: Vector3, color: Color, amount: int = 14,
		speed: float = 3.5, size: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := make(color, amount, speed, size)
	parent.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.emitting = true
