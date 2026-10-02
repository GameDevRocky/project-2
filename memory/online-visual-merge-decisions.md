# Combining Rocklyn's online branch with the overhaul: his gameplay wins

Rule (Jarman, 2026-10-02): when `origin/online` and the overhaul disagree on
gameplay or networking, Rocklyn's version wins. The overhaul supplies the look:
models, UI layout and theme, map art. Keep both where they do not collide.
Settled specifics:
- Respawn and spectating: his 3 s TDM respawn and killer-chain spectating,
  plus the overhaul's first/third-person toggle and death-screen look.
- Guns: his power-ball system only. The overhaul's gun models show the power
  held (2 Shot = Fine Liner, Rocket Launcher = Blob Lobber, Sprayer = Prism
  Beam, no power = Paint Blaster). The 5-gun loadout screen is dropped, and
  right mouse stays his invisibility toggle.
- The pause menu stays (his branch has none).
- The work goes on a new branch `online-visual`, made from `origin/online`,
  with `visual-ux-overhaul` merged in. Commits are local only unless Jarman
  says push.
- Done 2026-10-02 (merge resolved on `online-visual`; see the changelog's
  "Combined with Rocklyn's latest online" section). The loadout's
  weapons.gd was kept and repurposed as the power -> gun-model table rather
  than deleted (deleting needs Jarman's OK).

Why: Jarman asked to combine the branches and "go with his version" for
differences. That would have silently undone his own requests from
2026-10-01 (10 s respawn, teammate spectating, loadout), so the exceptions
were put to him and he chose the options above.

How to apply: resolve every conflict on `online-visual` with this list. If a
new conflict is not covered and it removes something Jarman asked for, ask
before dropping it. See [[online-branch-direction-differs-from-overhaul]].
