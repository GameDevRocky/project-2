"""
Pigment Heart - the inheritance core a defeated enemy drops (14 s pickup).

Plan: docs/VISUAL_OVERHAUL_PLAN.md section 4.9.

A faceted droplet of concentrated paint hangs inside a slowly turning metal
brush-ferrule ring. Twelve raised ticks on the ring are a clock: Godot hides
one every 14/12 s, so the pickup's lifetime drains visibly. Two thin gimbal
hoops turn around the droplet, and a small wet puddle sits on the floor
beneath it. The metal is neutral grey-lilac so charcoal and white cores
still read; everything that carries the pair colour is Accent/Wet.

Axes: Z is up (Godot Y). The object origin is the centre of the droplet.
The pickup node floats 0.7 m above the floor, so the floor is at z = -0.70.

Nodes Godot relies on (names must not change):
    PigmentCore  root (plain Node3D), at the droplet centre.
    Droplet      faceted teardrop, tip up, ORIGIN at (0, 0, 0).
                 Material PK_AccentGlow (pair colour, glowing).
    Ring         the ferrule ring, horizontal, ORIGIN at (0, 0, 0) so it can
                 spin around the vertical axis. Material PK_Metal.
    Tick_00..11  children of Ring, material PK_Accent (pair colour). Tick_00
                 is at the front (-Y); the numbers run CLOCKWISE seen from
                 above (-Y, -X, +Y, +X), 30 degrees apart. Each tick's
                 ORIGIN is the middle of its base, on top of the ring.
    Gimbal_A     thin hoop standing in the XZ plane, ORIGIN (0, 0, 0).
    Gimbal_B     thin hoop standing in the YZ plane, ORIGIN (0, 0, 0).
                 Both PK_Metal; they turn around the droplet.
    Puddle       flat wet puddle on the floor: top at z = -0.68, bottom at
                 -0.69, ORIGIN at (0, 0, -0.69). Material PK_Wet.

Run:  blender -b --factory-startup --python tools/blender/create_inheritance_core.py
"""

import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("PigmentCore", seed=7)

glow = pk.mat("PK_AccentGlow")
accent = pk.mat("PK_Accent")
metal = pk.mat("PK_Metal")
wet = pk.mat("PK_Wet")

root = pk.empty("PigmentCore")


def mesh_object(name, bm, material, loc=(0, 0, 0), rot_z=0.0, parent_obj=None):
    """Turn a finished bmesh into an object in the asset's collection."""
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    pk._collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (0.0, 0.0, rot_z)
    mesh.materials.append(material)
    if parent_obj is not None:
        pk.parent(obj, parent_obj)
    return obj


def face_outward(bm, centre):
    """Make every face point away from `centre` (for small convex parts
    that are left open underneath, where recalc_face_normals can guess
    wrong)."""
    for face in bm.faces:
        face.normal_update()
        if face.normal.dot(face.calc_center_median() - Vector(centre)) < 0.0:
            face.normal_flip()


# --- Droplet: an icosphere pulled into a teardrop, tip up ---------------------
DROP_R = 0.22
droplet = pk.ico("Droplet", DROP_R, material=glow, subdiv=2)
TIP = 1.35 * DROP_R                          # tip height above the belly
for v in droplet.data.vertices:
    t = v.co.z / DROP_R                      # -1 at the bottom, +1 at the top
    if t > 0.0:
        # Upper half: lift towards the tip and narrow with slightly concave
        # sides, like a drop about to fall upwards.
        sphere_width = math.sqrt(max(1.0 - t * t, 1e-6))
        drop_width = (1.0 - t) ** 1.15
        v.co.x *= drop_width / sphere_width
        v.co.y *= drop_width / sphere_width
        v.co.z = t * TIP
    else:
        v.co.z *= 0.95                       # slightly heavy, round belly
# Centre the teardrop on the origin (the pickup's floating point).
zs = [v.co.z for v in droplet.data.vertices]
shift = (max(zs) + min(zs)) * 0.5
for v in droplet.data.vertices:
    v.co.z -= shift
pk.parent(droplet, root)

# --- Ring: a metal brush-ferrule band, lying flat around the droplet ---------
# Closed cross-section (radius, height): flat inner wall, chamfered corners,
# a slightly proud outer face. First point repeated at the end to close it.
RING_TOP = 0.034
ring = pk.lathe("Ring", [
    (0.398, -RING_TOP), (0.438, -0.042), (0.452, -0.026), (0.452, 0.026),
    (0.438, 0.042), (0.398, RING_TOP), (0.398, -RING_TOP)],
    material=metal, segments=24, parent_obj=root)

# --- 12 ticks on top of the ring, children of Ring ----------------------------
TICK_R = 0.424          # radius of the tick centres
TICK_LEN = 0.1          # along the ring
# Cross-section (outward, up): a squat trapezoid, so each tick reads as a
# chunky bevelled block for only 10 triangles.
TICK_PROFILE = [(-0.03, 0.0), (0.03, 0.0), (0.019, 0.03), (-0.019, 0.03)]
for i in range(12):
    angle = math.radians(-90.0 - 30.0 * i)      # clockwise from -Y, seen from above
    bm = bmesh.new()
    ends = []
    for x in (-TICK_LEN * 0.5, TICK_LEN * 0.5):
        # Local axes: X along the ring, Y outward, Z up.
        ends.append([bm.verts.new((x, u, v)) for u, v in TICK_PROFILE])
    bm.faces.new(ends[0])
    bm.faces.new(ends[1])
    n = len(TICK_PROFILE)
    for k in range(1, n):                       # k = 0 would be the hidden base
        a, b = k, (k + 1) % n
        bm.faces.new((ends[0][a], ends[0][b], ends[1][b], ends[1][a]))
    face_outward(bm, (0.0, 0.0, 0.015))
    loc = (math.cos(angle) * TICK_R, math.sin(angle) * TICK_R, RING_TOP)
    mesh_object("Tick_%02d" % i, bm, accent, loc=loc, rot_z=angle - math.pi / 2,
                parent_obj=ring)

# --- Gimbal hoops: thin, turning around the droplet ---------------------------
# Diamond cross-section (4 sides) smoothed round, to keep the triangle count
# low. B is the inner hoop, A the outer; both clear the droplet at any angle.
gimbal_a = pk.torus("Gimbal_A", 0.345, 0.012, rot=(90, 0, 0), material=metal,
                    segments=22, ring_segments=4, parent_obj=root)
gimbal_b = pk.torus("Gimbal_B", 0.3, 0.012, rot=(90, 0, 90), material=metal,
                    segments=22, ring_segments=4, parent_obj=root)
for g in (gimbal_a, gimbal_b):
    pk.apply(g, location=False, rotation=True, scale=True)

# --- Puddle: flat wet splat on the floor, directly below ---------------------
PUDDLE_TOP = -0.68
PUDDLE_BOTTOM = -0.69
rng = random.Random(3)
bm = bmesh.new()
outer, inner = [], []
PUDDLE_POINTS = 18
phase_a, phase_b = rng.uniform(0, math.tau), rng.uniform(0, math.tau)
for i in range(PUDDLE_POINTS):
    # Evenly spaced points on a smooth lobed curve: a liquid, rounded outline
    # (per-point noise made it look like a shard of rock).
    angle = math.tau * i / PUDDLE_POINTS
    radius = 0.235 * (1.0 + 0.11 * math.sin(3 * angle + phase_a)
                      + 0.06 * math.sin(5 * angle + phase_b))
    c, s = math.cos(angle), math.sin(angle)
    outer.append(bm.verts.new((c * radius, s * radius, PUDDLE_BOTTOM)))
    inner.append(bm.verts.new((c * (radius - 0.02), s * (radius - 0.02), PUDDLE_TOP)))
bm.faces.new(inner)                              # the flat top
for i in range(PUDDLE_POINTS):
    j = (i + 1) % PUDDLE_POINTS
    bm.faces.new((outer[i], outer[j], inner[j], inner[i]))   # soft rounded rim
face_outward(bm, (0.0, 0.0, PUDDLE_BOTTOM - 0.05))
puddle = mesh_object("Puddle", bm, wet, parent_obj=root)
pk.set_origin(puddle, (0.0, 0.0, PUDDLE_BOTTOM))

pk.smooth_all(35.0)

# The droplet is meant to be FACETED, like a cut gem of paint.
pk.select_only(droplet)
bpy.ops.object.shade_flat()
# The gimbals' 4-sided cross-section should still look round.
for g in (gimbal_a, gimbal_b):
    pk.select_only(g)
    bpy.ops.object.shade_smooth(keep_sharp_edges=False)

pk.export("core_pigment.glb", budget=900)
