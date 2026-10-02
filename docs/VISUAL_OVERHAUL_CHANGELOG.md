# Visual + UX Overhaul — Change Log

Companion to `docs/VISUAL_OVERHAUL_PLAN.md`. Newest stage at the top of each
section. "Stage N" refers to the work order in the plan (§9).

## TDM HUD
Stage 3 (2026-09-29):
- New `scripts/ui/tdm_hud.gd`, created by `tdm_match_controller.gd`
  (`HudScript.new()` in `_build_hud()`). Adds the missing gameplay HUD:
  crosshair (with a small outward kick on each shot), health meter, paint-tank
  gauge, inheritance card, hurt flash + vignette.
- Top-centre score pill: RED score · big clock · BLUE score, your team
  underlined, "YOU ARE TEAM …" caption. Clock turns warm under 30 s.
- "PAINTED OUT / Respawning in 2.4" overlay while dead. The controller keeps
  the respawn `SceneTreeTimer` and exposes `local_respawn_time_left()`; the
  3 s delay is unchanged.
- Result screen rebuilt with containers: winner (team colour / white for
  DRAW), final score, YOUR MATCH K/D/A, RETURN TO MAIN MENU (keyboard-focused).
- Everything anchored (top-centre / bottom-left / bottom-right / centre);
  verified at 1280×720, 1920×1080, 1280×800 and 1920×800 (ultrawide).
- Team colours now come from one place, `UITheme.TEAM_RED/TEAM_BLUE`
  (same hex values jcodes chose).

## Scoreboard
Stage 3:
- New `scripts/ui/tdm_scoreboard.gd` + `scripts/ui/scoreboard_row.gd`.
- Fixed-width K/D/A cells (46 px) and a rank cell, name takes the rest with
  `clip_text` + ellipsis overrun, so columns always line up and long names end
  in "…".
- Teams side by side, team-coloured borders, big team totals, column-title row,
  rows sorted by kills ↓ / deaths ↑ (display order only).
- Local row: team-tinted background, thick team edge, yellow YOU chip.
- Still held (not toggled). Tab is now checked every frame (was every 0.25 s);
  contents still refresh 4×/s while open and on every death.
- Reads `controller.players / scores / remaining` directly; no copies.

## Menu
Stage 3:
- Shared theme `scripts/ui/ui_theme.gd` on the menu root: buttons have inner
  padding (text no longer touches the border), distinct hover/pressed/focus
  styles with a painted left edge, consistent heading sizes.
- Every page rebuilt with containers + anchors instead of pixel positions:
  - Main / Settings / Customize: card anchored to the left edge, full height.
  - Mode Select: centred card; each mode's title + description now live INSIDE
    its button (were overlapping labels), plus a "10 V 10" / "6 WAVES" tag.
  - Lobby: header, two expanding team panels, footer pinned to the bottom;
    OPEN SLOT padded; YOU chip; long names end in "…".
  - Customize: one-line title; options in a 2-column grid whose buttons wrap
    their text (PAINTBALL SPLATTER no longer spills out of the panel); locked
    message wraps; selected category/option use the toggle "pressed" style;
    no full-panel flash on every click; drag-to-rotate starts at the panel's
    real right edge.
  - Settings: value readouts (volume %, sensitivity ×1.00); fullscreen toggle
    updates in place.
- Esc now goes back on Mode Select too (was the only page where it did nothing).
- New `scripts/ui/widgets/brush_stroke.gd`: painted swash behind page titles.
- Verified at 1280×720, 1920×1080, 1280×800, 1920×800.

## Weapon
Stage 5 (2026-09-30):
- `player.gd` builds the first-person gun from `paint_blaster.glb` (fallback:
  the original boxes). Drawn 1.15x, scaled AROUND the muzzle so `Muzzle`
  stays at view-model (0, 0, -0.36): the glob spawn point is identical.
- Bristles, tank paint and drips share one material that `_apply_pair()`
  already repaints, so all three show the pair colour.
- Tank paint drains toward the back as `ammo` falls; pressure needle follows;
  regulator spins while refilling; bristles squash on each shot. Read-only.
- The gun no longer casts a shadow on the floor in front of you.
- Gun-skin band found by name (`SkinBand`), not `get_child(2)`.
- Menu preview bean (`character_preview.gd`) holds the same Paint Blaster
  with the chosen gun skin on its band.

## Player
Stage 5:
- TDM bots wear the Canvas Runner (`canvas_runner.glb`) in their team
  colour: team armbands, chevron, knee pads and visor glow; the Paint Blaster
  in the right hand with team-coloured brush and tank. Legs stride with
  speed, body bobs, gun recoils on firing. Capsule/AI/scoring unchanged.

## Back bling
Stage 5:
- Chromatic Reservoir on every runner's back (`Socket_Back`), tank paint in
  team colour.

## Enemies
Stage 5:
- New `scripts/visual/combatant_visual.gd`, added as a child by
  `enemy._build_mesh()` (fallback: the original sphere). Each archetype wears
  its own model, painted from `stats.color`:
  Sprayer (legs stride, nozzle crown spins on fire), Bounder (springs bounce,
  rollers spin, arms swing on a melee hit), Blotter (paint sloshes, mortar
  recoils and reloads its glob), Monolith (top slab breathes, cannon
  recoils), Ghost (floats, strips sway, eyes brighten while it regenerates).
- Hit/fire flash is now a brief white overlay over the whole model
  (`paint_kit.flash`), attached only while it runs.
- Death squash animates the visual node, never the physics body.
- Accent paint glows at 0.55 (the old spheres used 0.6) so colour reads at
  range; all enemy materials stay fog-free as before.
- Team colours in enemy.gd now come from `UITheme` (same values).

## Cores
Stage 5:
- `core_pickup.gd` shows the Pigment Heart: faceted glowing droplet in a ring
  with 12 ticks and two gimbals, plus a wet puddle on the floor (fallback:
  the original crystal). Droplet, ring and gimbals bob and spin together;
  the puddle stays put.
- The 12 ticks go dark one by one over the 14 s lifetime (read-only on
  `_age / lifetime`); the existing last-3-seconds blink is kept.

## Healing Station
Stage 5:
- `healing_station.gd` shows the Paint Restoration Station easel (fallback:
  the original boxes). The palette paint and the canvas plus use
  `_core_material`, the material `_set_state()` already recolours, so
  READY/COOLDOWN colours are unchanged. A slow glow pulse while READY.
- Untouched: Area3D, range, state machine, hold/cooldown timings, the
  `_status` label, `station_state_changed`, and
  `power_traded(power_type, player, station)`. No Snitch logic.

## Environment
Stage 6 (2026-09-30):
- New `scripts/visual/arena_surface.gdshader` on every floor/wall/cover box
  (arena.gd `_surface_material`): faint canvas weave up close, broad brush
  variation, soft edge darkening, dried-paint flecks on floors. All effects
  are centred on zero, so each surface keeps its Stage-1 colour/brightness.
- Area identities via a painted wall band: NW paint storage ochre, NE mixing
  room lilac, SW gallery clay, south lane runoff sea-glass, hub pillars get a
  brush-ferrule band, perimeter gets a dark skirting.
- Set dressing (`DRESSING` / `FLOOR_STAINS` tables, `_build_dressing()`):
  palette inlay on the hub platform + hanging mobile overhead; can stacks on
  NW wall tops; mixing vats on the NE north wall; framed canvases in the SW
  gallery; pipes along the south lane walls; murals and banners high on the
  perimeter; giant brushes/paint tubes flush in the four corners; 16 old
  dried-paint stains on the floor. **No collision added, no `_add_solid` call
  changed** - layout, cover and sightlines are identical.
- Menu backdrop: the neon slats became glowing giant paint brushes.

## Paint VFX
Stage 5:
- Globs use the teardrop mesh (one shared mesh), turned along their flight
  direction in `setup()`. Movement/hit code unchanged.
- Splats (`paint_splat.glb`, 4 variants) lie flat on the surface hit: turned
  to the ray's hit normal, lifted 1.2 cm, random spin and 0.8-1.2x size,
  shaded wet paint with a faint glow. Fade after 6 s; at most 64 alive
  (oldest removed first).
- Hits on enemies/players make a quick paint puff instead of a splat, so
  nothing hangs in mid-air when the target moves.

## Polish (Stage 7, 2026-09-30) - all visual only
- New `scripts/visual/paint_fx.gd`: self-freeing one-shot CPUParticles3D
  paint bursts (work in both renderers; one shared droplet mesh/material).
- Muzzle paint puff on every shot, in the pair colour, riding the bristles.
- Crosshair hit marker: projectile.gd records whether it damaged anything
  (direct or splash) and tells its `source_player`, which emits the new
  `hit_confirmed` signal; both HUDs flash four diagonal ticks. Damage code
  untouched (the glob only reports after `take_damage` has run).
- Death burst in the combatant's colour (archetype / team); pickup burst in
  the pair colour when a core is taken.
- Low-health edge pulse: below 30% health the screen corners pulse red,
  stronger the lower you are (`screen_fx.set_health_fraction`).
- Inheritance card flashes bright when a new pair is taken.
- Tab scoreboard fades in over 0.1 s / out over 0.08 s; still held, not
  toggled.
- Menu buttons grow 2% on hover/focus (from their left edge, so they never
  push into the card margin) and squash on press.
- No camera shake, recoil on aim, slow-down or timing change of any kind.
- Performance after Stage 7 (TDM 20 players): 300-335 fps windowed, slowest
  frame 9-10 ms, 0 hitches; headless physics 3.2-3.6 ms per step (old code
  4.0). The drop from Stage 6's ~8.5 ms is not fully explained yet -
  re-verify in Stage 8.

## Regression testing (Stage 8, 2026-09-30)

All runs on Godot 4.7.2 (Windows console build, driven from WSL). Tools are in
`tools/tests/` and can be re-run any time.

| Check | Tool | Result |
|---|---|---|
| Survival 15-point list (+ paint drain/refill split) | `survival_checklist.gd` (headless) | **16/16 PASS**, incl. all six waves to "CANVAS CLEAN" |
| TDM 26-point list (entered via the real menu) | `tdm_checklist.gd` (headless + windowed) | **27/27 PASS**, 3 consecutive runs |
| Autoplay Survival (bot) | `match.tscn -- --autoplay` | 0 errors; waves cleared, pairs inherited |
| Every gameplay tuning value vs the original commit `3b09061` | scratch dump of WAVES, PAIRS, TYPES, player/core/station/TDM/menu/projectile/arena constants | **26/26 lines identical**; all 33 `_add_solid` collision calls identical |
| Menu pages at 1280x720, 1920x1080, 1280x800, 1024x768, 1920x800, 1924x1175 | `screenshots.gd --only=menu` | no overlap, clipping or escaped text; layouts hold at every aspect |
| Before/after screenshots | `screenshots.gd` on a worktree of `3b09061` | compared side by side (scratch) |
| Import | `godot --headless --import` | 0 errors |
| Performance, desktop (TDM, 20 players) | `perf_probe.gd` | 291-339 fps, slowest frame 11-12 ms, 0 hitches |
| Performance, web renderer | `perf_probe.gd` + `--rendering-method gl_compatibility` | 209-228 fps; 0-1 hitch of <=58 ms (original code: one 124 ms freeze per match) |
| Web export | `--export-release "Web"` | **not run locally**: the web export templates are not installed on this PC (CI downloads them). Verified via the Compatibility renderer instead |

Found and fixed in Stage 8:
- Web renderer froze ~140 ms at the first shot and first death of every
  match while compiling effect shaders. New `scripts/visual/shader_warmup.gd`
  draws each effect material once (1 cm, in front of the camera) during
  loading; the materials come from shared static builders
  (`projectile.gd` `glob/splat/puff/burst_material`,
  `paint_kit.flash_overlay_material`) so the warm-up cannot drift.

### Manual F5 checklist (things a headless test cannot press)
1. Menu: hover each button (slight grow), click through every page, Esc backs
   out of Mode Select / Customize / Settings / Lobby.
2. Customize: drag the character to rotate (from anywhere right of the panel),
   pick items in every category, rename, BACK.
3. Settings: drag both sliders (readouts update), toggle fullscreen and back.
4. Survival: shoot an enemy (hit ticks on the crosshair, paint puff at the
   gun, the gun's tank drains and refills), pick up a core with E (burst, card
   flash), hold E at a healing station, drop below 30 health (red edges).
5. TDM: hold Tab mid-fight (board fades in, YOU row highlighted), release
   (board fades out), die and watch "PAINTED OUT - Respawning in 3..2..1",
   play to the result screen and press RETURN TO MAIN MENU.
6. Resize the window to an odd shape; menu and HUD should stay in place.

## Survival HUD
Stage 3:
- `scripts/hud.gd` rebuilt from the same shared widgets (crosshair, health,
  paint tank, inheritance card, screen fx). Public API unchanged.
- Pair card moved bottom-left above health (same layout as TDM); Apprentice
  Brush now reads "NO ABILITY · NO WEAKNESS" in grey + how-to-inherit hint.
- Wave readout in a top-centre pill; inherit offer in a panel under the
  crosshair with green/red halves; banner tween now cancels the previous one;
  end panel centred with containers.

## Lighting
Stage 6:
- SSAO (low intensity) for contact shading; Forward+ only, the web renderer
  ignores it.
- Rim light on combatant/pickup materials (paint_kit `_add_rim`) to separate
  them from the room.
- Sun, ambient, tonemap and the Compatibility sun compensation unchanged.
  Sunlit floor measures 191/255 (Forward+) and 197/255 (Compatibility),
  matching each other as the Stage-1 note requires.

## Blender scripts
Stage 4 (2026-09-30). Rebuild everything with `tools/blender/build_all.sh`
(~35 s); each script refuses to export a model over its triangle budget.
Models are generated and imported but **not yet used by the game** (Stage 5).

| Script (tools/blender/) | Output (models/generated/) | Tris / budget | Nodes Godot will use |
|---|---|---|---|
| `paintkit.py` | shared kit: scene reset, role materials, bevelled primitives, lathe/prism/tube, budget check, GLB export, 4-view Cycles preview | – | – |
| `create_paint_blaster.py` | `paint_blaster.glb` | 3480 / 3500 | `Muzzle` (origin = glob spawn, Godot (0,0,-0.36)), `Fill`, `SkinBand`, `Needle`, `Regulator` |
| `create_canvas_runner.py` | `canvas_runner.glb` | 2852 / 3000 | `Body`, `Leg_L`/`Leg_R` (hip pivots), `Socket_Back`, `Socket_Hand_R` |
| `create_chromatic_reservoir.py` | `chromatic_reservoir.glb` | 1132 / 1200 | `Pack`, `Fill`, `Needle` |
| `create_sprayer.py` | `enemy_sprayer.glb` | 1492 / 1500 | `NozzleFan` (hub pivot), `Leg_L`/`Leg_R` |
| `create_bounder.py` | `enemy_bounder.glb` | 1992 / 2000 | `Spring_L/R` (top pivot), `Arm_L/R` (shoulder), `Roller_L/R` (axis) |
| `create_blotter.py` | `enemy_blotter.glb` | 2464 / 2500 | `Fill`, `Mortar` (hinge), `Glob` (child of Mortar) |
| `create_monolith.py` | `enemy_monolith.glb` | 2484 / 2500 | `TopSlab`, `Cannon`, `Shield` |
| `create_ghost.py` | `enemy_ghost.glb` | 1326 / 1500 | `Eyes`, `Hem`, `Strip_0..4` (top-edge pivots) |
| `create_inheritance_core.py` | `core_pigment.glb` | 892 / 900 | `Droplet`, `Ring` + `Tick_00..11`, `Gimbal_A/B`, `Puddle` |
| `create_healing_station.py` | `healing_station.glb` | 1954 / 2000 | `BasinPaint` + `PlusSign` (PK_StationGlow), `Easel`, `Canvas` |
| `create_paint_glob.py` | `paint_glob.glb` | 120 / 120 | `Glob` (head forward = Godot -Z) |
| `create_paint_splat.py` | `paint_splat.glb` | 312 / 360 | `Splat_0..3` (flat, normal = up) |
| `create_arena_props.py` | 10 × `prop_*.glb` | 268–1456 each | paint tube, giant brush, can stack, mixing vat, frame, banner, pipe run, palette inlay, hub mobile, splat decor |

Deviations recorded from the builds:
- Runner: the weapon socket is on **-X**, the runner's real right hand
  (facing -Y puts its right on -X); the plan said +X, which was wrong.
- Healing Station is 1.21 m tall (limit 1.5) so nothing crosses the
  existing progress ring at 1.25 m; the ceramic basin is `Palette`, the paint
  surface `BasinPaint`.
- Core: droplet, ring and gimbals must bob together in Stage 5 (the droplet tip
  would pass through the gimbals otherwise); the puddle stays on the floor.
- Sprayer legs are slim digitigrade legs (coil springs would not fit 1500 tris);
  its 5 nozzles form an even crown so it can spin.
- Materials are single-sided (back-face culled) everywhere; thin parts are
  closed solids or wall/floor-facing sheets.
- Weapon skin band uses its own role `PK_Skin`, not `PK_Team`.

## Character select, cosmetics and variety (2026-10-01)
- Merged `main` (Rocklyn's dual main/online Pages workflow, 5e10ed5) into
  this branch; no conflicts. The `online` branch was NOT merged (not asked;
  it rewrites the same files - see memory note).
- **Character select now dresses the Canvas Runner**, the same model TDM bots
  wear (`scripts/visual/runner_dresser.gd`, used by the menu preview AND the
  bots). jcodes's bean stays as a fallback. Categories: OUTFITS (10), SUIT
  COLORS (10, incl. rainbow and camo patterns via `suit_pattern.gdshader`),
  HATS (9), MASKS (9), GUN SKINS (10), BACK BLING (12). Outfits hide hats/masks
  ("this outfit has its own headgear"); every outfit can wear back bling.
  Opening BACK BLING turns the character round.
- **Gun skins restyle the whole Paint Blaster** (body, trim, band, grip;
  `scripts/visual/gun_skins.gd`, WOODGRAIN uses `woodgrain.gdshader`), on your
  first-person gun and on bots. The bristles/tank keep showing the pair colour.
- **New Blender models** (tools/blender -> models/generated):
  `create_cosmetic_outfits_a.py` (skeleton, superhero, zombie, astronaut,
  ninja, robot, paintball splatter; 8,382 tris), `create_cosmetic_outfits_b.py`
  (ghost, samurai, cyberpunk + bot-only ART CRITIC, STUDIO JANITOR, MIME, INK
  GOLEM; 7,710), `create_cosmetic_hats.py` (9; 3,129), `create_cosmetic_masks.py`
  (9; 2,287), `create_cosmetic_backbling.py` (11 distinct silhouettes; 8,450),
  `create_enemy_accessories.py` (6 toppers + 4 stickers; 1,936). The runner
  was rebuilt with a separate `Head` and `Socket_Head/Face/Chest`.
- **TDM bots** each get a random look from their lobby record
  (`random_bot_customization`): ~14% a bot-only outfit, ~22% a player outfit,
  the rest a runner with suit colour, often a hat/mask; random gun skin and
  back bling; never a suit colour that reads as the other team. Team marks
  (armbands, chevron, visor, pack paint) always show the team colour.
- **Survival enemies** get a random small topper (beret, party hat, propeller
  cap, bow, tiny crown, sprout) or, on the Monolith/Ghost, a sticker. Their
  colour and outline never change.
- Shader warm-up now draws every mesh+material in the match and each enemy
  type once during loading (the cosmetics added new materials).
- Fixed: `PaintKit.variant` left a whole hidden copy of each cosmetic file
  alive (leak warnings at exit); deferred menu focus calls could hit a removed
  button.

## Map: "The Artist's Desk" (2026-10-01)
Same layout and collision (all 33 `_add_solid` calls identical to 3b09061);
only how things look changed.
- `arena_surface.gdshader` gained 10 skins chosen per box in arena.gd: the
  floor is a painting in progress (watercolour wash per zone, pencil guide
  lines and circles, painter's tape along the walls); low cover = stacks of
  three sketchbooks; hub pillars = crayon boxes; building walls = stretched
  canvases with murals in the zone colour; centre platform = stacked boards
  with an 8-point compass whose diagonal points use the four zone colours;
  ramps/rails/window bars = rulers; outer walls = a corkboard in a wooden
  frame; lane walls = a metal paint trough; SW deck = wooden planks.
- New props (`create_desk_props.py`): crayons in each pillar, giant pinned
  sketches on the corkboard (14), painter's tape at the corners.
- **Landmarks** outside each wall (`create_landmarks.py`), rising far above
  it, no shadows: NORTH giant easel with a painting, SOUTH jar of brushes, EAST
  paint tubes, WEST desk lamp with a glowing bulb.
- Removed from the dressing (models kept): the hub palette inlay (the compass
  replaces it), the perimeter banners and the perimeter framed murals (the
  pinned sketches replace them).
- Sunlit floor 191/255 Forward+, 197/255 Compatibility (unchanged).

## Online merge, pause menu, spectating and loadouts (2026-10-01)
Merged `origin/main` (b46987a, Rocklyn's online PR #4) into this branch.
`main` made both modes online and human-only; that direction was kept, with
the overhaul's look laid over it:
- **Menu:** `main`'s online setup (CREATE LOBBY / JOIN with a code) and online
  lobby (code in the header, START MATCH for the host only, a single PLAYERS
  list for Survival) rebuilt on the container layout. Mode descriptions use
  `main`'s wording.
- **Match:** `main`'s online controller, drawing with the overhaul HUDs: TDM
  uses `tdm_hud.gd` (score pill, Tab scoreboard filled from the server's
  kills/deaths, result screen) plus a new top-right **kill feed** in place of
  `main`'s centre banner; Survival uses `hud.gd` with a players-alive pill.
- **Other players** (`remote_player.gd`) are dressed as Canvas Runners in their
  own customization by `scripts/visual/remote_look.gd`, from outside the
  networking code. Their gun is the Paint Blaster prop on the same `AimPivot`
  (moved into the runner's hand), so it still follows their aim pitch.
- **Shots:** `main`'s small fast tracers with no impact splats (Rocklyn's
  recorded decision) replace the overhaul's splats; the crosshair hit marker
  is kept.

New features (Jarman's request):
- **Pause menu** (`scripts/ui/pause_menu.gd`), `Esc` in TDM and Survival:
  RESUME / LEAVE MATCH. Online, so the world keeps going; your own inputs stop.
- **10 second TDM respawn** (`RESPAWN_SECONDS` in `network_session.gd`) with a
  **death screen** (`scripts/ui/death_screen.gd`): who painted you out, the
  countdown, and **spectating** a living teammate
  (`scripts/spectator_camera.gd`) in third person or first person (`Q`/`E`,
  `V`).
- **Loadout:** five guns (`scripts/weapons.gd`) picked on the death screen and
  equipped on respawn — Brush Rifle (AR, unchanged), Fine Liner (sniper with a
  scope), Prism Beam (overheating rainbow energy gun), Splat Bucket (8-pellet
  shotgun), Blob Lobber (arcing splash launcher). Four new generated models
  (`tools/blender/create_weapon_*.py`) with first-person and one-piece prop
  copies; gun skins restyle them all. Shots carry the gun id so other players
  see the right gun and shot.

**Needs a server redeploy (Rocklyn):** the 10 s respawn, passing the gun id
along with shots, and accepting back bling 10–11 all live in the dedicated
server's copy of `network_session.gd`. Until the live server is updated it
keeps respawning after 3 s (the death screen simply closes early), other
players see everyone's shots as the Brush Rifle, and back bling 10–11 shows as
9 to others.

## Bugs discovered
Stage 1 (2026-09-29), on `main` at `3b09061`:
1. **TDM has no gameplay HUD.** `game.gd::_ready()` returns before
   `_build_hud()` in TDM: no crosshair, health, paint or pair readout.
2. **Scoreboard columns misalign.** Rows are space-padded strings in a
   proportional font; long names push K/D/A right; "• YOU" lands after the
   stats.
3. **Scoreboard Tab lag.** Visibility is polled every 0.25 s.
4. **Customize: option buttons overlap** and "PAINTBALL SPLATTER" extends past
   the panel into the 3D view.
5. **Customize: locked-category message** does not wrap and runs off the panel.
6. **Customize: title crowds its hint line.**
7. **Mode Select: descriptions are drawn over the buttons** instead of inside
   them.
8. **All menu buttons: text touches the left border** (no content margin).
9. **Fixed-pixel layout everywhere:** at 16:10 / 4:3 pages stick to the
   top-left with an empty band below. The TDM top bar is a fixed 1280 px wide.
10. **Back navigation inconsistent:** Esc does nothing on Mode Select;
    Settings' BACK skips the fade other pages use.
11. **Paint splats** are world-up squashed spheres: they stick out of walls and
    float in the air when they land on a moving target.
12. **Survival HUD, Apprentice Brush** shows a green "▲ Nothing yet" line that
    reads like a buff.
13. **`MECHANICS.md` Testing command is outdated:** the main scene is now the
    menu, so `-- --autoplay` without `res://scenes/match.tscn` tests nothing.
14. **Fragile lookup:** `player._apply_menu_customization()` finds the gun
    band as `_view_model.get_child(2)`.
15. **Environment (not code):** `.godot/` is owned by `root` (imports cannot be
    written), and Blender's glTF exporter needs `python3-numpy`, which is not
    installed.
16. **Survival can stall (pre-existing, found Stage 3):** enemies steer in a
    straight line with no pathfinding, so one can get pinned against the centre
    platform edge or in the recessed south lane; the autoplay bot cannot reach
    it either and the wave never clears. Reproduced on the untouched
    pre-overhaul code. Not fixed (gameplay).

Noted but **not** changed (gameplay): TDM respawn does not refill paint; TDM
never drops cores, so TDM players always carry the Apprentice Brush.

## Bugs fixed
Stage 6 (performance, found by measuring a full 2x10 TDM match):
- HUD widgets rewrote their labels (and a colour override) on every
  `stats_changed` - up to 60x/s - forcing text re-measure and container
  re-layout: ~7 ms per physics step. Now only written when the shown number
  changes.
- The hidden Tab scoreboard rebuilt all 20 rows on every death inside the
  physics step: ~3 ms per step. Now refreshes only while open.
- Bots carried the 27-part first-person blaster; now a one-piece copy
  (`paint_blaster_prop.glb`, 1 node / 4 materials). Props export as one mesh
  each. Bot gun/pack and flat wall props no longer cast shadows.
- A ~35 ms stutter at the first shot and first wall hit of every match (first
  load of the glob/splat models) -> `PaintKit.warm_up()` during arena setup.
- Result (this machine, TDM 20 players): draw calls 1280 -> ~730, objects
  drawn 3985 -> ~2070, physics step 13.2 -> ~8.5 ms, windowed ~200 -> ~330
  fps, slowest frame 65-90 ms -> 11-17 ms, 0 hitches.
- Blender: `remap_materials` must rebuild the slot list before reassigning
  faces (clearing materials resets every face to slot 0).

Stage 5:
- #11 Splats stuck out of walls / floated on moving targets -> surface-aligned
  splats on world hits only.
- #14 Fragile `get_child(2)` gun-band lookup -> named `SkinBand`.
- Found and fixed while integrating: `get_meta(key, null)` logs an error when
  the key is missing (a null default counts as "no default"); the flash
  helper checks `has_meta()` first.

Stage 4 (pipeline, found while building):
- `paintkit.parent()` / `set_origin()` read a stale `matrix_world` for parts
  whose transform had just been set in Python, so parts lost their rotation
  when parented (the first blaster preview had its body standing on end).
  Fixed by refreshing the view layer first.
- Parallel previews overwrote each other's temp tile (`_pk_tile.png`); temp
  name now includes the process id.
- Every material exported `doubleSided`; `mat()` now enables back-face culling
  by default (`double_sided=True` opts out).
- `build_all.sh` uses `--python-exit-code 1`, otherwise Blender reports success
  even when a script crashes.
- `__pycache__/` added to `.gitignore` (Blender's Python writes it when a
  script imports paintkit).

Stage 3:
- #1 TDM had no gameplay HUD → `tdm_hud.gd`.
- #2 Scoreboard columns misaligned → fixed-width cells.
- #3 Scoreboard Tab lag → checked every frame.
- #4–#10 Menu overlap/overflow/margins/fixed layout/Esc → container rebuild.
- #12 Apprentice shown as a buff → neutral "NO ABILITY · NO WEAKNESS".
- New, found and fixed in Stage 3: the health readout could show a negative
  number (e.g. -899) for one frame on a killing blow, because the player emits
  `stats_changed` before clamping health to 0. Display now clamps at 0; the
  player script is unchanged.

Online merge (2026-10-01), both found in code that came from `main`:
- Online Survival ran the offline wave code every frame against a HUD that is
  never built (`game.gd::_process` → `_update_offer` → `_hud.set_offer` on
  null), and a death would have called the offline ending the same way.
  `game.gd` now skips that code when the offline HUD does not exist, and only
  connects the offline death handler outside online matches.
- LEAVE LOBBY (or the server dropping while in the menu) made Godot reject the
  menu's lobby update ("Cannot convert argument 1 from Array to Array"):
  `NetworkSession` sends a plain empty list, the handler only took a typed
  one. The handler now accepts any list.
