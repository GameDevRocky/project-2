extends RefCounted
class_name CharacterCustomizationData

## Frontend selection data. `scene_path` is the replacement seam for imported
## character scenes; empty paths use the procedural preview builder.
const SKINS := [
	{"id": "skeleton", "name": "SKELETON", "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": false, "scene_path": ""},
	{"id": "superhero", "name": "SUPERHERO", "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": false, "scene_path": ""},
	{"id": "zombie", "name": "ZOMBIE", "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": false, "scene_path": ""},
	{"id": "astronaut", "name": "ASTRONAUT", "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": false, "scene_path": ""},
	{"id": "ninja", "name": "NINJA", "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": false, "scene_path": ""},
	{"id": "robot", "name": "ROBOT", "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": false, "scene_path": ""},
	{"id": "paintball_splatter", "name": "PAINTBALL SPLATTER", "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": false, "scene_path": ""},
	{"id": "ghost", "name": "GHOST", "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": false, "scene_path": ""},
	{"id": "samurai", "name": "SAMURAI", "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": false, "scene_path": ""},
	{"id": "cyberpunk", "name": "CYBERPUNK", "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": false, "scene_path": ""},
]

const BODY_COLORS := [
	{"id": "classic_black", "name": "CLASSIC BLACK", "color": "#242735"},
	{"id": "neon_green", "name": "NEON GREEN", "color": "#65F581"},
	{"id": "electric_blue", "name": "ELECTRIC BLUE", "color": "#3A9EFF"},
	{"id": "hot_pink", "name": "HOT PINK", "color": "#FF4EAC"},
	{"id": "pure_white", "name": "PURE WHITE", "color": "#F7F7F4"},
	{"id": "blood_red", "name": "BLOOD RED", "color": "#D93555"},
	{"id": "gold_metallic", "name": "GOLD METALLIC", "color": "#E5B842", "metallic": true},
	{"id": "camo_green", "name": "CAMO GREEN", "color": "#637B48"},
	{"id": "purple_haze", "name": "PURPLE HAZE", "color": "#9A67E8"},
	{"id": "rainbow_gradient", "name": "RAINBOW GRADIENT", "color": "#FFFFFF", "rainbow": true},
]

const HATS := ["NONE", "VISOR", "CROWN", "BUCKET HAT", "BEANIE", "ANTENNA", "CAP", "HALO", "FLOWER", "TOP HAT"]
const MASKS := ["NONE", "MINT MASK", "SPLASH MASK", "PIXEL MASK", "BANDANA", "VISOR MASK", "STAR MASK", "GRID MASK", "HALF MASK", "GLOW MASK"]
const BACK_BLING := ["NONE", "MINI TANK", "ORB PACK", "PAINT CAN", "WING PACK", "JET PACK", "BUBBLE PACK", "PIXEL PACK", "SPLASH PACK", "STAR PACK"]
const GUN_SKINS := ["MINT", "CYAN", "MAGENTA", "SUNBURST", "VIOLET", "PEARL", "CORAL", "LEAF", "SKY", "WOODGRAIN"]
const ACCENT_COLORS := ["#FF6FAE", "#63D9C7", "#54C9E8", "#F5C45E", "#A78BFA", "#F5F4F0", "#FF867C", "#79C991", "#70BCEB", "#C18B67"]
const OPTION_SCENE_PATHS := {
	"HATS": ["", "", "", "", "", "", "", "", "", ""],
	"MASKS": ["", "", "", "", "", "", "", "", "", ""],
	"BACK BLING": ["", "", "", "", "", "", "", "", "", ""],
}
const GUN_MATERIAL_PATHS := ["", "", "", "", "", "", "", "", "", ""]


static func create_session_data() -> Dictionary:
	return {
		"username": "Player",
		"skin": "default",
		"body_color": 4,
		"hat": 0,
		"mask": 0,
		"gun_skin": 0,
		"back_bling": 0,
	}


static func skin_by_id(skin_id: String) -> Dictionary:
	if skin_id == "default":
		return {"id": "default", "name": "DEFAULT BEAN", "allows_body_color": true, "allows_hat": true, "allows_mask": true, "allows_back_bling": true, "scene_path": ""}
	for skin in SKINS:
		if skin.id == skin_id:
			return skin
	return skin_by_id("default")


static func category_allows(data: Dictionary, category: String) -> bool:
	var skin := skin_by_id(str(data.get("skin", "default")))
	match category:
		"BODY COLORS": return bool(skin.allows_body_color)
		"HATS": return bool(skin.allows_hat)
		"MASKS": return bool(skin.allows_mask)
		"BACK BLING": return bool(skin.allows_back_bling)
		_: return true


static func option_scene_path(category: String, index: int) -> String:
	var paths: Array = OPTION_SCENE_PATHS.get(category, [])
	return str(paths[index]) if index >= 0 and index < paths.size() else ""


static func gun_material_path(index: int) -> String:
	return str(GUN_MATERIAL_PATHS[index]) if index >= 0 and index < GUN_MATERIAL_PATHS.size() else ""
