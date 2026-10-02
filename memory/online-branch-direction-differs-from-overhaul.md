# Rocklyn's `online` branch sets the gameplay; the overhaul supplies the look

History:
- 2026-10-01: Rocklyn's first online version reached `main` (PR #4) and was
  merged into `visual-ux-overhaul` (commit fe40c10): human-only matches,
  dedicated WebSocket server, tracer shots without splats, remote players
  with an `AimPivot` gun.
- 2026-10-01 (later): Rocklyn kept going on `origin/online` (afccd48): lobby
  browser, TDM rounds (random teams, 25 kills, 10 s intermission, 3 s
  respawn), 100 shield + 100 health with 4.4-damage bullets, flying power
  balls (Invisibility on right mouse, Sprayer, Rocket Launcher, Speed,
  2 Shot) replacing inheritance pickups, tall green trade stations, killer-
  chain spectating, a 135 m open-air arena, controller support, impact debris.

He rewrites the same files as the overhaul (menu.gd, tdm_match_controller.gd,
player.gd, projectile.gd, game.gd, hud.gd, arena.gd, healing_station.gd), so
every combine conflicts.

Why: twice now his branch moved while the overhaul was being built on an older
copy, and the overhaul's gameplay changes ended up competing with his.

How to apply: before touching any of those files, `git fetch` and look at
`origin/online` and `origin/main`. Follow
[[online-visual-merge-decisions]] for who wins a conflict. Keep presentation
code driven by lobby-record data so remote players can reuse it, and keep his
`AimPivot` behaviour if the remote model changes.
