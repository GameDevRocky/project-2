"""
Monolith - the charcoal heavy enemy (extremely durable, slow, hard-hitting).

Plan: docs/VISUAL_OVERHAUL_PLAN.md section 4.7.

A golem stacked out of four thick charcoal slabs, each one caked with a band
of dried paint along its bottom edge that drips over the slab below. Enormous
shoulder blocks, a head sunk between them that shows only a narrow glowing
slit, a heavy flat house-painter's brush for a right arm, a slab shield on the
left arm, and thick column legs. The only boxy, top-heavy outline in the game.

The charcoal body (PK_Accent) is meant to be the darkest thing in the arena;
the ochre / lilac / clay dried-paint bands (PK_Dry1..3) keep its outline
readable against the dark walls.

Axes: the enemy faces BLENDER -Y (the exporter turns that into Godot +Z).
X is its LEFT, so its right arm is on -X. Z is up. The origin is on the floor
between the feet.

Nodes Godot relies on (names must not change):
    Monolith  root empty at the floor, between the feet.
    TopSlab   the head block (with its slit). Origin at the centre of its
              base, so moving it up a few centimetres is the slow "breath".
    Cannon    right arm: upper arm, forearm, glowing ferrule and a wide flat
              bristle block pointing forward (-Y). Origin at the right
              shoulder joint, for recoil.
    Shield    left arm: upper arm, forearm and a slab shield. Origin at the
              left shoulder joint.

Run:  blender -b --factory-startup --python tools/blender/create_monolith.py
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("Monolith", seed=44)

CHARCOAL = "#2B2D42"
accent = pk.mat("PK_Accent", color=CHARCOAL)
glow = pk.mat("PK_AccentGlow", color="#D9CCFF")
wet = pk.mat("PK_Wet", color=CHARCOAL)
dry1 = pk.mat("PK_Dry1")   # ochre
dry2 = pk.mat("PK_Dry2")   # lilac
dry3 = pk.mat("PK_Dry3")   # clay
metal = pk.mat("PK_Metal")
dark = pk.mat("PK_Dark")

root = pk.empty("Monolith")

LIP_H = 0.08        # height of the dried-paint band on each slab
LIP_OUT = 0.03      # how far that band stands proud of the slab faces


def drip(name, top, length, radius, material):
    """A short fat drop of paint hanging from point `top`: a neck where it
    leaves the edge, a round bulb at the bottom. Open at the top, which is
    buried in the paint band it hangs from."""
    return pk.lathe(name, [(radius * 0.75, 0.012), (radius, -length * 0.55),
                           (radius * 0.55, -length * 0.9), (0.0, -length)],
                    loc=top, material=material, segments=5)


def drip_row(prefix, size, centre, z_bottom, rz, material, front, side, back, sides=(-1, 1)):
    """Drips along the bottom edge of a paint band: `front` of them on the
    -Y face, `side` on each X face listed in `sides`, `back` on the +Y face."""
    sx, sy = size[0] + 2 * LIP_OUT, size[1] + 2 * LIP_OUT
    c, s = math.cos(math.radians(rz)), math.sin(math.radians(rz))
    spots = []
    for i in range(front):
        spots.append((sx * ((i + 0.5) / front - 0.5) + random.uniform(-0.05, 0.05), -sy * 0.5))
    for i in range(back):
        spots.append((sx * ((i + 0.5) / back - 0.5) + random.uniform(-0.05, 0.05), sy * 0.5))
    for sign in sides:
        for i in range(side):
            spots.append((sign * sx * 0.5, sy * ((i + 0.5) / side - 0.5) + random.uniform(-0.05, 0.05)))
    parts = []
    for i, (lx, ly) in enumerate(spots):
        radius = random.uniform(0.04, 0.05)
        # Pull the drip in so it never sticks out past the band: it runs down
        # the slab face just below.
        inset_x = -math.copysign(radius, lx) if abs(abs(lx) - sx * 0.5) < 1e-6 else 0.0
        inset_y = -math.copysign(radius, ly) if abs(abs(ly) - sy * 0.5) < 1e-6 else 0.0
        lx, ly = lx + inset_x, ly + inset_y
        wx = centre[0] + lx * c - ly * s
        wy = centre[1] + lx * s + ly * c
        parts.append(drip("%sDrip%d" % (prefix, i), (wx, wy, z_bottom + 0.01),
                          random.uniform(0.09, 0.17), radius, material))
    return parts


def slab(name, size, centre, z_bottom, rz, material, front=3, side=1, back=1,
         sides=(-1, 1), band_on_top=False, bevel=0.045, segments=2, extra=()):
    """A charcoal slab with a band of dried paint round its bottom edge (or,
    with band_on_top, poured over its top edge) and a row of drips hanging
    off that band. Everything is merged into one object."""
    sx, sy, sz = size
    body = pk.box(name + "Body", (sx, sy, sz), loc=(centre[0], centre[1], z_bottom + sz * 0.5),
                  rot=(0, 0, rz), material=accent, bevel=bevel, segments=segments)
    if band_on_top:
        band_bottom, band_h = z_bottom + sz - LIP_H, LIP_H + 0.02
    else:
        band_bottom, band_h = z_bottom, LIP_H
    band = pk.box(name + "Band", (sx + 2 * LIP_OUT, sy + 2 * LIP_OUT, band_h),
                  loc=(centre[0], centre[1], band_bottom + band_h * 0.5), rot=(0, 0, rz),
                  material=material, bevel=0.025, segments=1)
    parts = [body, band] + drip_row(name, size, centre, band_bottom, rz, material,
                                    front, side, back, sides)
    obj = pk.join(name, parts + list(extra))
    pk.apply(obj, location=False, rotation=True, scale=True)
    return obj


# --- Legs: thick columns on flat feet, with clay knee plates -------------------
legs = []
for sign in (-1, 1):
    x = sign * 0.27
    legs.append(pk.box("LegCol%d" % (sign > 0), (0.32, 0.36, 0.76), loc=(x, 0.02, 0.10 + 0.38),
                       material=accent, bevel=0.04, segments=1))
    legs.append(pk.box("Foot%d" % (sign > 0), (0.40, 0.50, 0.14), loc=(x, -0.04, 0.07),
                       material=dark, bevel=0.035, segments=1))
    legs.append(pk.box("Knee%d" % (sign > 0), (0.36, 0.08, 0.20), loc=(x, -0.17, 0.52),
                       material=dry3, bevel=0.025, segments=1))
pk.parent(pk.join("Legs", legs), root)

# --- The stack: three body slabs, each a little wider than the one below -------
pk.parent(slab("Slab1", (0.84, 0.58, 0.30), (0.02, 0.00), 0.80, 2.0, dry3, back=0), root)
pk.parent(slab("Slab2", (0.98, 0.64, 0.34), (-0.03, -0.01), 1.10, -2.5, dry1), root)
collar = pk.box("Collar", (0.62, 0.14, 0.22), loc=(0.0, -0.27, 1.86 + 0.11), material=accent,
                bevel=0.035, segments=1)
pk.parent(slab("Slab3", (1.14, 0.72, 0.42), (0.015, 0.01), 1.44, 1.5, dry2, front=4,
               extra=[collar]), root)

# --- Enormous shoulder blocks, paint poured over their tops -------------------
for sign, material, suffix in ((-1, dry1, "R"), (1, dry1, "L")):
    pk.parent(slab("Shoulder" + suffix, (0.40, 0.80, 0.54), (sign * 0.635, 0.0), 1.64, 0.0,
                   material, front=2, side=2, back=0, sides=(sign,), band_on_top=True), root)

# --- TopSlab: the head, sunk between the shoulders, showing a glowing slit -----
# Its paint band sits on the chest where the collar hides it, so it gets no
# drips; an ochre brow right above the slit outlines the head instead.
HEAD_Y = 0.06
HEAD_FRONT = HEAD_Y - 0.26
visor = pk.box("Visor", (0.54, 0.03, 0.14), loc=(0.0, HEAD_FRONT - 0.01, 2.15), material=dark)
slit = pk.box("Slit", (0.42, 0.03, 0.05), loc=(0.0, HEAD_FRONT - 0.025, 2.15), material=glow)
brow = pk.box("Brow", (0.76, 0.10, 0.07), loc=(0.0, HEAD_FRONT - 0.02, 2.245), material=dry1,
              bevel=0.025, segments=1)
top_slab = slab("TopSlab", (0.72, 0.52, 0.44), (0.0, HEAD_Y), 1.86, -1.0, dry1,
                front=0, side=0, back=0, extra=[visor, slit, brow])
pk.set_origin(top_slab, (0.0, HEAD_Y, 1.86))
pk.parent(top_slab, root)

# --- Cannon (right arm, -X): a wide flat house-painter's brush -----------------
R_SHOULDER = (-0.625, 0.0, 1.70)
cx = R_SHOULDER[0]
arm_z = 1.30
cannon_parts = [
    pk.box("UpperArmR", (0.26, 0.30, 0.50), loc=(cx, 0.02, 1.45), material=accent,
           bevel=0.03, segments=1),
    pk.box("ForearmR", (0.26, 0.36, 0.26), loc=(cx, -0.08, arm_z), material=accent,
           bevel=0.03, segments=1),
    pk.box("Ferrule", (0.48, 0.18, 0.30), loc=(cx, -0.33, arm_z), material=metal,
           bevel=0.035, segments=1),
    pk.box("FerruleGlow", (0.49, 0.05, 0.312), loc=(cx, -0.30, arm_z), material=glow),
]
# Bristles: a wedge drawn side-on in (forward, up) and given its width along X.
# The last stretch is loaded with wet charcoal paint.
BRISTLE_Y = -0.42
cannon_parts.append(pk.prism("Bristles", [
    (-0.30, -0.095), (0.0, -0.12), (0.0, 0.12), (-0.30, 0.095)],
    0.44, loc=(cx, BRISTLE_Y, arm_z), rot=(90, 0, 90), material=dry1, bevel=0.02, segments=1))
# The wet tip is a little smaller than the bristle block, so from the front
# the ochre bristles frame a dark core of paint.
cannon_parts.append(pk.prism("BristleTip", [
    (-0.39, -0.045), (-0.36, -0.07), (-0.28, -0.075), (-0.28, 0.075), (-0.36, 0.07),
    (-0.39, 0.045), (-0.41, 0.015), (-0.41, -0.015)],
    0.38, loc=(cx, BRISTLE_Y, arm_z), rot=(90, 0, 90), material=wet, bevel=0.015, segments=1))
cannon = pk.join("Cannon", cannon_parts)
pk.apply(cannon, location=False, rotation=True, scale=True)
pk.set_origin(cannon, R_SHOULDER)
pk.parent(cannon, root)

# --- Shield (left arm, +X): a slab shield with a clay frame --------------------
L_SHOULDER = (0.625, 0.0, 1.70)
sx = L_SHOULDER[0]
shield_parts = [
    pk.box("UpperArmL", (0.26, 0.30, 0.50), loc=(sx, 0.02, 1.45), material=accent,
           bevel=0.03, segments=1),
    pk.box("ForearmL", (0.24, 0.30, 0.24), loc=(sx, -0.14, arm_z), material=accent,
           bevel=0.03, segments=1),
    pk.box("ShieldFrame", (0.52, 0.06, 0.92), loc=(0.605, -0.33, 1.26), material=dry3,
           bevel=0.025, segments=1),
    pk.box("ShieldPlate", (0.44, 0.10, 0.84), loc=(0.605, -0.39, 1.26), material=accent,
           bevel=0.04, segments=2),
]
for i, (x, length) in enumerate(((0.485, 0.15), (0.695, 0.11))):
    shield_parts.append(drip("ShieldDrip%d" % i, (x, -0.35, 0.81), length, 0.045, dry3))
shield = pk.join("Shield", shield_parts)
pk.apply(shield, location=False, rotation=True, scale=True)
pk.set_origin(shield, L_SHOULDER)
pk.parent(shield, root)

pk.smooth_all(35.0)
pk.export("enemy_monolith.glb", budget=2500)
