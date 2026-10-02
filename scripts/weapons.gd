extends RefCounted

## ============================================================================
## WEAPONS - the five guns you can pick from the loadout screen.
## ============================================================================
##
## Like traits.gd, this file is a lookup table and holds no behaviour. Other
## scripts write:
##
##     const Weapons = preload("res://scripts/weapons.gd")
##     var gun: Dictionary = Weapons.get_weapon(2)
##
## A gun is chosen in Team Deathmatch while you wait to respawn (the death
## screen in scripts/ui/death_screen.gd) and is equipped when you respawn.
## Everyone starts a match with the BRUSH RIFLE.
##
## HOW THE NUMBERS COMBINE WITH YOUR INHERITED PAIR
## The pair (traits.gd) still multiplies everything: a gun says "my shots do 85
## damage", and the pair's damage_mult scales that, exactly as it scaled the old
## single gun's base_damage. So the Brush Rifle below, with every number equal
## to the old player.gd base values, plays exactly like the gun did before.
##
## WHAT EACH KEY MEANS
##   id, name, role, blurb  what the loadout screen shows
##   damage        health removed by one direct hit (per pellet for the bucket)
##   interval      seconds between shots (smaller = faster)
##   ammo          how much the tank holds
##   cost          how much of the tank one shot uses
##   regen         tank refilled per second, once `regen_delay` has passed
##   speed         projectile metres per second (the server allows at most 120)
##   life          seconds a shot flies before vanishing (sets the range)
##   pellets       projectiles per shot; spread is the cone they fan out in
##   spread        degrees of random aim wobble (0 = perfectly accurate)
##   zoom_spread   the wobble while zoomed (only guns with zoom_fov use it)
##   zoom_fov      field of view while holding right mouse; 0 = cannot zoom
##   gravity       downward pull on the shot (0 = flies straight)
##   splash_radius, splash_mult  a burst on impact (combined with the pair's)
##   overheat      true = the tank is HEAT CHARGE: run it dry and the gun locks
##                 until it is completely recharged
##   bullet, trail, trail_width  how the shot looks in flight (metres)
##   rainbow       true = each shot takes the next colour of the rainbow
##   model         the generated model (models/generated/<model>.glb and
##                 <model>_prop.glb for the copy other players see)
##   view_offset   nudges the first-person model so it sits well on screen
##   bars          0..1 ratings drawn on the loadout card: damage, rate, range

const BRUSH_RIFLE := 0
const FINE_LINER := 1
const PRISM_BEAM := 2
const SPLAT_BUCKET := 3
const BLOB_LOBBER := 4

const WEAPONS := [
	{
		"id": "brush_rifle", "name": "BRUSH RIFLE", "role": "ASSAULT RIFLE",
		"blurb": "The trusty Paint Blaster. Full-auto, steady and reliable at any range.",
		"damage": 22.0, "interval": 0.28, "ammo": 30.0, "cost": 1.0,
		"regen": 11.0, "regen_delay": 0.6, "speed": 90.0, "life": 4.0,
		"pellets": 1, "spread": 0.0, "zoom_spread": 0.0, "zoom_fov": 0.0, "gravity": 0.0,
		"splash_radius": 0.0, "splash_mult": 0.0, "overheat": false,
		"bullet": 0.06, "trail": 1.15, "trail_width": 0.022, "rainbow": false,
		"model": "paint_blaster", "view_offset": Vector3.ZERO,
		"bars": [0.35, 0.55, 0.7],
	},
	{
		"id": "fine_liner", "name": "FINE LINER", "role": "SNIPER",
		"blurb": "A giant ink pen. Hold RIGHT MOUSE to zoom; two clean lines paint anyone out.",
		"damage": 85.0, "interval": 1.3, "ammo": 5.0, "cost": 1.0,
		"regen": 1.0, "regen_delay": 1.2, "speed": 120.0, "life": 3.0,
		"pellets": 1, "spread": 3.5, "zoom_spread": 0.0, "zoom_fov": 32.0, "gravity": 0.0,
		"splash_radius": 0.0, "splash_mult": 0.0, "overheat": false,
		"bullet": 0.045, "trail": 4.0, "trail_width": 0.018, "rainbow": false,
		"model": "weapon_fine_liner", "view_offset": Vector3(-0.02, 0.0, -0.12),
		"bars": [0.95, 0.12, 1.0],
	},
	{
		"id": "prism_beam", "name": "PRISM BEAM", "role": "ENERGY GUN",
		"blurb": "Splits light into rainbow bolts. No paint to run out of - but empty the charge and it overheats.",
		"damage": 9.0, "interval": 0.085, "ammo": 100.0, "cost": 6.0,
		"regen": 45.0, "regen_delay": 0.3, "speed": 120.0, "life": 2.5,
		"pellets": 1, "spread": 0.8, "zoom_spread": 0.0, "zoom_fov": 0.0, "gravity": 0.0,
		"splash_radius": 0.0, "splash_mult": 0.0, "overheat": true,
		"bullet": 0.04, "trail": 2.4, "trail_width": 0.016, "rainbow": true,
		"model": "weapon_prism_beam", "view_offset": Vector3.ZERO,
		"bars": [0.2, 1.0, 0.75],
	},
	{
		"id": "splat_bucket", "name": "SPLAT BUCKET", "role": "SHOTGUN",
		"blurb": "Flings a fistful of paint droplets. Devastating up close, useless far away.",
		"damage": 10.0, "interval": 0.85, "ammo": 6.0, "cost": 1.0,
		"regen": 2.5, "regen_delay": 0.8, "speed": 75.0, "life": 0.36,
		"pellets": 8, "spread": 7.0, "zoom_spread": 0.0, "zoom_fov": 0.0, "gravity": 0.0,
		"splash_radius": 0.0, "splash_mult": 0.0, "overheat": false,
		"bullet": 0.05, "trail": 0.45, "trail_width": 0.02, "rainbow": false,
		"model": "weapon_splat_bucket", "view_offset": Vector3.ZERO,
		"bars": [0.85, 0.3, 0.2],
	},
	{
		"id": "blob_lobber", "name": "BLOB LOBBER", "role": "LAUNCHER",
		"blurb": "Lobs heavy paint blobs in an arc that burst on impact. Aim high to reach far.",
		"damage": 50.0, "interval": 1.0, "ammo": 4.0, "cost": 1.0,
		"regen": 0.9, "regen_delay": 1.0, "speed": 34.0, "life": 4.0,
		"pellets": 1, "spread": 0.0, "zoom_spread": 0.0, "zoom_fov": 0.0, "gravity": 16.0,
		"splash_radius": 4.5, "splash_mult": 0.8, "overheat": false,
		"bullet": 0.17, "trail": 0.5, "trail_width": 0.07, "rainbow": false,
		"model": "weapon_blob_lobber", "view_offset": Vector3.ZERO,
		"bars": [0.75, 0.2, 0.55],
	},
]


static func count() -> int:
	return WEAPONS.size()


## The gun at `index`, wrapped into range so a bad number can never crash.
static func get_weapon(index: int) -> Dictionary:
	return WEAPONS[posmod(index, WEAPONS.size())]


## Turns a direction into a slightly random one inside a cone `degrees` wide.
## Used for spread (the Fine Liner unzoomed, the Prism Beam) and for the
## Splat Bucket's pellets.
static func spread_direction(direction: Vector3, degrees: float, rng: RandomNumberGenerator = null) -> Vector3:
	if degrees <= 0.0:
		return direction.normalized()
	var forward := direction.normalized()
	# Any vector not parallel to `forward` gives a sideways axis to tilt about.
	var side := forward.cross(Vector3.UP if absf(forward.y) < 0.98 else Vector3.RIGHT).normalized()
	var r1 := rng.randf() if rng != null else randf()
	var r2 := rng.randf() if rng != null else randf()
	# sqrt keeps the shots spread evenly over the cone instead of bunching in
	# the middle.
	var tilt := deg_to_rad(degrees) * 0.5 * sqrt(r1)
	var spin := TAU * r2
	return forward.rotated(side, tilt).rotated(forward, spin).normalized()


## Sets how a shot from `weapon` flies and looks: its range, its arc and the
## size of its bullet and trail. Used for your own shots AND for the copies of
## other players' shots, so both look the same.
static func apply_to_shot(glob, weapon: Dictionary) -> void:
	glob.life = float(weapon.life)
	glob.gravity = float(weapon.gravity)
	glob.bullet_radius = float(weapon.bullet)
	glob.trail_length = float(weapon.trail)
	glob.trail_radius = float(weapon.trail_width)


## The colour of the Prism Beam's `shot_number`th bolt: around the rainbow in
## seven steps, kept pastel to match the art direction.
static func rainbow_color(shot_number: int) -> Color:
	return Color.from_hsv(fmod(float(shot_number) / 7.0, 1.0), 0.55, 1.0)
