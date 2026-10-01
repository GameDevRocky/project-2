extends RefCounted

## ============================================================================
## GUN SKINS - restyles the whole Paint Blaster for each gun skin.
## ============================================================================
##
## The Paint Blaster models name their materials by role. A gun skin swaps four
## of them: the ceramic body (PK_Body), the dark trim bands (PK_Trim), the skin
## band (PK_Skin) and the grip/hose (PK_Rubber). The paint parts - bristles,
## tank, drips - are NOT touched: on your own gun they show your inherited
## pair's colour, on a bot's gun its team colour, and both of those matter in a
## fight.
##
## Order matches CharacterCustomizationData.GUN_SKINS.

const WoodShader = preload("res://scripts/visual/woodgrain.gdshader")

const PALETTES := [
	{"body": "#E9F7F2", "trim": "#2F6B63", "band": "#63D9C7", "grip": "#24413D"},   # MINT
	{"body": "#E6F6FB", "trim": "#1F5F73", "band": "#54C9E8", "grip": "#1E3A44"},   # CYAN
	{"body": "#F8E8F2", "trim": "#6B2A55", "band": "#E05AB0", "grip": "#3A1E33"},   # MAGENTA
	{"body": "#FFF2D6", "trim": "#9A5A12", "band": "#F5B23E", "grip": "#4A3214"},   # SUNBURST
	{"body": "#EEE8FA", "trim": "#4B3A80", "band": "#A78BFA", "grip": "#2C2448"},   # VIOLET
	{"body": "#F6F2EE", "trim": "#B7B2C6", "band": "#E8E2F5", "grip": "#6E6A7A", "pearl": true},   # PEARL
	{"body": "#FCE9E4", "trim": "#8A3C33", "band": "#FF867C", "grip": "#4A2420"},   # CORAL
	{"body": "#EAF4E4", "trim": "#3E6B3A", "band": "#79C991", "grip": "#26402A"},   # LEAF
	{"body": "#E8F2FB", "trim": "#2F5A80", "band": "#70BCEB", "grip": "#22384F"},   # SKY
	{"body": "wood", "trim": "#C9A45C", "band": "#6B4226", "grip": "#3B2618", "brass_trim": true},  # WOODGRAIN
]

static var _cache: Dictionary = {}


## The four materials for one gun skin, built once and shared.
static func materials(index: int, fogless: bool) -> Dictionary:
	index = posmod(index, PALETTES.size())
	var key := "%d|%s" % [index, str(fogless)]
	if _cache.has(key):
		return _cache[key]
	var p: Dictionary = PALETTES[index]
	var mats := {}
	if str(p["body"]) == "wood":
		var wood := ShaderMaterial.new()
		wood.shader = WoodShader
		mats["PK_Body"] = wood
	else:
		var body := _mat(Color(p["body"]), 0.45, 0.0, fogless)
		if bool(p.get("pearl", false)):
			# Pearl: a soft sheen with a shifting rim.
			body.metallic = 0.35
			body.roughness = 0.18
			body.clearcoat_enabled = true
			body.rim_enabled = true
			body.rim = 0.6
			body.rim_tint = 0.8
		mats["PK_Body"] = body
	mats["PK_Trim"] = _mat(Color(p["trim"]), 0.35, 0.7 if bool(p.get("brass_trim", false)) else 0.35, fogless)
	mats["PK_Skin"] = _mat(Color(p["band"]), 0.4, 0.0, fogless)
	mats["PK_Rubber"] = _mat(Color(p["grip"]), 0.85, 0.0, fogless)
	_cache[key] = mats
	return mats


static func _mat(color: Color, roughness: float, metallic: float, fogless: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	m.disable_fog = fogless
	return m


## Applies a gun skin to a Paint Blaster model (first-person or one-piece).
## Call AFTER any other repainting, since it replaces those four surfaces.
static func apply(gun_root: Node, index: int, fogless := false) -> void:
	var mats := materials(index, fogless)
	for node in gun_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(i)
			if source != null and mats.has(source.resource_name):
				mi.set_surface_override_material(i, mats[source.resource_name])
