# Online modes use human players only

Fact: Do not populate matches with bots. Team Deathmatch is human RED versus
human BLUE. Survival is a human-versus-human mode rather than the existing PvE
wave simulation.

Why: The online branch is intended to replace simulated players and NPC combat
with multiplayer matches.

How to apply: Lobby records must always represent connected humans. Do not call
the simulated lobby fill or spawn `enemy.gd` actors as player replacements.
Clarify the exact Survival win and respawn rules before implementing that mode.
