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

var _age := 0.0


func _ready() -> void:
	position = Vector3(0.0, 0.0, -0.6)
	var sphere := SphereMesh.new()
	sphere.radial_segments = 6
	sphere.rings = 3
	var glob_mesh: Mesh = PaintKit.mesh("paint_glob", "Glob")
	_add(glob_mesh if glob_mesh != null else sphere, Projectile.glob_material(Color.WHITE), null)
	var splat_mesh: Mesh = PaintKit.mesh("paint_splat", "Splat_0")
	_add(splat_mesh if splat_mesh != null else sphere, Projectile.splat_material(Color.WHITE), null)
	_add(sphere, Projectile.puff_material(Color.WHITE), null)
	_add(sphere, Projectile.burst_material(Color.WHITE), null)
	var overlay := PaintKit.flash_overlay_material()
	overlay.albedo_color.a = 0.5
	_add(sphere, StandardMaterial3D.new(), overlay)
	var burst := PaintFx.make(Color.WHITE, 1, 0.0, 0.02, 0.3)
	add_child(burst)
	burst.emitting = true


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
	if _age > 0.25:
		queue_free()
