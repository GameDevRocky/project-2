# The Web export config and GitHub Pages deploy are already set up

Two files do this, both already in the repo:

- `export_presets.cfg` — tells Godot how to package the project as a browser
  build (WASM + HTML + a `.pck` of the game's assets). One preset named
  "Web". Thread Support is off, so the browser build does not need special
  cross-origin server headers — GitHub Pages can't set custom headers anyway,
  so this was the only setting that would actually work there.
- `.github/workflows/deploy-pages.yml` — a GitHub Actions workflow. On every
  push to `main` (or a manual "Run workflow" click from any branch), a
  GitHub-hosted Linux machine downloads Godot 4.7.2 and the Web export
  templates itself, runs the "Web" export, and publishes the result to
  GitHub Pages. Nothing exports on Jarman's own machine and no build output
  is committed — `build/` is in `.gitignore`.

To get the live link:

1. On GitHub: repo Settings > Pages > Build and deployment > Source, set to
   "GitHub Actions" (one-time, done in the browser, not something Claude can
   click).
2. Push to `main` (or merge `GDD_V1` into it). The Actions tab shows the
   workflow run.
3. The link is `https://gamedevrocky.github.io/project-2/` (repo is
   `GameDevRocky/project-2`) — also shown in the workflow run's "deploy" job
   output once it finishes.

Why: Jarman asked for a way to play the game from a GitHub Pages link without
manually re-exporting every time. `export_presets.cfg` alone is not enough —
Godot won't export anything unless it exists, but nothing publishes it
automatically without the workflow.

How to apply: if the site 404s after a push, check the Actions tab first —
the export step needs the Pages source set to "GitHub Actions" (step 1
above) or it has nowhere to deploy to. If glow/bloom effects (see
[[jolt-rejects-non-uniform-body-scale]] for another renderer-specific gotcha)
look flat in the browser, that's expected: Web export uses the Compatibility
renderer, not Forward+, and Compatibility does not do glow.
