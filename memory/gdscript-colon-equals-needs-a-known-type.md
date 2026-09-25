# In GDScript, `:=` fails on any property the parser cannot type

`:=` means "infer the type from the value". When the value is a variable this
project added to a script, and the node holding it is typed as its engine class
(`var player: ColorRect`), the parser does not know that variable exists. It
falls back to `Variant`, and `:=` then errors with:

    Parser Error: Cannot infer the type of "x" variable because the value
    doesn't have a set type.

The fix is to write the type out instead of inferring it:

    var player_speed: float = player.velocity.length()   # works
    var player_speed := player.velocity.length()         # parser error

Built-in members are fine with `:=` - `player.position` and `player.size` are
real `ColorRect` properties, so those infer without complaint. Only
project-added members trip it.

Why: On 2026-09-23 this error stopped `scripts/enemy.gd` on its first launch.
`velocity` and `take_damage()` were added to `player.gd`, but `enemy.gd` held
the player as a plain `ColorRect`, so neither was visible to the parser.

How to apply: Any time one script reaches across to a variable or function
another script defined, write the type by hand rather than using `:=`. The
alternative - giving `player.gd` a `class_name` so the type becomes real - is
cleaner, but it registers a global class name that could collide with the
multiplayer or UX teammates' scripts, so do not add one without asking Jarman.
