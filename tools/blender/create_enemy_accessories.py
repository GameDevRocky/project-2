"""
Enemy accessories - small cosmetic add-ons that Survival-mode enemies wear at
random, so two Sprayers in the same wave do not look identical.

They are deliberately SMALL and MUTED: a felt beret, a striped party hat, a
propeller cap, a ribbon bow, a tiny crown, a leaf sprout, and four flat
stickers. None of them glows and none uses an enemy's own colour (pink, mint,
teal, charcoal, white) or the outline/team colours, so the enemy's colour is
still the brightest, most readable thing on it and its outline stays its own.

Axes: like the enemies, the FRONT is BLENDER -Y (Godot +Z). Z is up.
Every accessory sits on top of the others at the file's origin - that is
intended: Godot picks one, moves it onto an enemy and scales it to fit.

Nodes Godot relies on (names must not change). Each is ONE mesh, parented to
the root empty `Accessories`, with no rotation and scale (1, 1, 1):

  Hats / toppers - ORIGIN at the centre of the BOTTOM contact point, (0, 0, 0);
  the item grows upward (+Z). Sized for a head about 0.35-0.45 m across
  (footprint <= 0.32 m, height <= 0.25 m):
    Acc_BERET          painter's felt beret, puff tipped to the enemy's left.
    Acc_PARTY_HAT      striped cone with a fluffy pompom.
    Acc_PROPELLER_CAP  panelled beanie, little front brim, two-blade propeller.
    Acc_BOW            ribbon bow standing up, facing front.
    Acc_TINY_CROWN     five-point crown with bead tips and a front gem.
    Acc_SPROUT         seedling: short stem, two round leaves and a bud.

  Stickers - thin raised decals (<= 1.2 cm thick) about 0.16 m across, lying in
  the XZ plane and facing FRONT (-Y). ORIGIN at the centre of the BACK face, so
  Godot can press the origin onto a body surface:
    Sticker_STAR  Sticker_SMILEY  Sticker_BANDAGE  Sticker_NUMBER7

Run:  blender -b --factory-startup --python tools/blender/create_enemy_accessories.py
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("Accessories", seed=21)

# --- Palette: muted art-studio colours, matte or a soft sheen, no emission ----
# Shared by several items, so the whole file uses only a handful of materials.


def paint_mat(name, colour, roughness=0.85, metallic=0.0):
    return pk.mat("PK_Canvas", name=name, color=colour, roughness=roughness,
                  metallic=metallic)


WINE = paint_mat("PK_AccWine", "#7A3E48", roughness=0.95)        # felt
WINE_DARK = paint_mat("PK_AccWineDark", "#56303A", roughness=0.95)
BLUE = paint_mat("PK_AccBlue", "#5E7FA3", roughness=0.7)
MUSTARD = paint_mat("PK_AccMustard", "#D2AC55", roughness=0.7)
MUSTARD_DARK = paint_mat("PK_AccOchre", "#A9853C", roughness=0.7)
BRICK = paint_mat("PK_AccBrick", "#B5625A", roughness=0.75)
PLUM = paint_mat("PK_AccPlum", "#8C76AC", roughness=0.6)
PLUM_DARK = paint_mat("PK_AccPlumDark", "#68578A", roughness=0.6)
GOLD = paint_mat("PK_AccGold", "#C4A25A", roughness=0.4, metallic=0.5)  # soft sheen
SAGE = paint_mat("PK_AccSage", "#8BA862", roughness=0.75)
OLIVE = paint_mat("PK_AccOlive", "#617B44", roughness=0.8)
INK = paint_mat("PK_AccInk", "#403B4E", roughness=0.6)
TAN = paint_mat("PK_AccTan", "#CDA883", roughness=0.8)
TAN_DARK = paint_mat("PK_AccTanDark", "#AE8A68", roughness=0.8)

root = pk.empty("Accessories")


# --- Helpers ------------------------------------------------------------------

def bake(obj):
    """Fold the part's position/rotation/scale into its mesh, so it sits at
    the right place with a clean (identity) transform before joining."""
    pk.apply(obj, location=True, rotation=True, scale=True)


def finish(name, parts):
    """Join the parts into one mesh named `name`, origin at (0, 0, 0)."""
    for p in parts:
        bake(p)
    obj = pk.join(name, parts)   # also applies each part's bevel
    pk.parent(obj, root)
    return obj


def paint(obj, materials, pick):
    """Give one mesh several materials: pick(face_centre) returns the index
    into `materials` for each face (used for stripes and cap panels)."""
    mesh = obj.data
    mesh.materials.clear()
    for m in materials:
        mesh.materials.append(m)
    for poly in mesh.polygons:
        poly.material_index = pick(poly.center)


def rot2(points, degrees, offset=(0.0, 0.0)):
    """Rotate 2D outline points around (0, 0), then shift them."""
    a = math.radians(degrees)
    c, s = math.cos(a), math.sin(a)
    return [(x * c - y * s + offset[0], x * s + y * c + offset[1]) for x, y in points]


def rounded_rect(width, height, radius, per_corner=3):
    """Counter-clockwise outline of a rectangle with rounded corners."""
    hx, hy = width * 0.5 - radius, height * 0.5 - radius
    pts = []
    for cx, cy, start in ((hx, -hy, -90), (hx, hy, 0), (-hx, hy, 90), (-hx, -hy, 180)):
        for i in range(per_corner):
            a = math.radians(start + 90.0 * i / (per_corner - 1))
            pts.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    return pts


def ellipse(cx, cy, rx, ry, count):
    return [(cx + rx * math.cos(math.tau * i / count), cy + ry * math.sin(math.tau * i / count))
            for i in range(count)]


def decal(name, outline, depth, material, back=0.0, bevel=0.0):
    """A flat raised piece for a sticker. `outline` is drawn as (x, z) points
    the way you see it from the front. Its back face sits `back` metres in
    front of the sticker's back plane (y = 0) and it is `depth` thick, toward
    -Y. rot (90, 0, 0) stands the prism's flat outline up in the XZ plane."""
    return pk.prism(name, outline, depth, loc=(0, -(back + depth * 0.5), 0), rot=(90, 0, 0),
                    material=material, bevel=bevel, segments=1)


def centre_sticker(obj):
    """Move the mesh so its back face is centred on the origin (x and z)."""
    xs = [v.co.x for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    shift = Vector((-(min(xs) + max(xs)) * 0.5, 0.0, -(min(zs) + max(zs)) * 0.5))
    for v in obj.data.vertices:
        v.co += shift


# =============================================================================
# TOP accessories (origin at the bottom contact point, growing up +Z)
# =============================================================================

# --- Beret: a felt disc that overhangs a short headband, tipped to one side ---
BAND_TOP = 0.024
BERET_TILT = math.radians(9.0)   # puff tips toward +X (the enemy's left)
beret = pk.lathe("BeretFelt", [
    (0.000, 0.004), (0.097, 0.000), (0.102, BAND_TOP), (0.128, 0.036),
    (0.139, 0.051), (0.124, 0.067), (0.078, 0.079), (0.000, 0.084)],
    material=WINE, segments=16)


def tip_beret(co):
    """Rotate a point above the headband around the band's top centre."""
    rel_x, rel_z = co.x, co.z - BAND_TOP
    return Vector((rel_x * math.cos(BERET_TILT) + rel_z * math.sin(BERET_TILT) + 0.008,
                   co.y,
                   -rel_x * math.sin(BERET_TILT) + rel_z * math.cos(BERET_TILT) + BAND_TOP))


for v in beret.data.vertices:
    if v.co.z > BAND_TOP + 1e-4:
        v.co = tip_beret(v.co)
paint(beret, [WINE, WINE_DARK], lambda c: 1 if c.z < BAND_TOP else 0)
stalk_base = tip_beret(Vector((0.0, 0.0, 0.080)))
stalk = pk.cyl("BeretStalk", 0.009, 0.024, radius_top=0.006, material=WINE_DARK, verts=6,
               loc=stalk_base + Vector((math.sin(BERET_TILT), 0, math.cos(BERET_TILT))) * 0.012,
               rot=(0, math.degrees(BERET_TILT), 0))
finish("Acc_BERET", [beret, stalk])

# --- Party hat: a striped cone with a fluffy pompom ---------------------------
HAT_H, HAT_R, STRIPES = 0.168, 0.072, 5
cone = pk.lathe("HatCone", [(0.0, 0.0)] +
                [(HAT_R * (1 - i / STRIPES), HAT_H * i / STRIPES) for i in range(STRIPES)] +
                [(0.0, HAT_H)], material=BLUE, segments=14)
paint(cone, [BLUE, MUSTARD], lambda c: int(c.z / (HAT_H / STRIPES)) % 2)
pompom = pk.sphere("HatPompom", 0.024, loc=(0, 0, HAT_H + 0.012), material=BRICK,
                   segments=8, rings=5)
pk.displace_random(pompom, 0.0025, seed=3)   # a little lumpy, like yarn
finish("Acc_PARTY_HAT", [cone, pompom])

# --- Propeller cap: six-panel beanie, a little brim, a two-blade propeller ----
CAP_TOP = 0.084
dome = pk.lathe("CapDome", [
    (0.000, 0.000), (0.098, 0.000), (0.096, 0.024), (0.084, 0.050),
    (0.060, 0.070), (0.030, 0.081), (0.000, CAP_TOP)], material=BRICK, segments=12)
# Six wedge panels in three colours (two lathe segments per panel). The
# panel centred on angle 270 deg (the front, -Y) is a whole panel.
paint(dome, [BRICK, MUSTARD, BLUE],
      lambda c: int((math.atan2(c.y, c.x) % math.tau) / (math.tau / 6)) % 3)
# Brim: a crescent sticking out at the front, kicked up 6 degrees so it clears
# a rounded forehead.
brim_outline = ([(math.cos(math.radians(a)) * 0.135, math.sin(math.radians(a)) * 0.135)
                 for a in (215, 242, 270, 298, 325)] +
                [(math.cos(math.radians(a)) * 0.088, math.sin(math.radians(a)) * 0.088)
                 for a in (318, 270, 222)])
brim = pk.prism("CapBrim", brim_outline, 0.007, loc=(0, 0, 0.0065), rot=(-6, 0, 0),
                material=BLUE)
stem = pk.cyl("CapStem", 0.006, 0.03, loc=(0, 0, CAP_TOP + 0.009), material=INK, verts=6)
hub = pk.cyl("CapHub", 0.013, 0.012, loc=(0, 0, CAP_TOP + 0.026), material=MUSTARD, verts=8)
blade_outline = [(0.008, -0.005), (0.05, -0.014), (0.086, -0.008), (0.086, 0.008),
                 (0.05, 0.014), (0.008, 0.005)]
blades = [pk.prism("CapBlade%d" % i, blade_outline, 0.004, loc=(0, 0, CAP_TOP + 0.026),
                   rot=(16, 0, 180 * i), material=(BLUE, BRICK)[i]) for i in range(2)]
finish("Acc_PROPELLER_CAP", [dome, brim, stem, hub] + blades)

# --- Bow: two flattened ribbon loops, a knot and two notched tails ------------
loops = []
for side in (1, -1):
    loop = pk.lathe("BowLoop", [
        (0.000, 0.000), (0.018, 0.008), (0.040, 0.040), (0.048, 0.072),
        (0.036, 0.100), (0.000, 0.110)], material=PLUM, segments=8)
    for v in loop.data.vertices:
        v.co.y *= 0.45          # flatten the loop front-to-back, like ribbon
    # Lathe runs along local Z; turning it 70 deg (not 90) points it sideways
    # and tips its outer end up 20 deg, the way a hair bow perks up.
    loop.location = (0.010 * side, 0.0, 0.036)
    loop.rotation_euler = (0.0, math.radians(70 * side), 0.0)
    loops.append(loop)
knot = pk.sphere("BowKnot", 0.026, loc=(0, -0.002, 0.026), scale=(0.85, 0.75, 1.0),
                 material=PLUM_DARK, segments=8, rings=4)
tail = [(0.000, 0.016), (0.036, 0.000), (0.046, 0.009), (0.058, 0.004), (0.016, 0.036)]
tails = [decal("BowTail0", tail, 0.008, PLUM, back=-0.002),
         decal("BowTail1", [(-x, z) for x, z in reversed(tail)], 0.008, PLUM, back=-0.002)]
finish("Acc_BOW", loops + [knot] + tails)

# --- Tiny crown: a five-point ring with bead tips and a front gem -------------
CROWN_RO, CROWN_RI, TIP_Z, VALLEY_Z = 0.072, 0.064, 0.090, 0.046
mesh = bpy.data.meshes.new("CrownRing")
bm = bmesh.new()
rings = {"bo": [], "bi": [], "to": [], "ti": []}
for i in range(10):
    a = math.radians(270 + 36 * i)          # i = 0 is a tip, straight at the front
    top = TIP_Z if i % 2 == 0 else VALLEY_Z
    co, si = math.cos(a), math.sin(a)
    rings["bo"].append(bm.verts.new((co * CROWN_RO, si * CROWN_RO, 0.0)))
    rings["bi"].append(bm.verts.new((co * CROWN_RI, si * CROWN_RI, 0.0)))
    rings["to"].append(bm.verts.new((co * CROWN_RO, si * CROWN_RO, top)))
    rings["ti"].append(bm.verts.new((co * CROWN_RI, si * CROWN_RI, top)))
for i in range(10):
    j = (i + 1) % 10
    for a_ring, b_ring in (("bo", "to"), ("to", "ti"), ("ti", "bi"), ("bi", "bo")):
        bm.faces.new((rings[a_ring][i], rings[a_ring][j], rings[b_ring][j], rings[b_ring][i]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(mesh)
bm.free()
crown = bpy.data.objects.new("CrownRing", mesh)
pk._collection.objects.link(crown)
mesh.materials.append(GOLD)
crown_parts = [crown]
for i in range(5):
    a = math.radians(270 + 72 * i)
    r = (CROWN_RO + CROWN_RI) * 0.5
    crown_parts.append(pk.ico("CrownBead%d" % i, 0.0105,
                              loc=(math.cos(a) * r, math.sin(a) * r, TIP_Z + 0.006),
                              material=GOLD, subdiv=1))
crown_parts.append(pk.sphere("CrownGem", 0.012, loc=(0, -CROWN_RO - 0.001, 0.024),
                             scale=(1.0, 0.5, 1.0), material=BRICK, segments=6, rings=4))
finish("Acc_TINY_CROWN", crown_parts)

# --- Sprout: a short leaning stem, two round leaves and a bud -----------------
STEM_H, LEAN = 0.10, 0.12            # lean: x shift per metre of height
nub = pk.cyl("SproutNub", 0.022, 0.012, radius_top=0.009, loc=(0, 0, 0.006),
             material=OLIVE, verts=8)
stem_obj = pk.cyl("SproutStem", 0.0075, STEM_H, radius_top=0.0055, loc=(0, 0, STEM_H * 0.5),
                  material=OLIVE, verts=6)
bake(stem_obj)
for v in stem_obj.data.vertices:
    v.co.x += v.co.z * LEAN
leaf_base = Vector((STEM_H * LEAN, 0.0, STEM_H - 0.004))
leaves = []
LEAF_L, LEAF_W = 0.082, 0.032       # leaf length and half-width
for side in (1, -1):
    leaf = pk.sphere("SproutLeaf", 1.0, scale=(LEAF_L * 0.5, LEAF_W, 0.007), material=SAGE,
                     segments=10, rings=4)
    for v in leaf.data.vertices:
        x = v.co.x + LEAF_L * 0.5            # base at x = 0, tip at x = LEAF_L
        t = x / LEAF_L
        v.co.y *= 1.0 - 0.5 * max(0.0, t - 0.5) / 0.5     # pinch to a soft point
        v.co.z += 1.3 * x * x                              # tip curls upward
        v.co.x = x
    # Roll the flat leaf 38 deg so its face turns toward the front (-Y) and
    # reads from the player's view, then tip it up 26 deg. The second leaf is
    # the same leaf turned 180 deg around Z (rolled the other way so it also
    # ends up facing front).
    leaf.location = leaf_base
    leaf.rotation_euler = (math.radians(38 * side), math.radians(-26),
                           math.radians(0 if side > 0 else 180))
    leaves.append(leaf)
bud = pk.ico("SproutBud", 0.011, loc=leaf_base + Vector((0.002, 0, 0.012)),
             scale=(0.8, 0.8, 1.2), material=SAGE, subdiv=1)
finish("Acc_SPROUT", [nub, stem_obj] + leaves + [bud])

# =============================================================================
# FLAT stickers (XZ plane, facing -Y, origin at the back-face centre)
# =============================================================================


def star(outer, inner):
    return [((outer if k % 2 == 0 else inner) * math.cos(math.radians(90 + 36 * k)),
             (outer if k % 2 == 0 else inner) * math.sin(math.radians(90 + 36 * k)))
            for k in range(10)]


def sticker(name, parts):
    for p in parts:
        bake(p)
    obj = pk.join(name, parts)
    centre_sticker(obj)
    pk.parent(obj, root)
    return obj


# Star: a darker ochre backing with a raised mustard star on it.
sticker("Sticker_STAR", [
    decal("StarBack", star(0.084, 0.039), 0.005, MUSTARD_DARK),
    decal("StarFace", star(0.066, 0.031), 0.0045, MUSTARD, back=0.0045, bevel=0.0015),
])

# Smiley: a mustard disc with ink eyes and a smile.
face = pk.cyl("SmileyFace", 0.08, 0.006, loc=(0, -0.003, 0), rot=(90, 0, 0),
              material=MUSTARD, verts=20)
smile = ([(math.cos(math.radians(a)) * 0.050, math.sin(math.radians(a)) * 0.050 + 0.008)
          for a in (200, 226, 252, 288, 314, 340)] +
         [(math.cos(math.radians(a)) * 0.037, math.sin(math.radians(a)) * 0.037 + 0.008)
          for a in (334, 306, 270, 234, 206)])
sticker("Sticker_SMILEY", [
    face,
    decal("SmileyEyeL", ellipse(-0.026, 0.024, 0.010, 0.017, 6), 0.003, INK, back=0.0055),
    decal("SmileyEyeR", ellipse(0.026, 0.024, 0.010, 0.017, 6), 0.003, INK, back=0.0055),
    decal("SmileyMouth", smile, 0.003, INK, back=0.0055),
])

# Bandage: two crossed tan strips with a pad (and its little holes) at the cross.
strip = rounded_rect(0.185, 0.048, 0.022)
pad = rot2(rounded_rect(0.046, 0.038, 0.01, per_corner=2), -35)
bandage = [
    # A starts 0.5 mm off the back plane so its back face never fights B's.
    decal("BandageA", rot2(strip, 35), 0.0035, TAN, back=0.0005),
    decal("BandageB", rot2(strip, -35), 0.0065, TAN),
    decal("BandagePad", pad, 0.0035, TAN_DARK, back=0.0055),
]
for i, (dx, dz) in enumerate(((-0.011, -0.008), (0.011, -0.008), (-0.011, 0.008), (0.011, 0.008))):
    (hx, hz), = rot2([(dx, dz)], -35)
    bandage.append(pk.cyl("BandageHole%d" % i, 0.0032, 0.0016, loc=(hx, -0.0094, hz),
                          rot=(90, 0, 0), material=TAN, verts=5))
sticker("Sticker_BANDAGE", bandage)

# Number 7: a dusty-blue rounded badge with a raised mustard 7, like a jersey.
seven = [(-0.036, 0.048), (0.040, 0.048), (0.040, 0.031), (0.003, -0.050),
         (-0.018, -0.050), (0.016, 0.030), (-0.036, 0.030)]
sticker("Sticker_NUMBER7", [
    decal("BadgeBack", rounded_rect(0.148, 0.156, 0.032), 0.006, BLUE, bevel=0.0015),
    decal("BadgeSeven", seven, 0.004, MUSTARD, back=0.0055, bevel=0.0012),
])

pk.smooth_all(35.0)

# --- Self-check: fail loudly if an item breaks the size/origin/budget rules ---
TOPS = ["Acc_BERET", "Acc_PARTY_HAT", "Acc_PROPELLER_CAP", "Acc_BOW", "Acc_TINY_CROWN",
        "Acc_SPROUT"]
STICKERS = ["Sticker_STAR", "Sticker_SMILEY", "Sticker_BANDAGE", "Sticker_NUMBER7"]
_, per_item = pk.triangle_count()
problems = []
for name in TOPS + STICKERS:
    obj = bpy.data.objects[name]
    pts = [v.co for v in obj.data.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    size = hi - lo
    print("[accessories] %-18s %3d tris  size x %.3f  y %.3f  z %.3f  min z %.4f  max y %.4f"
          % (name, per_item[name], size.x, size.y, size.z, lo.z, hi.y))
    if obj.parent is not root or obj.location.length > 1e-6 or \
            Vector(obj.rotation_euler).length > 1e-6 or (Vector(obj.scale) - Vector((1, 1, 1))).length > 1e-6:
        problems.append("%s: transform is not clean" % name)
    if per_item[name] > 250:
        problems.append("%s: %d triangles (limit 250)" % (name, per_item[name]))
    if name in TOPS:
        if abs(lo.z) > 1e-4 or max(size.x, size.y) > 0.32 or size.z > 0.25:
            problems.append("%s: must start at z = 0, footprint <= 0.32, height <= 0.25" % name)
    elif abs(hi.y) > 1e-4 or size.y > 0.012 or abs(lo.x + hi.x) > 1e-4 or abs(lo.z + hi.z) > 1e-4:
        problems.append("%s: must be <= 1.2 cm thick, back face centred on the origin" % name)
if problems:
    print("[accessories] ERROR:\n  " + "\n  ".join(problems))
    sys.exit(1)

pk.export("enemy_accessories.glb", budget=2500)
