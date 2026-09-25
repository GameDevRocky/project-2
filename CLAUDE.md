# Project instructions

## Who I am

- Jarman Perry, a student in COMP 440 at NC A&T.
- I am brand new to Godot and brand new to GDScript. Explain engine concepts
  (nodes, scenes, signals, the node tree, `_ready` vs `_process`) and GDScript
  syntax from scratch, every time, in plain language. Do not assume I know a
  term just because you used it in an earlier message. When you show me code,
  say what each part does and where the file goes.

## This project

- Godot 4.7 (Forward+ renderer).
- The game: a first-person paint-shooter where you hunt enemies and inherit one
  defeated enemy's ability and weakness in place of your current pair, then use
  that combination to take on tougher targets. Set in a vibrant pastel world
  where you wield a paintbrush-rifle to clean up canvas-like battlefields.
- Three systems: Multiplayer, Game Logic, and UX. Multiplayer talks to game
  logic by sending data from client to server. UX talks to game logic by letting
  players click buttons that perform an action in the game. Those two crossings
  are the seams. Multiplayer is the seam most likely to break first.
- GDScript only. Godot 4 syntax only. Before writing engine code, use the
  godot_docs tool to check the docs for my Godot version.

## Always

- Work in small steps. After each step, stop and tell me what changed.
- After any change to a script or scene, run the game and test the change with
  the Godot tools before you tell me it works.

## Ask first

- Deleting or renaming a file.
- Installing an addon, plugin, or package.
- Git commits or pushes.

## Never

- Add features I did not ask for.
- Touch these folders:
  - `assets/` — art, audio, and models.
  - `addons/` — holds the godot_mcp plugin; breaking it breaks your own tools.
  - `.godot/` — Godot's generated import cache, never hand-edited.
  - `scripts/multiplayer/` and `scripts/ux/` — my teammates' systems. (Rename
    these to the real paths once we settle the folder layout.)
- Read or change files outside this project folder.

## Memory

Keep a folder named memory/ in this project. It holds what you have learned about
working with me, so we do not repeat mistakes across sessions.

- At the start of every session, read memory/INDEX.md.
- When I correct you, or when we settle a decision, write a short note in memory/.
  One fact per file. Each note says:
  - the fact or rule,
  - Why: what went wrong, or why I decided it,
  - How to apply: when it matters next time.
- Then add one line to memory/INDEX.md that names the file and says what it covers.
- Before you write a new note, check whether an old one already covers it. Update the
  old note instead of making a second one. Delete a note that turns out to be wrong.
- When I say "remember this", write a note in memory/ and nowhere else.
