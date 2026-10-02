# jcodes's menu and TDM files may be edited for the visual overhaul

Teammate **jcodes** (`thejcodes101@gmail.com`) wrote `scripts/menu.gd`,
`scripts/tdm_match_controller.gd`, the character-customization scripts, and
recent edits to `game.gd`, `player.gd`, `arena.gd`, `enemy.gd`,
`projectile.gd` and `healing_station.gd` (commit `cda925c`, PR #3). These are
the real Multiplayer and UX systems that CLAUDE.md's placeholder folders
(`scripts/multiplayer/`, `scripts/ux/`) were standing in for.

On 2026-09-29 Jarman said "Yes, edit freely" to changing those files for the
visual + UX overhaul spec (TDM HUD, Tab scoreboard, menu layout audit).

Why: CLAUDE.md forbids touching teammates' systems, but the overhaul spec needs
big layout changes inside exactly those files, so I asked before starting.

How to apply: for work under that overhaul spec, edit jcodes's files like any
other. It is not a blanket permission. For any other task that would change
those files, ask again. Keep their gameplay seams intact either way (for example
`power_traded(power_type, player, station)` on the healing station).
