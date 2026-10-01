"""
Ghost - the white regenerating enemy.

Plan: docs/VISUAL_OVERHAUL_PLAN.md section 4.8.

A painter's drop-cloth come alive: a tall, narrow, hooded drape of canvas that
floats with its ragged hem 0.25 m off the floor (the only enemy with a gap
under it). A dark face opening inside the hood holds two soft glowing eyes,
five ragged canvas strips trail behind and around it, and a thin sleeve holds
a palette knife like a wand. A dark ink trim runs round the hem so the pale
body still reads against the pale floor. The body is fully opaque so it stays
easy to target; only two of the strips are a see-through veil.

Axes: the enemy faces BLENDER -Y (the exporter turns that into Godot +Z).
X is its LEFT, so its knife arm is on -X (its right). Z is up. The origin is
on the floor, centred under the body.

Nodes Godot relies on (names must not change):
    Ghost     root empty at the floor, centre of the body.
    Hem       the dark ink trim round the ragged hem (PK_Dark), its own
              object so it can brighten while the Ghost regenerates.
    Eyes      both eyes in one object (PK_AccentGlow); origin between them.
    Strip_0 .. Strip_4
              the trailing canvas strips. Each ORIGIN is on the strip's top
              edge, where it hangs from the body, so rotating it sways the
              strip. Strip_3 and Strip_4 use the translucent PK_Veil.

Run:  blender -b --factory-startup --python tools/blender/create_ghost.py
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("Ghost", seed=55)

WHITE = "#FFFFFF"
canvas = pk.mat("PK_Canvas")
dark = pk.mat("PK_Dark")
glow = pk.mat("PK_AccentGlow", color=WHITE)
veil = pk.mat("PK_Glass", name="PK_Veil", color=WHITE, alpha=0.45)
metal = pk.mat("PK_Metal")

root = pk.empty("Ghost")

SEGMENTS = 24
STEP = 360.0 / SEGMENTS
# Turn the lathe half a step so a column of faces is centred on the front (-Y);
# the face opening is cut from five of those columns.
OFFSET = STEP * 0.5

# --- The drape: one lathe from the hood peak down to the hem and back up
# underneath, so the underside is closed (it is seen from below). ------------
PROFILE = [
    (0.0, 1.70),     # 0  hood peak
    (0.14, 1.655),
    (0.205, 1.595),
    (0.232, 1.51),
    (0.238, 1.42),
    (0.232, 1.34),   # 5  bottom of the hood
    (0.26, 1.26),    #    shoulders
    (0.295, 1.14),
    (0.302, 0.96),
    (0.325, 0.72),
    (0.352, 0.53),
    (0.368, 0.47),   # 11 top edge of the ink trim
    (0.38, 0.40),    # 12 hem
    (0.355, 0.375),  # 13 lip, turning under (the lowest ring)
    (0.29, 0.43),    # 14 underside
    (0.0, 0.53),     # 15 underside centre
]
TRIM_TOP = 11
HEM_ROWS = {11: 0.75, 12: 1.0, 13: 1.0, 14: 0.5}   # how much of the tatter each ring gets

body = pk.lathe("Body", PROFILE, rot=(0, 0, OFFSET), material=canvas, segments=SEGMENTS)
pk.apply(body, location=False, rotation=True, scale=True)
mesh = body.data


def profile_index(co):
    r = math.hypot(co.x, co.y)
    return min(range(len(PROFILE)),
               key=lambda i: abs(PROFILE[i][0] - r) + abs(PROFILE[i][1] - co.z))


ring = [profile_index(v.co) for v in mesh.vertices]

# Ragged hem: every other column of the hem hangs down into a torn point of
# uneven length; the columns between are pulled up by varying amounts.
rng = random.Random(55)
tatter = []
for i in range(SEGMENTS):
    if i % 2:
        tatter.append(rng.choice((0.06, 0.085, 0.11, 0.12)) + rng.uniform(-0.01, 0.0))
    else:
        tatter.append(rng.uniform(-0.03, 0.02))


def smoothstep(edge0, edge1, x):
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


for v, k in zip(mesh.vertices, ring):
    x, y, z = v.co
    r = math.hypot(x, y)
    if r < 1e-6:
        if z > 1.6:
            v.co.y += 0.10          # hood peak droops backward
        continue
    theta = math.atan2(y, x)
    # Folds in the drape: six soft ridges (one centred on the front), strongest
    # near the hem, none on the hood.
    fold = 0.12 * smoothstep(1.30, 0.50, z) * math.cos(6 * theta + math.pi)
    r *= 1.0 + fold
    x, y = r * math.cos(theta), r * math.sin(theta)
    # Hood leans back into a soft point.
    if z > 1.55:
        y += 0.10 * ((z - 1.55) / 0.15) ** 2
    if k in HEM_ROWS:
        column = int(round((math.degrees(theta) - OFFSET) / STEP)) % SEGMENTS
        z -= tatter[column] * HEM_ROWS[k]
    v.co = (x, y, z)

pk.displace_random(body, 0.008, seed=55)

# Split the ink trim (everything from the trim's top ring down, including the
# underside) off into its own object, Hem.
hem = body.copy()
hem.data = mesh.copy()
hem.name = "Hem"
hem.data.name = "Hem"
bpy.context.view_layer.active_layer_collection.collection.objects.link(hem)


def keep_faces(obj, want_hem):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    # Both meshes are still untouched copies here, so vertex indices match `ring`.
    gone = [f for f in bm.faces
            if all(ring[v.index] >= TRIM_TOP for v in f.verts) != want_hem]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()


keep_faces(hem, True)
keep_faces(body, False)

# Cut the face opening out of the front of the hood: faces in front (-Y) and
# between the hood's bottom ring and the ring at 1.595 m.
bm = bmesh.new()
bm.from_mesh(mesh)
bm.faces.ensure_lookup_table()
hole = []
for f in bm.faces:
    c = f.calc_center_median()
    ang = math.degrees(math.atan2(c.y, c.x))
    if 1.36 < c.z < 1.58 and abs(ang + 90.0) < STEP * 2.5:
        hole.append(f)
bmesh.ops.delete(bm, geom=hole, context="FACES")
bm.to_mesh(mesh)
bm.free()
hem.data.materials.clear()
hem.data.materials.append(dark)
pk.parent(body, root)
pk.parent(hem, root)

# --- Face: a dark void behind the opening, an arched canvas brim round it, and
# two soft glowing eyes -------------------------------------------------------
FACE_Z = 1.47
TILT = 9.0      # the face leans back a little, following the hood


def hood_front_y(x, z):
    """Where the (unfolded) hood surface is at height z, x across, on the front."""
    for (r0, z0), (r1, z1) in zip(PROFILE, PROFILE[1:]):
        if z1 <= z <= z0:
            r = r0 + (r1 - r0) * (z - z0) / (z1 - z0)
            break
    y = -math.sqrt(max(r * r - x * x, 0.0))
    if z > 1.55:
        y += 0.10 * ((z - 1.55) / 0.15) ** 2
    return y


# The opening's edge runs up one side, over the top in a soft point, and down
# the other side; the chin below it is the drape itself.
brim_path = []
for x, z in ((-0.155, 1.31), (-0.165, 1.46), (-0.12, 1.60), (0.0, 1.655),
             (0.12, 1.60), (0.165, 1.46), (0.155, 1.31)):
    brim_path.append((x, hood_front_y(x, z) - 0.012, z))
pk.tube("HoodBrim", brim_path, 0.036, material=canvas, resolution=1, path_resolution=2,
        parent_obj=root)

face = pk.sphere("Face", 1.0, loc=(0, -0.10, FACE_Z), scale=(0.165, 0.12, 0.165),
                 rot=(-TILT, 0, 0), material=dark, segments=10, rings=6)
pk.apply(face, location=False, rotation=True, scale=True)
pk.parent(face, root)

EYE_Y = -0.207
eyes = []
for side in (-1, 1):
    eyes.append(pk.sphere("Eye%d" % (side > 0), 0.038, loc=(side * 0.066, EYE_Y, FACE_Z + 0.01),
                          scale=(1.0, 0.5, 1.3), material=glow, segments=8, rings=4))
eyes_obj = pk.join("Eyes", eyes)
pk.set_origin(eyes_obj, (0, EYE_Y, FACE_Z + 0.01))
pk.parent(eyes_obj, root)

# --- Knife arm (its right, -X): a thin sleeve holding a palette knife ----------
SHOULDER = Vector((-0.25, -0.09, 1.16))
WRIST = Vector((-0.33, -0.17, 0.92))
KNIFE_DIR = Vector((-0.10, -0.25, -1.0)).normalized()   # held low, tip forward


def aimed_cone(name, start, end, r0, r1, material, verts=8):
    """A tapered cylinder from point `start` (radius r0) to `end` (radius r1)."""
    start, end = Vector(start), Vector(end)
    d = end - start
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
    return pk.cyl(name, r0, d.length, loc=(start + end) * 0.5,
                  rot=tuple(math.degrees(a) for a in rot), radius_top=r1,
                  material=material, verts=verts)


arm_dir = (WRIST - SHOULDER).normalized()
arm_parts = [
    aimed_cone("Sleeve", SHOULDER, WRIST, 0.062, 0.045, canvas),
    aimed_cone("Cuff", WRIST - arm_dir * 0.02, WRIST + arm_dir * 0.05, 0.05, 0.068, canvas),
    aimed_cone("Handle", WRIST, WRIST + KNIFE_DIR * 0.13, 0.024, 0.02, dark, verts=6),
]
# The blade: a flat trowel shape carrying on from the handle, flat face to the front.
blade_root = WRIST + KNIFE_DIR * 0.12
blade = pk.prism("Blade", [(0.0, -0.018), (0.05, -0.04), (0.16, -0.036), (0.22, -0.012),
                           (0.225, 0.0), (0.22, 0.012), (0.16, 0.036), (0.05, 0.04),
                           (0.0, 0.018)], 0.014, material=metal)
# Outline drawn along local +X with its flat face on local Z: send +X down the
# arm and turn the flat face as close to the front (-Y) as the arm allows.
face = Vector((0, -1, 0))
face = (face - KNIFE_DIR * face.dot(KNIFE_DIR)).normalized()
frame = Matrix((KNIFE_DIR, face.cross(KNIFE_DIR), face)).transposed().to_4x4()
frame.translation = blade_root
blade.matrix_world = frame
bpy.context.view_layer.update()
arm_parts.append(blade)
arm = pk.join("Arm", arm_parts)
pk.apply(arm, location=False, rotation=True, scale=True)
pk.set_origin(arm, SHOULDER)
pk.parent(arm, root)


# --- Five trailing strips -----------------------------------------------------
def ribbon(name, pts, width, material, twist=0.0, thickness=0.018, seed=0):
    """A ragged canvas strip along the points `pts` (top first). At the top
    its flat face looks away from the body; it turns `twist` degrees about its
    length by the end, narrows, and finishes in a notched, torn tip dipped in
    ink (PK_Dark). Thickness comes from a Solidify modifier (applied on
    export)."""
    r = random.Random(seed)
    pts = [Vector(p) for p in pts]
    n = len(pts)
    bm = bmesh.new()
    rows = []
    frames = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        radial = Vector((p.x, p.y, 0.0)).normalized()
        side = t.cross(radial).normalized()
        side = Matrix.Rotation(math.radians(twist * i / (n - 1)), 3, t) @ side
        frames.append((side, t))
        w = width * (1.0 - 0.3 * i / (n - 1)) * 0.5
        if i < n - 1:
            rows.append((bm.verts.new(p - side * w), bm.verts.new(p + side * w)))
    side, t = frames[-1]
    w = width * 0.7 * 0.5
    tip_l = bm.verts.new(pts[-1] - side * w + t * r.uniform(-0.04, 0.03))
    tip_r = bm.verts.new(pts[-1] + side * w + t * r.uniform(-0.04, 0.03))
    notch = bm.verts.new(pts[-2] + (pts[-1] - pts[-2]) * r.uniform(0.3, 0.5))
    for a, b in zip(rows, rows[1:]):
        bm.faces.new((a[0], b[0], b[1], a[1]))
    last = rows[-1]
    tip = bm.faces.new((last[0], tip_l, notch, tip_r, last[1]))
    tip.material_index = 1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.view_layer.active_layer_collection.collection.objects.link(obj)
    mesh.materials.append(material)
    mesh.materials.append(dark)
    mod = obj.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 0.0
    pk.set_origin(obj, pts[0])
    pk.parent(obj, root)
    return obj


def polar_path(thetas, radii, heights):
    return [(r * math.cos(math.radians(a)), r * math.sin(math.radians(a)), z)
            for a, r, z in zip(thetas, radii, heights)]


# Angles are measured round the body from +X (its left side); 90 is straight
# behind, 180 is its right side. Each strip leaves the body, stands off it and
# drifts backward as it falls, so it reads as a separate ribbon.
STRIPS = [
    # (angle path, radius path, height path, width, twist, material)
    ((90, 88, 92, 89, 91, 90), (0.23, 0.31, 0.36, 0.395, 0.42, 0.435),
     (1.31, 1.14, 0.96, 0.79, 0.63, 0.50), 0.15, 25, canvas),
    ((18, 24, 30, 36, 41, 45), (0.26, 0.345, 0.385, 0.405, 0.42, 0.435),
     (1.24, 1.10, 0.94, 0.78, 0.63, 0.49), 0.12, 70, canvas),
    ((162, 156, 150, 144, 139, 135), (0.26, 0.345, 0.385, 0.405, 0.42, 0.435),
     (1.24, 1.10, 0.94, 0.78, 0.63, 0.49), 0.12, -70, canvas),
    ((58, 60, 62, 63, 64, 65), (0.27, 0.33, 0.37, 0.40, 0.42, 0.435),
     (1.20, 1.04, 0.87, 0.71, 0.56, 0.42), 0.11, -40, veil),
    ((122, 120, 118, 117, 116, 115), (0.27, 0.33, 0.37, 0.40, 0.42, 0.435),
     (1.20, 1.04, 0.87, 0.71, 0.56, 0.42), 0.11, 40, veil),
]
for i, (thetas, radii, heights, width, twist, material) in enumerate(STRIPS):
    ribbon("Strip_%d" % i, polar_path(thetas, radii, heights), width, material, twist=twist,
           seed=55 + i)

# Cloth should look soft, so the drape is smoothed across its folds (70
# degrees); everything else, including the hem's torn points, uses the usual
# 35. (A second smoothing pass would keep the first pass's sharp edges, so the
# drape gets only the one.)
for obj in pk.objects():
    pk.smooth(obj, 70.0 if obj is body else 35.0)
pk.export("enemy_ghost.glb", budget=1500)
