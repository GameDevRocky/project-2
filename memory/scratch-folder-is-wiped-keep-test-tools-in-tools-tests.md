# The /tmp scratch folder does not survive overnight; test tools live in tools/tests/

Claude's session scratch folder is under `/tmp/claude-1000/...`. WSL clears
`/tmp` when it restarts, so anything there is gone the next day.

On 2026-09-30 the screenshot harness, the TDM probe, the menu-flow probe, the
position probe and all the Stage 1 "before" screenshots from 2026-09-29 had
vanished. The harnesses were rebuilt INSIDE the project:

- `tools/tests/screenshots.gd` - every menu page, TDM HUD/scoreboard/respawn/
  result, Survival HUD/offer/end, at a chosen resolution (windowed).
- `tools/tests/tdm_probe.gd` - headless 2x10 TDM with the autoplay bot,
  prints scores/K-D-A/hp/paint; `--shorten=N`, `--tab`.
- `tools/tests/menu_flow_probe.gd` - drives PLAY -> TDM/Survival through the
  real menu functions and reports which HUD exists.
- `tools/tests/model_viewer.gd` - photographs the generated models in the
  real arena lighting.
- `tools/tests/perf_probe.gd` - TDM fps / draw calls / physics ms / hitches.
- `tools/tests/survival_checklist.gd` and `tdm_checklist.gd` - the spec's
  15- and 26-point regression lists as PASS/FAIL (headless). TDM goes through
  the real menu, takes ~75 s.

Gotcha found writing them: a test that presses an action must do it right
after `await physics_frame`. A press made from a timer callback lands after
the frame's scripts ran, so `is_action_just_pressed()` never sees it - the
checklist first reported E-to-inherit and the healing station as broken when
the game was fine. And compare UI positions to `root.get_visible_rect()`,
not `root.size` (canvas_items stretch: canvas units != window pixels).

Run any of them with `--script res://tools/tests/<name>.gd` (windowed for the
visual ones). Old "before" pictures can be regenerated from a `git worktree`
of the older commit.

Why: losing them mid-overhaul cost a rebuild and the before/after comparison.

How to apply: anything needed for more than one session goes in the project
(tools/tests/ for test harnesses), never only in /tmp. Screenshots themselves
can stay in /tmp; they are cheap to retake.
