# Rocklyn's `online` branch heads a different way from the visual overhaul

As of 2026-10-01, teammate Rocklyn Clarke's `online` branch (browser
multiplayer, not yet on main) decides, in its own memory notes:
- online modes are humans only: no bots, no simulated lobby fill;
- projectiles become small fast tracers (90 m/s) with NO impact splats;
- remote players show a third-person paintbrush rifle under an `AimPivot`
  that follows synced yaw/pitch;
- it rewrites menu.gd, tdm_match_controller.gd, player.gd, projectile.gd
  and game.gd heavily (`scripts/net/network_session.gd`, `remote_player.gd`).

The `visual-ux-overhaul` branch changes the same five files, so merging the
two will conflict.

Why: found while merging main into visual-ux-overhaul; Jarman asked only for
main, so online was not merged.

How to apply: before touching any of those five files, check whether online
has landed on main (`git log origin/main`). Keep presentation code driven by
lobby-record data (`record.customization`) so remote players can reuse it.
When the branches meet, ask Jarman (and Rocklyn) which projectile look wins
rather than picking one. See [[jcodes-files-are-open-for-the-visual-overhaul]].
