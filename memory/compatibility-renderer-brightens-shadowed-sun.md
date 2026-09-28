# The web renderer draws a shadow-casting sun far brighter than desktop

The GitHub Pages build runs on Godot's Compatibility renderer; F5 on the desktop
runs Forward+. In Godot 4.7.2, with the same `DirectionalLight3D.light_energy`
and `shadow_enabled = true`, Compatibility lit the sunlit floor about 2.7x
brighter than Forward+ (more on dimly lit vertical faces), and the response is
not linear in energy. Turn the sun's shadows off and the two renderers match
pixel for pixel; turn the sun off and they also match. So the extra light comes
only from the shadowed sun.

The fix in `scripts/arena.gd` `_build_light()`: if
`RenderingServer.get_current_rendering_method() == "gl_compatibility"`, the sun
uses energy 0.25 instead of 1.0. That value came from screenshots of both
renderers until the sunlit floor matched (200/255 on both).

Why: On 2026-09-27, in the Stage 1 brightness pass, the desktop screenshots
looked fixed, but the same scene under `--rendering-method gl_compatibility`
was still washed out. Jarman shares the game through the Pages link, so that was
the version that mattered most. Before the fix, the web build clipped the floor
to pure white even worse than desktop did.

How to apply: after ANY change to lighting, ambient, tonemap, material albedo
or emission, screenshot both renderers (run once normally, once with
`--rendering-method gl_compatibility`) and compare. If the sun's energy,
shadows, or the number of shadowed lights ever changes, re-measure the 0.25.
See [[godot-cli-runs-the-game-headless]] for how to take screenshots, and
[[github-pages-web-export-config]].
