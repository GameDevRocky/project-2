# Enemy contact damage is decided by current speed, not top speed

When the player square and an enemy square overlap, whichever one is moving
faster *at that moment* deals 1 damage to the other. A tie damages both. This
compares live movement speed (the length of the velocity the square actually
moved at this frame), not the `speed` export value. A player standing still has
a current speed of 0 and therefore always loses the exchange; a player who is
moving (400) beats the enemy (250) and always wins it.

Why: On 2026-09-23 Jarman asked for an enemy square that chases you, which you
kill "by moving into it before it can move into you." I offered three combat
rules and warned that "faster square wins" would collapse into "the player
always wins" — that warning was only true for fixed top speeds. Comparing
current speed is what makes standing still lethal and moving into the enemy the
attack, which is exactly the mechanic he described. He chose that rule.

How to apply: Any code that resolves a contact hit reads the player's live
velocity, so `player.gd` must keep exposing the velocity it moved at this frame.
Do not "simplify" the comparison to the `speed` export values — that silently
deletes the mechanic. If enemies later get variable speeds (charging, slowing,
stunned), the same rule still holds and no special-casing is needed.
