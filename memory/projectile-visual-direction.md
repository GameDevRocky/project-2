# Online projectiles are small, fast tracers without impact splats

Fact: Player projectiles use a small glowing bullet with a tapered trail, move
at 90 metres per second, and leave no decorative paint splat when they hit.
Splash damage and its brief radius indicator remain part of the Splatter
ability.

Why: Large, slow paint globs obscured aiming and the persistent impact effect
did not match the intended online shooter presentation.

How to apply: Keep the projectile's ray collision when changing its speed or
visual size. Align the projectile node's local forward axis to its direction so
the child trail remains behind the bullet.
