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
| **Inherit a core** | `E` while standing near it |
| Release / recapture mouse | `Esc` / click |
| Restart after a run ends | `R` |

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

A 46m square with deliberate cover: four tall pillars that break line of sight,
four mid blocks that break up the long wall runs, four low corner blocks, and a
jumpable platform in the middle that trades sightlines for exposure. The layout
is fixed, never randomised — dying should teach you the room.

## The three systems

| System | Lives in | Owns |
| --- | --- | --- |
| **Game logic** | `scripts/game.gd` | Waves, spawning, the inherit offer, win/loss |
| **UX** | `scripts/hud.gd` | Everything drawn on top of the 3D world |
| **Multiplayer** | *Cut #1 — not in this build* | — |

Both seams run **one way only**. `game.gd` calls into the HUD; the HUD never
calls back. `game.gd` spawns the player and enemies; they report back only by
signal. A bug in the HUD can make the game look wrong but never behave wrong.

The multiplayer seam would attach at `_spawn_enemy()` in `game.gd`, which is
deliberately the only place in the project that invents new world state.

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
