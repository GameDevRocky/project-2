"""
Paint Restoration Station - the healing station (hold E to heal).

Plan: docs/VISUAL_OVERHAUL_PLAN.md section 4.10.

A stout three-legged artist's easel. Its ledge holds a ceramic palette
(kidney shape with a thumb hole) whose well is full of glowing restorative
paint. A small canvas above it is painted with a bold plus, and a brush cup
with three brushes stands on the ledge beside it.

Size limits (the station has NO collision, so it must stay small):
    footprint within 1.1 m x 1.1 m, centred on the origin.
    Everything stays below 1.21 m: healing_station.gd shows its progress
    ring at 1.25 m (a flat torus that grows from radius 0.15 to 0.48 right
    over the centre) and its label at 1.65 m, so nothing may reach up there.

Axes: Z is up (Godot Y). The front, where the plus faces, is Blender -Y
(Godot +Z). The object origin is the centre of the footprint on the floor.

Nodes Godot relies on (names must not change):
    HealingStation  root (plain Node3D), floor centre.
    Easel           the wooden A-frame: legs, head, ledges, arms, braces and
                    the clamp over the canvas top, as one mesh (PK_Wood).
    Canvas          the small canvas panel (PK_Canvas).
    BasinPaint      the glowing paint surface in the palette's well. ORIGIN at
                    the centre of the surface, so it can ripple/scale.
    PlusSign        the plus painted on the canvas. ORIGIN at its centre, so
                    it can pulse.
                    BasinPaint and PlusSign share the material PK_StationGlow
                    (teal #36E6D2); Godot swaps it for its ready / cooldown
                    material.
    Palette         the ceramic palette basin (PK_Body).
    BrushCup        tin cup + three brushes (PK_Metal, PK_Trim, PK_Dry*).
    PaletteDabs     dried paint dabs on the palette rim (PK_Dry*).

Run:  blender -b --factory-startup --python tools/blender/create_healing_station.py
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("HealingStation", seed=5)

wood = pk.mat("PK_Wood")
ceramic = pk.mat("PK_Body")
canvas_mat = pk.mat("PK_Canvas")
metal = pk.mat("PK_Metal")
trim = pk.mat("PK_Trim")
station_glow = pk.mat("PK_AccentGlow", name="PK_StationGlow", color="#36E6D2")
ochre = pk.mat("PK_Dry1")
lilac = pk.mat("PK_Dry2")
clay = pk.mat("PK_Dry3")

root = pk.empty("HealingStation")


def beam(name, p0, p1, width, depth, bevel=0.012, segments=2):
    """A bevelled wooden beam running from point p0 to point p1."""
    p0, p1 = Vector(p0), Vector(p1)
    direction = p1 - p0
    turn = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized()).to_euler()
    return pk.box(name, (width, depth, direction.length), loc=(p0 + p1) * 0.5,
                  rot=tuple(math.degrees(a) for a in turn), material=wood,
                  bevel=bevel, segments=segments)


def point_on(p0, p1, z):
    """Where the straight line p0 -> p1 crosses height z."""
    p0, p1 = Vector(p0), Vector(p1)
    t = (z - p0.z) / (p1.z - p0.z)
    return p0 + (p1 - p0) * t


# --- Easel ---------------------------------------------------------------------
# Two front legs lean back ~10 degrees and meet a head block; the third leg
# props the frame from behind. Feet are placed so the footprint is centred
# after the final shift below.
FOOT_L, TOP_L = (-0.42, 0.08, 0.0), (-0.12, 0.28, 1.195)
FOOT_R, TOP_R = (0.42, 0.08, 0.0), (0.12, 0.28, 1.195)
REAR_TOP, REAR_FOOT = (0.0, 0.30, 1.13), (0.0, 0.50, 0.0)
LEAN = math.atan2(TOP_L[1] - FOOT_L[1], TOP_L[2] - FOOT_L[2])    # radians

parts = [
    beam("LegL", FOOT_L, TOP_L, 0.075, 0.06, bevel=0.015),
    beam("LegR", FOOT_R, TOP_R, 0.075, 0.06, bevel=0.015),
    beam("LegRear", REAR_FOOT, REAR_TOP, 0.065, 0.055, bevel=0.014),
    # Head block where the three legs meet.
    pk.box("Head", (0.32, 0.075, 0.08), loc=(0.0, 0.3, 1.13), rot=(-math.degrees(LEAN), 0, 0),
           material=wood, bevel=0.014, segments=2),
]
# Low cross bar between the front legs, and a stay back to the rear leg.
low = point_on(FOOT_R, TOP_R, 0.32)
parts.append(pk.box("CrossBar", (low.x * 2 + 0.1, 0.045, 0.05), loc=(0.0, low.y, 0.32),
                    material=wood, bevel=0.01, segments=1))
rear_low = point_on(REAR_FOOT, REAR_TOP, 0.32)
parts.append(beam("Stay", (0.0, low.y + 0.02, 0.32), (0.0, rear_low.y, 0.32), 0.04, 0.035,
                  bevel=0.008, segments=1))
# The ledge: a plank across the front legs. It holds the palette (on two
# arms reaching forward) and, on its right end, the brush cup.
LEDGE_TOP = 0.83
ledge_y = point_on(FOOT_R, TOP_R, LEDGE_TOP).y
parts.append(pk.box("Ledge", (0.78, 0.12, 0.035), loc=(0.11, ledge_y, LEDGE_TOP - 0.0175),
                    material=wood, bevel=0.01, segments=1))
for side in (-1, 1):
    parts.append(pk.box("Arm", (0.05, 0.42, 0.03), loc=(side * 0.13, -0.04, LEDGE_TOP - 0.015),
                        material=wood, bevel=0.009, segments=1))
    # A diagonal brace under each arm, back to the front leg.
    leg_at = point_on(FOOT_R, TOP_R, 0.62)
    parts.append(beam("Brace", (side * 0.13, -0.16, LEDGE_TOP - 0.03),
                      (side * leg_at.x * 0.9, leg_at.y - 0.02, 0.62), 0.035, 0.03,
                      bevel=0.008, segments=1))
# Canvas ledge: a thin bar behind the palette that the canvas stands on.
CANVAS_BOTTOM = 0.935
cl = point_on(FOOT_R, TOP_R, CANVAS_BOTTOM - 0.015)
parts.append(pk.box("CanvasLedge", (0.5, 0.05, 0.03), loc=(0.0, cl.y - 0.035, CANVAS_BOTTOM - 0.015),
                    material=wood, bevel=0.008, segments=1))
# (The canvas clamp at the top is added to `parts` in the canvas section.)

# --- Canvas + plus sign ----------------------------------------------------------
CANVAS_W, CANVAS_H, CANVAS_T = 0.46, 0.235, 0.03
canvas_mid_z = CANVAS_BOTTOM + CANVAS_H * 0.5 * math.cos(LEAN)
leg_mid = point_on(FOOT_R, TOP_R, canvas_mid_z)
# In front of the legs, leaning back with them.
canvas_centre = Vector((0.0, leg_mid.y - 0.03 - CANVAS_T * 0.5 - 0.004, canvas_mid_z))
canvas = pk.box("Canvas", (CANVAS_W, CANVAS_T, CANVAS_H), loc=canvas_centre,
                rot=(-math.degrees(LEAN), 0, 0), material=canvas_mat, bevel=0.008, segments=1,
                parent_obj=root)
front = Vector((0.0, -math.cos(LEAN), math.sin(LEAN)))       # canvas face normal
up = Vector((0.0, math.sin(LEAN), math.cos(LEAN)))            # up the canvas face
# Clamp: a wooden cap over the canvas's top edge, reaching back to the legs,
# the classic easel detail that holds the canvas in place.
canvas_top = canvas_centre + up * (CANVAS_H * 0.5)
parts.append(pk.box("Clamp", (0.3, 0.08, 0.045), loc=canvas_top + up * -0.0025,
                    rot=(-math.degrees(LEAN), 0, 0), material=wood, bevel=0.01, segments=1))
easel = pk.join("Easel", parts)
# join() keeps the first leg's tilted transform; bake it so the mesh is in
# world space (origin back on the floor centre) before touching vertices.
pk.apply(easel, location=True, rotation=True, scale=True)
# Tilted legs poke a few millimetres below the floor: flatten the feet.
for v in easel.data.vertices:
    if v.co.z < 0.0:
        v.co.z = 0.0
pk.parent(easel, root)

ARM, HALF = 0.032, 0.09          # plus: bar half-thickness, half-length
plus_outline = [(ARM, -HALF), (ARM, -ARM), (HALF, -ARM), (HALF, ARM), (ARM, ARM),
                (ARM, HALF), (-ARM, HALF), (-ARM, ARM), (-HALF, ARM), (-HALF, -ARM),
                (-ARM, -ARM), (-ARM, -HALF)]
PLUS_T = 0.014
# Slightly below the middle, clear of the clamp.
plus_centre = canvas_centre + front * (CANVAS_T * 0.5 + PLUS_T * 0.5 - 0.002) + up * -0.012
# prism() extrudes along local Z; rot X = 90 - lean stands it on the canvas face.
plus = pk.prism("PlusSign", plus_outline, PLUS_T, loc=plus_centre,
                rot=(90 - math.degrees(LEAN), 0, 0), material=station_glow, bevel=0.005,
                segments=1, parent_obj=root)

# --- Palette basin ---------------------------------------------------------------
PAL = Vector((0.0, -0.08, 0.0))     # palette centre (x, y)
PAL_A, PAL_B = 0.32, 0.24            # half width, half depth
NOTCH = math.radians(200)            # the kidney's notch, on the left
THUMB = math.radians(158)            # the thumb hole, just behind the notch
PAL_BOTTOM, RIM_TOP, WELL_FLOOR = 0.83, 0.895, 0.862
PAINT_Z = 0.885
PAL_POINTS = 32


def angle_gap(a, b):
    return (a - b + math.pi) % math.tau - math.pi


def outline_radius(theta):
    """Kidney outline: an ellipse with a soft notch pressed into one side."""
    ellipse = PAL_A * PAL_B / math.hypot(PAL_B * math.cos(theta), PAL_A * math.sin(theta))
    return ellipse * (1.0 - 0.26 * math.exp(-(angle_gap(theta, NOTCH) / 0.34) ** 2))


def rim_width(theta):
    """The rim is narrow, but wide around the thumb hole."""
    return 0.03 + 0.105 * math.exp(-(angle_gap(theta, THUMB) / 0.5) ** 2)


# Rings of points from the bottom, up and over the rounded rim, down into the
# well: (radius offset from the outline, height). Negative = inwards.
LOOPS = [
    (lambda r, w: r * 0.93, PAL_BOTTOM),
    (lambda r, w: r, PAL_BOTTOM + 0.015),
    (lambda r, w: r, 0.874),
    (lambda r, w: r - 0.004, 0.889),
    (lambda r, w: r - 0.016, RIM_TOP),
    (lambda r, w: r - w, RIM_TOP),
    (lambda r, w: r - w - 0.012, WELL_FLOOR),
]
bm = bmesh.new()
rings = []
for rule, z in LOOPS:
    ring = []
    for i in range(PAL_POINTS):
        theta = math.tau * i / PAL_POINTS
        radius = rule(outline_radius(theta), rim_width(theta))
        ring.append(bm.verts.new((PAL.x + math.cos(theta) * radius,
                                  PAL.y + math.sin(theta) * radius, z)))
    rings.append(ring)
bm.faces.new(list(reversed(rings[0])))          # underside
for lower, upper in zip(rings, rings[1:]):
    for i in range(PAL_POINTS):
        j = (i + 1) % PAL_POINTS
        bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
bm.faces.new(rings[-1])                         # well floor
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
mesh = bpy.data.meshes.new("Palette")
bm.to_mesh(mesh)
bm.free()
palette = bpy.data.objects.new("Palette", mesh)
pk._collection.objects.link(palette)
mesh.materials.append(ceramic)

# Thumb hole: cut straight down through the wide part of the rim.
thumb_r = outline_radius(THUMB) - 0.016 - (rim_width(THUMB) - 0.016) * 0.5
thumb_at = (PAL.x + math.cos(THUMB) * thumb_r, PAL.y + math.sin(THUMB) * thumb_r, 0.86)
cutter = pk.cyl("ThumbCutter", 0.03, 0.2, loc=thumb_at, verts=12)
cut = palette.modifiers.new("ThumbHole", "BOOLEAN")
cut.operation = "DIFFERENCE"
cut.solver = "EXACT"
cut.object = cutter
pk.select_only(palette)
bpy.ops.object.modifier_apply(modifier=cut.name)
bpy.data.objects.remove(cutter, do_unlink=True)
pk.parent(palette, root)

# --- Basin paint: the glowing surface filling the well ---------------------------
bm = bmesh.new()
edge = []
for i in range(PAL_POINTS):
    theta = math.tau * i / PAL_POINTS
    radius = outline_radius(theta) - rim_width(theta) - 0.002
    edge.append(bm.verts.new((PAL.x + math.cos(theta) * radius,
                              PAL.y + math.sin(theta) * radius, PAINT_Z)))
middle = bm.verts.new((PAL.x, PAL.y, PAINT_Z + 0.004))     # a gentle meniscus
for i in range(PAL_POINTS):
    bm.faces.new((edge[i], edge[(i + 1) % PAL_POINTS], middle))
mesh = bpy.data.meshes.new("BasinPaint")
bm.to_mesh(mesh)
bm.free()
basin_paint = bpy.data.objects.new("BasinPaint", mesh)
pk._collection.objects.link(basin_paint)
mesh.materials.append(station_glow)
pk.set_origin(basin_paint, (PAL.x, PAL.y, PAINT_Z))
pk.parent(basin_paint, root)

# --- Dried paint dabs around the thumb hole -------------------------------------
dabs = []
for k, (offset, dist, mat, size) in enumerate(((-0.42, 0.012, ochre, 0.03),
                                              (0.4, 0.0, lilac, 0.026),
                                              (0.7, 0.03, clay, 0.024))):
    theta = THUMB + offset
    r = outline_radius(theta) - 0.016 - (rim_width(theta) - 0.016) * 0.5 - dist
    dabs.append(pk.sphere("Dab%d" % k, size, loc=(PAL.x + math.cos(theta) * r,
                                                  PAL.y + math.sin(theta) * r, RIM_TOP),
                          scale=(1.0, 0.85, 0.32), material=mat, segments=6, rings=4))
pk.parent(pk.join("PaletteDabs", dabs), root)

# --- Brush cup on the right end of the ledge -------------------------------------
CUP = Vector((0.4, ledge_y, LEDGE_TOP))
cup_parts = [pk.lathe("Cup", [
    (0.0, 0.0), (0.05, 0.0), (0.056, 0.012), (0.056, 0.118), (0.048, 0.12),
    (0.045, 0.03), (0.0, 0.03)], loc=CUP, material=metal, segments=12)]
for k, (tilt, heading, length, tip_mat) in enumerate(((16, 20, 0.22, ochre),
                                                      (10, 150, 0.25, lilac),
                                                      (19, 265, 0.2, clay))):
    # Each brush stands in the cup, leaning out; parts are built upright at
    # the origin, then tilted and moved into place together.
    brush = [
        pk.cyl("Handle", 0.011, length, loc=(0, 0, length * 0.5), material=trim, verts=6),
        pk.cyl("Ferrule", 0.0135, 0.045, loc=(0, 0, length + 0.0225), material=metal, verts=6),
        pk.cyl("Tip", 0.015, 0.05, loc=(0, 0, length + 0.07), radius_top=0.004,
               material=tip_mat, verts=6),
    ]
    b = pk.join("Brush%d" % k, brush)
    pk.set_origin(b, (0.0, 0.0, 0.0))            # pivot at the handle's base
    b.rotation_euler = (math.radians(tilt), 0.0, math.radians(heading))
    b.location = CUP + Vector((0.0, 0.0, 0.035))
    pk.apply(b, location=True, rotation=True, scale=True)
    cup_parts.append(b)
pk.parent(pk.join("BrushCup", cup_parts), root)

# --- Centre the footprint on the origin -------------------------------------------
bpy.context.view_layer.update()
lo = Vector((1e9, 1e9, 1e9))
hi = Vector((-1e9, -1e9, -1e9))
for obj in pk.objects():
    if obj.type == "MESH":
        for v in obj.data.vertices:
            w = obj.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
shift = Vector(((lo.x + hi.x) * -0.5, (lo.y + hi.y) * -0.5, 0.0))
for obj in root.children:
    obj.location += shift
bpy.context.view_layer.update()
print("[station] footprint %.3f x %.3f m, height %.3f m (shifted by %.3f, %.3f)"
      % (hi.x - lo.x, hi.y - lo.y, hi.z, shift.x, shift.y))

pk.smooth_all(35.0)
pk.export("healing_station.glb", budget=2000)
