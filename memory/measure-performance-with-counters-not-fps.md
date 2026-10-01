# Measure performance with steady counters, and suspect per-frame UI writes first

`tools/tests/perf_probe.gd` runs a full 2x10 TDM match and prints fps, the
slowest frame, hitches (with the time each happened), and per-frame draw
calls, objects drawn, process ms and physics ms. Run it windowed for
rendering and `--headless` for pure CPU. Switches (`--remove-visuals`,
`--remove-dressing`, `--mute-hud`, `--no-ssao`, ...) turn one thing off.

What 2026-09-30 taught:
- On Jarman's laptop, windowed fps swings +-40% run to run (GPU clocks).
  Draw calls, objects drawn and headless physics ms are steady - compare those.
- A random TDM fight still varies a few ms between runs; run each config
  twice before believing a difference under ~2 ms.
- Code called from a signal inside `_physics_process` counts as physics
  time, and so does deferred work it queues (container re-layout, text
  shaping). The two biggest costs were UI: labels rewritten every frame
  (~7 ms) and a hidden scoreboard rebuilt on every death (~3 ms).
- Hitches at the same timestamp every run are first-time loads (a model
  file's first `load()` is ~35 ms), not ongoing cost. Warm them up at setup.
- Many small nodes under a moving CharacterBody3D cost every physics step;
  export static parts as one mesh (paintkit `merge_all`).

Why: Stage 6 dropped TDM from ~570 to ~200 fps and the first guesses
(SSAO, the new shader) were wrong; bisecting against a `git worktree` of
the old commit found the real causes.

How to apply: after any visual/UI change, run perf_probe windowed and headless
and compare counters with the previous numbers in
docs/VISUAL_OVERHAUL_CHANGELOG.md. Never write Label text or theme overrides
every frame - only on change. See [[blender-pipeline-gotchas]].
