# Memory index

One line per note. Read this file at the start of every session.

- [godot-mcp-tools-not-connected.md](godot-mcp-tools-not-connected.md) — the
  godot_mcp addon is installed in the project but is not registered with Claude
  Code, so the Godot tools are unavailable until that is set up.
- [enemy-contact-damage-current-speed.md](enemy-contact-damage-current-speed.md) — on
  contact, the square with the greater *current* speed wins; standing still
  always loses.
- [godot-cli-runs-the-game-headless.md](godot-cli-runs-the-game-headless.md) —
  where the Godot 4.7.2 exe is and the two commands that parse-check a script
  and run the game headless, so changes get tested without the MCP tools; also
  how to call it from WSL and how to take screenshots for visual changes.
- [gdscript-colon-equals-needs-a-known-type.md](gdscript-colon-equals-needs-a-known-type.md)
  — `:=` errors on a property one script added to another; write `: float` etc.
  by hand instead.
- [autoplay-harness-tests-the-game-headless.md](autoplay-harness-tests-the-game-headless.md)
  — tools/autoplay.gd fakes a player so headless runs actually test combat;
  the command line, and how to probe whether the game is completable.
- [never-gate-gameplay-on-display-server-state.md](never-gate-gameplay-on-display-server-state.md)
  — reading Input.mouse_mode back to decide if firing is allowed broke all
  shooting headless; keep the rule in the game, push it outward.
- [fire-from-the-muzzle-toward-the-crosshair.md](fire-from-the-muzzle-toward-the-crosshair.md)
  — shots spawned at the offset muzzle must aim at the crosshair's hit point,
  or they land beside the target at every range.
- [jolt-rejects-non-uniform-body-scale.md](jolt-rejects-non-uniform-body-scale.md)
  — squash the MeshInstance3D in death animations, never the physics body.
- [github-pages-web-export-config.md](github-pages-web-export-config.md) —
  export_presets.cfg + the deploy-pages.yml workflow are already set up; how
  to flip on Pages and where the live link is; the web build's renderer DOES
  do glow (simplified).
- [compatibility-renderer-brightens-shadowed-sun.md](compatibility-renderer-brightens-shadowed-sun.md)
  — the web renderer draws a shadow-casting sun ~2.7x brighter than desktop;
  arena.gd lowers it to 0.25 there; check both renderers after lighting changes.
- [browser-multiplayer-target.md](browser-multiplayer-target.md) — the shipped
  multiplayer client runs from GitHub Pages and requires browser networking plus
  an external service.
- [human-only-pvp-modes.md](human-only-pvp-modes.md) — online matches contain
  human players only; TDM is RED versus BLUE and Survival replaces the PvE wave path.
- [remote-player-weapon-sync.md](remote-player-weapon-sync.md) — remote players
  need a visible rifle whose yaw and pitch follow their synchronized aim.
- [projectile-visual-direction.md](projectile-visual-direction.md) — player shots
  are small 90 m/s tracers and leave no decorative impact splat.
- [expanded-open-air-arena.md](expanded-open-air-arena.md) - the multiplayer
  arena is 135 metres square, open to the sky, and has more outer-route cover.
- [controller-layout.md](controller-layout.md) - gameplay uses the left stick,
  right stick, right trigger, and south face button.
- [shot-impact-feedback.md](shot-impact-feedback.md) - shots create impact
  debris without shaking the camera.
- [public-lobby-browser.md](public-lobby-browser.md) - online setup lists
  joinable lobbies for the selected mode and filters them by room code.
- [tdm-round-format.md](tdm-round-format.md) - TDM uses balanced random teams,
  a 25-kill target, and a 10-second intermission before the next round.
- [killer-spectate-chain.md](killer-spectate-chain.md) - dead players spectate
  their killer and follow that killer's elimination chain.
- [team-leaderboards.md](team-leaderboards.md) - the TDM HUD shows per-team
  player rankings sorted by kills.
- [match-disconnect-rules.md](match-disconnect-rules.md) - disconnected actors
  disappear, underpopulated matches return to the menu, and empty TDM teams trigger a new round.
- [healing-station-visual-style.md](healing-station-visual-style.md) - healing
  stations are tall green portals with world UI in their entrances, and arena
  polish should add landmarks and feedback without camera shake.
- [snitch-durability.md](snitch-durability.md) - flying Snitches take two
  ordinary bullet hits to destroy.
