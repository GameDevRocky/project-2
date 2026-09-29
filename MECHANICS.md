# Project 2: Inheritance — Mechanics

A first-person paint-shooter. Hunt enemies, inherit one defeated enemy's ability
and weakness **in place of** your current pair, and use that combination to take
on tougher targets.

Open the project in Godot 4.7 and press **F5**.

## Controls

| Action | Key |
| --- | --- |
| Move | `W` `A` `S` `D` |
| Jump | `Space` |
| Fire paint | Left mouse |
| Look | Mouse movement |
| **Inherit a core** | `E` while standing near it |
| Release / recapture mouse | `Esc` / click |
| Restart after a run ends | `R` |
| Hold the TDM scoreboard | `Tab` |

## Game modes

**PLAY** opens the game-mode screen. The modes are separate:

- **Team Death Match** fills two local simulated teams of ten, counts down,
  then starts a ten-minute match. Team kills score points. The local player and
  bots use the shared paint projectile and damage path. Bots target the other
  team, respawn after three seconds, and update kills, deaths, and assists.
  Holding `Tab` shows the live roster scoreboard. At `00:00`, the higher team
  kill total wins (equal totals draw).
- **Survival** starts the original six-wave run directly. Its waves, enemy
  archetypes, inheritance, and Survival HUD remain on the existing path.

The menu passes generic lobby records and the selected mode into `game.gd`.
`game.gd` keeps Survival orchestration and starts
`scripts/tdm_match_controller.gd` only for TDM. TDM bots are adapted from
`scripts/enemy.gd`; `scripts/projectile.gd` remains the shared paint projectile.
This is local simulation, not networking.

## The core loop

1. A wave spawns around the edge of the arena.
2. You kill an enemy. It drops a glowing **paint core** in its own colour.
3. Press `E` near that core to inherit its pair.
4. Clear all six waves.

## Inheritance

This is the whole game. Every pair is **one ability bolted to one weakness**, and
you can never take one half without the other. Inheriting **replaces** your
current pair — the old ability is gone.

You start with the **Apprentice Brush**, which does nothing at all: no ability,
no weakness. That is deliberate. It means your first inheritance is a real
decision rather than a free upgrade.

| Dropped by | Ability | Weakness |
| --- | --- | --- |
| **Sprayer** (pink) | Rapid Brush — fire rate ×2.4 | Thin Paint — damage ×0.55 |
| **Bounder** (mint) | Light Step — move ×1.45, jump ×1.3 | Brittle Canvas — damage taken ×1.7 |
| **Blotter** (teal) | Splatter Rounds — globs burst for 60% splash in 3.2m | Heavy Reservoir — move ×0.75, half refill rate |
| **Monolith** (charcoal) | Thick Coat — damage taken ×0.45 | Sluggish Brush — fire rate ×0.55 |
| **Ghost** (white) | Second Wind — regain 7 health/sec after 3s unhurt | Faded Pigment — half paint capacity |

Nothing here is strictly best. Rapid Brush shreds swarms but cannot punch through
a Monolith. Thick Coat roughly doubles how long you survive but makes every fight
take twice as long. Light Step makes you very hard to hit and very easy to kill.

**Cores expire after 14 seconds.** You commit to a pair while the fight is still
going, rather than clearing the room and shopping at leisure.

## Enemies

Each archetype fights the way its dropped pair plays, so you already know what
taking it will feel like before you take it.

- **Sprayer** — fast trigger, weak globs, dies quickly.
- **Bounder** — no gun. Rushes you, hits, then withdraws for about a second
  before coming in again. That withdrawal is your window.
- **Blotter** — slow artillery. Lobs splashing paint from range. You cannot
  out-strafe the splash, so you have to go deal with it.
- **Monolith** — takes 45% less damage and hits hard, but is slow enough that you
  can always disengage. This is the "tougher target" the loop is pointing at.
- **Ghost** — heals itself if you stop shooting it, so chip damage is worthless.

**Enemies aim at where you are, never where you are going.** Strafing is
therefore a reliable dodge, and it is the main thing that keeps the game hard
rather than unfair.

## Paint

Your reservoir holds 30 and refills at 11/sec, starting 0.6s after your last
shot. Hold the trigger down and you run dry; break contact for a moment and it
comes back. The Sprayer pair spends paint almost exactly as fast as it returns,
so rapid fire is a sustain problem as well as a damage one.

## Waves and difficulty

Six waves. Each introduces at most one new archetype, so you always get a wave to
learn something in before it appears in a mix. The Monolith does not show up
until wave 4, by which point you have had three chances to pick up something that
handles it.

Clearing a wave heals you **+40** and gives a 5-second breather. Enemy health
scales **+6% per wave** — the difficulty is meant to come from the enemy mix and
from the pair you are carrying, not from bullet sponges.

## Arena

A fixed 90m square arena built around a central hub, three enterable buildings,
multiple side routes, and a recessed southern lane with ramps at both ends. The
southwest building has a reachable upper firing floor; the central platform
offers exposed high ground with a long sightline. Four Healing Stations sit in the northwest
and northeast buildings, on the southwest upper floor, and along the lower route.
The layout
is fixed, never randomised — dying should teach you the room.

## Current code boundaries

| System | Lives in | Owns |
| --- | --- | --- |
| **Survival game logic** | `scripts/game.gd` | Waves, Survival spawning, inherit offer, Survival endings |
| **TDM match state** | `scripts/tdm_match_controller.gd` | Lobby roster, teams, TDM bot spawning, score, timer, respawn, scoreboard/results |
| **Survival UX** | `scripts/hud.gd` | Survival HUD and Survival end panel |
| **TDM UX** | `scripts/tdm_match_controller.gd` | TDM score/timer HUD, live scoreboard, TDM result panel |
| **Networking** | Not implemented | Replace local simulated lobby records and bot actors with session-backed player records/actors later |

The offline TDM controller is the current authority for TDM-only match state.
Do not route Survival through that controller. A future online session should
replace the local lobby population and authority layer, while keeping the menu
and scoreboard data contracts generic.

## Snitch mechanics handoff (implementation stub)

**Status:** Snitch Ball behavior is not implemented in this checkout. No Snitch
script or scene currently exists. The Healing Station already exposes the
integration seam below; keep its implementation unchanged when adding Snitch
behavior.

### Existing handoff contract

`scripts/healing_station.gd` declares:

```gdscript
signal power_traded(power_type: Variant, player: Node3D, station: Node3D)
```

The station emits this only after the interaction completes, its player power
API confirms consumption, and the station heals the player. The signal is not
emitted for the current healing-only fallback. `require_power_to_trade` defaults
to `false`, so stations remain usable while the player power API is being built.

The station expects the eventual player power API to provide:

```gdscript
has_current_power() -> bool
get_current_power_type() -> Variant
can_trade_power_at_station() -> bool
try_consume_power_for_station() -> bool
```

The player is responsible for owning/consuming its power. The station does not
store powers or decide Snitch pickup effects.

### Suggested implementation seam

Add a small `SnitchBallSystem` (or equivalent manager) and a reusable
`SnitchBall` scene/script. In `game.gd::_build_healing_station()`, connect each
station's `power_traded` signal to the manager. Suggested responsibilities:

```gdscript
SnitchBallSystem.register_station(station: Node3D) -> void
SnitchBallSystem._on_station_power_traded(
    power_type: Variant, player: Node3D, station: Node3D
) -> void
SnitchBall.setup(power_type: Variant, system: Node) -> void
SnitchBall.collect(player: Node3D) -> void
```

These are design stubs, not existing methods. The manager should spawn one ball
with the surrendered power type at the emitting station; the ball should accept
only a valid player pickup and report collection once. Use the future shared
power data/API rather than adding a second power inventory to the Snitch. Before
implementing the pickup result, confirm the intended GDD rule for what collecting
the ball does; that rule is not specified by the current code. Also confirm
whether the mechanic is enabled in both modes or Survival only.

### Integration and validation checklist for the next contributor

1. Read this section and inspect `healing_station.gd`, `player.gd`, and the
   current power data/API before editing.
2. Leave `healing_station.gd` and `arena.gd` unchanged unless a concrete API
   mismatch makes a minimal change necessary; prefer connecting its existing
   signal from `game.gd`.
3. Keep ball ownership and power types data-driven. Do not add online/network
   assumptions or a second player power store.
4. Verify a successful trade emits once with the correct power/player/station;
   a canceled, interrupted, or unavailable-power interaction emits no ball.
5. Verify pickup is one-shot, the intended power result is applied, the ball
   cleans up, station cooldown still works, and Survival behavior is preserved.

## Testing

The game can be driven without a human at the keyboard:

```
GODOT="C:/Users/jlion/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --headless --path . --quit-after 18000 -- --autoplay
```

`tools/autoplay.gd` fakes a player — aims, burst-fires, strafes, grabs cores —
and prints a trace of every wave, kill and inheritance. It is only created when
that flag is passed. Use `--verbose` for the logging without the bot.

The bot is deliberately mediocre and dies around wave 3–4 of 6. That is the
tuning target, not a bug.
