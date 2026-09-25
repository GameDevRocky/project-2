extends RefCounted

## ============================================================================
## TRAITS - the data behind the Inheritance mechanic.
## ============================================================================
##
## This file holds no behaviour. It is a lookup table: a list of "pairs", where
## each pair is one ABILITY bolted to one WEAKNESS. You can never take an
## ability without also taking the weakness that comes with it, and taking a new
## pair throws your old pair away completely. That is the whole design.
##
## HOW THIS FILE IS USED
## Other scripts do NOT write `extends` or `new()` on this. They write:
##
##     const Traits = preload("res://scripts/traits.gd")
##     var pair: Dictionary = Traits.get_pair("sprayer")
##
## `preload` loads the file once when the game starts and hands back the script
## itself. Because the functions below are marked `static`, you can call them
## straight on the script without making an object first. Think of it as a
## reference book sitting on a shelf that anyone can open.
##
## WHY A DICTIONARY AND NOT A CLASS
## A Dictionary is GDScript's key/value store, written with curly braces.
## Looking up pair["damage_mult"] reads the value stored under that name. We use
## one because the pairs are pure data - numbers and text - and data like that
## is much easier to read, tweak and balance when it is all in one table you can
## scan with your eyes.
##
## NOTE ON class_name: this script deliberately does not declare one. A
## class_name registers a global name for the whole project, which could collide
## with a script Jadin or Rocklyn writes. preload avoids that.


# --- The art-direction palette, straight from the GDD -----------------------
# Color normally takes red/green/blue from 0.0 to 1.0 rather than 0-255, so
# these use Color's hex constructor instead, which accepts the same "#RRGGBB"
# string you would paste into an art tool.
const WHITE := Color("#FFFFFF")      ## Primary canvas
const PINK := Color("#FFB7C5")       ## Core pastel pink
const MINT := Color("#98FF98")       ## Core mint green
const TEAL := Color("#00A896")       ## Accent teal
const CHARCOAL := Color("#2B2D42")   ## Structural accent


## Every pair, keyed by a short id. The id is also the id of the enemy type that
## drops it, so killing a "sprayer" lets you inherit the "sprayer" pair.
##
## WHAT THE NUMBERS MEAN
## Anything ending in _mult is a MULTIPLIER applied to the player's base value.
## 1.0 means "no change", 2.0 means "twice as much", 0.5 means "half".
## Multipliers are used instead of flat numbers so that one balance change to a
## player base value automatically rebalances every pair along with it.
const PAIRS := {

	# ------------------------------------------------------------------------
	# The pair you start the run with. It is deliberately boring: every
	# multiplier is 1.0, so it changes nothing at all. That is the point - it
	# makes your first inheritance feel like a real decision instead of a
	# sidegrade, because you are trading "nothing" for "something with a cost".
	# ------------------------------------------------------------------------
	"apprentice": {
		"name": "Apprentice Brush",
		"color": WHITE,
		"ability_name": "Nothing yet",
		"ability_desc": "You have inherited no one. Go take something.",
		"weakness_name": "Nothing yet",
		"weakness_desc": "Also no drawbacks. Enjoy it while it lasts.",
		"fire_rate_mult": 1.0,
		"damage_mult": 1.0,
		"move_mult": 1.0,
		"jump_mult": 1.0,
		"taken_mult": 1.0,
		"splash_radius": 0.0,
		"splash_mult": 0.0,
		"regen": 0.0,
		"regen_delay": 99.0,
		"ammo_mult": 1.0,
		"ammo_regen_mult": 1.0,
	},

	# ------------------------------------------------------------------------
	# SPRAYER - the swarm-clearing pair.
	# Fires far faster but each glob is weak. 2.4 x 0.55 = 1.32, so it is only a
	# 32% damage-per-second gain overall. What you really buy is the ability to
	# hit fast-moving targets more often and to correct your aim mid-burst.
	# What you lose is any hope of punching through something armoured.
	# ------------------------------------------------------------------------
	"sprayer": {
		"name": "Sprayer's Pair",
		"color": PINK,
		"ability_name": "Rapid Brush",
		"ability_desc": "Fire rate x2.4",
		"weakness_name": "Thin Paint",
		"weakness_desc": "Damage per glob x0.55",
		"fire_rate_mult": 2.4,
		"damage_mult": 0.55,
		"move_mult": 1.0,
		"jump_mult": 1.0,
		"taken_mult": 1.0,
		"splash_radius": 0.0,
		"splash_mult": 0.0,
		"regen": 0.0,
		"regen_delay": 99.0,
		"ammo_mult": 1.0,
		"ammo_regen_mult": 1.0,
	},

	# ------------------------------------------------------------------------
	# BOUNDER - the high-risk mobility pair.
	# You become genuinely hard to hit, but anything that DOES land hurts 70%
	# more. This is the pair that is strongest in a careful player's hands and
	# most punishing in a reckless one's, which is exactly what a weakness
	# should do: change how you have to play, not just shrink a number.
	# ------------------------------------------------------------------------
	"bounder": {
		"name": "Bounder's Pair",
		"color": MINT,
		"ability_name": "Light Step",
		"ability_desc": "Move speed x1.45, jump x1.3",
		"weakness_name": "Brittle Canvas",
		"weakness_desc": "Damage taken x1.7",
		"fire_rate_mult": 1.0,
		"damage_mult": 1.0,
		"move_mult": 1.45,
		"jump_mult": 1.3,
		"taken_mult": 1.7,
		"splash_radius": 0.0,
		"splash_mult": 0.0,
		"regen": 0.0,
		"regen_delay": 99.0,
		"ammo_mult": 1.0,
		"ammo_regen_mult": 1.0,
	},

	# ------------------------------------------------------------------------
	# BLOTTER - the crowd-control pair.
	# Your globs burst on impact and splash everything nearby for 60% damage.
	# Superb against the tight packs that show up in later waves. The cost is
	# that you are slow and your paint refills at half speed, so you cannot
	# kite, and you have to make the shots count.
	# ------------------------------------------------------------------------
	"blotter": {
		"name": "Blotter's Pair",
		"color": TEAL,
		"ability_name": "Splatter Rounds",
		"ability_desc": "Globs burst for 60% splash in 3.2m",
		"weakness_name": "Heavy Reservoir",
		"weakness_desc": "Move speed x0.75, paint refills at half rate",
		"fire_rate_mult": 1.0,
		"damage_mult": 1.0,
		"move_mult": 0.75,
		"jump_mult": 1.0,
		"taken_mult": 1.0,
		"splash_radius": 3.2,
		"splash_mult": 0.6,
		"regen": 0.0,
		"regen_delay": 99.0,
		"ammo_mult": 1.0,
		"ammo_regen_mult": 0.5,
	},

	# ------------------------------------------------------------------------
	# MONOLITH - the tank pair, inherited from the toughest enemy in the game.
	# Halves incoming damage, which roughly doubles how long you survive. The
	# price is brutal: your fire rate is nearly halved, so fights take about
	# twice as long. It turns a fast fight you might lose into a slow fight you
	# probably win, which is a real strategic choice rather than a free buff.
	# ------------------------------------------------------------------------
	"monolith": {
		"name": "Monolith's Pair",
		"color": CHARCOAL,
		"ability_name": "Thick Coat",
		"ability_desc": "Damage taken x0.45",
		"weakness_name": "Sluggish Brush",
		"weakness_desc": "Fire rate x0.55",
		"fire_rate_mult": 0.55,
		"damage_mult": 1.0,
		"move_mult": 1.0,
		"jump_mult": 1.0,
		"taken_mult": 0.45,
		"splash_radius": 0.0,
		"splash_mult": 0.0,
		"regen": 0.0,
		"regen_delay": 99.0,
		"ammo_mult": 1.0,
		"ammo_regen_mult": 1.0,
	},

	# ------------------------------------------------------------------------
	# GHOST - the attrition pair.
	# You heal back up between fights instead of slowly bleeding out over a run,
	# which matters enormously in a wave game. The cost is that your paint
	# reservoir is halved, so you cannot hold the trigger down - you run dry
	# mid-fight and have to break away and wait.
	# ------------------------------------------------------------------------
	"ghost": {
		"name": "Ghost's Pair",
		"color": WHITE,
		"ability_name": "Second Wind",
		"ability_desc": "Regain 7 health/sec after 3s unhurt",
		"weakness_name": "Faded Pigment",
		"weakness_desc": "Paint capacity x0.5",
		"fire_rate_mult": 1.0,
		"damage_mult": 1.0,
		"move_mult": 1.0,
		"jump_mult": 1.0,
		"taken_mult": 1.0,
		"splash_radius": 0.0,
		"splash_mult": 0.0,
		"regen": 7.0,
		"regen_delay": 3.0,
		"ammo_mult": 0.5,
		"ammo_regen_mult": 1.0,
	},
}


## Hand back one pair by id. `static` means you call this on the script itself
## (Traits.get_pair("ghost")) instead of having to create an object first.
##
## If the id is not in the table we fall back to the starting pair rather than
## crashing. A typo in an enemy's id should make the game slightly wrong, not
## dead - that is much easier to notice and fix than a hard crash mid-wave.
static func get_pair(id: String) -> Dictionary:
	if PAIRS.has(id):
		return PAIRS[id]
	push_warning("Traits.get_pair: no pair with id '%s', using apprentice." % id)
	return PAIRS["apprentice"]


## The id the player starts every run with.
static func starting_id() -> String:
	return "apprentice"
