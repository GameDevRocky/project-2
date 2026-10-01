extends RefCounted
class_name CharacterCustomizationData

## Frontend selection data. The customization DICTIONARY (username, skin,
## body_color, hat, mask, gun_skin, back_bling) is the contract: the menu
## writes it, lobby records carry it, and scripts/visual/runner_dresser.gd turns
## it into a dressed Canvas Runner (menu preview, TDM bots, and later online
## players). `scene_path` stays as the seam for hand-made character scenes.
##
## Outfit visuals live in models/generated/cosmetic_outfits_a.glb / _b.glb as
## `Outfit_<ID>` (id upper-cased). `suit` and `helmet` recolour the runner's
## own suit and helmet underneath the outfit; `hides_head` swaps the runner's
## helmet for the outfit's own head.
const SKINS := [
	{"id": "skeleton", "name": "SKELETON", "suit": "#2F2B3D", "helmet": "#EDE6D4", "hides_head": true, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": ""},
	{"id": "superhero", "name": "SUPERHERO", "suit": "#7B4FD0", "helmet": "#F4C430", "hides_head": false, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": ""},
	{"id": "zombie", "name": "ZOMBIE", "suit": "#8F80AE", "helmet": "#776A93", "hides_head": true, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": ""},
	{"id": "astronaut", "name": "ASTRONAUT", "suit": "#ECE9E1", "helmet": "#F2A541", "hides_head": true, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": ""},
	{"id": "ninja", "name": "NINJA", "suit": "#383B5E", "helmet": "#26283E", "hides_head": false, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": ""},
	{"id": "robot", "name": "ROBOT", "suit": "#7D8796", "helmet": "#E3B23C", "hides_head": true, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": ""},
	{"id": "paintball_splatter", "name": "PAINTBALL SPLATTER", "suit": "#F1ECF7", "helmet": "#B9A7F2", "hides_head": false, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": ""},
	{"id": "ghost", "name": "GHOST", "suit": "#A9BFCB", "helmet": "#E3F1EF", "hides_head": true, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": ""},
	{"id": "samurai", "name": "SAMURAI", "suit": "#4E4670", "helmet": "#2E2638", "hides_head": false, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": ""},
	{"id": "cyberpunk", "name": "CYBERPUNK", "suit": "#3A3650", "helmet": "#5C6178", "hides_head": false, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": ""},
]

## Outfits only computer players wear - the player cannot pick these. They make
## the TDM lobby feel like a crowd of characters rather than a row of clones.
const BOT_SKINS := [
	{"id": "art_critic", "name": "ART CRITIC", "suit": "#34303F", "helmet": "#ECE2CF", "hides_head": false, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": "", "bot_only": true},
	{"id": "janitor", "name": "STUDIO JANITOR", "suit": "#A8996F", "helmet": "#E4DAC2", "hides_head": false, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": "", "bot_only": true},
	{"id": "mime", "name": "MIME", "suit": "#F2EFE9", "helmet": "#F5F2EC", "hides_head": false, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": "", "bot_only": true},
	{"id": "ink_golem", "name": "INK GOLEM", "suit": "#352C52", "helmet": "#352C52", "hides_head": true, "allows_body_color": false, "allows_hat": false, "allows_mask": false, "allows_back_bling": true, "scene_path": "", "bot_only": true},
]

## Suit colours for the default Canvas Runner.
const BODY_COLORS := [
	{"id": "classic_black", "name": "CLASSIC BLACK", "color": "#242735"},
	{"id": "neon_green", "name": "NEON GREEN", "color": "#65F581"},
	{"id": "electric_blue", "name": "ELECTRIC BLUE", "color": "#3A9EFF"},
	{"id": "hot_pink", "name": "HOT PINK", "color": "#FF4EAC"},
	{"id": "pure_white", "name": "CANVAS WHITE", "color": "#E9E1D2"},
	{"id": "blood_red", "name": "BLOOD RED", "color": "#D93555"},
	{"id": "gold_metallic", "name": "GOLD METALLIC", "color": "#E5B842", "metallic": true},
	{"id": "camo_green", "name": "CAMO GREEN", "color": "#637B48", "camo": true},
	{"id": "purple_haze", "name": "PURPLE HAZE", "color": "#9A67E8"},
	{"id": "rainbow_gradient", "name": "RAINBOW GRADIENT", "color": "#FFFFFF", "rainbow": true},
]

## Index 0 of HATS and MASKS is "nothing". The cosmetic models are named
## `Hat_<NAME>` / `Mask_<NAME>` / `Back_<NAME>` with spaces as underscores.
const HATS := ["NONE", "VISOR", "CROWN", "BUCKET HAT", "BEANIE", "ANTENNA", "CAP", "HALO", "FLOWER", "TOP HAT"]
const MASKS := ["NONE", "MINT MASK", "SPLASH MASK", "PIXEL MASK", "BANDANA", "VISOR MASK", "STAR MASK", "GRID MASK", "HALF MASK", "GLOW MASK"]
## Every runner carries its paint on its back, so there is no "none": index 0
## is the standard Chromatic Tank.
const BACK_BLING := ["CHROMATIC TANK", "MINI TANK", "ORB PACK", "PAINT CAN", "WING PACK", "JET PACK", "BUBBLE PACK", "PIXEL PACK", "SPLASH PACK", "STAR PACK", "EASEL PACK", "ROLLER RIG"]
## Restyles the whole Paint Blaster (scripts/visual/gun_skins.gd).
const GUN_SKINS := ["MINT", "CYAN", "MAGENTA", "SUNBURST", "VIOLET", "PEARL", "CORAL", "LEAF", "SKY", "WOODGRAIN"]
const ACCENT_COLORS := ["#FF6FAE", "#63D9C7", "#54C9E8", "#F5C45E", "#A78BFA", "#F5F4F0", "#FF867C", "#79C991", "#70BCEB", "#C18B67"]
const OPTION_SCENE_PATHS := {
	"HATS": ["", "", "", "", "", "", "", "", "", ""],
	"MASKS": ["", "", "", "", "", "", "", "", "", ""],
	"BACK BLING": ["", "", "", "", "", "", "", "", "", "", "", ""],
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


## A random look for a computer player. About a third wear a full outfit
## (bot-only outfits included); the rest are Canvas Runners in a random suit
## colour, often with a hat and/or mask. Pass a seeded generator for a look
## that stays the same every time that bot respawns.
## Suit colours a bot on each team never wears, because they look like the
## OTHER team's colour from across the arena (team marks stay readable, but a
## whole red suit on a blue player is still confusing in a fight).
const TEAM_CLASH := {"BLUE": ["blood_red", "hot_pink"], "RED": ["electric_blue"]}


static func random_bot_customization(rng: RandomNumberGenerator, team: String = "") -> Dictionary:
	var data := create_session_data()
	data["gun_skin"] = rng.randi_range(0, GUN_SKINS.size() - 1)
	data["back_bling"] = rng.randi_range(0, BACK_BLING.size() - 1)
	var roll := rng.randf()
	if roll < 0.14:
		data["skin"] = str(BOT_SKINS[rng.randi_range(0, BOT_SKINS.size() - 1)].id)
	elif roll < 0.36:
		data["skin"] = str(SKINS[rng.randi_range(0, SKINS.size() - 1)].id)
	else:
		var allowed: Array = []
		for i in BODY_COLORS.size():
			if not str(BODY_COLORS[i].id) in TEAM_CLASH.get(team, []):
				allowed.append(i)
		data["body_color"] = allowed[rng.randi_range(0, allowed.size() - 1)]
		if rng.randf() < 0.6:
			data["hat"] = rng.randi_range(1, HATS.size() - 1)
		if rng.randf() < 0.35:
			data["mask"] = rng.randi_range(1, MASKS.size() - 1)
	return data


static func skin_by_id(skin_id: String) -> Dictionary:
	if skin_id == "default":
		return {"id": "default", "name": "CANVAS RUNNER", "allows_body_color": true, "allows_hat": true, "allows_mask": true, "allows_back_bling": true, "scene_path": "", "hides_head": false}
	for skin in SKINS:
		if skin.id == skin_id:
			return skin
	for skin in BOT_SKINS:
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


## Name of the model node for an option, e.g. ("HATS", 3) -> "Hat_BUCKET_HAT".
static func cosmetic_node(category: String, index: int) -> String:
	var lists := {"HATS": [HATS, "Hat_"], "MASKS": [MASKS, "Mask_"], "BACK BLING": [BACK_BLING, "Back_"]}
	if not lists.has(category):
		return ""
	var names: Array = lists[category][0]
	if index <= 0 or index >= names.size():
		return ""
	return str(lists[category][1]) + str(names[index]).replace(" ", "_")


static func option_scene_path(category: String, index: int) -> String:
	var paths: Array = OPTION_SCENE_PATHS.get(category, [])
	return str(paths[index]) if index >= 0 and index < paths.size() else ""


static func gun_material_path(index: int) -> String:
	return str(GUN_MATERIAL_PATHS[index]) if index >= 0 and index < GUN_MATERIAL_PATHS.size() else ""
