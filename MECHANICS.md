# Paint Strike: Glowfall - Online Mechanics

The `online` branch is a browser multiplayer shooter backed by a dedicated
Godot WebSocket server. Matches contain human players only.

## Controls

| Action | Keyboard and mouse | Controller |
| --- | --- | --- |
| Move | `W` `A` `S` `D` | Left stick |
| Look | Mouse | Right stick |
| Jump | `Space` | South button |
| Fire | Left mouse | Right trigger |
| Toggle invisibility | Right mouse | Left shoulder |
| Use a trade station | Hold `E` | Hold west button |
| Release mouse | `Esc` | - |

## Match modes

- **Survival:** every player fights every other player. Eliminated players
  spectate their killer and follow the killer chain if that player dies.
- **Team Deathmatch:** players are split evenly and randomly between red and
  blue each round. The first team to 25 kills wins. Players respawn after three
  seconds with full health and shield.
- Matches with fewer than two players return to the menu. A team round ends if
  one team becomes empty. A new round starts after a ten second intermission.

## Vitality and weapons

Every player starts with 100 shield and 100 health. Damage removes shield first.
Ordinary paint bullets deal 4.4 damage, which is 80% below the earlier 22 damage
value. Projectiles are raycast between physics frames so fast shots cannot pass
through thin geometry.

## Flying power balls

At the beginning of each round the server creates one flying ball for every
power. Their paths, health, destruction, and ownership are server controlled and
synchronized to all clients. A ball has 35 health. The player who destroys it
receives its power. If that player already held a power, the replaced power is
released back into the arena as another ball.

Power definitions live in `scripts/power_abilities.gd` so future abilities can
be added without adding another inventory or networking path.

| Power | Effect |
| --- | --- |
| Invisibility | Right mouse or left shoulder toggles it. The player remains collidable and damageable but cannot shoot while hidden. |
| Sprayer | Fires 2.5 times faster. |
| Rocket Launcher | Fires slower rockets with a seven metre blast, large sparks, splash falloff, and close range self damage. |
| Speed | Doubles movement speed. |
| 2 Shot | Deals 100 damage per shot with a slower fire rate, so two direct hits remove a full 100 shield plus 100 health. |

A glowing halo in the power's color appears above every visible powered player.

## Trade stations

Two stations are placed in opposite buildings. A player carrying a power can
hold `E` without moving or taking damage to trade it. The server then restores
that player to 100 health and 100 shield, removes the power, and creates a new
ball containing the traded power above that station.

## Authority boundaries

| System | Owner |
| --- | --- |
| Lobbies, teams, health, shield, powers, ball paths, ball damage, scoring, respawns, and trades | `scripts/net/network_session.gd` on the dedicated server |
| Local movement, shooting, first person weapon, and input | `scripts/player.gd` |
| Remote human actors and smoothing | `scripts/net/remote_player.gd` |
| Projectile flight and effects | `scripts/projectile.gd` |
| Flying ball visuals and interpolation | `scripts/flying_power_ball.gd` |
| Match actors, spectator flow, and online HUD | `scripts/tdm_match_controller.gd` |

The public browser build is published at
`https://gamedevrocky.github.io/project-2/online/`.
