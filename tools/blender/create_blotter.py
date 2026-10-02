"""
Blotter - the teal artillery enemy (slow, big splash).

Plan: docs/VISUAL_OVERHAUL_PLAN.md section 4.6.

A paint bucket turned siege engine: a big round glass paint tank full of teal
paint, a painted-metal band with rivets round its middle, a metal cup under it
standing on four stubby splayed legs, and a short fat mortar on a yoke on top,
tilted 50 degrees up and forward with a glob of paint sitting in its mouth.
The widest, roundest outline in the game.

Axes: the enemy faces BLENDER -Y (the exporter turns that into Godot +Z, the
way enemy.gd turns an enemy toward its target). X is right, Z is up. The
origin is on the floor, centred under the tank.

Nodes Godot relies on (names must not change):
    Blotter  root empty at the floor, centre of the body.
    Fill     teal paint inside the glass tank (PK_Fill). Origin at the tank
             centre, so Godot can tilt it a little to make the paint slosh.
    Mortar   tube + flared muzzle. Origin on the yoke hinge; the hinge axis is
             X. The barrel points 50 degrees up and forward, i.e. along
             Blender (0, -0.643, 0.766). Rest rotation is zero, so recoil is
             a small move back along that line or a tilt about X.
    Glob     the paint glob in the mortar's mouth (PK_Wet), a CHILD of Mortar.
             Origin at its own centre, so Godot can scale it to zero on each
             shot and grow it back.

Run:  blender -b --factory-startup --python tools/blender/create_blotter.py
"""

import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("Blotter", seed=33)

TEAL = "#00A896"
glass = pk.mat("PK_Glass")
fill_mat = pk.mat("PK_Fill", color=TEAL)
wet = pk.mat("PK_Wet", color=TEAL)
accent = pk.mat("PK_Accent", color=TEAL)
trim = pk.mat("PK_Trim")
metal = pk.mat("PK_Metal")
rubber = pk.mat("PK_Rubber")
dark = pk.mat("PK_Dark")

root = pk.empty("Blotter")


def aimed_box(name, size, start, end, material, bevel=0.0, segments=2):
    """A bevelled box stretched from point `start` to point `end`.
    size = (width, depth) across the box; its length runs start -> end."""
    start, end = Vector(start), Vector(end)
    direction = end - start
    rot = Vector((0, 0, 1)).rotation_difference(direction.normalized()).to_euler()
    return pk.box(name, (size[0], size[1], direction.length), loc=(start + end) * 0.5,
                  rot=tuple(math.degrees(a) for a in rot), material=material,
                  bevel=bevel, segments=segments)


def baked(obj):
    """Bake a joined object's leftover rotation into its mesh, so the node
    exports with a clean transform (it keeps the first part's rotation)."""
    pk.apply(obj, location=False, rotation=True, scale=True)
    return obj


# --- Glass paint tank ---------------------------------------------------------
# A sphere 1.06 m wide and 1.0 m tall, sliced flat at the top where the lid sits.
TANK_Z = 0.60          # tank centre height
TANK_RX = 0.53         # horizontal radius
TANK_RZ = 0.50         # vertical radius
TOP = 0.34             # flat top, measured up from the tank centre
FILL_TOP = 0.19        # the fill line, measured up from the tank centre


def sphere_profile(rx, rz, top, steps):
    """(radius, height) points up a squashed sphere from the bottom pole to
    height `top`."""
    phi_top = math.asin(top / rz)
    pts = []
    for i in range(steps + 1):
        phi = -math.pi / 2 + (phi_top + math.pi / 2) * i / steps
        pts.append((rx * math.cos(phi), rz * math.sin(phi)))
    pts[0] = (0.0, -rz)
    return pts


# Open at the top: the lid closes it.
pk.lathe("Tank", sphere_profile(TANK_RX, TANK_RZ, TOP, 8), loc=(0, 0, TANK_Z),
         material=glass, segments=20, parent_obj=root)

# The paint inside: the same sphere a little smaller, cut flat at the fill line.
# Its origin stays at the tank centre (the slosh pivot).
fill_profile = sphere_profile(TANK_RX - 0.03, TANK_RZ - 0.03, FILL_TOP, 5)
fill_profile.append((0.0, FILL_TOP))
fill_obj = pk.lathe("Fill", fill_profile, loc=(0, 0, TANK_Z), material=fill_mat,
                    segments=16, parent_obj=root)

# --- Lid on the flat top, and the metal cup under the tank --------------------
LID_H = 0.058
pk.lathe("Lid", [(0.0, TOP - 0.03), (0.39, TOP - 0.03), (0.412, TOP), (0.398, TOP + 0.04),
                 (0.33, TOP + LID_H), (0.0, TOP + LID_H)],
         loc=(0, 0, TANK_Z), material=metal, segments=20, parent_obj=root)
pk.lathe("Cup", [(0.0, -0.52), (0.22, -0.505), (0.34, -0.44), (0.425, -0.33),
                 (0.43, -0.30), (0.40, -0.29)],
         loc=(0, 0, TANK_Z), material=trim, segments=16, parent_obj=root)

# --- Equator band with rivets -------------------------------------------------
pk.lathe("Band", [(0.52, -0.075), (0.556, -0.068), (0.568, 0.0), (0.556, 0.068),
                  (0.52, 0.075)],
         loc=(0, 0, TANK_Z), material=trim, segments=16, parent_obj=root)
rivets = []
for i in range(8):
    a = math.tau * (i + 0.5) / 8
    # Squash a small sphere along its local Z, then turn that Z to face outward.
    rivet = pk.sphere("Rivet%d" % i, 0.03, loc=(math.cos(a) * 0.562, math.sin(a) * 0.562, TANK_Z),
                      scale=(1, 1, 0.55), rot=(0, 90, math.degrees(a)), material=metal,
                      segments=6, rings=3)
    rivets.append(rivet)
pk.parent(baked(pk.join("Rivets", rivets)), root)

# --- Four stubby splayed legs -------------------------------------------------
legs = []
for i in range(4):
    a = math.radians(45 + 90 * i)
    c, s = math.cos(a), math.sin(a)
    hip = (c * 0.34, s * 0.34, 0.36)
    foot = (c * 0.62, s * 0.62, 0.075)
    leg = aimed_box("Leg%d" % i, (0.17, 0.19), hip, foot, trim, bevel=0.035, segments=2)
    legs.append(leg)
    legs.append(pk.sphere("Foot%d" % i, 0.14, loc=(c * 0.64, s * 0.64, 0.0588),
                          scale=(1, 1, 0.42), material=rubber, segments=8, rings=4))
pk.parent(baked(pk.join("Legs", legs)), root)

# --- Yoke on the lid ----------------------------------------------------------
LID_TOP = TANK_Z + TOP + LID_H
HINGE = Vector((0.0, 0.04, 1.240))     # mortar pivot; the hinge axis is X
pk.lathe("Turntable", [(0.0, 0.03), (0.24, 0.03), (0.265, 0.012), (0.26, -0.01)],
         loc=(0, 0.02, LID_TOP), material=trim, segments=16, parent_obj=root)
yoke = []
# Each cheek is a flat plate with a rounded top, drawn in (forward, up) and
# stood up with its thickness along X (same trick as the blaster's grip).
cheek_top = HINGE.z + 0.10 - LID_TOP
outline = [(-0.14, 0.0), (0.14, 0.0), (0.14, cheek_top - 0.14)]
for k in range(1, 6):
    ang = math.pi * k / 6
    outline.append((0.14 * math.cos(ang), cheek_top - 0.14 + 0.14 * math.sin(ang)))
outline.append((-0.14, cheek_top - 0.14))
for side in (-1, 1):
    yoke.append(pk.prism("Cheek%d" % (side > 0), outline, 0.06,
                         loc=(side * 0.225, HINGE.y, LID_TOP), rot=(90, 0, 90),
                         material=trim, bevel=0.012, segments=1))
    yoke.append(pk.cyl("Pin%d" % (side > 0), 0.075, 0.05, loc=(side * 0.28, HINGE.y, HINGE.z),
                       rot=(0, 90, 0), material=metal, verts=10))
pk.parent(baked(pk.join("Yoke", yoke)), root)

# --- Mortar: a short fat tube with a flared teal muzzle -----------------------
# Built along local Z, then tipped forward 40 degrees about X so the barrel
# points 50 degrees above the horizon, toward -Y (the enemy's front). A dark
# lip frames the glob so it pops against the teal bell.
TILT = (40, 0, 0)
tube = pk.lathe("MortarTube", [
    (0.0, -0.15), (0.10, -0.145), (0.155, -0.12), (0.18, -0.075),
    (0.18, 0.22), (0.19, 0.25)], loc=HINGE, rot=TILT, material=metal, segments=16)
bell = pk.lathe("MortarBell", [
    (0.185, 0.24), (0.215, 0.29), (0.245, 0.35), (0.252, 0.385)],
    loc=HINGE, rot=TILT, material=accent, segments=16)
lip = pk.lathe("MortarLip", [
    (0.252, 0.38), (0.232, 0.405), (0.185, 0.405), (0.158, 0.375), (0.0, 0.36)],
    loc=HINGE, rot=TILT, material=dark, segments=16)
mortar = pk.join("Mortar", [tube, bell, lip])
pk.apply(mortar, location=False, rotation=True, scale=True)
pk.set_origin(mortar, HINGE)
pk.parent(mortar, root)

# --- The glob sitting in the mouth --------------------------------------------
barrel = Vector((0.0, -math.sin(math.radians(40)), math.cos(math.radians(40))))
glob = pk.sphere("Glob", 0.14, loc=HINGE + barrel * 0.39, scale=(1.0, 1.0, 0.92),
                 material=wet, segments=10, rings=6)
pk.displace_random(glob, 0.012, seed=33)
pk.parent(glob, mortar)

pk.smooth_all(35.0)
pk.export("enemy_blotter.glb", budget=2500)
