# A fake player (tools/autoplay.gd) is how this game gets tested headless

A headless run has no keyboard or mouse, so the player just stands still and
dies. That proves the game boots and nothing else. `tools/autoplay.gd` fakes a
player: it aims at the nearest enemy, bursts the trigger, strafes, and presses E
on cores. It is only created when the flag is passed, so it costs a real play
session nothing.

    GODOT="C:/Users/jlion/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
    "$GODOT" --headless --path "<project>" res://scenes/match.tscn --quit-after 18000 -- --autoplay

Update 2026-09-29: since jcodes's PR #3 the main scene is the MENU
(`scenes/main.tscn` -> `menu.gd`), so the old command without
`res://scenes/match.tscn` just idles on the menu and tests nothing. Naming the
match scene starts Survival directly (game.gd defaults to `game_mode =
"SURVIVAL"`). MECHANICS.md's Testing section still shows the old command.
TDM cannot be started this way - game.gd needs lobby records - and game.gd
never attaches the autoplay bot in TDM. To test TDM, use a throwaway
`extends SceneTree` script that instantiates match.tscn, sets `game_mode =
"TEAM_DEATH_MATCH"`, `session_team` and 20 `lobby_players` records, then adds
`tools/autoplay.gd` itself.

The bare `--` matters: everything after it goes to the game, not the engine.
`--autoplay` also turns on `[game]` logging (wave start/clear, each kill, each
inheritance, death). `--verbose` gives the logging without the bot.

Roughly 18000 frames covers a losing run; a full six-wave win needs ~70000.

Two tricks that made balance measurable:
- To check the game is *completable* at all, temporarily set `max_health` very
  high and watch every wave clear. That is how the wave-2 softlock was found.
- To check there is headroom for a skilled player, temporarily double
  `max_health` - a rough stand-in for "dodges twice as well".

Why: On 2026-09-23, building the 3D shooter, three separate bugs (no shots
firing, shots landing beside the crosshair, rushers becoming unshootable) were
all invisible to a plain headless run and all obvious within one autoplay run.

How to apply: after any change to combat, movement or waves, run autoplay and
read the trace. The bot is deliberately mediocre - it dies around wave 3-4 of 6,
and that is the tuning target, not a bug. Do not balance the game so the bot
wins; a human who dodges and picks pairs sensibly is much stronger than it.
See [[godot-cli-runs-the-game-headless]].
