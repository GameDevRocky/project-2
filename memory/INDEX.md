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
  the command line (must name res://scenes/match.tscn since the menu became
  the main scene), how to test TDM, and how to probe completability.
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
- [pushing-from-wsl-needs-windows-credentials.md](pushing-from-wsl-needs-windows-credentials.md)
  — the WSL checkout has no git identity or GitHub login; the one-off
  `git -c ...` commit and push commands that work without touching config.
- [jcodes-files-are-open-for-the-visual-overhaul.md](jcodes-files-are-open-for-the-visual-overhaul.md)
  — teammate jcodes wrote menu.gd / tdm_match_controller.gd; Jarman OK'd
  editing them for the visual + UX overhaul only; ask again for other tasks.
- [stop-after-each-stage-even-if-a-spec-says-not-to.md](stop-after-each-stage-even-if-a-spec-says-not-to.md)
  — CLAUDE.md's "stop after each step" beats a pasted spec's "don't stop";
  one stage, test, explain, wait for go.
- [survival-autoplay-stalls-are-arena-pathing-not-regressions.md](survival-autoplay-stalls-are-arena-pathing-not-regressions.md)
  — a Survival bot run stuck in one wave is usually an enemy pinned by the
  centre platform / south lane (no pathfinding); A/B against the old commit
  before blaming the latest change.
- [commands-for-jarmans-terminal-use-full-paths-no-bang.md](commands-for-jarmans-terminal-use-full-paths-no-bang.md)
  — give Jarman absolute-path commands without `!` for his own terminal; also
  records that .godot ownership and Blender's numpy were fixed 2026-09-30.
- [blender-pipeline-gotchas.md](blender-pipeline-gotchas.md) — how to rebuild
  the generated models (build_all.sh + Godot import) and six Blender traps
  already hit (stale matrix_world, exit codes, smoothing, culling, handedness).
- [scratch-folder-is-wiped-keep-test-tools-in-tools-tests.md](scratch-folder-is-wiped-keep-test-tools-in-tools-tests.md)
  — /tmp scratch is wiped when WSL restarts; all test tools (screenshots,
  TDM/menu probes, perf, the Survival/TDM PASS-FAIL checklists) live in
  tools/tests/; how to press keys correctly from a test.
- [measure-performance-with-counters-not-fps.md](measure-performance-with-counters-not-fps.md)
  — tools/tests/perf_probe.gd; compare draw calls / headless physics ms, not
  fps; UI writes every frame and first-time loads were the real costs.
- [online-branch-direction-differs-from-overhaul.md](online-branch-direction-differs-from-overhaul.md)
  — Rocklyn's `online` branch: humans only, tracer shots without splats,
  rewrites the same 5 files as the overhaul; check before editing them.
- [character-select-dresses-the-canvas-runner.md](character-select-dresses-the-canvas-runner.md)
  — customize screen dresses the Canvas Runner; bots and Survival enemies get
  varied looks (enemy colour/outline never change); map keeps its layout.
- [browser-multiplayer-target.md](browser-multiplayer-target.md) — the shipped
  multiplayer client runs from GitHub Pages and requires browser networking plus
  an external service.
- [human-only-pvp-modes.md](human-only-pvp-modes.md) — online matches contain
  human players only; TDM is RED versus BLUE and Survival replaces the PvE wave path.
- [remote-player-weapon-sync.md](remote-player-weapon-sync.md) — remote players
  need a visible rifle whose yaw and pitch follow their synchronized aim.
- [projectile-visual-direction.md](projectile-visual-direction.md) — player shots
  are small 90 m/s tracers and leave no decorative impact splat.
