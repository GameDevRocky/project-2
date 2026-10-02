"""
Chromatic Reservoir - the paint tank every Canvas Runner wears on its back.

Plan: docs/VISUAL_OVERHAUL_PLAN.md section 4.3.

An artist's paint canister turned into life support: a vertical glass capsule
full of glowing team paint, domed painted-metal pressure caps with team-colour
rings, held in a frame of two rounded rails and three rubber cross straps. A
small ceramic regulator with a round gauge sits on the top cap, one rubber
hose arcs up over the wearer's right shoulder, and a small brush is holstered
diagonally on the left side.

Axes: the ORIGIN is the mounting point, the centre of the pack's front face
(the face that touches the runner's back). The pack extends toward BLENDER +Y,
which is behind the runner. Z is up. It is built in the runner's own frame,
so the runner's right side is -X (where the hose goes over the shoulder).
Canvas Runner's Socket_Back empty has no rotation, so the pack drops onto it
as is. Size: 0.40 wide (X) x 0.52 tall (Z) x 0.24 deep (Y), plus the hose.

Nodes Godot relies on (names must not change):
    ChromaticReservoir  root empty at the mounting point.
    Fill                paint inside the tank, material PK_Fill (team colour,
                        emissive). ORIGIN AT THE BOTTOM OF THE PAINT, so Godot
                        can scale it along its up axis (Blender Z = Godot Y)
                        to lower the level or bob the surface without the
                        paint leaving the tank bottom.
    Needle              regulator gauge needle, material PK_Dark. ORIGIN AT
                        THE DIAL CENTRE. The dial faces backward (Blender +Y =
                        Godot -Z), so the needle swings by rotating about that
                        axis (Godot Z).
    Pack                every part that never moves, joined into one mesh
                        (glass, caps, rings, rails, straps, regulator, hose,
                        brush). Not animated; named only for completeness.

Material roles: PK_Glass tank shell, PK_Fill paint, PK_Metal caps, PK_Team cap
rings, PK_Trim rails, PK_Rubber straps and hose, PK_Body regulator, PK_Dial
dial face, PK_Dark needle, PK_Wood / PK_Metal / PK_Dry1 brush.

Run:  blender -b --factory-startup --python tools/blender/create_chromatic_reservoir.py
"""

import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("ChromaticReservoir", seed=43)

glass = pk.mat("PK_Glass")
# The fill is team paint (plan 4.3), so preview it in the kit's default team
# colour; Godot swaps PK_Fill for the real team colour at runtime.
fill_mat = pk.mat("PK_Fill", color=pk.PRESETS["PK_Team"]["color"], emission=0.5)
metal = pk.mat("PK_Metal")
team = pk.mat("PK_Team")
trim = pk.mat("PK_Trim")
rubber = pk.mat("PK_Rubber")
ceramic = pk.mat("PK_Body")
dial = pk.mat("PK_Body", name="PK_Dial", color="#FBF8F0")
dark = pk.mat("PK_Dark")
wood = pk.mat("PK_Wood")
tuft = pk.mat("PK_Dry1")

RIGHT = -1.0            # the wearer's right side is -X
LEFT = -RIGHT

root = pk.empty("ChromaticReservoir")


# ---------------------------------------------------------------------------
# Local helpers
# ---------------------------------------------------------------------------

def along(direction):
    """Rotation (degrees) that turns a part's local +Z to point along `direction`."""
    e = Vector(direction).to_track_quat("Z", "Y").to_euler()
    return tuple(math.degrees(a) for a in e)


def spun(name, profile, p0, p1, material, segments):
    """Lathe a (radius, distance) profile around the line from p0 toward p1."""
    obj = pk.lathe(name, profile, loc=tuple(p0), rot=along(Vector(p1) - Vector(p0)),
                   material=material, segments=segments, parent_obj=root)
    pk.apply(obj, location=False, rotation=True, scale=True)
    return obj


def capsule(name, p0, p1, radius, material, segments=8, cap=2):
    p0, p1 = Vector(p0), Vector(p1)
    length = (p1 - p0).length
    profile = []
    for i in range(cap + 1):
        a = -math.pi / 2 + (math.pi / 2) * i / cap
        profile.append((radius * math.cos(a) if i else 0.0, radius * math.sin(a)))
    for i in range(cap + 1):
        a = (math.pi / 2) * i / cap
        profile.append((radius * math.cos(a) if i < cap else 0.0, length + radius * math.sin(a)))
    return spun(name, profile, p0, p1, material, segments)


def thick_line(points, width):
    """Outline (for pk.prism) of a flat strip of `width` following a 2D
    polyline, with mitred corners. Used for the straps that wrap the tank."""
    pts = [Vector((x, y)) for x, y in points]
    left, right = [], []
    for i, p in enumerate(pts):
        d_in = (p - pts[i - 1]).normalized() if i > 0 else None
        d_out = (pts[i + 1] - p).normalized() if i + 1 < len(pts) else None
        d = (d_in + d_out).normalized() if d_in and d_out else (d_in or d_out)
        n = Vector((-d.y, d.x))
        miter = 1.0
        if d_in and d_out:
            miter = 1.0 / max(0.4, n.dot(Vector((-d_in.y, d_in.x))))
        left.append(p + n * width * 0.5 * miter)
        right.append(p - n * width * 0.5 * miter)
    return [tuple(v) for v in left + right[::-1]]


# ---------------------------------------------------------------------------
# Tank: glass capsule shell, paint fill, domed caps with team rings
# ---------------------------------------------------------------------------

TANK_Y = 0.121          # tank axis, behind the mounting face
TANK_R = 0.098
TANK = Vector((0.0, TANK_Y, 0.0))
UP = TANK + Vector((0, 0, 1))
SEG = 12

pk.lathe("Tank", [(0.084, -0.19), (TANK_R, -0.172), (TANK_R, 0.172), (0.084, 0.19)],
         loc=tuple(TANK), material=glass, segments=SEG, parent_obj=root)

fill = pk.cyl("Fill", 0.087, 0.31, loc=(0, TANK_Y, -0.015), material=fill_mat, verts=SEG,
              parent_obj=root)
pk.set_origin(fill, (0, TANK_Y, -0.17))

for sign, tag in ((1, "Top"), (-1, "Bottom")):
    # Profile runs from the tank axis outward and over the dome; `sign`
    # mirrors it for the bottom cap.
    cap = [(0.0, 0.163), (0.106, 0.163), (0.11, 0.19), (0.097, 0.224), (0.058, 0.25),
           (0.0, 0.259)]
    pk.lathe("Cap" + tag, [(r, z * sign) for r, z in cap], loc=tuple(TANK), material=metal,
             segments=SEG, parent_obj=root)
    ring = [(0.104, 0.158), (0.117, 0.176), (0.104, 0.194)]
    pk.lathe("CapRing" + tag, [(r, z * sign) for r, z in ring], loc=tuple(TANK),
             material=team, segments=SEG, parent_obj=root)


# ---------------------------------------------------------------------------
# Frame: two rounded rails against the wearer's back, three rubber straps
# that wrap around the back of the tank and bolt to the rails
# ---------------------------------------------------------------------------

RAIL_X, RAIL_Y, RAIL_R = 0.158, 0.03, 0.024
for side, tag in ((LEFT, "L"), (RIGHT, "R")):
    capsule("Rail" + tag, (side * RAIL_X, RAIL_Y, -0.23), (side * RAIL_X, RAIL_Y, 0.23),
            RAIL_R, trim, segments=8)

strap_r = TANK_R + 0.009
arc = [(math.cos(math.radians(a)) * strap_r, TANK_Y + math.sin(math.radians(a)) * strap_r)
       for a in range(-15, 196, 30)]
strap_path = [(RAIL_X - 0.004, RAIL_Y + 0.012)] + arc + [(-RAIL_X + 0.004, RAIL_Y + 0.012)]
for i, z in enumerate((-0.105, 0.0, 0.105)):
    pk.prism("Strap%d" % i, thick_line(strap_path, 0.014), 0.032, loc=(0, 0, z),
             material=rubber, parent_obj=root)


# ---------------------------------------------------------------------------
# Regulator on the top cap (wearer's right), gauge facing backward
# ---------------------------------------------------------------------------

REG = Vector((RIGHT * 0.145, 0.128, 0.2))
pk.box("Regulator", (0.07, 0.085, 0.08), loc=tuple(REG), material=ceramic, bevel=0.016,
       segments=1, parent_obj=root)
GAUGE = REG + Vector((0, 0.048, 0.0))
# rot (-90, 0, 0) turns a cylinder's local Z toward +Y, so the dial faces back.
pk.cyl("GaugeRim", 0.033, 0.016, loc=tuple(GAUGE), rot=(-90, 0, 0), material=trim, verts=12,
       parent_obj=root)
pk.cyl("GaugeFace", 0.025, 0.006, loc=tuple(GAUGE + Vector((0, 0.008, 0))), rot=(-90, 0, 0),
       material=dial, verts=12, parent_obj=root)
DIAL_CENTRE = GAUGE + Vector((0, 0.013, 0))
needle = pk.box("Needle", (0.008, 0.005, 0.026),
                loc=tuple(DIAL_CENTRE + Vector((0, 0, 0.009))), material=dark, parent_obj=root)
pk.set_origin(needle, tuple(DIAL_CENTRE))
# Tip it to "two-thirds pressure" around the dial axis (Y), then bake that in
# so the node itself has no rotation and Godot can jitter it from zero.
needle.rotation_euler = (0.0, math.radians(35), 0.0)
pk.apply(needle, location=False, rotation=True, scale=True)

# ---------------------------------------------------------------------------
# Hose: out of the regulator, up and forward over the wearer's right shoulder
# ---------------------------------------------------------------------------

# It clears the helmet by a few cm and comes to rest on the front of the
# shoulder pad (positions checked against canvas_runner.glb's Socket_Back).
pk.tube("Hose", [tuple(REG + Vector((0, -0.01, 0.03))), (RIGHT * 0.185, 0.06, 0.279),
                 (RIGHT * 0.225, -0.06, 0.274), (RIGHT * 0.24, -0.165, 0.25),
                 (RIGHT * 0.245, -0.225, 0.205)],
        0.017, material=rubber, resolution=1, path_resolution=2, parent_obj=root)


# ---------------------------------------------------------------------------
# Holstered brush on the wearer's left side, tuft up and leaning back
# ---------------------------------------------------------------------------

BRUSH_X = LEFT * 0.174
b0 = Vector((BRUSH_X, 0.078, -0.2))      # handle end
b1 = Vector((BRUSH_X, 0.206, 0.15))      # tuft tip
axis = (b1 - b0).normalized()
length = (b1 - b0).length
handle_end = b0 + axis * (length - 0.13)
capsule("BrushHandle", b0, handle_end, 0.013, wood, segments=8, cap=1)
spun("BrushFerrule", [(0.012, -0.01), (0.018, 0.004), (0.017, 0.056)],
     handle_end, b1, metal, 8)
spun("BrushTuft", [(0.015, 0.05), (0.02, 0.075), (0.017, 0.11), (0.0, 0.13)],
     handle_end, b1, tuft, 8)
holster_at = b0 + axis * 0.2
spun("Holster", [(0.012, -0.02), (0.021, 0.0), (0.012, 0.02)],
     holster_at, holster_at + axis, rubber, 8)

# Everything that never moves becomes one mesh named Pack, so each of the 19
# runners costs Godot one node (a surface per material) instead of twenty.
static = [o for o in pk.objects() if o.type == "MESH" and o.name not in ("Fill", "Needle")]
pack = pk.join("Pack", static)
pk.apply(pack, location=True, rotation=True, scale=True)

pk.smooth_all(35.0)
pk.export("chromatic_reservoir.glb", budget=1200)
