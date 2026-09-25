# Do not store a game rule in the windowing system

`player.gd` used to decide whether you were allowed to shoot by reading
`Input.mouse_mode != Input.MOUSE_MODE_CAPTURED`. Mouse capture is a *request*,
and a display server is free to ignore it - the headless server always does. So
the check read "not captured" forever and the gun never fired a single shot.

The fix was to keep our own `_mouse_captured` flag, have one function
(`_set_mouse_captured`) tell the display server about it, and have every game
rule read the flag instead of the server.

Why: On 2026-09-23 this silently broke all shooting in every headless test run.
It would never have shown up in a real play session, which is worse, not better
- the bug was invisible exactly where testing happens.

How to apply: whenever a rule of the game depends on window focus, mouse mode,
screen size or anything else owned by the OS, keep the authoritative answer in
the game and push it outward. Reading it back means the game's behaviour depends
on whether the platform felt like honouring the request.
