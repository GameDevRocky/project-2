# The Godot 4.7.2 binary is on this machine and can test the game from Bash

The executable lives at:
`C:/Users/jlion/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`
(the `.exe` at the end of the folder name is not a typo - it is a directory).
Use the `_console` build, because the plain one writes nothing to stdout.

Two commands cover most testing:

- Parse-check one script without running anything:
  `"$GODOT" --headless --path "C:/Users/jlion/downloads/project-2" --check-only --script "res://scripts/enemy.gd"`
- Run the real game for a fixed number of frames and read its `print()` output:
  `"$GODOT" --headless --path "C:/Users/jlion/downloads/project-2" --quit-after 260`
  (260 frames is roughly 4 seconds. `--quit-after` exits cleanly.)

Filter the output through `grep -viE "MCP|bridge|websocket|listening"` to drop
the game-bridge autoload's startup chatter.

Why: On 2026-09-23 I twice shipped Jarman code I had not run, saying only that
the Godot MCP tools were missing. The second time he hit a parser error on the
first launch. The MCP tools really are missing, but that was never a reason not
to test - the engine itself was sitting in his Downloads folder the whole time,
and one search would have found it.

How to apply: CLAUDE.md says run the game and test the change before saying it
works. Do that with these commands after every script or scene edit. Headless
runs get no keyboard input, so the player square never moves: that exercises the
"standing still loses" path automatically, but a path that needs a key held down
still has to go to Jarman for a real F5. Say which of the two a claim rests on.
Do not use `timeout` to stop a run - killing the process mid-frame produces a
wall of fake `Unreferenced static string` errors that look like real bugs.
See [[godot-mcp-tools-not-connected]].
