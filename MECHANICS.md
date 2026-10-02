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
| Zoom (Fine Liner only) | Hold right mouse |
| Look | Mouse movement |
| **Inherit a core** | `E` while standing near it |
| Pause menu (Resume / Leave Match) | `Esc` |
| Return to menu after Survival ends | `R` |
| Hold the TDM scoreboard | `Tab` |
| While waiting to respawn (TDM): switch teammate / first-third person | `Q` `E` / `V` |
| While waiting to respawn (TDM): pick a gun | `1`–`5` or click a card |

## Game modes

Both modes are **online and human-only** (merged from `main` on 2026-10-01,
Rocklyn's online branch). **PLAY** → pick a mode → **CREATE LOBBY** (you get a
five-letter code) or type a friend's code and **JOIN**. The host presses
**START MATCH**. A dedicated Godot server (`scripts/net/network_session.gd`,
run with `-- --server`) owns lobbies, teams, health, scores, eliminations and
respawns; each client reports its own shots and hits.

- **Team Death Match** — RED versus BLUE, ten minutes, most eliminations wins.
  When you are painted out you wait **10 seconds** to respawn. Meanwhile you
  **spectate a living teammate** in third person (behind their shoulder) or
  first person (from their eyes, with their gun on screen) — `Q`/`E` switch
  teammate, `V` switches view; with no teammate alive the camera circles where
  you fell. The same screen holds the **loadout**: pick one of five guns and you
  respawn with it.
- **Survival** — free-for-all, one life each, last player standing wins.

`Esc` opens the **pause menu** in both modes (RESUME / LEAVE MATCH). An online
match cannot stop for one player, so pausing frees your mouse and ignores your
own keys until you resume; the world keeps going and the menu says so.

The offline paths (Survival's six PvE waves, TDM's local bot teams) are still
in `game.gd` / `enemy.gd` but nothing reaches them any more: `game.gd` sends you
back to the menu unless you are in an online match.

## Loadout (TDM)

Everyone starts a match with the Brush Rifle. Pick a gun on the death screen;
it is equipped when you respawn. Numbers live in `scripts/weapons.gd`, and the
inherited pair still multiplies them (damage, fire rate, tank size, refill).

| # | Gun | Role | Effect |
| --- | --- | --- | --- |
| 1 | **Brush Rifle** | Assault rifle | The original Paint Blaster: 22 damage, 0.28 s, 30 paint. Unchanged. |
| 2 | **Fine Liner** | Sniper | 85 damage, one shot per 1.3 s, 5 paint. Hold right mouse to zoom (scope overlay, slower turning); a little spread unless zoomed. |
| 3 | **Prism Beam** | Energy gun | 9 damage bolts every 0.085 s in rainbow colours. No paint: a charge that, emptied, **overheats** and locks until fully recharged. |
| 4 | **Splat Bucket** | Shotgun | 8 droplets × 10 damage in a 7° cone, short range (~27 m), 6 loads. |
| 5 | **Blob Lobber** | Launcher | Heavy blobs that **arc** under gravity and burst (4.5 m splash), 50 damage, 4 loads. |

Each shot tells the server which gun fired it, so other players see the right
gun in your hands and the right shot (pellets, arc, rainbow bolts).

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

With the Brush Rifle your reservoir holds 30 and refills at 11/sec, starting
0.6s after your last shot (other guns: see the loadout table above). Hold the trigger down and you run dry; break contact for a moment and it
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
| **Match scene** | `scripts/game.gd` | Builds the arena and local player, then hands an online match to the controller (its offline wave code is unreachable for now) |
| **Survival UX** | `scripts/hud.gd` | Survival HUD (players-alive pill) and end panel |
| **TDM UX** | `scripts/tdm_match_controller.gd` → `scripts/ui/tdm_hud.gd`, `tdm_scoreboard.gd` | The controller owns every TDM number and creates the HUD; the HUD files only draw (score/timer pill, kill feed, crosshair, health, paint tank, pair card, death screen, scope, Tab scoreboard, result panel) |
| **Shared UI** | `scripts/ui/ui_theme.gd`, `scripts/ui/widgets/` | One theme and the HUD widgets used by menu, Survival HUD and TDM HUD. Read-only views of player/controller state |
| **Presentation** | `scripts/visual/`, `models/generated/` | Combatant/core/station/arena models, effects, surface shader. Visual children only — never collision, never gameplay numbers |
| **Model sources** | `tools/blender/` | Blender Python scripts that generate `models/generated/*.glb` (`tools/blender/build_all.sh`) |
| **Networking** | `scripts/net/network_session.gd`, `scripts/net/remote_player.gd` (Rocklyn) | Lobbies, teams, health, scores, eliminations, respawns (server); other players' synced bodies |
| **Online match** | `scripts/tdm_match_controller.gd` | Both online modes: turns network events into actors and HUD updates; spectating and the picked gun while dead; pause menu |
| **Loadout data** | `scripts/weapons.gd` | The five guns' numbers and effects |
| **Pause / death screen** | `scripts/ui/pause_menu.gd`, `scripts/ui/death_screen.gd`, `scripts/spectator_camera.gd` | Draw and report clicks; the controller decides |

The dedicated server is the authority for match state. The match controller
only mirrors it; the HUD files only draw.

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

Matches are online-only now, so most testing runs a **local copy of the
server** plus test clients on this computer (never the live server):

| Tool | What it checks |
| --- | --- |
| `tools/tests/run_online_checklist.sh` | Starts a local server and three clients (`online_checklist.gd`): menu → lobby → TDM match, shooting, scores, 10 s respawns, the death screen, spectating (third/first person), loadout picks, other players seeing your new gun, the pause menu, LEAVE MATCH. `MODE=survival` runs the Survival version; `WINDOWED=host SHOTS=<dir>` saves screenshots |
| `weapons_checklist.gd` | All five guns against a practice dummy, no server: damage, pellets, zoom, overheat, arc, splash, range |
| `parse_all.gd` | Compiles every script with the autoloads loaded (`--check-only` alone wrongly reports `NetworkSession` as missing) |
| `model_viewer.gd` | The generated models under in-game lighting (windowed) |

Run the `.gd` tools with
`godot --headless --path . --script res://tools/tests/<name>.gd`.

The older tools (`survival_checklist.gd`, `tdm_checklist.gd`, `tdm_probe.gd`,
`menu_flow_probe.gd`, `perf_probe.gd`, `screenshots.gd`, and
`tools/autoplay.gd`) drive the OFFLINE Survival waves and bot TDM, which the
game no longer reaches since `main` went online-only. They are kept until the
team decides whether those offline modes come back.
