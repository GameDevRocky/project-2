# A stalled Survival autoplay run is usually the arena, not a regression

Since jcodes's expanded arena (PR #3), a headless Survival autoplay run can sit
in one wave for minutes with no kills and no death. Enemies steer in a straight
line toward the player (no pathfinding), so one can get stuck against the
centre platform's edge or down in the recessed south lane, and the autoplay bot
cannot walk to it either. The wave then never clears.

Measured 2026-09-29 with a position probe on the untouched pre-overhaul code:
a Sprayer sat at y = -2.4 in the south lane for 100+ s in wave 1, and a
Bounder at full health stayed pinned at (-1, 0, -4) on the platform edge for
100+ s in wave 3. The overhaul build did the same thing on some runs and not on
others.

Why: during the Stage-3 UI pass two long runs stalled and it looked like the new
HUD had broken combat. It hadn't - the HUD cannot touch gameplay - but proving
that took an A/B run.

How to apply: when a Survival run stalls, don't assume the latest change caused
it. Print enemy and player positions every ~20 s (a throwaway `SceneTree`
script that loads match.tscn; game.gd still attaches the bot because
`--autoplay` is in the user args) and compare against a clean `git worktree` of
the previous commit. Only call it a regression if the old code does NOT stall
the same way over several runs. Fixing the pathing is a gameplay change - ask
before touching it. See [[autoplay-harness-tests-the-game-headless]].
