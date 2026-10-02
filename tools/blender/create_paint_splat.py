"""
Paint Splat - flat wet-paint marks left where a glob hits the world.

Plan: docs/VISUAL_OVERHAUL_PLAN.md section 4.13.

Four variants of one idea: an irregular central blob with ragged lobes, plus
three small satellite droplets flung out from it. Each is a very low dome
(no more than 1 cm high) so the wet highlight rolls over its edge. There is
no bottom face: a splat always lies on a wall or floor, so the underside is
never seen.

Axes: every splat lies flat in the Blender XY plane with its surface normal
(its "up") along +Z and its bottom at z = 0. projectile.gd turns +Z to the
hit normal, so the same mesh works on floors, walls and ceilings.

Nodes Godot relies on (names must not change):
    PaintSplat   root (plain Node3D).
    Splat_0..3   the four variants, each ONE mesh (blob + 3 droplets),
                 ORIGIN at (0, 0, 0) = the impact point. They all overlap on
                 purpose; Godot shows one of them. Material PK_Wet (paint
                 colour, replaced at runtime). At most 80 triangles each.

Run:  blender -b --factory-startup --python tools/blender/create_paint_splat.py
"""

import math
import os
import random
import sys

import bpy
import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("PaintSplat", seed=1)

wet = pk.mat("PK_Wet")

root = pk.empty("PaintSplat")

BLOB_POINTS = 21       # outline points of the central blob
DROP_POINTS = 5        # outline points of each satellite droplet
RIM_HEIGHT = 0.007     # where the rounded rim meets the top
PEAK_HEIGHT = 0.009    # centre of the dome (the splat's full thickness)


def blob_outline(rng):
    """The blob's outline as (angle, radius) pairs, counter-clockwise seen
    from +Z. It is made of 7 lobes of random width. Each lobe is one point
    in the dip before it plus two close points forming its rounded tip, so
    the edge alternates bump / dip like splashed paint. Most lobes are short
    bumps; two are long fingers.

    Returns the outline and the long fingers as (angle, length), so the
    satellite droplets can be flung out past them."""
    lobes = BLOB_POINTS // 3
    widths = [rng.uniform(0.7, 1.3) for _ in range(lobes)]
    scale = math.tau / sum(widths)
    widths = [w * scale for w in widths]
    base = rng.uniform(0.185, 0.2)
    long_ones = rng.sample(range(lobes), 2)
    angle = rng.uniform(0, math.tau)
    points, fingers = [], []
    for j, width in enumerate(widths):
        points.append((angle, base * rng.uniform(0.7, 0.84)))          # dip
        if j in long_ones:
            length = 0.32 if j == long_ones[0] else rng.uniform(0.27, 0.3)
            half_tip = rng.uniform(0.026, 0.034)                        # metres
        else:
            length = base * rng.uniform(1.0, 1.25)
            half_tip = rng.uniform(0.03, 0.05)
        mid = angle + width * rng.uniform(0.45, 0.55)
        spread = min(half_tip / length, width * 0.3)
        points.append((mid - spread, length * rng.uniform(0.95, 1.0)))
        points.append((mid + spread, length * rng.uniform(0.95, 1.0)))
        if j in long_ones:
            fingers.append((mid, length))
        angle += width
    fingers.sort(key=lambda f: -f[1])     # the longest finger first
    return points, fingers


def build_splat(name, seed):
    rng = random.Random(seed)
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()

    # --- Central blob: outer rim at z = 0, inner rim raised, then a fan up
    # to the dome's centre. Outline -> rim band (2 tris per point) + fan
    # (1 tri per point) = 3 x BLOB_POINTS triangles.
    outline, fingers = blob_outline(rng)
    outer, inner = [], []
    for angle, radius in outline:
        c, s = math.cos(angle), math.sin(angle)
        inset = min(0.03, radius * 0.2)
        outer.append(bm.verts.new((c * radius, s * radius, 0.0)))
        inner.append(bm.verts.new((c * (radius - inset), s * (radius - inset), RIM_HEIGHT)))
    peak = bm.verts.new((0.0, 0.0, PEAK_HEIGHT))
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((outer[i], outer[j], inner[j], inner[i]))
        bm.faces.new((inner[i], inner[j], peak))

    # --- Three satellite droplets: one flung straight out past each long
    # finger and one on the far side. Each is a tiny stretched dome:
    # 5 points round a raised centre = 5 triangles.
    drops = [(a + rng.uniform(-0.06, 0.06), length + rng.uniform(0.05, 0.065))
             for a, length in fingers]
    gap = fingers[0][0] + math.pi + rng.uniform(-0.6, 0.6)
    drops.append((gap, rng.uniform(0.27, 0.31)))
    for angle, dist in drops:
        length = rng.uniform(0.03, 0.042)      # along the flight direction
        width = rng.uniform(0.02, 0.025)
        cx, cy = math.cos(angle) * dist, math.sin(angle) * dist
        ux, uy = math.cos(angle), math.sin(angle)      # radial direction
        vx, vy = -uy, ux                               # sideways
        ring = []
        for m in range(DROP_POINTS):
            a = math.tau * m / DROP_POINTS
            along, side = math.cos(a) * length, math.sin(a) * width
            ring.append(bm.verts.new((cx + ux * along + vx * side,
                                      cy + uy * along + vy * side, 0.0)))
        top = bm.verts.new((cx, cy, 0.005))
        for m in range(DROP_POINTS):
            bm.faces.new((ring[m], ring[(m + 1) % DROP_POINTS], top))

    # Everything was wound counter-clockwise seen from above, so every face
    # already points up (+Z). Check anyway rather than trust it.
    for face in bm.faces:
        face.normal_update()
        if face.normal.z < 0.0:
            face.normal_flip()

    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    pk._collection.objects.link(obj)
    mesh.materials.append(wet)
    pk.parent(obj, root)
    return obj


for variant in range(4):
    build_splat("Splat_%d" % variant, seed=variant + 1)

pk.smooth_all(35.0)

# Guard the per-variant budget too (the kit only checks the total).
_total, _per = pk.triangle_count()
for _name, _tris in _per.items():
    if _tris > 80:
        print("[paintkit] ERROR: %s has %d triangles (max 80 per variant)" % (_name, _tris))
        sys.exit(1)

pk.export("paint_splat.glb", budget=360)
