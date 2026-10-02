extends RefCounted

## One data table drives player tuning, server validation, HUD copy, halos, and
## Snitch Ball visuals. Adding another power only requires another entry here;
## the networking and pickup systems iterate ORDER automatically.

const ORDER: Array[String] = [
	"invisibility", "sprayer", "rocket_launcher", "speed", "two_shot",
]

const BASE_DAMAGE := 4.4

const POWERS := {
	"invisibility": {
		"name": "INVISIBILITY",
		"description": "Right click / LB toggles invisibility. You cannot shoot while hidden.",
		"color": Color("#B9F7FF"),
		"damage": BASE_DAMAGE,
		"fire_interval": 0.28,
		"move_mult": 1.0,
		"projectile_speed": 90.0,
		"projectile_kind": "bullet",
		"splash_radius": 0.0,
		"splash_mult": 0.0,
	},
	"sprayer": {
		"name": "SPRAYER",
		"description": "Fires paint rounds 2.5 times faster.",
		"color": Color("#54F08B"),
		"damage": BASE_DAMAGE,
		"fire_interval": 0.112,
		"move_mult": 1.0,
		"projectile_speed": 90.0,
		"projectile_kind": "bullet",
		"splash_radius": 0.0,
		"splash_mult": 0.0,
	},
	"rocket_launcher": {
		"name": "ROCKET LAUNCHER",
		"description": "Launches explosive rockets. Their blast can hurt you up close.",
		"color": Color("#FF9B42"),
		"damage": 90.0,
		"fire_interval": 1.2,
		"move_mult": 1.0,
		"projectile_speed": 52.0,
		"projectile_kind": "rocket",
		"splash_radius": 7.0,
		"splash_mult": 1.0,
	},
	"speed": {
		"name": "SPEED",
		"description": "Doubles movement speed.",
		"color": Color("#FFE35B"),
		"damage": BASE_DAMAGE,
		"fire_interval": 0.28,
		"move_mult": 2.0,
		"projectile_speed": 90.0,
		"projectile_kind": "bullet",
		"splash_radius": 0.0,
		"splash_mult": 0.0,
	},
	"two_shot": {
		"name": "2 SHOT",
		"description": "Each shot removes half of a fully charged player's total vitality.",
		"color": Color("#F062FF"),
		"damage": 100.0,
		"fire_interval": 0.9,
		"move_mult": 1.0,
		"projectile_speed": 100.0,
		"projectile_kind": "bullet",
		"splash_radius": 0.0,
		"splash_mult": 0.0,
	},
}


static func get_power(id: String) -> Dictionary:
	if not POWERS.has(id):
		return {}
	return (POWERS[id] as Dictionary).duplicate(true)


static func is_valid(id: String) -> bool:
	return POWERS.has(id)


static func color_for(id: String) -> Color:
	return get_power(id).get("color", Color.WHITE)

