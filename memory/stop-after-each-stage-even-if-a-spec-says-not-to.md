# Stop after each stage, even when a pasted spec says to keep going

When a pasted task spec says "do not stop, run every stage", CLAUDE.md's
"work in small steps, stop after each step" still wins. Jarman chose this
directly on 2026-09-29 for the 9-stage visual + UX overhaul.

Why: Jarman is new to Godot and GDScript and wants to follow what each chunk
of work changed. Nine stages of engine code in one go is too much to take in.

How to apply: finish one stage, test it, then stop. Explain what changed
(files, what each part does, how to see it in the game) and wait for a "go"
before starting the next.
