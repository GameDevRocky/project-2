"""
Sprayer - the pink rapid-fire enemy (Rapid Brush / Thin Paint).

Plan: docs/VISUAL_OVERHAUL_PLAN.md section 4.4.

An aerosol can that learned to run: a tall, slim ceramic spray can wrapped in
two wide pink bands, tipped 8 degrees forward on two thin digitigrade legs,
with a dome cap for a head (one dark visor slit with a glowing line) and a
crown of five metal nozzles fanned out from its chest. The thinnest, spikiest
outline in the game.

Axes: the enemy FACES BLENDER -Y (the exporter turns that into Godot +Z, the
direction enemy.gd turns toward the player). X is the enemy's left, Z is up.
The origin is on the floor, centred under the body (the capsule's base).
Size: 1.60 m tall, 0.62 m wide (fin tip to fin tip) - the r 0.40 / h 1.60
capsule.

Nodes Godot relies on (names must not change):
    Sprayer    root empty at the origin.
    NozzleFan  the hub and all five nozzles as one mesh. Its ORIGIN is the hub
               centre and it has no rotation, so spinning it around its local
               Z axis in Godot (the enemy's forward axis) turns the crown in
               place. Materials PK_Metal + PK_Wet (paint on the tips).
    Leg_L      left leg (+X). ORIGIN at the hip joint, no rotation, so a
               rotation around local X swings it forward/back.
    Leg_R      right leg (-X). Same as Leg_L.

Material roles Godot recolours: PK_Accent (bands), PK_AccentGlow (visor line),
PK_Fill (reservoir paint), PK_Wet (drips, nozzle tips).

Run:  blender -b --factory-startup --python tools/blender/create_sprayer.py
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

COLLECTION = pk.begin("Sprayer", seed=44)

PINK = "#FFB7C5"
body = pk.mat("PK_Body")
trim = pk.mat("PK_Trim")
metal = pk.mat("PK_Metal")
rubber = pk.mat("PK_Rubber")
dark = pk.mat("PK_Dark")
glass = pk.mat("PK_Glass")
accent = pk.mat("PK_Accent", color=PINK)
glow = pk.mat("PK_AccentGlow", color=PINK)
fill = pk.mat("PK_Fill", color=PINK)
wet = pk.mat("PK_Wet", color=PINK)

root = pk.empty("Sprayer")


# ---------------------------------------------------------------------------
# Local helpers (small shapes paintkit does not have)
# ---------------------------------------------------------------------------

def _new_object(name, bm, material):
    mesh = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    COLLECTION.objects.link(obj)
    if material is not None:
        mesh.materials.append(material)
    return obj


def soft(obj, angle=80.0):
    """Mark a low-poly round part (a small ball, a thin rod, a coil) to be
    shaded smooth up to `angle` degrees, so its few sides don't show as
    facets. Everything else keeps the house 35-degree smoothing."""
    obj["soft"] = angle
    return obj


SHADED = set()


def build(name, parts):
    """Bake each part's modifiers and shading (35 degrees, or its soft()
    angle), then join them into one object. Shading is baked per part so
    each keeps its own look after the join."""
    for p in parts:
        pk.select_only(p)
        for mod in list(p.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        pk.smooth(p, p.get("soft", 35.0))
        if "soft" in p:
            del p["soft"]
    obj = pk.join(name, parts)
    SHADED.add(obj.name)
    return obj


def shade_rest():
    """Shade every object build() has not already shaded."""
    for obj in pk.objects():
        if obj.type == "MESH" and obj.name not in SHADED:
            pk.smooth(obj, obj.get("soft", 35.0))
            if "soft" in obj:
                del obj["soft"]


def limb(name, a, b, r0, r1, verts=6, material=None):
    """An open tapered tube from point a to point b. The open ends are hidden
    inside joint balls, so no cap triangles are wasted on them."""
    a, b = Vector(a), Vector(b)
    axis = b - a
    to_world = Matrix.Translation(a) @ axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bm = bmesh.new()
    rings = []
    for r, z in ((r0, 0.0), (r1, axis.length)):
        rings.append([bm.verts.new(to_world @ Vector((r * math.cos(math.tau * i / verts),
                                                         r * math.sin(math.tau * i / verts), z)))
                      for i in range(verts)])
    for i in range(verts):
        j = (i + 1) % verts
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    return soft(_new_object(name, bm, material), 80.0)


def arc_slab(name, r_in, r_out, rows, span_deg, steps, materials, centre_deg=-90.0):
    """A curved strip wrapped around the Z axis (a visor on a round head).
    `rows` are the z heights of the outer face's bands, bottom to top; outer
    band k gets materials[k]. The inside, top, bottom and ends use materials[0]."""
    bm = bmesh.new()
    start = math.radians(centre_deg - span_deg * 0.5)
    step = math.radians(span_deg) / steps
    cols = []
    for s in range(steps + 1):
        a = start + step * s
        c, si = math.cos(a), math.sin(a)
        outer = [bm.verts.new((r_out * c, r_out * si, z)) for z in rows]
        inner = [bm.verts.new((r_in * c, r_in * si, z)) for z in (rows[0], rows[-1])]
        cols.append((outer, inner))
    faces_by_mat = []
    for s in range(steps):
        (o0, i0), (o1, i1) = cols[s], cols[s + 1]
        for k in range(len(rows) - 1):
            faces_by_mat.append((bm.faces.new((o0[k], o1[k], o1[k + 1], o0[k + 1])), k))
        faces_by_mat.append((bm.faces.new((i0[0], i0[1], i1[1], i1[0])), 0))
        faces_by_mat.append((bm.faces.new((o0[-1], o1[-1], i1[1], i0[1])), 0))
        faces_by_mat.append((bm.faces.new((o0[0], i0[0], i1[0], o1[0])), 0))
    for outer, inner in (cols[0], cols[-1]):
        faces_by_mat.append((bm.faces.new(outer + [inner[1], inner[0]]), 0))
    for f, k in faces_by_mat:
        f.material_index = k
    obj = _new_object(name, bm, None)
    for m in materials:
        obj.data.materials.append(m)
    return obj


def paint(obj, material, test):
    """Give the faces whose centre (object space) passes test() a second
    material, so a band or a wet tip costs no extra triangles."""
    names = [m.name for m in obj.data.materials]
    if material.name not in names:
        obj.data.materials.append(material)
        names.append(material.name)
    index = names.index(material.name)
    for poly in obj.data.polygons:
        if test(poly.center):
            poly.material_index = index


def drip(name, top, length, width, material, segments=5):
    """A paint drip: a thin run that swells into a bead at the bottom."""
    w = width * 0.5
    # (radius, height above the bottom tip); starts and ends on the axis.
    profile = [(0.0, 0.0), (w, w * 0.7), (w * 0.62, w * 2.2), (w * 0.48, length * 0.85),
               (0.0, length)]
    return soft(pk.lathe(name, profile, loc=(top[0], top[1], top[2] - length),
                         material=material, segments=segments), 80.0)


# ---------------------------------------------------------------------------
# The can is built upright, then everything on it is tipped 8 degrees forward
# around the can's bottom centre. tilt() bakes that into each part.
# ---------------------------------------------------------------------------

CAN_Y = 0.045            # can axis sits a little back, so the lean stays centred
CAN_Z0 = 0.637           # bottom of the can
CAN_H = 0.70
CAN_R = 0.20
TILT_DEG = 8.0
PIVOT = Vector((0.0, CAN_Y, CAN_Z0))
TILT = (Matrix.Translation(PIVOT) @ Matrix.Rotation(math.radians(TILT_DEG), 4, "X")
        @ Matrix.Translation(-PIVOT))


def on_can(x, y, z):
    """A point given relative to the upright can (x, y from its axis, z up
    from its bottom) -> its world position after the forward lean."""
    return TILT @ Vector((x, CAN_Y + y, CAN_Z0 + z))


def tilt(obj):
    bpy.context.view_layer.update()
    obj.matrix_world = TILT @ obj.matrix_world
    pk.apply(obj, location=False, rotation=True, scale=True)
    return obj


can_parts = []

# --- Can body: ceramic white, rounded bottom and shoulder -------------------
# The two wide pink bands are painted onto the can's own faces (flush), so they
# cost only the four extra rings that mark their edges.
BANDS = ((0.07, 0.205), (0.265, 0.385))
can = pk.lathe("Can", [
    (0.000, 0.000), (0.165, 0.000), (CAN_R, 0.045),
    (CAN_R, BANDS[0][0]), (CAN_R, BANDS[0][1]), (CAN_R, BANDS[1][0]), (CAN_R, BANDS[1][1]),
    (CAN_R, 0.560), (0.186, 0.622), (0.152, 0.668), (0.110, 0.695)],
    loc=(0, CAN_Y, CAN_Z0), material=body, segments=14)
paint(can, accent, lambda c: any(z0 < c.z < z1 for z0, z1 in BANDS) and c.xy.length > CAN_R * 0.9)
can_parts.append(can)

# Neck collar under the cap.
can_parts.append(pk.lathe("Neck", [
    (0.112, 0.690), (0.143, 0.702), (0.143, 0.732)],
    loc=(0, CAN_Y, CAN_Z0), material=trim, segments=14))

# Reservoir bulb on the back: a metal neck, a glass bulb, glowing paint inside.
BULB_Z = 0.30
BULB_R = 0.068
can_parts.append(soft(pk.cyl("BulbNeck", 0.03, 0.05, loc=(0, CAN_Y + CAN_R + 0.015, CAN_Z0 + BULB_Z),
                             rot=(90, 0, 0), material=metal, verts=6), 65))
bulb_centre = (0, CAN_Y + CAN_R + 0.03 + BULB_R, CAN_Z0 + BULB_Z)
can_parts.append(soft(pk.sphere("BulbGlass", BULB_R, loc=bulb_centre, material=glass,
                                segments=10, rings=5), 50))
can_parts.append(soft(pk.sphere("BulbFill", BULB_R * 0.78, loc=bulb_centre, material=fill,
                                segments=8, rings=4), 60))

# Two stubby fins low on the flanks, swept down and back like a toy rocket.
# prism() rot (90, 0, 0) lays the (x, z) outline upright with thickness in Y.
for side in (1, -1):
    outline = [(0.17, 0.30), (0.17, 0.05), (0.33, -0.05), (0.33, 0.07)]
    if side < 0:
        outline = [(-x, z) for x, z in reversed(outline)]
    fin = pk.prism("Fin_%s" % ("L" if side > 0 else "R"), outline, 0.036,
                   loc=(0, CAN_Y + 0.02, CAN_Z0), rot=(90, 0, side * 22), material=trim,
                   bevel=0.012, segments=1)
    can_parts.append(fin)

# --- Head: a dome cap with one visor slit -------------------------------------
HEAD_Z = 0.70            # cap base, relative to the can bottom
head = pk.lathe("Cap", [
    (0.136, 0.020), (0.157, 0.044), (0.157, 0.145), (0.136, 0.214), (0.080, 0.258),
    (0.000, 0.272)],
    loc=(0, CAN_Y, CAN_Z0 + HEAD_Z), material=body, segments=14)
can_parts.append(soft(head, 45))
visor = arc_slab("Visor", 0.140, 0.166, [0.078, 0.101, 0.121, 0.144], 116, 6,
                 [dark, glow, dark])
visor.location = (0, CAN_Y, CAN_Z0 + HEAD_Z)
can_parts.append(visor)

# Mount the nozzle fan sits on (static; the fan itself spins in front of it).
FAN_Z = 0.52             # height of the fan hub on the can
can_parts.append(soft(pk.cyl("FanMount", 0.05, 0.05, loc=(0, CAN_Y - CAN_R + 0.005, CAN_Z0 + FAN_Z),
                             rot=(90, 0, 0), material=trim, verts=8), 50))

# Wet pink drips running down the can under the fan.
drips = []
for i, (ang, z_top, length) in enumerate(((-90 - 30, FAN_Z - 0.035, 0.105),
                                          (-90 + 4, FAN_Z - 0.07, 0.085),
                                          (-90 + 29, FAN_Z - 0.045, 0.075))):
    a = math.radians(ang)
    r = CAN_R + 0.004
    drips.append(drip("Drip%d" % i, (r * math.cos(a), CAN_Y + r * math.sin(a), CAN_Z0 + z_top),
                      length, 0.034, wet))
drip_obj = build("Drips", drips)
can_parts.append(drip_obj)

for p in can_parts:
    tilt(p)

body_obj = build("Body", [p for p in can_parts if p is not drip_obj])
pk.apply(body_obj, location=False, rotation=True, scale=True)
pk.parent(body_obj, root)
pk.parent(drip_obj, root)

# --- NozzleFan: hub + a crown of five nozzles, spinning on the forward axis ---
# Built level (not leaning), so its axis is exactly the enemy's forward axis.
mount_front = on_can(0, -CAN_R, FAN_Z)
HUB_BACK_Y = mount_front.y - 0.02
HUB_LEN = 0.08
hub_centre = Vector((0.0, HUB_BACK_Y - HUB_LEN * 0.5, mount_front.z))
FORWARD = Vector((0, -1, 0))

# lathe() spins around local Z; rot (90, 0, 0) turns local Z to face -Y.
hub = pk.lathe("Hub", [
    (0.000, 0.000), (0.060, 0.000), (0.074, 0.015), (0.074, 0.050), (0.056, 0.072),
    (0.000, HUB_LEN + 0.004)],
    loc=(0, HUB_BACK_Y, hub_centre.z), rot=(90, 0, 0), material=trim, segments=10)
fan_parts = [soft(hub, 40)]

SPLAY = math.radians(40)   # how far each nozzle leans out from the axis
NOZZLE_LEN = 0.165
for k in range(5):
    phi = math.radians(90 + 72 * k)          # first nozzle points straight up
    radial = Vector((math.cos(phi), 0.0, math.sin(phi)))
    direction = (FORWARD * math.cos(SPLAY) + radial * math.sin(SPLAY)).normalized()
    base = hub_centre + FORWARD * 0.012 + radial * 0.03
    nozzle = pk.lathe("Nozzle%d" % k, [
        (0.022, 0.000), (0.022, NOZZLE_LEN - 0.05), (0.033, NOZZLE_LEN - 0.038),
        (0.033, NOZZLE_LEN), (0.000, NOZZLE_LEN)],
        material=metal, segments=6)
    soft(nozzle, 65)
    # Paint coats the flared tip of each nozzle.
    paint(nozzle, wet, lambda c: c.z > NOZZLE_LEN - 0.045)
    nozzle.matrix_world = (Matrix.Translation(base)
                           @ Vector((0, 0, 1)).rotation_difference(direction).to_matrix().to_4x4())
    fan_parts.append(nozzle)

fan = build("NozzleFan", fan_parts)
pk.apply(fan, location=False, rotation=True, scale=True)
pk.set_origin(fan, hub_centre)
pk.parent(fan, root)

# --- Legs: thin digitigrade legs (thigh, shin, long foot bone) ----------------
# Joint positions for the LEFT leg (+X); the right leg mirrors x.
HIP = Vector((0.105, 0.04, 0.68))
KNEE = Vector((0.125, -0.085, 0.46))
HOCK = Vector((0.12, 0.09, 0.195))
ANKLE = Vector((0.115, -0.005, 0.058))

for side, suffix in ((1, "L"), (-1, "R")):
    def m(v):
        return Vector((v.x * side, v.y, v.z))
    parts = [
        limb("Thigh", m(HIP), m(KNEE), 0.048, 0.036, verts=6, material=trim),
        soft(pk.sphere("Knee", 0.05, loc=m(KNEE), material=metal, segments=7, rings=4)),
        limb("Shin", m(KNEE), m(HOCK), 0.034, 0.029, verts=6, material=trim),
        soft(pk.sphere("Hock", 0.044, loc=m(HOCK), material=metal, segments=7, rings=4)),
        limb("Foot", m(HOCK), m(ANKLE), 0.03, 0.027, verts=6, material=trim),
        pk.box("Toe", (0.095, 0.19, 0.06), loc=(ANKLE.x * side, ANKLE.y - 0.05, 0.03),
               material=rubber, bevel=0.018, segments=1),
    ]
    leg = build("Leg_" + suffix, parts)
    pk.apply(leg, location=False, rotation=True, scale=True)
    pk.set_origin(leg, m(HIP))
    pk.parent(leg, root)

shade_rest()

# Report the finished size, so it can be checked against the capsule.
bpy.context.view_layer.update()
lo = Vector((1e9, 1e9, 1e9))
hi = Vector((-1e9, -1e9, -1e9))
for obj in pk.objects():
    if obj.type == "MESH":
        for v in obj.data.vertices:
            w = obj.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
print("[sprayer] bounds x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % (lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
for obj in pk.objects():
    if obj.name in ("Sprayer", "NozzleFan", "Leg_L", "Leg_R"):
        print("[sprayer] node %-10s parent=%-8s loc=(%.3f, %.3f, %.3f) rot=(%.1f, %.1f, %.1f) scale=(%.2f, %.2f, %.2f)" % (
            obj.name, obj.parent.name if obj.parent else "-", *obj.location,
            *(math.degrees(a) for a in obj.rotation_euler), *obj.scale))

pk.export("enemy_sprayer.glb", budget=1500)
