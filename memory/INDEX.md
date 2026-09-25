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
  and run the game headless, so changes get tested without the MCP tools.
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
