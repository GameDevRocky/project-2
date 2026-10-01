# Visual + UX Overhaul Plan — Project 2: Inheritance

Status: **implemented (Stages 3–9 done, 2026-09-30).** What was built, every
deviation from this plan, and the test results are in
`docs/VISUAL_OVERHAUL_CHANGELOG.md`. Notable deviations: the runner's weapon
socket is on its real right hand (−X, not +X as §4.2 said); bots carry a
one-piece copy of the blaster (`paint_blaster_prop.glb`) for performance;
props export as one mesh each; a shader warm-up was added for the web
renderer.
Written 2026-09-29 against `main` at `3b09061` (after PR #3, TDM + frontend).

This is a **presentation pass**. Nothing in here changes how the game plays.
Every model, material, HUD widget and menu change sits *on top of* the existing
gameplay nodes and reads their state. It never replaces or duplicates that state.

---

## 0. Ground rules

### 0.1 Gameplay invariants (never edited)

| System | Values that stay exactly as they are | Where they live |
|---|---|---|
| Survival waves | 6 waves, `WAVES` table, +6%/wave health, +40 heal, 5 s breather, 0.35 s spawn stagger | `game.gd` |
| Paint | capacity 30, refill 11/s, refill delay 0.6 s, 1 paint per shot | `player.gd` |
| Pairs | every multiplier in `PAIRS` | `traits.gd` |
| Cores | 14 s lifetime, 2.6 m pickup range, `E` to inherit, replace-not-stack | `core_pickup.gd`, `game.gd` |
| Enemies | `TYPES` stats, AI, collision capsules (radius/height), aim-at-present-position | `enemy.gd` |
| Projectiles | damage, speed, splash maths, ray-based hit test, hit masks, 4 s life | `projectile.gd` |
| TDM | 2×10, 5 s lobby countdown, 600 s match, 3 s respawn, 8 s assist window, team-kill scoring, win/draw rule, bot targeting | `tdm_match_controller.gd`, `menu.gd` |
| Healing Station | 1.5 s hold, 5 s cooldown, 2.5 m range, `power_traded(power_type, player, station)` contract | `healing_station.gd` |
| Arena | 90 m square, every `_add_solid` box (position, size, rotation), spawn-point rules | `arena.gd` |
| Snitch Ball | **not implemented, not invented.** The seam stays untouched | `MECHANICS.md` |

### 0.2 Code ownership (from `MECHANICS.md`, kept)

| System | Owner | This pass may… |
|---|---|---|
| Survival logic | `game.gd` | not touch logic. `_build_hud()` still builds the Survival HUD |
| TDM match state | `tdm_match_controller.gd` | keep all state here. The HUD/scoreboard *drawing* moves to `scripts/ui/`, but the controller still creates it and is still the only thing that owns scores, timer, K/D/A |
| Survival UX | `hud.gd` | restyle with shared widgets while keeping its public API (`bind_player`, `set_wave`, `set_enemies_left`, `set_offer`, `announce`, `show_ending`) |
| TDM UX | `tdm_match_controller.gd` → `scripts/ui/tdm_*.gd` | build the new HUD, scoreboard, result screen |
| Menu | `menu.gd` | rebuild layout with containers; same screens, same flow, same data |

Permission to edit jcodes's files for this pass: see
`memory/jcodes-files-are-open-for-the-visual-overhaul.md`.

### 0.3 One source of truth

| Shown on screen | Read from | Never stored in UI |
|---|---|---|
| Health / max health | `player.health`, `player.max_health` via `stats_changed` | ✓ |
| Paint / capacity | `player.ammo`, `player.get_max_ammo()` via `stats_changed` | ✓ |
| Ability / weakness | `player.pair` via `pair_inherited` | ✓ |
| Timer | `controller.remaining` | ✓ |
| Team scores | `controller.scores` | ✓ |
| K / D / A | `controller.players[i]` | ✓ |
| Respawn countdown | the controller's respawn `SceneTreeTimer.time_left` (exposed by one getter) | ✓ |

The only UI-side values are purely cosmetic ones: the previous frame's paint
value (to show "REFILLING"), and tween positions.

---

## 1. What Stage 1 found

### 1.1 Technical facts that shape this plan

- **Everything is built in code.** The three `.tscn` files are 6 lines each and
  just attach a script, so every visual change here is a script change.
- **Two renderers.** Desktop F5 = Forward+. The GitHub Pages build =
  Compatibility. Compatibility **does not support `Decal`** (checked in the 4.7
  class reference), and it draws a shadowed sun ~2.7× brighter (already
  compensated in `arena.gd`). So paint splats must be mesh-based, and every
  lighting/material change gets screenshotted in both renderers.
- **Stretch mode** is `canvas_items` + `expand`, base 1280×720. At any 16:9 size
  (720p, 1080p, 1440p) the UI just scales uniformly. The layout only breaks at
  *other* aspect ratios (16:10, 4:3, ultrawide), which is where the fixed
  pixel positions show.
- **`.godot/` is owned by `root`.** Godot can read it but not write it, so new
  `.glb` files cannot be imported until ownership is fixed (Jarman runs
  `sudo chown -R jlion:jlion .godot icon.svg.import`; CLAUDE.md forbids me
  touching `.godot/`).
- **Blender 5.0.1** (Ubuntu package, Python 3.14) is installed, but its glTF
  exporter needs `numpy`, which is not installed. Fix: `sudo apt install
  python3-numpy` (Jarman's call: installing packages is ask-first). Fallback if
  declined: a small hand-written GLB writer inside `tools/blender/paintkit.py`
  (glTF is JSON + one binary buffer; no numpy needed).
- **The main scene is now the menu.** The Survival autoplay test must name
  `res://scenes/match.tscn`; `MECHANICS.md`'s Testing section is out of date.
  TDM has no test entry point, so testing uses a throwaway `SceneTree` script.

### 1.2 Menu inventory (every reachable page)

Route map: `Main → PLAY → Mode Select → {TDM → Lobby → countdown → Match → Result → Main}`
/ `{Survival → Match → end panel (R restarts)}`; `Main → Customize ⇄`;
`Lobby → Customize ⇄ Lobby`; `Main → Settings → Main`; `Main → Quit`.

| # | Page | Problems found (1280×720 unless stated) |
|---|---|---|
| 1 | Main | Button text touches the button's left border (no content margin). Fixed pixel card, so at 16:10/4:3 it stays top-left with dead space below. |
| 2 | Mode Select | Mode descriptions are separate labels drawn *on top of* the buttons, so the title is centred in the button and the description overlaps its lower half. Esc does nothing here (everywhere else it goes back). Card is not centred at 16:10. |
| 3 | TDM Lobby (waiting) | "OPEN SLOT" text flush against the slot edge. Bottom buttons 8 px from the screen edge, text flush left. Fixed layout leaves an empty band at 16:10. |
| 4 | TDM Lobby (countdown) | Same as 3. Countdown number is small for the most important info on screen. |
| 5 | Customize — item grid | Buttons grow to fit their text but are placed on a fixed 98 px grid, so they overlap ("DEFAULT BEAN" under "SKELETON", "WING/BUBBLE/SPLASH PACK" into the next column). "PAINTBALL SPLATTER" sticks out past the panel into the 3D view. |
| 6 | Customize — title | "CHARACTER / INSPECTION" (2 lines, 28 px) crowds the hint line directly under it. |
| 7 | Customize — locked category | "THIS COMPLETE SKIN DOES NOT SUPPORT THIS ACCESSORY" does not wrap and runs off the panel. |
| 8 | Settings | No value readout on the sliders. BACK skips the fade every other page uses. |
| 9 | TDM Result | Default-theme button; the stats line is spaced with typed spaces. |
| 10 | Survival end panel | Readable; will pick up the shared theme only. |

### 1.3 HUD / scoreboard findings

- **TDM has no gameplay HUD.** `game.gd::_ready()` returns before `_build_hud()`
  in TDM, so there's no crosshair, health, paint or pair readout; only the
  score/timer bar.
- **Scoreboard columns drift.** Rows are one string padded with spaces
  (`"%-24s %3d %3d %3d"`), but the font is proportional, so K/D/A never line up,
  a long name pushes its numbers right, and "• YOU" lands after the stats.
- The scoreboard shows/hides on a 0.25 s poll, so Tab can lag by up to 250 ms.
- **Survival HUD, Apprentice Brush:** shows a green "▲ Nothing yet — …" line,
  which reads like a buff. The spec asks that the Apprentice state clearly say
  *no ability, no weakness*.

### 1.4 Visual findings

- All five enemies are the same 7-segment ball in different colours, so they're
  identified by colour only.
- TDM combatants are team-coloured balls; no player model exists.
- Weapon = three boxes; the pair colour is a white cube at the tip.
- Cores = low-poly sphere + halo. Healing Station = three boxes + torus.
- Paint splats are squashed spheres aligned to world-up: on a wall they stick
  out horizontally, and on an enemy they hang in mid-air after it moves.
- Arena = flat-coloured boxes. Lighting was already fixed in the Stage-1
  brightness pass (`65d0d2e`); the room reads mid-value and uncluttered.

### 1.5 Fragile code the overhaul must respect

- `player._apply_menu_customization()` finds the gun-skin band as
  `_view_model.get_child(2)`. A new weapon model changes child order, so this
  becomes a named lookup.
- `player._muzzle` is both the glob spawn point (`_muzzle.global_position`) and
  the pair-colour readout (`_muzzle.material_override`). Both roles stay on
  one node.
- `enemy._mesh` is used by `_flash()` (emission spike) and `_die()` (squash
  tween). The new visual keeps a single root to squash, and flash moves to a
  `material_overlay` so it works on multi-mesh models.
- `enemy._die()` squashes the **mesh**, never the body (Jolt rejects
  non-uniform body scale — see memory). New visuals follow the same rule.

---

## 2. Art direction — "Stylized Combat Art Studio"

The arena is an oversized artist's studio that has been turned into a sports
court: primed-canvas floors, plaster walls with painted bands, giant tools
leaning in the corners, and paint everywhere combat has happened. Combatants
are chunky, toy-like-but-not-childish machines and painters, built from art
tools (spray cans, rollers, brushes, stretcher frames, palette knives).

### 2.1 Readability rules (in priority order)

1. **Silhouette first.** Every archetype must be nameable from its outline
   alone at 30 m. Colour is the second cue, never the only one.
2. **Value structure.** The room sits in the middle of the brightness range
   (Stage-1 rule, kept). Pastel enemies sit *above* it (brighter, emissive
   trims); the charcoal Monolith sits clearly *below* it.
3. **Only gameplay glows.** Emission is reserved for combatants' accent
   trims, paint (globs, cores, reservoir fill), and interaction points. The
   room never crosses the glow threshold.
4. **Wet vs dry.** Fresh gameplay paint is glossy (low roughness, slight
   emission); decorative dried paint in the room is matte. That's how you
   tell a live splat from set dressing.
5. **Keep the centre clean.** HUD elements stay out of the middle ~40% of the
   screen, except the crosshair and the transient prompt below it.

### 2.2 Palette

| Role | Colours | Notes |
|---|---|---|
| Archetype / pair colours (unchanged) | Sprayer pink `#FFB7C5`, Bounder mint `#98FF98`, Blotter teal `#00A896`, Monolith charcoal `#2B2D42`, Ghost white `#FFFFFF` | from `traits.gd`; used on enemies, cores, pair UI, player brush |
| Team colours (kept) | RED `#FF627E`, BLUE `#58D7F2` | from jcodes's menu/controller. Centralised into one file instead of four copies |
| Room neutrals (unchanged values) | floor `#C4BCB3`, walls `#6C6592`, cover slate/rose/sage/teal/pale | Stage-1 tuned; the shader adds texture, not brightness |
| Studio "dried paint" accents | ochre `#C9A45C`, lilac `#9C8FC4`, clay `#B7806E`, sea-glass `#7FA9A3` | set-dressing only, deliberately muted and never an exact archetype hue |
| Ink (UI dark, outlines) | `#1B1D2B` / `#2B2D42` | text outlines, panel backs |
| UI surfaces | panel `#12141F` @ 92%, panel line `#2E3247`, text `#F4F1FF`, dim text `#A7A9BC` | shared theme |
| Benefit / cost | benefit `#8CFF9E`, cost `#FF8FA0`, neutral `#C9CBD8` | pair UI |

**Team vs archetype rule.** Team colour only ever appears as *team marks*:
armbands, visor strip, chest chevron, reservoir paint, TDM paint globs, and UI.
Archetype colours only appear on enemies, cores and the inheritance UI. TDM
spawns no archetype enemies and drops no cores, so the two sets never share a
screen in a way that confuses inheritance.

### 2.3 Material families (all `StandardMaterial3D`, all Compatibility-safe)

| Family | Albedo | Roughness | Metallic | Emission | Used for |
|---|---|---|---|---|---|
| Ceramic white | `#F2EEE6` | 0.45 | 0 | – | weapon body, runner helmet, station frame |
| Painted metal | per part | 0.38 | 0.35 | – | ferrules, rails, pistons, caps |
| Matte plastic | per part | 0.7 | 0 | – | grips, casings, enemy shells |
| Rubber | `#2A2C3A` | 0.9 | 0 | – | grips, boots, hoses |
| Canvas | `#E9E1D2` | 0.95 | 0 | – | Ghost drapes, banners, Monolith slab faces |
| Paint tank glass | colour @ 45% alpha | 0.1 | 0 | fill glows 0.4–0.8 | reservoirs (glass shell alpha; fill opaque) |
| Wet paint (gameplay) | archetype/team colour | 0.15 | 0 | 0.6–1.8 | globs, drips, accent trims, cores |
| Dried paint (decor) | studio accents | 0.85 | 0 | – | splotches, drips on props |

Transparency is limited to glass shells, core halos and the Ghost's outer veil,
and always sits over an opaque inner part, so nothing important is only a
see-through surface.

### 2.4 Geometry language

Chunky, rounded, bevelled (2–4 segment bevels on every hard edge), slightly
oversized functional parts (nozzles, caps, rollers), with thick silhouettes and
no sub-2 cm detail. Flat-shaded faces are avoided; smooth-by-angle (~35°)
gives soft forms that still hold a crisp outline.

---

## 3. Asset pipeline

### 3.1 Folders

| Path | Contents |
|---|---|
| `tools/blender/paintkit.py` | shared helpers (scene reset, working collection, primitives, bevel, materials, origin, export, tri-count report) |
| `tools/blender/create_*.py` | one script per asset (list in §4) |
| `tools/blender/build_all.sh` | runs every script in order |
| `models/generated/*.glb` | exported models (plus Godot's `.glb.import` files, committed) |
| `scripts/visual/paint_kit.gd` | Godot-side helpers: instance a model, recolour by material name, hit-flash overlay |
| `scripts/visual/*_visual.gd` | small per-object visual drivers (animation only, read-only on gameplay state) |
| `scripts/ui/…` | shared theme + HUD widgets + TDM HUD/scoreboard/result |

`assets/` is **not** used (CLAUDE.md forbids it). No `.blend` files are saved
inside the project: Godot would try to import them and require every teammate
to have Blender configured. The scripts are the source of truth. Re-running
them regenerates the GLBs exactly (fixed random seeds).

### 3.2 Blender conventions

- Units: metres, 1 BU = 1 m. Run with
  `blender -b --factory-startup --python tools/blender/create_x.py -- <out.glb>`.
- **Axes.** glTF export (+Y up) maps Blender −Y to Godot +Z. Enemies and
  runners face Godot **+Z** (`enemy._face()` turns +Z toward the target), so
  they are modelled facing **Blender −Y**. The weapon points down Godot −Z
  (camera forward), so it is modelled pointing **Blender +Y**.
- **Origins.** Characters: between the feet at floor level (matches the
  capsule, whose base is at the body origin). Weapon: the grip's pivot, with
  the `Muzzle` object's origin placed at the glob spawn point. Props: base
  centre.
- **Hierarchy.** Moving parts are separate objects parented to a named root,
  with origins on their pivots (e.g. `Leg_L` at the hip). Names survive into
  Godot as node names, so visual scripts can find them.
- **Material slots are named by role**, not by colour: `PK_Body`, `PK_Trim`,
  `PK_Accent` (archetype/pair colour), `PK_Team` (team colour),
  `PK_AccentGlow`, `PK_Glass`, `PK_Fill`, `PK_Metal`, `PK_Rubber`,
  `PK_Canvas`, `PK_Dark`, `PK_Wet`, `PK_Dry1..4`. Godot swaps these for runtime
  materials by name, so gameplay colours stay code-driven (`traits.gd`, team
  constants) and never get baked into a file.
- Modifiers (bevel, solidify, mirror, at most one subsurf level) are applied on
  export. Smooth-by-angle 35°. Exported with `export_apply=True`, no cameras
  or lights. Each script prints its triangle count and fails if it's over
  budget.

### 3.3 Godot integration pattern

```
Existing gameplay node   (CharacterBody3D / Node3D - unchanged)
├── CollisionShape3D      (unchanged)
├── existing script       (unchanged behaviour)
└── Visual (Node3D)       ← NEW: instance of models/generated/x.glb
    └── …meshes, recoloured at runtime by material name
```

- Default GLB import settings (no generated collision, LODs on). Imported
  models are **never** given physics shapes; collision stays whatever the
  gameplay script already builds.
- Visual roots are scaled uniformly only. Squash animations run on the
  visual root, never on a physics body.
- `paint_kit.gd` exposes: `instance_model(path) -> Node3D`,
  `recolor(root, {"PK_Accent": Color, …})`, `find_part(root, name)`,
  `flash(root, strength, seconds)` (tweens a shared white `material_overlay`
  so hit flashes work on any multi-mesh model).
- If a GLB is missing (script not run yet), every call site falls back to
  today's primitive mesh, so the game never breaks mid-pipeline.

---

## 4. Asset designs

Budgets are in **triangles** after modifiers. Heights are chosen to match the
existing collision capsules, so shots land where the model is.

### 4.1 Player weapon — "Paint Blaster" (`paint_blaster.glb`)

**Purpose.** The first-person gun; also carried by TDM runners (same model).

**Silhouette.** A long, chunky artist's brush fused onto a pressure sprayer.
From first person: a fat flared bristle head at the tip, a glass paint tank on
top, and a loop of hose between them. Nothing reads as a real firearm: no
magazine, no stock, no barrel shroud.

**Theme.** A painter's tool turned into a blaster: bristles instead of a
barrel, paint tank instead of a magazine, a pressure gauge instead of sights.

**Main shapes.**
- Grip: rounded rubber handle raked 15° back, finger grooves, with a
  trigger inside a round trigger guard.
- Body: ceramic-white pressure chamber (bevelled cylinder, r 0.045, 0.30 long)
  with two painted-metal hoop bands.
- Skin band: one wide band on the body (gun-skin colour).
- Paint tank: glass capsule on top (r 0.035, 0.16 long) with an inner `Fill`
  cylinder, plus a brass cap and pressure valve.
- Hose: tube from the tank rear, looping down and forward into the ferrule
  (curve → bevel depth).
- Gauge: small round dial on the left (−X) face, which is the side the player
  sees.
- Ferrule: crimped metal collar (two crimp rings).
- Bristles (`Muzzle`): flared tuft, 12 clumped wedges, slightly splayed.
- Wet drips: 3 drips hanging off the ferrule.

**Materials.** Ceramic white body, rubber grip/hose, painted metal ferrule and
bands, glass tank, `PK_Fill` + `PK_Accent` + `PK_Wet` = the current **pair
colour** (bristles, tank fill, drips), `PK_Skin` = gun-skin band (its own role,
so the menu's gun skin never shares a material with team colour; on TDM
runners the same band takes the team colour).

**Accent colours.** The bristles, the tank fill and the ferrule drips carry the
pair colour. That's today's "white cube at the tip" readout, made bigger and
more obvious. The skin band carries the menu gun-skin colour, as today.

**Animation.**
- Tank `Fill` scales on Y with `ammo / get_max_ammo()` (read-only), so the
  gun's own tank is a second paint gauge.
- Bristles squash 10% on each shot (the existing kick already moves the
  whole view model).
- Gauge needle rotates with the fill level.
- A small muzzle paint puff (Stage 7).

**Gameplay constraints.** `_muzzle` stays a `MeshInstance3D` whose origin is
the glob spawn point at view-model local `(0, 0, −0.36)`, same as today, so
aim-toward-crosshair maths is unaffected. `_view_model_home`, sway, bob and
kick are unchanged. Fire timing, paint cost, damage and projectile code are
untouched. `_apply_pair()` still recolours the muzzle; it now also recolours
the fill/drips through the same call.

**Budget.** ≤ 3,500 tris (on screen every frame, so it gets the most detail).

**Blender construction.** Cylinders/capsules from `bpy.ops.mesh.primitive_*`,
each bevelled. Grip is a bmesh profile extruded and bevelled. Hose is a Bezier
curve with bevel depth 0.012, converted to mesh. Bristle tuft: 12 wedge prisms
arranged radially, each tapered and randomly tilted (seed 11), then joined.
Trigger guard: a torus segment. Drips: UV-sphere teardrops (scaled top). The
root empty `PaintBlaster` sits at the grip pivot. `Muzzle` origin is snapped to
`(0, +0.36, 0)` in Blender (+Y forward), so after export it lands at
`(0, 0, −0.36)`.

**Godot integration.** `player._build_view_model()` instances the GLB under
`_view_model` (scale 1). `_muzzle` = the `Muzzle` mesh node. The band lookup
becomes `find_part(model, "SkinBand")`. `_apply_menu_customization()` and
`_apply_pair()` use `recolor()`. Falls back to the three boxes if the file is
missing. No collision (the view model never had any).

---

### 4.2 Player character — "Canvas Runner" (`canvas_runner.glb`)

**Purpose.** The body of every TDM combatant. In this build that means the 19
bots, the "other players". The local player never sees their own body (first
person), so nothing changes for them.

**Silhouette.** A chunky arena painter at 1.6 m: big rounded helmet with a
wide visor band, broad padded shoulders, a slightly forward athletic lean, big
boots, the Paint Blaster held across the body, and the Chromatic Reservoir on
the back. It reads as "person with a paint gun and a tank", which is different
from every enemy silhouette.

**Theme.** Painter's jumpsuit and gloves, splattered with dried paint in
studio colours. The helmet is a smooth ceramic "blank canvas" face with a visor.

**Main shapes.** Boots (bevelled blocks, rubber soles) · padded legs (tapered
capsules, knee pads) · torso (rounded box, apron panel, chest chevron) ·
shoulder pads (flattened spheres) · arms (capsules with gloves, posed holding
the blaster) · helmet (sphere with a flattened front, visor band inset) ·
`Socket_Back` (empty) for the reservoir · `Socket_Hand_R` (empty) for the
blaster.

**Materials.** Jumpsuit off-white canvas `#E9E1D2`, rubber boots/gloves,
ceramic helmet, `PK_Team` on the armbands, visor strip (emissive), chest
chevron and knee pads, `PK_Dry1..4` splotches.

**Accent colours.** **Team colour only** (see §2.2 rule). No archetype colour
appears on a runner.

**Animation.** No skeleton. `runner_visual.gd` animates separate parts: legs
swing about the hip on X in step with ground speed, body bob and forward lean
from velocity, a small recoil on firing, and a death squash on the visual root
(replacing today's mesh squash).

**Gameplay constraints.** TDM bots keep `enemy.gd`'s capsule (r 0.4, h 1.6),
layers, groups (`enemies`, `tdm_combatants`), `tdm_team`, targeting, respawn
and scoring. The model fits inside that capsule (±10% at the shoulders), so
hits match what you see. The overhead health bar stays at `height + 0.45`.

**Budget.** ≤ 3,000 tris (×19 on screen at worst, plus the blaster via LOD).

**Blender construction.** Primitive parts bevelled then smooth-by-angle,
mirrored left/right with a Mirror modifier. Legs are separate objects with
their origin at the hip. Dried-paint splotches are flattened icospheres
shrink-wrapped onto the suit (seed 21). Sockets are empties.

**Godot integration.** In `enemy._build_mesh()`: if `tdm_team` is set,
instance `canvas_runner.glb` (+ reservoir at `Socket_Back`, blaster at
`Socket_Hand_R`) instead of the Sprayer body. `PK_Team` becomes the team
colour. `_mesh` becomes the visual root. Collision is not touched.

**Decision for Jarman — menu character.** The menu's customize screen uses
jcodes's **bean** (with 10 skins, hats, masks and back blings that are placed
to fit the bean's shape). This plan **leaves the menu bean as is** and uses the
Canvas Runner only in-match. Swapping the menu bean for the runner would break
the positions of every hat, mask and back bling jcodes built. The alternative
is to plug the runner in as an 11th skin through jcodes's `scene_path` seam in
`character_customization_data.gd`, which is a new cosmetic option. Say if you
want that instead.

---

### 4.3 Back bling — "Chromatic Reservoir" (`chromatic_reservoir.glb`)

**Purpose.** The visible paint supply on every runner's back. It explains where
the paint comes from and makes team identity readable from behind.

**Silhouette.** A vertical glass paint tank in a sturdy frame, two domed
pressure caps, one hose arcing over the right shoulder, and a small brush
holstered diagonally. Stays inside the shoulder line (≤ 0.40 m wide, ≤ 0.55 m
tall, ≤ 0.24 m deep), so the runner's outline stays a person, not a
backpack.

**Theme.** An artist's paint canister turned into life-support.

**Main shapes.** Frame (two rounded rails + three cross straps) · tank (glass
capsule r 0.11, 0.38 tall) with inner `Fill` · caps (domed cylinders, painted
metal) · regulator block with a round gauge · hose (Bezier) · holstered brush
(handle + ferrule + tuft).

**Materials.** Painted metal frame and caps, rubber hose and straps, glass
shell, `PK_Fill` (team colour, emissive 0.5), ceramic regulator.

**Accent colours.** Tank fill and cap rings in team colour.

**Animation.** The fill's surface bobs slightly when the runner moves (slosh),
and the gauge needle jitters when firing. Bots have no paint counter, so the
fill level itself stays full rather than inventing a fake value.

**Gameplay constraints.** Visual child only: no collision, no data.

**Budget.** ≤ 1,200 tris.

**Blender construction.** Same kit. Exported as its own GLB with its origin at
the mounting point (the back plate centre), so it snaps to `Socket_Back`.

**Godot integration.** Instanced into the runner's `Socket_Back` by
`runner_visual.gd`. Recoloured through `PK_Fill`/`PK_Team`.

---

### 4.4 Sprayer — pink (`enemy_sprayer.glb`)

**Purpose.** Fast trigger, weak globs, fragile (Sprayer's Pair: Rapid Brush /
Thin Paint).

**Silhouette.** Slim and upright: a tall narrow spray-can body on two thin
spring legs, with a **fan of five small nozzles** sticking out the front like a
crown. The thinnest, spikiest outline in the game.

**Theme.** An aerosol can that learned to run. Speed + volume.

**Main shapes.** Can body (cylinder r 0.2, 0.7 tall, rounded shoulder) tilted
8° forward · dome cap head with one visor slit · a 5-nozzle fan on the front
(`NozzleFan`, a separate object that spins while firing) · a tiny reservoir
bulb on the back · two thin digitigrade legs with small feet · two stubby fins.

**Materials.** Ceramic white can wrapped in two wide **pink** bands
(`PK_Accent`) · metal nozzles · wet pink drips under the nozzles · dark visor
slit (emissive pink 0.6).

**Accent colours.** Pink bands, visor, drips, reservoir fill.

**Animation.** `NozzleFan` spins briefly on each shot (hooked to the existing
`_flash()` call made when it fires). Legs bounce with speed. Hit flash via
overlay.

**Gameplay constraints.** Capsule r 0.4 / h 1.6 unchanged; model height
1.6 m, width ≤ 0.8 m. Health bar position unchanged.

**Budget.** ≤ 1,500 tris.

**Blender construction.** Lathe (spin) profile for the can and cap, 5 nozzles
duplicated with 18° spacing, leg = 3 bevelled segments per side (mirror).

**Godot integration.** `enemy._build_mesh()` chooses the GLB by `type_id`.
`PK_Accent` = `stats.color`. `_mesh` → visual root (for the squash). `_flash()`
→ `paint_kit.flash()` + a "fired" pulse to the visual driver.

---

### 4.5 Bounder — mint (`enemy_bounder.glb`)

**Purpose.** Melee rusher that strikes and withdraws (Light Step / Brittle
Canvas).

**Silhouette.** Low, wide and bottom-heavy: two big **coil-spring legs**, a
compact forward-hunched torso, and two oversized **paint-roller fists**. No gun.
Reads as "it will jump at you".

**Theme.** A house-painter's roller turned brawler. Mobility and impact.

**Main shapes.** Coil springs (helix, 5 turns) inside piston sleeves · rounded
torso shell · small head bump with twin eye lights · arms ending in paint
rollers (cylinder r 0.12, 0.3 long, on a handle yoke) dripping mint.

**Materials.** Matte plastic shell `#DCE6DE` with **mint** panels · metal springs ·
rollers covered in wet mint paint.

**Accent colours.** Mint shell panels, rollers, eyes.

**Animation.** Springs compress/extend with vertical bob at run speed. Rollers
swing forward on a melee hit (a one-line visual hook added in
`_try_attack()`, after the damage call, which changes nothing it does). Rollers
spin with movement.

**Gameplay constraints.** Capsule r 0.45 / h 1.4 unchanged; standoff and reach
logic untouched. Model 1.4 m tall, ≤ 1.0 m wide at the fists.

**Budget.** ≤ 2,000 tris.

**Blender construction.** Springs from a spiral curve (screw modifier on a
circle) → mesh; rollers are bevelled cylinders; everything mirrored.

**Godot integration.** Same as 4.4.

---

### 4.6 Blotter — teal (`enemy_blotter.glb`)

**Purpose.** Slow artillery with big splash (Splatter Rounds / Heavy
Reservoir).

**Silhouette.** Round, tank-heavy and wide: a big glass **paint tank body**
on four stubby splayed legs, with a short fat **mortar tube** angled 50° up.
The widest, roundest outline.

**Theme.** An ink blotter / paint bucket turned siege engine. Weight + splash.

**Main shapes.** Tank (sphere r 0.5, flattened top, glass shell over a teal
fill with a visible fill line) · metal equator band with rivets · mortar
(cylinder r 0.16, 0.55 long, flared muzzle) on a yoke · a big **glob** visible
in the mortar mouth · 4 stubby legs.

**Materials.** Glass tank + **teal** fill (emissive 0.6) · painted-metal band,
yoke and legs · wet teal glob.

**Accent colours.** Tank fill, glob, muzzle ring.

**Animation.** Mortar recoils and the glob disappears then refills on each
shot (the visual reads its own "fired" pulse; interval stays in `enemy.gd`).
Fill sloshes with movement.

**Gameplay constraints.** Capsule r 0.6 / h 1.7 unchanged. Model 1.7 m to the
mortar tip, ≤ 1.3 m wide.

**Budget.** ≤ 2,500 tris.

**Blender construction.** UV sphere for the tank with the top flattened by a
bisect; mortar is a lathe profile; legs are bevelled boxes, 4× radial array.

**Godot integration.** Same as 4.4. The glass shell is the only alpha
material, and it sits over the opaque fill.

---

### 4.7 Monolith — charcoal (`enemy_monolith.glb`)

**Purpose.** Armoured, slow, hard-hitting (Thick Coat / Sluggish Brush).

**Silhouette.** A massive **rectangular stack of slabs**: a tall block body,
enormous shoulder blocks, and a heavy flat **house-brush cannon** on the right
arm. The only boxy, top-heavy enemy.

**Theme.** A golem built from canvas stretcher frames caked with layers of
dried paint. Armour + weight.

**Main shapes.** 4 stacked slabs (each offset and bevelled, with dried-paint
drip edges) · shoulder blocks · recessed head with a narrow glowing slit ·
right arm = wide flat brush cannon (bristle block + ferrule) · left arm = slab
shield · thick column legs.

**Materials.** Charcoal matte slabs (`PK_Accent` = charcoal) · slab edges in
dried-paint accents (ochre/lilac/clay) so the dark mass still reads in shadow ·
slit and cannon ferrule glow soft white-violet.

**Accent colours.** Charcoal body (the archetype colour); a light edge trim
keeps the silhouette visible against the dark walls.

**Animation.** Slow "breathing" rise of the top slab. The cannon recoils on
firing. Heavy footfall bob.

**Gameplay constraints.** Capsule r 0.75 / h 2.3 unchanged. Model 2.3 m, ≤ 1.7 m
wide at the shoulders (≤ 15% outside the capsule, visual only).

**Budget.** ≤ 2,500 tris.

**Blender construction.** Bevelled boxes (3 segments), drip edges = a row of
short extruded teardrops along each slab's bottom edge (seed 44).

**Godot integration.** Same as 4.4. The base emission stays low (it's meant to
be the darkest thing in the arena), and the trim material carries the
readability.

---

### 4.8 Ghost — white (`enemy_ghost.glb`)

**Purpose.** Regenerating skirmisher (Second Wind / Faded Pigment).

**Silhouette.** Narrow, tall and **floating**: a hooded, draped canvas form
with no legs (the hem hovers 0.25 m off the floor), trailing ragged canvas
strips behind it. The only enemy with a gap under it.

**Theme.** A painter's drop-cloth come alive. Regeneration + fading.

**Main shapes.** Hooded drape (cone-ish lathe with folds) · dark face void with
two soft glowing eyes · 5 trailing `Strip_*` ribbons (separate objects, pivot
at the top) · a small palette-knife "wand" arm.

**Materials.** Opaque canvas white body, with a dark **ink hem trim** so it
reads against the pale floor · a 40%-alpha outer veil on 2 strips only · glowing
eyes · faint white wisps.

**Accent colours.** White body. Eyes and trim glow while regenerating.

**Animation.** Float bob and strip sway. **Regeneration pulse**: when its
health rises (read each frame by the visual; no new state), the eyes and hem
brighten, so you can see it healing.

**Gameplay constraints.** Capsule r 0.4 / h 1.7 unchanged. The model fills the
capsule, and the opaque body is never transparent, so it stays easy to target.

**Budget.** ≤ 1,500 tris.

**Blender construction.** Lathe profile with a noise displace (seed 55) for the
folds. Strips are subdivided planes with solidify, and their origins sit on
their top edges.

**Godot integration.** Same as 4.4.

---

### 4.9 Inheritance core — "Pigment Heart" (`core_pigment.glb`)

**Purpose.** The dropped pair (14 s, press `E`).

**Silhouette.** A faceted paint droplet suspended inside a slowly turning
**brush-ferrule ring**, with a small wet puddle on the floor beneath it.

**Theme.** Concentrated living paint.

**Main shapes.** Droplet (icosphere teardrop, faceted, r 0.22) · ring (torus
r 0.42) with 12 raised **tick segments** `Tick_00..11` · two thin gimbal hoops
· floor puddle (flat splat).

**Materials.** Droplet = pair colour, emissive 1.6 (as today) · ring painted
metal with pair-colour ticks · puddle wet pair colour.

**Accent colours.** Everything reads in the pair colour. The ring metal is
neutral, so charcoal (Monolith) and white (Ghost) cores still read.

**Animation.** Existing spin/bob/halo pulse/last-3-seconds blink kept. **Time
readout:** one tick goes dark every 14/12 s (`_age / lifetime`, read-only), so
the 14-second lifetime is visible as a draining clock. Gimbals rotate.

**Gameplay constraints.** `lifetime`, `pickup_range`, `collect()`,
`distance_to_player()`, the `cores` group and the offer logic in `game.gd` are
untouched. `_mesh`/`_halo` keep their roles (the droplet and the halo).

**Budget.** ≤ 900 tris.

**Blender construction.** Icosphere (subdiv 2) pulled into a teardrop; torus;
ticks = 12 bevelled boxes on a radial array. The puddle comes from the splat
generator (4.12).

**Godot integration.** `core_pickup._build_visuals()` instances the GLB
(fallback: today's sphere). Recolour `PK_Accent`. `_process` hides ticks by
age.

---

### 4.10 Healing Station — "Paint Restoration Station" (`healing_station.glb`)

**Purpose.** Hold `E` 1.5 s to heal fully. 5 s cooldown.

**Silhouette.** A stout three-legged **easel** holding a round **palette basin**
of glowing restorative paint at waist height, with a small canvas panel above
it painted with a bold "+". Distinct from every combatant and prop.

**Theme.** Where paint gets restored.

**Main shapes.** Easel A-frame (3 bevelled legs + cross bar) · palette-shaped
basin (kidney disc with a thumb hole) holding a `Basin` paint surface · canvas
panel with a painted plus · a brush cup · the progress ring (`_ring`), restyled
as a paint ring.

**Materials.** Warm wood-look painted easel (matte) · ceramic basin · `Basin`
surface = `_core_material` (READY teal `#36E6D2` / COOLDOWN `#536C70`,
emissive as today).

**Accent colours.** Basin + plus sign = state colour.

**Animation.** Basin surface ripples slowly when READY, and the plus sign pulses.
While INTERACTING, the existing `_ring` scale-up drives a spiral of rising
paint motes.

**Gameplay constraints.** **No collision** (the station has none today, so
adding some would change movement). Footprint ≤ 1.1 m × 1.1 m, height ≤ 1.5 m.
`Area3D`, `interaction_range`, state machine, `_status` Label3D,
`station_state_changed` and **`power_traded(power_type, player, station)` are
untouched.** No Snitch logic.

**Budget.** ≤ 2,000 tris.

**Blender construction.** Bevelled boxes/cylinders; the basin is a kidney
curve extruded and bevelled; the plus is a bevelled cross.

**Godot integration.** `healing_station._build_visuals()` instances the GLB.
`_core_material` = the runtime material assigned to `Basin`. `_ring` and
`_status` keep their current node roles. Fallback: today's boxes.

---

### 4.11 Paint projectile — "Glob" (`paint_glob.glb`)

**Purpose.** The single shared projectile (player, enemies, TDM bots).

**Silhouette.** A glossy teardrop stretched along its flight direction, with
two small trailing droplets.

**Theme.** Thrown paint, not a bullet.

**Main shapes.** Teardrop (low-poly smooth, r 0.14 like today's sphere) +
2 tail droplets.

**Materials.** Wet paint, glob colour, emission 1.8 (as today), fog-immune.

**Animation.** Oriented along `direction` once in `setup()`. A slight wobble
scale in `_process`.

**Gameplay constraints.** Everything in `_physics_process`, `_impact`,
`_splash`, masks, damage and life stays as is. Visual only.

**Budget.** ≤ 120 tris (dozens alive at once).

**Blender construction.** UV sphere (8×6) stretched and tapered. The
droplets are small icospheres.

**Godot integration.** `projectile._ready()` instances a **preloaded,
shared** mesh (no per-glob import cost) and sets its own material as today.
Fallback: today's sphere.

---

### 4.12 Arena decorative props (`prop_*.glb`)

**Purpose.** Give each area of the map an identity without changing the map.

**Placement rules (hard).**
1. No prop adds or changes collision.
2. Props go only where they can't be walked into or shot "through" in a way
   you'd notice: **flush on walls** (≤ 0.35 m deep), **above head height**
   (≥ 4.5 m, beyond even a Light-Step jump from the centre platform), **on top
   of existing solids**, or **as flat floor/wall paint** (≤ 2 cm).
3. Nothing goes in a doorway (3.6 m openings), on a ramp, on the SW upper deck
   floor, in the recessed lane floor, or on the spawn ring (r 36).

| Prop | Shape | Where |
|---|---|---|
| `prop_paint_tube` | giant squeezed tube, crimped end, cap (3 m) | flush along perimeter walls, standing on end |
| `prop_giant_brush` | 4 m brush, wet tip | flush against perimeter corners |
| `prop_can_stack` | stacked paint cans with drips | wall tops of the NW building (paint storage) |
| `prop_mixing_vat` | ribbed vat + paddle | wall tops of the NE building (mixing room) |
| `prop_frame` | ornate picture frame + painted canvas (flat) | walls of the SW building (gallery) |
| `prop_banner` | hanging canvas banner strip | perimeter walls, above 4.5 m |
| `prop_pipe_run` | pipe segment with brackets | top edge of the south lane walls (runoff channel) |
| `prop_palette_inlay` | palette-shaped paint inlay (flat, 1 cm) | top of the central platform (hub motif) |
| `prop_hub_mobile` | hanging sculpture of 5 brush-stroke ribbons | above the hub, 6.5–8.5 m |
| `prop_splat_decor` | dried splat variants (flat) | floors/walls near combat areas, matte |

**Regions.** Central hub: palette inlay + mobile, and the four hub pillars get
a painted "brush handle" band via material. NW: paint storage (ochre bands,
can stacks). NE: mixing room (lilac bands, vats). SW: gallery (rose bands,
frames, banners). South lane: runoff channel (sea-glass bands, pipes, drip
stains down the retaining walls).

**Materials.** Dried-paint accents only. Nothing emissive. Matte.

**Budgets.** 150–1,500 tris each; the whole dressing set ≤ 40k tris on screen.

**Blender construction.** `create_arena_props.py` exports one GLB per prop from
the same kit (tube = lathe + crimp; brush = handle + ferrule + tuft; frame =
bevelled profile swept around a rectangle; mobile = 5 twisted ribbon
strips).

**Godot integration.** A new `_build_dressing()` in `arena.gd` places prop
instances from a readable table, like `COVER`. It adds visuals only, with no
`_add_solid` calls, and runs after all solids are built.

### 4.13 Paint impacts, environment surfaces (Godot-side)

**Splats (`paint_splat.glb`).** Irregular flat splat (≤ 80 tris) + 3 satellite
droplets. Several variants from seeds 1–4.

- Placement: `projectile._impact()` receives the ray's hit **normal** (already
  in the `intersect_ray` result). The splat sits at `hit + normal × 0.012`, is
  rotated so its up = normal, gets a random spin around the normal, and a
  scale of 0.8–1.2 (0.6–0.8 for splash bursts).
- **World hits only** (layer 1). Hits on combatants spawn a small droplet burst
  instead, so nothing floats in mid-air when the target moves.
- Lifetime: fade after 6 s (today ~2.3 s). A group cap of 64 live splats: the
  oldest is released first. That's the existing fade-and-free cleanup, just
  bounded.
- Mesh-based, not `Decal`, because the web build (Compatibility) has no decals.

**Surface shader (`scripts/visual/arena_surface.gdshader`).** One small
spatial shader for floors/walls/cover: faint world-space canvas weave (two
sine-thread patterns), soft darkening at box edges (computed from local
position vs a `size` uniform), and an optional painted band (height + colour
uniforms). It adds texture but no brightness: the mean albedo matches today's
colour. Every existing `_add_solid` keeps its body and shape; only the visible
material changes.

---

## 5. UI plan

### 5.1 Shared theme — `scripts/ui/ui_theme.gd`

A static `build() -> Theme` so the menu and both HUDs share one look:
- **Buttons.** Content margins (18 px left/right, 10 px top/bottom), so text
  never touches the border. Distinct normal/hover/pressed/focus/disabled
  styles, with a thick paint-edge left border on hover/focus.
- **Panels.** `PanelContainer` style: dark ink panel, 1–2 px line, 10 px
  radius, soft shadow.
- **Labels.** Outlines (HUD), size scale (title 40 / header 24 / body 16 /
  small 12). Nothing under 12 px.
- LineEdit and HSlider styled to match.
- Default engine font kept (no font download). Weight via `FontVariation`
  embolden for titles.

### 5.2 Shared HUD widgets — `scripts/ui/widgets/`

| Widget | What it draws | Data in |
|---|---|---|
| `crosshair.gd` | 4 arms, 5 px gap, 2 px, white with a 1 px ink outline, centre dot; optional hit tick | none (+ `pulse()` for fire/hit) |
| `health_meter.gd` | big number + 10-segment bar, low-health pulse under 30% | `set_values(hp, max)` |
| `paint_tank_meter.gd` | a paint-tank gauge (rounded vessel with fill + meniscus), "24 / 30", REFILLING tag while it rises | `set_values(ammo, max)` |
| `inheritance_card.gd` | pair name in pair colour, ▲ benefit line (green), ▼ cost line (red); **Apprentice: "NO ABILITY · NO WEAKNESS" in neutral grey** | `set_pair(pair)` |

The widgets are dumb views: the HUD that owns them feeds them values from the
player's signals.

### 5.3 TDM HUD — `scripts/ui/tdm_hud.gd` (created by the controller)

```
┌─────────────────────────────────────────────────────────────┐
│            ┌──────────────────────────────┐                 │
│            │ RED 12  │  09:41  │  14 BLUE │   TEAM BLUE ←you│
│            └──────────────────────────────┘                 │
│                                                             │
│                           ─ ┼ ─                             │
│                                                             │
│ ┌ SPRAYER'S PAIR ───────┐                                   │
│ │▲ Rapid Brush  ×2.4    │                                   │
│ │▼ Thin Paint   ×0.55   │                                   │
│ └───────────────────────┘                 ┌─ PAINT ───────┐ │
│ ┌ HEALTH ──────────────┐                  │ ▓▓▓▓▓▓░░ 24/30│ │
│ │ 100  ▮▮▮▮▮▮▮▮▮▮       │                  └───────────────┘ │
│ └──────────────────────┘                                    │
└─────────────────────────────────────────────────────────────┘
```

- **Anchors, not coordinates.** Top-centre score pill; bottom-left stack
  (inheritance card above health); bottom-right paint tank; everything inside
  `MarginContainer`s with a 24 px safe margin.
- The **timer and scores** are the largest text (timer 32 px, scores 28 px).
  Own team is marked with a small "YOU" tag.
- **Respawn overlay** while dead: "PAINTED OUT" + "Respawning in 2.4", read
  from the controller's respawn timer (one new getter; timing unchanged).
- HUD binds to the local player's `stats_changed`, `hurt`, `pair_inherited`.
  The player node survives respawn (`tdm_respawn()`), so the HUD stays bound.
- The Survival HUD is never created in TDM, and the TDM HUD never in Survival.

### 5.4 Tab scoreboard — `scripts/ui/tdm_scoreboard.gd` + `scoreboard_row.gd`

```
                 TEAM DEATHMATCH  ·  09:41
┌ TEAM RED ─────────────── 12 ┐  ┌ TEAM BLUE ────────────── 14 ┐
│ #  PLAYER            K  D  A │  │ #  PLAYER            K  D  A │
│ 1  GlowBean          5  2  1 │  │ 1 [YOU] Player        4  1  2 │ ← highlighted row
│ 2  ExtremelyLongPl…  3  3  0 │  │ 2  PaintGhost         3  2  1 │
│ …                            │  │ …                            │
└──────────────────────────────┘  └──────────────────────────────┘
```

- **Held, not toggled** (as today). Visibility is checked every frame
  (removing today's 250 ms lag). Contents refresh every 0.25 s and on every
  death (`combatant_died` already calls `_refresh_scoreboard()`).
- Each row: `PanelContainer` → `HBoxContainer` with rank (32 px), name
  (`EXPAND_FILL`, `clip_text`, ellipsis overrun), K/D/A (48 px each, centred).
  Fixed stat widths make every column line up. Header row uses the same widths.
- Team header: name in team colour + big total. Teams side by side with a gap,
  each panel team-bordered.
- Rows sorted by kills ↓, then deaths ↑ (display order only).
- Local row: brighter background, team-colour left edge, "YOU" chip before the
  name.
- Reads `controller.players`/`scores`/`remaining` directly. No copies.

### 5.5 TDM result screen

Same theme: winner title (team colour, or white for DRAW), a two-team score
line built from containers, a "YOUR MATCH" K/D/A strip, and the
RETURN TO MAIN MENU button. Winner/draw logic untouched.

### 5.6 Survival HUD (`hud.gd`)

Same public API; internally uses the shared widgets, so both modes look like
one game. Fixes the Apprentice line. The wave readout, offer prompt, banner,
vignette, hurt flash and end panel keep their current behaviour.

---

## 6. Menu plan (`menu.gd`)

**Structure.** The `_label/_panel/_button(parent, text, at, size, …)` helpers
become container-friendly versions (no `at/size`). Each `_show_*` builds its
page from `MarginContainer`/`VBoxContainer`/`HBoxContainer`/`GridContainer`/
`CenterContainer`. The theme from §5.1 goes on `screen_root`. Screen names,
navigation, lobby records, queue generation, countdown, customization data and
the match hand-off are unchanged.

| Page | Fix |
|---|---|
| Main | Card anchored left, full height with 40 px margins. VBox: title, tagline, pilot line, 4 buttons (full width), spacer, footer. |
| Mode Select | `CenterContainer` card. Each mode is one button containing its own title + description (children ignore the mouse), so nothing overlaps. Esc → Main. |
| Lobby | Full-screen margin. Header (title, status, large countdown); two team panels side by side (`EXPAND_FILL`, ratio 1:1); footer row anchored to the bottom (Customize ← fill counter → Leave). Slot text gets padding. |
| Customize | Left panel anchored full height. Title on one line (32 px) + hint; username; categories (VBox) beside a 2-column `GridContainer` of options whose buttons have a fixed min width and wrap/clip their text (API to be checked in the 4.7 docs before use). The locked message wraps. The drag-to-rotate area starts at the panel's real right edge, not a hard-coded 450. |
| Settings | Same card as Main. Sliders get value readouts (volume %, sensitivity ×). BACK uses the same fade as every other page. |

**Visual direction.** Panels get a "brush-stroke" header bar (a small custom
`Control` that draws an irregular paint-stroke polygon behind section titles),
and a thin painted accent edge. The 3D showcase behind the menu swaps its neon
slats for studio props from §4.12 (giant brush, tubes, easel) under warm
studio light, keeping the bean on its pedestal where it is today. No random
splatter over text.

**Resolutions validated.** 1280×720, 1920×1080, 2560×1440 (16:9, uniform
scale), plus 1280×800 (16:10), 1024×768 (4:3) and 2560×1080 (ultrawide), which
are the ones that actually expose anchoring bugs.

---

## 7. Environment + lighting plan

- Apply the surface shader to floor, walls, cover and building shells (§4.13),
  with region band colours from §4.12.
- Add the dressing table (`_build_dressing()`).
- **Lighting.** Keep the Stage-1 sun/ambient/tonemap and the Compatibility
  sun compensation. Add, in this order and only if screenshots justify each:
  1. **Rim** on combatant materials (`rim_enabled`, cheap, both renderers),
     to separate combatants from the room;
  2. **SSAO** at low intensity (Forward+ only; ignored by Compatibility) for
     contact shading under props and cover;
  3. A 5–10% lower ambient if the new surface texture reads flat.
- Every lighting/material change: screenshot Forward+ **and**
  `--rendering-method gl_compatibility`, and compare the floor value with the
  Stage-1 numbers (200/255 sunlit floor).

## 8. VFX / feedback (Stage 7, presentation only)

Hit flash via overlay (all combatants) · muzzle paint puff (6-particle
`CPUParticles3D`, one-shot) · droplet burst on combatant hits · core pickup
burst · reservoir refill shimmer on the paint gauge · low-health vignette pulse ·
scoreboard fade/slide in · menu button hover/press tweens · crosshair tick on a
confirmed hit (needs one visual-only callback from the projectile to its
shooter; no damage path change). **No** camera shake, recoil on aim, aim punch,
slow-downs, or anything that changes input or timing.

---

## 9. Work breakdown

| Stage | Output | Main files |
|---|---|---|
| 3 UI | theme, widgets, TDM HUD, scoreboard, result screen, Survival HUD restyle, menu rebuild | `scripts/ui/**`, `tdm_match_controller.gd`, `hud.gd`, `menu.gd` |
| 4 Blender | `paintkit.py`, 12 `create_*.py`, `build_all.sh`, GLBs, first import | `tools/blender/**`, `models/generated/**` |
| 5 Integration | weapon, runner + reservoir, 5 enemies, core, station, glob, splat | `player.gd`, `enemy.gd`, `core_pickup.gd`, `healing_station.gd`, `projectile.gd`, `scripts/visual/**` |
| 6 Environment | surface shader, dressing, lighting | `arena.gd`, `scripts/visual/arena_surface.gdshader` |
| 7 Polish | §8 list | widgets, visual drivers |
| 8 Regression | full test matrix (§10), both renderers, screenshots | — |
| 9 Cleanup | remove only code/files proven unreferenced (ask before deleting any file) | — |

Each stage ends with a test run and a stop for review.

## 10. Test plan

**Tools.** Survival: `godot --headless --path <proj> res://scenes/match.tscn
--quit-after 18000 -- --autoplay`. TDM: scratchpad `tdm_probe.gd` (starts a
2×10 match, attaches autoplay, prints scores / K-D-A / hp / paint; `--shorten`
to test the ending). Visuals: scratchpad `shoot_screens.gd` (every menu page,
TDM HUD, held-Tab scoreboard, result, Survival HUD) at each resolution, both
renderers.

| Check | How |
|---|---|
| Survival 15-point list | autoplay trace (waves, kills, cores, inherit, replace, heal) + screenshots of the HUD per pair |
| TDM 26-point list | probe trace (scores, K/D/A, respawns, timer, end, draw via equal scores) + screenshots (HUD after respawn, Tab held/released, long name) |
| No TDM UI in Survival and vice versa | node-tree check in both probes |
| Tuning unchanged | `git diff` on the invariant files in §0.1 shows no numeric changes |
| Menu | screenshots of pages 1–10 at 6 resolutions |
| Imports | `--headless --import` with zero errors; every GLB instanced once in a probe |
| Performance | frame time in a full TDM match (20 runners) vs today |

Things only a human can confirm (real mouse/keyboard feel, Tab held by hand,
Esc flows) go on a short F5 checklist for Jarman at Stage 8.

## 11. Open decisions (defaults used unless Jarman says otherwise)

1. **Canvas Runner in-match only**; menu bean untouched (§4.2).
2. **Survival HUD adopts the shared widgets** (§5.6) for one consistent look.
3. **Team colours kept** as jcodes chose, centralised in one place (§2.2).
4. **Blender export needs `python3-numpy`** (ask-first install); fallback =
   custom GLB writer.
5. **`.godot/` ownership** must be fixed by Jarman before Stage 4 imports.
