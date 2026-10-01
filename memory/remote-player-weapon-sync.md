# Remote players need a visible, synchronized weapon

Fact: Every remote player must show a third-person paintbrush rifle. Its world
position follows the remote character, its yaw follows the character body, and
its pitch follows the owning player's synchronized camera pitch.

Why: The first online implementation rendered only a capsule body and sphere
head. Although yaw and pitch were already sent over the network, the receiver
discarded pitch and had no weapon mesh, so other players could not see where a
player's gun was aiming.

How to apply: Keep remote weapon geometry under an `AimPivot` on the remote
character. Smooth body yaw and pivot pitch from transform packets, and preserve
this behavior if the placeholder player model is replaced later.
