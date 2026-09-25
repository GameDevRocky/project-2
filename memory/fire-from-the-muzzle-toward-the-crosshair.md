# A gun must fire toward the crosshair, not along the camera's axis

The paintbrush-rifle's muzzle sits about 32cm right and 26cm below the camera,
because that is where a gun looks right on screen. The first version spawned
each glob at the muzzle and sent it along the *camera's* forward direction. Both
halves sound correct and together they are wrong: the shot travels a line
parallel to your view but permanently offset, so it lands 32cm right and 26cm
low of the crosshair at every range. With enemies under a metre wide, most shots
missed.

The fix (`player.gd`, `_aim_point()`): raycast from the centre of the camera to
find what the crosshair is actually over, then aim the glob from the muzzle at
*that point*. The shot still visibly leaves the gun and it goes where you look.
Guard the case where the aim point is under ~2m away, or the correction swings
the shot wildly sideways.

Why: On 2026-09-23 this made the game look almost unwinnable - the test bot
cleared wave 1 only occasionally and it read as a balance problem rather than a
geometry bug.

How to apply: any time something is fired from a position that is not the
camera's own position - a gun, a shoulder launcher, a second barrel - it needs
this convergence step. A balance problem that appears the moment a weapon is
added is worth checking for this first.
