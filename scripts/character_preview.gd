extends Node3D
class_name CharacterPreview

## The character shown in the menu: the same dressed Canvas Runner that TDM
## bots wear (scripts/visual/runner_dresser.gd), so what you pick here is what
## a runner looks like in a match. If the runner model is missing, the original
## bean preview below is built instead.

const Data = preload("res://scripts/character_customization_data.gd")
const PaintKit = preload("res://scripts/visual/paint_kit.gd")
const RunnerDresser = preload("res://scripts/visual/runner_dresser.gd")
const DEFAULT_COLORS := ["#242735", "#65F581", "#3A9EFF", "#FF4EAC", "#F7F7F4", "#D93555", "#E5B842", "#637B48", "#9A67E8", "#FFFFFF"]

## Colour of the team marks while there is no team yet (the menu's mint).
var team_color := Color("#8CEADF")
var customization: Dictionary = Data.create_session_data()
var _material_nodes: Array[MeshInstance3D] = []


func set_customization(value: Dictionary) -> void:
	customization = value.duplicate(true)
	_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_material_nodes.clear()
	var runner := RunnerDresser.build(customization, team_color, false)
	if runner != null:
		add_child(runner)
		# Feet on the showcase seat (the old bean stood 0.14 m up its capsule),
		# and turned to face the camera like the bean did (the runner faces +Z).
		runner.position = Vector3(0.0, 0.13, 0.0)
		runner.rotation.y = PI
		return
	_rebuild_bean()


## The original procedural bean, kept as the fallback.
func _rebuild_bean() -> void:
	var skin_id := str(customization.get("skin", "default"))
	var skin := Data.skin_by_id(skin_id)
	if not str(skin.scene_path).is_empty() and ResourceLoader.exists(skin.scene_path):
		var skin_scene := load(skin.scene_path) as PackedScene
		if skin_scene:
			add_child(skin_scene.instantiate())
			_apply_accessories()
			_add_paint_gun()
			return
	var base_color := Color(DEFAULT_COLORS[int(customization.get("body_color", 0)) % DEFAULT_COLORS.size()])
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = base_color
	body_material.roughness = 0.68
	var body_position := Vector3(0, 0.94, 0)
	var bean := _capsule(0.48, 1.6, body_position, body_material)
	if skin_id != "default":
		_apply_skin(skin_id, body_material, body_position)
		_apply_accessories()
	else:
		_apply_body_color_variant(body_material, bean)
		_add_default_face()
		_apply_accessories()
	_add_paint_gun()


func _capsule(radius: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	node.mesh = mesh
	node.position = at
	node.material_override = material
	add_child(node)
	return node


func _box(size: Vector3, at: Vector3, color: Color, emissive := false, metallic := 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.42
	material.metallic = metallic
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.4
	node.material_override = material
	add_child(node)
	_material_nodes.append(node)
	return node


func _sphere(radius: float, at: Vector3, color: Color, emissive := false, alpha := 1.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	node.mesh = mesh
	node.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.roughness = 0.4
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.8
	node.material_override = material
	add_child(node)
	return node


func _torus(at: Vector3, color: Color, emissive := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.5
	mesh.outer_radius = 0.58
	node.mesh = mesh
	node.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.35
	material.roughness = 0.3
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.5
	node.material_override = material
	add_child(node)
	return node


func _apply_body_color_variant(material: StandardMaterial3D, bean: MeshInstance3D) -> void:
	var choice: Dictionary = Data.BODY_COLORS[int(customization.get("body_color", 0)) % Data.BODY_COLORS.size()]
	material.albedo_color = Color(choice.color)
	material.metallic = 0.78 if bool(choice.get("metallic", false)) else 0.0
	if bool(choice.get("rainbow", false)):
		var rainbow := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = "shader_type spatial; void fragment() { float h = UV.y * 6.0; vec3 a = vec3(0.95,0.25,0.55); vec3 b = vec3(0.95,0.72,0.22); vec3 c = vec3(0.30,0.92,0.62); vec3 d = vec3(0.25,0.68,0.96); ALBEDO = h < 2.0 ? mix(a,b,h*0.5) : (h < 4.0 ? mix(b,c,(h-2.0)*0.5) : mix(c,d,(h-4.0)*0.5)); ROUGHNESS = 0.5; }"
		rainbow.shader = shader
		bean.material_override = rainbow
	if str(choice.id) == "camo_green":
		for pos in [Vector3(-0.2, 0.75, -0.36), Vector3(0.18, 1.1, -0.35), Vector3(0.02, 1.3, -0.3), Vector3(-0.22, 1.25, 0.25)]:
			_sphere(0.1, pos, Color("#304A34"))


func _add_default_face() -> void:
	for x in [-0.16, 0.16]:
		_sphere(0.05, Vector3(x, 1.23, -0.445), Color("#202331"))


func _apply_skin(skin_id: String, material: StandardMaterial3D, body_at: Vector3) -> void:
	var bone := Color("#EDE6D4")
	var cyan := Color("#5AF5E4")
	var magenta := Color("#FF4EAC")
	var dark := Color("#202432")
	match skin_id:
		"skeleton":
			material.albedo_color = dark
			for y in [0.62, 0.78, 0.94, 1.1]:
				_box(Vector3(0.58, 0.07, 0.08), Vector3(0, y, -0.39), bone)
			_box(Vector3(0.1, 0.55, 0.1), Vector3(0, 0.84, -0.4), bone)
			_sphere(0.28, Vector3(0, 1.57, 0), bone)
			for x in [-0.1, 0.1]: _sphere(0.065, Vector3(x, 1.59, -0.24), Color("#151824"))
		"superhero":
			material.albedo_color = Color("#4C69DA")
			_box(Vector3(0.08, 1.18, 0.12), Vector3(0, 0.9, 0.53), magenta)
			_box(Vector3(0.82, 1.16, 0.1), Vector3(0, 0.96, 0.51), Color("#F13D8B"))
			_sphere(0.17, Vector3(0, 1.17, -0.43), Color("#FFD767"), true)
		"zombie":
			material.albedo_color = Color("#8BBF75")
			for x in [-0.16, 0.16]: _sphere(0.052, Vector3(x, 1.23, -0.45), Color("#FF3D76"), true)
			for pos in [Vector3(-0.25, 0.72, -0.31), Vector3(0.24, 0.95, -0.33), Vector3(-0.08, 1.3, 0.25)]:
				_sphere(0.13, pos, Color("#547A59"))
		"astronaut":
			material.albedo_color = Color("#F2F5F2")
			_torus(Vector3(0, 0.62, 0), cyan, true)
			_sphere(0.39, Vector3(0, 1.59, 0), Color("#78DFEF"), false, 0.52)
			_box(Vector3(0.36, 0.05, 0.07), Vector3(0, 0.89, -0.44), Color("#E8A9E4"), true)
		"ninja":
			material.albedo_color = Color("#171924")
			_box(Vector3(0.72, 0.16, 0.72), Vector3(0, 1.65, 0), magenta)
			_box(Vector3(0.62, 0.14, 0.09), Vector3(0, 1.2, -0.42), cyan, true)
			_torus(Vector3(0, 0.56, 0), cyan, true)
		"robot":
			material.albedo_color = Color("#929CA8")
			material.metallic = 0.82
			for x in [-0.3, 0.3]: _sphere(0.1, Vector3(x, 0.86, 0), cyan, true)
			for y in [0.7, 1.0, 1.3]: _box(Vector3(0.7, 0.05, 0.07), Vector3(0, y, -0.39), Color("#444D5C"), true, 0.7)
			for x in [-0.15, 0.15]: _sphere(0.055, Vector3(x, 1.25, -0.43), cyan, true)
		"paintball_splatter":
			material.albedo_color = Color("#F2F0E9")
			for entry in [[-0.25, 0.7, "#FF57A8"], [0.22, 0.82, "#43DCC8"], [-0.12, 1.15, "#54C9E8"], [0.23, 1.34, "#F5C45E"], [-0.28, 1.38, "#A78BFA"]]:
				_sphere(0.16, Vector3(entry[0], entry[1], -0.37), Color(entry[2]))
		"ghost":
			material.albedo_color = Color("#A9F5F0", 0.58)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.emission_enabled = true
			material.emission = cyan
			material.emission_energy_multiplier = 0.7
			_torus(Vector3(0, 0.93, 0), cyan, true)
			for x in [-0.16, 0.16]: _sphere(0.05, Vector3(x, 1.23, -0.44), Color("#6CFBF2"), true)
		"samurai":
			material.albedo_color = Color("#642F55")
			for x in [-0.44, 0.44]: _box(Vector3(0.28, 0.34, 0.55), Vector3(x, 1.26, 0), Color("#D4A752"), false, 0.55)
			_box(Vector3(0.82, 0.14, 0.1), Vector3(0, 0.7, -0.4), Color("#EF5E73"))
			_box(Vector3(0.74, 0.07, 0.08), Vector3(0, 1.64, 0), Color("#D8B65E"), false, 0.5)
		"cyberpunk":
			material.albedo_color = Color("#252638")
			for x in [-0.27, 0.27]: _box(Vector3(0.035, 0.88, 0.045), Vector3(x, 0.97, -0.4), cyan, true)
			_box(Vector3(0.64, 0.045, 0.045), Vector3(0, 1.0, -0.42), magenta, true)
			for x in [-0.16, 0.16]: _sphere(0.055, Vector3(x, 1.23, -0.44), magenta, true)


func _apply_accessories() -> void:
	var accent := Color(Data.ACCENT_COLORS[int(customization.get("hat", 0)) % Data.ACCENT_COLORS.size()])
	if Data.category_allows(customization, "HATS") and int(customization.get("hat", 0)) > 0:
		var hat_path := Data.option_scene_path("HATS", int(customization.hat))
		if not hat_path.is_empty() and ResourceLoader.exists(hat_path):
			var hat_scene := load(hat_path) as PackedScene
			if hat_scene: add_child(hat_scene.instantiate())
		else: _box(Vector3(0.78, 0.18, 0.68), Vector3(0, 1.78, 0), accent, int(customization.hat) == 7)
	if Data.category_allows(customization, "MASKS") and int(customization.get("mask", 0)) > 0:
		var mask_color := Color(Data.ACCENT_COLORS[int(customization.mask) % Data.ACCENT_COLORS.size()])
		var mask_path := Data.option_scene_path("MASKS", int(customization.mask))
		if not mask_path.is_empty() and ResourceLoader.exists(mask_path):
			var mask_scene := load(mask_path) as PackedScene
			if mask_scene: add_child(mask_scene.instantiate())
		else: _box(Vector3(0.48, 0.2, 0.09), Vector3(0, 0.96, -0.46), mask_color, int(customization.mask) == 9)
	if Data.category_allows(customization, "BACK BLING") and int(customization.get("back_bling", 0)) > 0:
		var pack_color := Color(Data.ACCENT_COLORS[int(customization.back_bling) % Data.ACCENT_COLORS.size()])
		var pack_path := Data.option_scene_path("BACK BLING", int(customization.back_bling))
		if not pack_path.is_empty() and ResourceLoader.exists(pack_path):
			var pack_scene := load(pack_path) as PackedScene
			if pack_scene: add_child(pack_scene.instantiate())
		else: _box(Vector3(0.48, 0.58, 0.28), Vector3(0, 0.94, 0.5), pack_color, int(customization.back_bling) == 2)


func _add_paint_gun() -> void:
	var gun_color := Color(Data.ACCENT_COLORS[int(customization.get("gun_skin", 0)) % Data.ACCENT_COLORS.size()])
	# The same Paint Blaster the player holds in a match, held where the old
	# box gun was and pointing the same way (+X). The gun-skin colour goes on
	# its skin band; the brush and tank use the old muzzle's mint.
	var blaster := PaintKit.instance("paint_blaster")
	if blaster != null:
		add_child(blaster)
		blaster.position = Vector3(0.53, 0.76, -0.56)
		# The model points down its -Z; turning it -90 degrees about Y points
		# it down +X, like the old box.
		blaster.rotation.y = -PI * 0.5
		blaster.scale = Vector3.ONE * 1.35
		PaintKit.paint(blaster, Color("#79F5E6"), Color.WHITE, false,
			{"PK_Skin": PaintKit.role_material("PK_Team", gun_color, false)})
		var material_path := Data.gun_material_path(int(customization.get("gun_skin", 0)))
		var band := PaintKit.part(blaster, "SkinBand") as GeometryInstance3D
		if band != null and not material_path.is_empty() and ResourceLoader.exists(material_path):
			band.material_override = load(material_path) as Material
		return
	var gun := _box(Vector3(0.2, 0.2, 0.9), Vector3(0.53, 0.76, -0.56), gun_color)
	var material_path := Data.gun_material_path(int(customization.get("gun_skin", 0)))
	if not material_path.is_empty() and ResourceLoader.exists(material_path):
		gun.material_override = load(material_path) as Material
	gun.rotation.y = PI * 0.5
	_box(Vector3(0.12, 0.26, 0.16), Vector3(0.48, 0.57, -0.54), Color("#35374A"))
	_sphere(0.12, Vector3(0.99, 0.76, -0.56), Color("#79F5E6"), true)
