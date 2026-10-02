"""
Back Bling - eleven alternative back cosmetics for the Canvas Runner.

Each one replaces the default Chromatic Reservoir on the runner's back, and
each has its own silhouette so it reads from 20 m behind:

    Back_MINI_TANK    two short fat glass paint canisters joined by an arched
                      pipe, on a small harness plate
    Back_ORB_PACK     one big glass sphere of paint in a three-ring metal cage
    Back_PAINT_CAN    a huge open paint bucket, wire handle laid back, paint
                      running over the rim, two brushes standing in the paint
    Back_WING_PACK    two wings of fanned paintbrushes, paint-loaded bristles
                      outward, just under 1 m tip to tip
    Back_JET_PACK     twin upside-down spray cans with thruster nozzle caps and
                      paint-drip "flames" underneath
    Back_BUBBLE_PACK  seven glossy paint bubbles rising past a bubble-wand ring
    Back_PIXEL_PACK   a stepped voxel backpack with a pixel-art paint drop
    Back_SPLASH_PACK  a frozen crown splash with droplets flying off the points
    Back_STAR_PACK    a big star-shaped wooden palette, a paint dollop per point
    Back_EASEL_PACK   a folded artist's easel strapped on at an angle, with a
                      small painted canvas on its ledge
    Back_ROLLER_RIG   two paint rollers crossed like swords, dripping paint

Axes: Blender Z is up and the runner faces Blender -Y, so its BACK faces +Y
and its right side is -X. Every item is modelled in place on the runner, and
its ORIGIN sits exactly on the runner's Socket_Back empty, Blender
(0, 0.102, 1.120). The dresser (scripts/visual/runner_dresser.gd) copies the
one node it needs, hangs it on Socket_Back and zeroes its transform, so the
pack lands where it was built. All eleven overlap in this file - intended.

Nodes Godot relies on (names must not change):
    BackBling          root empty (world origin)
    Back_<NAME>        one joined mesh per item, origin at Socket_Back

Material roles: PK_Fill is the paint in every item (Godot repaints it in the
wearer's team colour, emissive). PK_Team marks at most one small band/knob
per item. PK_Glass for glass shells (always over an opaque PK_Fill). Every
other part uses a named neutral variant (PK_BB_*), so it keeps its colour.

Run:  blender -b --factory-startup --python tools/blender/create_cosmetic_backbling.py
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

SOCKET = Vector((0.0, 0.102, 1.120))   # canvas_runner.glb's Socket_Back
LEAN = 7.0                             # the runner's upper body leans forward
LEAN_M = Matrix.Rotation(math.radians(LEAN), 4, "X")   # top tips toward -Y

pk.begin("BackBling", seed=17)

# --- Materials ---------------------------------------------------------------
FILL = pk.mat("PK_Fill")
TEAM = pk.mat("PK_Team")
GLASS = pk.mat("PK_Glass")
TIN = pk.mat("PK_Metal", name="PK_BB_Tin", color="#C3BED2")
STEEL = pk.mat("PK_Metal", name="PK_BB_Steel", color="#8F8BA6")
FRAME = pk.mat("PK_Trim", name="PK_BB_Frame", color="#3D4057")
STRAP = pk.mat("PK_Rubber", name="PK_BB_Strap", color="#2D2F3F")
CREAM = pk.mat("PK_Body", name="PK_BB_Cream", color="#EEE6D8")
WOOD = pk.mat("PK_Wood", name="PK_BB_Wood", color="#B98457")
WALNUT = pk.mat("PK_Wood", name="PK_BB_Walnut", color="#8A5E40")
LILAC = pk.mat("PK_Body", name="PK_BB_Lilac", color="#A898D6")
PLUM = pk.mat("PK_Body", name="PK_BB_Plum", color="#7A6AAE")
BUTTER = pk.mat("PK_Body", name="PK_BB_Butter", color="#F0D47F")
CANVAS = pk.mat("PK_Canvas", name="PK_BB_Canvas", color="#F1EADB")
SHINE = pk.mat("PK_Body", name="PK_BB_Shine", color="#FBF6EC", roughness=0.2)

root = pk.empty("BackBling")

# Parts of the item being built: (object, smoothing angle). Low-poly round
# parts get a big angle so they shade smooth; boxy parts keep crisp edges.
_parts = []


# ---------------------------------------------------------------------------
# Helpers. Everything is built around (0, 0, 0) = the socket; finish() moves
# the joined item onto the socket at the end.
# ---------------------------------------------------------------------------

def add(obj, angle=35.0):
    _parts.append((obj, angle))
    return obj


def basis(z_dir, x_hint=(1, 0, 0)):
    """4x4 rotation turning local +Z toward z_dir, local +X toward x_hint."""
    z = Vector(z_dir).normalized()
    x = Vector(x_hint) - z * Vector(x_hint).dot(z)
    if x.length < 1e-6:
        x = Vector((0, 1, 0)) - z * z.y
    x.normalize()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed().to_4x4()


def place(obj, origin=(0, 0, 0), z_dir=(0, 0, 1), x_hint=(1, 0, 0)):
    """Stand a part built around the world origin (axis +Z) at `origin`,
    pointing along `z_dir`."""
    bpy.context.view_layer.update()
    obj.matrix_world = Matrix.Translation(Vector(origin)) @ basis(z_dir, x_hint) @ obj.matrix_world
    return obj


def transform(obj, matrix):
    bpy.context.view_layer.update()
    obj.matrix_world = matrix @ obj.matrix_world
    return obj


def lean(obj):
    """Tip a part with the runner's 7-degree forward lean, about the socket."""
    return transform(obj, LEAN_M)


def rod(name, p0, p1, r0, r1=None, material=None, verts=8, x_hint=(1, 0, 0)):
    """A cylinder (or taper) from p0 to p1."""
    p0, p1 = Vector(p0), Vector(p1)
    length = (p1 - p0).length
    obj = pk.cyl(name, r0, length, loc=(0, 0, length * 0.5), material=material, verts=verts,
                 radius_top=r1)
    return place(obj, p0, p1 - p0, x_hint)


def beam(name, p0, p1, w, d, material, bevel=0.0, x_hint=(1, 0, 0)):
    """A box from p0 to p1, w wide (along x_hint) and d deep."""
    p0, p1 = Vector(p0), Vector(p1)
    length = (p1 - p0).length
    obj = pk.box(name, (w, d, length), loc=(0, 0, length * 0.5), material=material,
                 bevel=bevel, segments=1)
    return place(obj, p0, p1 - p0, x_hint)


def spun(name, profile, origin, z_dir=(0, 0, 1), material=None, segments=12, x_hint=(1, 0, 0),
         scale=None):
    """Lathe a (radius, distance) profile around the line from `origin` along
    `z_dir`. `scale` squashes it first (flat brush tufts, splash blobs)."""
    obj = pk.lathe(name, profile, material=material, segments=segments)
    if scale is not None:
        obj.scale = scale
        pk.apply(obj, location=False, rotation=False, scale=True)
    return place(obj, origin, z_dir, x_hint)


def ball(name, r, loc, material, segments=10, rings=6, scale=(1, 1, 1), z_dir=(0, 0, 1),
         x_hint=(1, 0, 0)):
    obj = pk.sphere(name, r, scale=scale, material=material, segments=segments, rings=rings)
    return place(obj, loc, z_dir, x_hint)


def drip(name, top, length, r, material=None, segments=6, direction=(0, 0, -1), squash=1.0,
         x_hint=(1, 0, 0)):
    """A hanging paint drip: thin neck at `top`, round bead `length` below."""
    profile = [(0.0, -r * 0.25), (r * 0.8, 0.0), (r * 0.6, length * 0.5),
               (r * 0.95, length - r * 1.05), (r * 0.85, length - r * 0.35), (0.0, length)]
    return spun(name, profile, top, direction, material or FILL, segments, x_hint,
                scale=(1.0, squash, 1.0) if squash != 1.0 else None)


def rounded_rect(hx, hy, r, per_corner=2):
    pts = []
    for cx, cy, start in ((hx - r, hy - r, 0), (-hx + r, hy - r, 90),
                          (-hx + r, -hy + r, 180), (hx - r, -hy + r, 270)):
        for i in range(per_corner + 1):
            a = math.radians(start + 90 * i / per_corner)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def flat(name, outline, depth, centre, material, bevel=0.0, segments=1):
    """Extrude an (x, z) outline `depth` thick along Y, centred on `centre`."""
    obj = pk.prism(name, outline, depth, rot=(90, 0, 0), material=material, bevel=bevel,
                   segments=segments)
    obj.location = centre
    return obj


def plate(w, h, t=0.03, z=0.0, x=0.0, material=None, radius=None, sink=0.015, per_corner=1):
    """The harness plate that rests on the runner's back: a rounded slab whose
    front face sits `sink` into the torso, tipped with the torso's lean."""
    r = radius if radius is not None else min(w, h) * 0.3
    obj = flat("Plate", rounded_rect(w * 0.5, h * 0.5, r, per_corner), t,
               (x, t * 0.5 - sink, z), material or FRAME)
    return add(lean(obj))


def thick_line(points, width):
    """Outline of a flat strip of `width` following a 2D polyline (mitred)."""
    pts = [Vector(p) for p in points]
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


def finish(name, cutters=()):
    """Bake every part, smooth it, join into ONE mesh named `name`, and move
    it onto the socket with its origin exactly there."""
    objs = []
    for obj, angle in _parts:
        pk.select_only(obj)
        for mod in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        pk.apply(obj, location=True, rotation=True, scale=True)
        pk.smooth(obj, angle)
        objs.append(obj)
    _parts.clear()
    for c in cutters:
        bpy.data.objects.remove(c, do_unlink=True)
    item = pk.join(name, objs) if len(objs) > 1 else objs[0]
    item.name = name
    item.data.name = name
    pk.apply(item, location=True, rotation=True, scale=True)
    # The mesh was modelled around (0, 0, 0) = the socket. Moving the object
    # (not the mesh) puts it on the runner with its origin on Socket_Back.
    item.location = SOCKET
    pk.parent(item, root)
    return item


# ---------------------------------------------------------------------------
# MINI_TANK: two short, fat glass canisters on a small harness
# ---------------------------------------------------------------------------

def mini_tank():
    plate(0.36, 0.28, t=0.032, z=-0.005, per_corner=1)
    seg = 10
    cy, cz = 0.128, 0.0
    for s in (1, -1):
        c = Vector((s * 0.118, cy, cz))
        add(spun("Glass", [(0.08, -0.104), (0.094, -0.088), (0.1, 0.0), (0.094, 0.088),
                           (0.08, 0.104)], c, material=GLASS, segments=seg), 50)
        # Paint fills the canister to ~85%.
        add(rod("Paint", c + Vector((0, 0, -0.09)), c + Vector((0, 0, 0.065)), 0.086,
                material=FILL, verts=seg), 50)
        cap = [(0.0, 0.084), (0.101, 0.084), (0.104, 0.106), (0.078, 0.14), (0.0, 0.154)]
        for sign in (1, -1):
            add(spun("Cap", [(r, z * sign) for r, z in cap], c, material=TIN, segments=seg), 50)
        add(spun("Band", [(0.092, -0.024), (0.1, -0.018), (0.1, 0.018), (0.092, 0.024)],
                 c, material=STRAP, segments=seg), 50)
        add(pk.box("Arm", (0.06, 0.05, 0.048), loc=(s * 0.11, 0.03, cz), material=STRAP))
    # Arched pipe joining the two caps, with a team-colour valve knob on top.
    add(pk.tube("Bridge", [(0.118, cy, 0.13), (0.11, cy, 0.19), (0.0, cy, 0.212),
                           (-0.11, cy, 0.19), (-0.118, cy, 0.13)],
                0.018, material=STEEL, resolution=1, path_resolution=2), 60)
    add(rod("Valve", (0, cy - 0.032, 0.212), (0, cy + 0.032, 0.212), 0.03, material=TEAM,
            verts=10), 50)
    return finish("Back_MINI_TANK")


# ---------------------------------------------------------------------------
# ORB_PACK: a big glass sphere of paint held in a metal cage
# ---------------------------------------------------------------------------

def orb_pack():
    R = 0.15
    c = Vector((0.0, 0.18, 0.0))
    plate(0.22, 0.3, t=0.032, z=-0.01, per_corner=1)
    add(pk.box("Neck", (0.11, 0.07, 0.12), loc=(0, 0.035, 0.0), material=FRAME, bevel=0.012,
               segments=1))
    add(ball("Orb", R, c, GLASS, segments=12, rings=8), 50)
    # Paint: the sphere filled to just above its equator, flat surface on top.
    r_in, level = R - 0.012, 0.04
    prof = [(0.0, -r_in)]
    for a in (-60, -30, 0):
        prof.append((r_in * math.cos(math.radians(a)), r_in * math.sin(math.radians(a))))
    prof += [(math.sqrt(r_in ** 2 - level ** 2), level), (0.0, level)]
    add(spun("Paint", prof, c, material=FILL, segments=12), 50)
    ring_r = R + 0.011
    add(pk.torus("RingBack", ring_r, 0.012, loc=c, rot=(90, 0, 0), material=STEEL,
                 segments=14, ring_segments=4), 60)
    add(pk.torus("RingSide", ring_r, 0.012, loc=c, rot=(0, 90, 0), material=STEEL,
                 segments=14, ring_segments=4), 60)
    add(pk.torus("RingEquator", ring_r + 0.004, 0.013, loc=c, material=STEEL,
                 segments=14, ring_segments=4), 60)
    # Filler valve on top (team knob) and a cradle cup underneath.
    add(spun("TopCap", [(0.0, R - 0.01), (0.05, R - 0.01), (0.052, R + 0.02), (0.0, R + 0.026)],
             c, material=FRAME, segments=10), 50)
    add(ball("Knob", 0.026, c + Vector((0, 0, R + 0.04)), TEAM, segments=8, rings=4), 80)
    add(spun("Cradle", [(0.0, -R - 0.034), (0.06, -R - 0.034), (0.085, -R + 0.02),
                        (0.07, -R + 0.03)], c, material=FRAME, segments=10), 50)
    return finish("Back_ORB_PACK")


# ---------------------------------------------------------------------------
# PAINT_CAN: a huge open bucket, wire handle, paint over the rim, two brushes
# ---------------------------------------------------------------------------

def bucket_radius(z):
    """Outer wall radius at height z (the bucket flares slightly upward)."""
    return 0.136 + (z + 0.228) / 0.278 * 0.016


def overflow_collar(name, centre, rings, bottom, columns, material):
    """Paint welling over a bucket's rim: a ring of `columns` columns through
    the (radius, z) `rings`, ending in a wavy lower edge bottom(angle) ->
    (radius, z). Faces are wound to point outward."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    grid = []
    for j in range(columns):
        a = math.tau * j / columns
        col = [(r, z) for r, z in rings] + [bottom(a)]
        grid.append([bm.verts.new((centre.x + r * math.cos(a), centre.y + r * math.sin(a), z))
                     for r, z in col])
    for j in range(columns):
        jn = (j + 1) % columns
        for k in range(len(grid[j]) - 1):
            bm.faces.new((grid[j][k], grid[j][k + 1], grid[jn][k + 1], grid[jn][k]))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.view_layer.active_layer_collection.collection.objects.link(obj)
    mesh.materials.append(material)
    return obj


def paint_can():
    ax = Vector((0.0, 0.168, 0.0))       # bucket axis; z is absolute below
    seg = 12
    plate(0.24, 0.26, t=0.05, z=-0.09)
    add(spun("Bucket", [(0.0, -0.24), (0.124, -0.24), (0.136, -0.228), (0.152, 0.05),
                        (0.141, 0.05), (0.139, 0.02)], ax, material=TIN, segments=seg), 40)
    # Paint surface, domed a little in the middle.
    add(spun("Paint", [(0.0, 0.052), (0.08, 0.046), (0.142, 0.036)], ax, material=FILL,
             segments=seg), 50)
    # One wide rubber band ties the bucket to the harness plate.
    zb = -0.1
    rb = bucket_radius(zb)
    add(spun("Band", [(rb - 0.003, zb - 0.028), (rb + 0.008, zb - 0.022), (rb + 0.008, zb + 0.022),
                      (rb - 0.003, zb + 0.028)], ax, material=STRAP, segments=seg), 50)
    # The bucket is brim-full: paint wells over the whole rim and runs down
    # the outside in a wavy edge, with three long runs (back and sides).
    runs = ((95, 0.075), (35, 0.045), (150, 0.055), (250, 0.03), (300, 0.035))

    def lower_edge(a):
        deg = math.degrees(a)
        drop = 0.012 * (1 + math.sin(a * 5.0))
        for at, extra in runs:
            d = (deg - at + 180) % 360 - 180
            drop += extra * max(0.0, 1.0 - (d / 16.0) ** 2)
        z = 0.022 - drop
        return (bucket_radius(z) + 0.004, z)

    add(overflow_collar("Overflow", ax, [(0.128, 0.043), (0.152, 0.07), (0.163, 0.054)],
                        lower_edge, 26, FILL), 60)
    for i, (deg, length, r) in enumerate(((95, 0.1, 0.022), (150, 0.06, 0.019),
                                          (35, 0.05, 0.018))):
        a = math.radians(deg)
        out = Vector((math.cos(a), math.sin(a), 0.0))
        rr, z = lower_edge(a)
        top = ax + out * (rr - 0.006) + Vector((0, 0, z + 0.012))
        add(drip("Drip%d" % i, top, length, r, squash=0.8,
                 x_hint=out.cross(Vector((0, 0, 1)))), 80)
    # Wire handle: hinged at the sides, laid back over the rear of the bucket.
    tilt = math.radians(58)
    pts = []
    for i in range(7):
        t = math.pi * i / 6
        pts.append(ax + Vector((0.172 * math.cos(t), 0.172 * math.sin(t) * math.sin(tilt),
                                0.012 + 0.172 * math.sin(t) * math.cos(tilt))))
    add(pk.tube("Handle", [tuple(p) for p in pts], 0.0085, material=STEEL, resolution=0,
                path_resolution=1), 80)
    mid = pts[3]
    add(rod("Grip", mid - Vector((0.05, 0, 0)), mid + Vector((0.05, 0, 0)), 0.018,
            material=WOOD, verts=8), 50)
    for s in (1, -1):
        add(pk.box("Lug", (0.02, 0.04, 0.04), loc=ax + Vector((s * 0.16, 0, 0.012)),
                   material=FRAME))
    # Two brushes standing in the paint (bristles under it), splayed outward.
    for name, base, direction, length, hmat, flatness in (
            ("BrushA", (0.035, 0.165, 0.0), (0.75, 0.05, 1.0), 0.2, WOOD, 0.55),
            ("BrushB", (-0.045, 0.19, 0.0), (-0.6, 0.3, 1.0), 0.17, BUTTER, 1.0)):
        base = Vector(base)
        d = Vector(direction).normalized()
        side = d.cross(Vector((0, 1, 0))).normalized()
        f1 = base + d * 0.11
        add(spun(name + "Ferrule", [(0.024, 0.0), (0.026, 0.09), (0.017, 0.115)], base, d,
                 material=TIN, segments=8, x_hint=side, scale=(1.0, flatness, 1.0)), 50)
        add(rod(name + "Handle", f1, f1 + d * length, 0.016, 0.012, material=hmat, verts=8), 50)
        add(ball(name + "End", 0.018, f1 + d * (length + 0.004), hmat, segments=6, rings=4), 80)
    return finish("Back_PAINT_CAN")


# ---------------------------------------------------------------------------
# WING_PACK: two wings of fanned paintbrushes
# ---------------------------------------------------------------------------

def wing_pack():
    plate(0.15, 0.26, t=0.034, z=-0.01)
    # A slim ceramic spine, topped by a cross bar across the shoulder blades
    # whose rounded ends are the wing roots.
    add(spun("Spine", [(0.0, -0.02), (0.03, -0.012), (0.04, 0.02), (0.04, 0.19), (0.0, 0.2)],
             (0, 0.03, -0.13), material=CREAM, segments=8), 60)
    add(spun("Shoulders", [(0.0, -0.13), (0.03, -0.122), (0.044, -0.1), (0.044, 0.1),
                           (0.03, 0.122), (0.0, 0.13)], (0, 0.05, 0.07), (1, 0, 0),
             material=CREAM, segments=8, x_hint=(0, 1, 0)), 60)
    sweep = math.radians(24)
    # (angle above horizontal, length): long primaries on top sweeping up and
    # out, shorter ones underneath, like a bird's wing seen from behind.
    feathers = ((62, 0.34), (44, 0.42), (26, 0.465), (8, 0.445), (-10, 0.39))
    for s in (1, -1):
        pivot = Vector((s * 0.09, 0.06, 0.07))
        plane_n = Vector((math.sin(sweep) * s, -math.cos(sweep), 0)).normalized()
        for k, (deg, length) in enumerate(feathers):
            a = math.radians(deg)
            d = Vector((s * math.cos(a) * math.cos(sweep), math.cos(a) * math.sin(sweep),
                        math.sin(a))).normalized()
            width_dir = plane_n.cross(d).normalized()
            ferrule_at = pivot + d * (length - 0.17)
            add(rod("Handle", pivot, ferrule_at, 0.012, 0.016,
                    material=WOOD if k % 2 else WALNUT, verts=6), 60)
            add(spun("Ferrule", [(0.017, -0.004), (0.021, 0.045)], ferrule_at, d, material=TIN,
                     segments=6, x_hint=width_dir, scale=(1.6, 0.75, 1.0)), 60)
            # Paint-loaded bristles: a broad, flat, round-tipped tuft lying in
            # the wing plane, so neighbouring tufts read as one feathered edge.
            add(spun("Tuft", [(0.019, 0.04), (0.027, 0.09), (0.021, 0.15), (0.0, 0.172)],
                     ferrule_at, d, material=FILL, segments=8, x_hint=width_dir,
                     scale=(1.95, 0.55, 1.0)), 80)
    return finish("Back_WING_PACK")


# ---------------------------------------------------------------------------
# JET_PACK: twin spray-can thrusters with paint-drip flames
# ---------------------------------------------------------------------------

def jet_pack():
    # Central core block rests on the back (front face sunk 1.5 cm).
    add(lean(pk.box("Core", (0.11, 0.075, 0.3), loc=(0, 0.0225, 0.01), material=CREAM,
                    bevel=0.02, segments=1)))
    add(lean(pk.box("CoreStripe", (0.114, 0.079, 0.04), loc=(0, 0.0225, 0.08), material=TEAM)))
    seg = 10
    cy = 0.13
    for s in (1, -1):
        c = Vector((s * 0.105, cy, 0.0))
        # An upside-down spray can: rolled rim at the top, shoulder dome and
        # valve at the bottom.
        add(spun("Can", [(0.0, 0.2), (0.052, 0.2), (0.062, 0.214), (0.069, 0.198),
                         (0.069, -0.09), (0.058, -0.128), (0.03, -0.148), (0.0, -0.152)],
                 c, material=BUTTER, segments=seg), 40)
        add(spun("Label", [(0.068, -0.02), (0.075, 0.04), (0.068, 0.1)],
                 c, material=LILAC, segments=seg), 40)
        # Nozzle cap: a flared thruster bell on the valve.
        add(spun("Bell", [(0.026, 0.0), (0.052, 0.058), (0.043, 0.064)],
                 c + Vector((0, 0, -0.145)), (0, 0, -1), material=FRAME, segments=seg), 50)
        # Paint flame: a lumpy drip falling from the bell, plus a falling bead.
        add(spun("Flame", [(0.045, -0.004), (0.053, 0.035), (0.036, 0.085), (0.043, 0.125),
                           (0.03, 0.17), (0.025, 0.2), (0.0, 0.222)],
                 c + Vector((0, 0, -0.2)), (0, 0, -1), material=FILL, segments=8), 70)
        add(ball("Bead", 0.022, c + Vector((s * 0.012, 0, -0.455)), FILL, segments=6, rings=4,
                 scale=(1, 1, 1.3)), 80)
        # Tail fin on the outside of each can.
        add(flat("Fin", [(0.0, 0.0), (0.075, -0.06), (0.075, -0.14), (0.0, -0.09)], 0.022,
                 (0, 0, 0), FRAME, bevel=0.006))
        fin = _parts[-1][0]
        fin.location = (s * 0.165, cy, 0.02)
        if s < 0:
            fin.rotation_euler = (math.radians(90), 0, math.radians(180))
        # Cross braces from the core to the can.
        add(pk.box("Brace", (0.06, 0.06, 0.03), loc=(s * 0.055, 0.075, 0.13), material=FRAME))
        add(pk.box("Brace", (0.06, 0.06, 0.03), loc=(s * 0.055, 0.08, -0.09), material=FRAME))
    return finish("Back_JET_PACK")


# ---------------------------------------------------------------------------
# BUBBLE_PACK: glossy paint bubbles caught in a bubble-wand ring
# ---------------------------------------------------------------------------

def bubble_pack():
    plate(0.17, 0.2, t=0.032, z=-0.1, x=-0.02, material=FRAME)
    bubbles = ((-0.055, 0.15, -0.12, 0.13), (0.115, 0.13, -0.17, 0.085),
               (0.1, 0.16, 0.0, 0.095), (-0.175, 0.12, -0.24, 0.055),
               (0.2, 0.17, 0.12, 0.062), (-0.06, 0.2, 0.05, 0.05),
               (0.215, 0.2, 0.22, 0.038))
    for i, (x, y, z, r) in enumerate(bubbles):
        add(pk.ico("Bubble%d" % i, r, loc=(x, y, z), material=FILL, subdiv=2), 80)
    # Wand ring around the big bubble (facing back) and its little handle.
    bx, by, bz, br = bubbles[0]
    ring_y = by + 0.055
    ring_r = math.sqrt(br ** 2 - 0.055 ** 2) + 0.004
    add(pk.torus("Wand", ring_r, 0.013, loc=(bx, ring_y, bz), rot=(90, 0, 0), material=STEEL,
                 segments=18, ring_segments=4), 60)
    a = math.radians(-115)
    w0 = Vector((bx + math.cos(a) * ring_r, ring_y, bz + math.sin(a) * ring_r))
    stick = Vector((-0.05, -0.02, -0.1))
    add(rod("WandStick", w0, w0 + stick, 0.012, material=STEEL, verts=6), 60)
    add(ball("WandEnd", 0.02, w0 + stick * 1.05, STRAP, segments=8, rings=4,
             scale=(1, 1, 1.3), z_dir=stick), 80)
    return finish("Back_BUBBLE_PACK")


# ---------------------------------------------------------------------------
# PIXEL_PACK: a stepped voxel backpack with a pixel-art paint drop
# ---------------------------------------------------------------------------

def pixel_pack():
    v, gap, depth = 0.066, 0.005, 0.15
    z0 = -0.03
    cells = []
    for j in range(-3, 3):
        for i in range(-2, 3):
            if abs(i) == 2 and j in (-3, 2):
                continue            # knocked-off corners: a "rounded" pixel outline
            mat = PLUM if j == 2 else LILAC
            cells.append((i * v, z0 + (j + 0.5) * v, (v - gap, depth, v - gap), mat))
    for s in (1, -1):              # side pockets
        for j in (-2, -1):
            cells.append((s * 3 * v, z0 + (j + 0.5) * v, (v - gap, depth * 0.62, v - gap), PLUM))
    for x, z, size, mat in cells:
        y = size[1] * 0.5 - 0.016
        add(lean(pk.box("Voxel", size, loc=(x, y, z), material=mat)))
    # The drop, in smaller pixels, standing proud of the back face.
    p = 0.046
    drop = ["..X..",
            ".XXX.",
            ".XXX.",
            "XSXXX",
            "XXXXX",
            "XXXXX",
            ".XXX."]
    back = depth - 0.016
    top = z0 + 0.165
    for row, line in enumerate(drop):
        for col, ch in enumerate(line):
            if ch == ".":
                continue
            mat = SHINE if ch == "S" else FILL
            add(lean(pk.box("Pixel", (p - 0.003, 0.032, p - 0.003),
                            loc=((col - 2) * p, back + 0.012, top - (row + 0.5) * p), material=mat)))
    # Team buckle on the top flap.
    add(lean(pk.box("Buckle", (0.07, 0.03, 0.05), loc=(0, back + 0.01, z0 + 2.5 * v),
                    material=TEAM)))
    return finish("Back_PIXEL_PACK")


# ---------------------------------------------------------------------------
# SPLASH_PACK: a frozen crown splash with flying droplets
# ---------------------------------------------------------------------------

def crown_mesh(name, spikes, rx0, ry0, rx1, ry1, valley_h, tip_hs, thick, rows=2):
    """An oval crown of paint: a wall flaring from (rx0, ry0) at the base to
    (rx1, ry1) at the rim. Each spike is four columns round the rim - a thin
    tip, two low shoulders and a valley - so the points are slim and the
    gaps between them are round, like a real milk-drop crown. Both faces of
    the wall are built, joined by a rim. Returns the object and the outer
    rim positions of the tips."""
    pattern = ((0.0, 1.0, 1.16), (0.17, 0.12, 1.04), (0.5, 0.0, 1.0), (0.83, 0.12, 1.04))
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    outer, inner, tips = [], [], []
    for k in range(rows + 1):
        f = k / rows
        o_row, i_row = [], []
        for n in range(spikes):
            for frac, rise, flare_out in pattern:
                a = math.tau * (n + frac) / spikes
                h_top = valley_h + (tip_hs[n] - valley_h) * rise
                flare = f ** 1.6
                out = flare_out if k == rows else 1.0 + (flare_out - 1.0) * f
                rx = rx0 + (rx1 * out - rx0) * flare
                ry = ry0 + (ry1 * out - ry0) * flare
                h = h_top * f
                o_row.append(bm.verts.new((rx * math.cos(a), ry * math.sin(a), h)))
                shrink = thick * (1.0 - 0.45 * f)
                i_row.append(bm.verts.new(((rx - shrink) * math.cos(a),
                                           (ry - shrink) * math.sin(a),
                                           h - (0.01 if k == rows else 0.0))))
                if k == rows and frac == 0.0:
                    tips.append(Vector((rx * math.cos(a), ry * math.sin(a), h)))
        outer.append(o_row)
        inner.append(i_row)
    cols = len(outer[0])
    for k in range(rows):
        for j in range(cols):
            jn = (j + 1) % cols
            bm.faces.new((outer[k][j], outer[k][jn], outer[k + 1][jn], outer[k + 1][j]))
            bm.faces.new((inner[k][j], inner[k + 1][j], inner[k + 1][jn], inner[k][jn]))
    for j in range(cols):
        jn = (j + 1) % cols
        bm.faces.new((outer[rows][j], outer[rows][jn], inner[rows][jn], inner[rows][j]))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.view_layer.active_layer_collection.collection.objects.link(obj)
    mesh.materials.append(FILL)
    return obj, tips


def splash_pack():
    tilt = Matrix.Rotation(math.radians(-10), 4, "X")      # crown opens up and back
    base = Vector((0.0, 0.13, -0.135))
    place_m = Matrix.Translation(base) @ tilt
    up = (place_m.to_3x3() @ Vector((0, 0, 1))).normalized()
    plate(0.2, 0.18, t=0.034, z=-0.1, material=FRAME)
    add(pk.box("Arm", (0.09, 0.08, 0.06), loc=(0, 0.04, -0.14), material=FRAME, bevel=0.012,
               segments=1))
    # Display base under the puddle.
    disc = rod("Base", (0, 0, -0.03), (0, 0, 0.0), 0.15, material=CREAM, verts=12)
    disc.scale = (1.3, 0.78, 1.0)
    add(transform(disc, place_m), 40)
    puddle = pk.lathe("Puddle", [(0.0, -0.004), (0.13, 0.0), (0.135, 0.012), (0.1, 0.024),
                                 (0.0, 0.03)], material=FILL, segments=10)
    puddle.scale = (1.25, 0.78, 1.0)
    add(transform(puddle, place_m), 60)
    heights = (0.25, 0.2, 0.23, 0.18, 0.21, 0.24, 0.19, 0.17)
    crown, tips = crown_mesh("Crown", 8, 0.1, 0.065, 0.2, 0.11, 0.12, heights, 0.02)
    add(transform(crown, place_m), 70)
    # A round bead of paint on every spike tip...
    for n, tip in enumerate(tips):
        out = Vector((tip.x, tip.y, 0.0)).normalized()
        r = (0.018, 0.023, 0.02)[n % 3]
        at = place_m @ (tip + out * 0.006 + Vector((0, 0, r * 0.7)))
        add(pk.ico("Bead%d" % n, r, loc=at, material=FILL, subdiv=1), 89)
    # ...and droplets flying off the sides and up.
    for n, (x, y, z, r) in enumerate(((0.255, 0.17, 0.115, 0.019), (-0.25, 0.16, 0.075, 0.017),
                                      (0.17, 0.2, 0.2, 0.015), (-0.14, 0.22, 0.16, 0.016))):
        add(pk.ico("Fly%d" % n, r, loc=(x, y, z), scale=(1.0, 1.0, 1.35), material=FILL,
                   subdiv=1), 89)
    # Central jet rising from the middle with a droplet on top.
    jet = pk.lathe("Jet", [(0.0, 0.0), (0.04, 0.01), (0.02, 0.07), (0.016, 0.12), (0.0, 0.135)],
                   material=FILL, segments=8)
    add(transform(jet, place_m), 70)
    add(ball("JetDrop", 0.026, place_m @ Vector((0, 0, 0.175)), FILL, segments=6, rings=4,
             scale=(1, 1, 1.25), z_dir=up), 80)
    return finish("Back_SPLASH_PACK")


# ---------------------------------------------------------------------------
# STAR_PACK: a big star-shaped palette with a paint dollop on every point
# ---------------------------------------------------------------------------

def star_pack():
    R_OUT, R_IN = 0.278, 0.122
    pts = []
    for k in range(10):
        a = math.radians(-90 + 36 * k)        # one point down, two up
        r = R_OUT if k % 2 == 0 else R_IN
        pts.append((r * math.cos(a), r * math.sin(a)))
    centre = Vector((0.0, 0.03, -0.035))
    thick = 0.042
    star = pk.prism("Star", pts, thick, rot=(90, 0, 0), material=WOOD)
    star.location = centre
    # Thumb hole: a palette needs one.
    hole = pk.cyl("ThumbHole", 0.03, 0.2, loc=centre + Vector((0.0, 0, 0.06)), rot=(90, 0, 0),
                  verts=12)
    mod = star.modifiers.new("Hole", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = hole
    bev = star.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.014
    bev.segments = 1
    bev.limit_method = "ANGLE"
    bev.angle_limit = math.radians(40)
    hole.hide_render = True
    add(lean(star), 40)
    face_y = centre.y + thick * 0.5
    # Mount block behind the centre.
    add(lean(pk.box("Mount", (0.12, 0.05, 0.1), loc=(0, 0.005, -0.06), material=FRAME,
                    bevel=0.012, segments=1)))
    for k in range(5):
        a = math.radians(-90 + 72 * k)
        r = 0.042 + 0.002 * ((k * 3) % 5)
        at = Vector((0.172 * math.cos(a), face_y - 0.004, 0.172 * math.sin(a))) + Vector(
            (centre.x, 0, centre.z))
        # A soft-serve blob: wide base, a pinched waist, a curled peak.
        blob = spun("Dollop%d" % k, [(0.0, -0.004), (r, 0.0), (r * 1.04, r * 0.3),
                                     (r * 0.78, r * 0.62), (r * 0.42, r * 0.8), (0.0, r * 0.9)],
                    at, (0, 1, 0), material=FILL, segments=10, x_hint=(1, 0, 0.3 * k - 0.6))
        add(lean(blob), 70)
    # Team-colour bolt cap in the middle.
    add(lean(rod("Bolt", (0, face_y - 0.004, centre.z), (0, face_y + 0.018, centre.z), 0.03,
                 material=TEAM, verts=10)), 50)
    return finish("Back_STAR_PACK", cutters=(hole,))


# ---------------------------------------------------------------------------
# EASEL_PACK: a folded easel strapped on at an angle, with a small canvas
# ---------------------------------------------------------------------------

def easel_pack():
    pivot = Vector((0.0, 0.0, -0.04))
    tilt = (Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(16), 4, "Y")
            @ Matrix.Translation(-pivot))
    built = []

    def part(obj, angle=35.0):
        built.append((obj, angle))
        return obj

    # Folded back leg lies on the runner's back; the two front legs make a
    # narrow A in front of it.
    part(beam("BackLeg", (0, -0.0, -0.33), (0, -0.0, 0.18), 0.034, 0.024, WALNUT, bevel=0.006))
    for s in (1, -1):
        part(beam("Leg", (s * 0.125, 0.06, -0.35), (s * 0.03, 0.06, 0.2), 0.034, 0.024, WALNUT,
                  bevel=0.006))
    part(pk.box("Head", (0.11, 0.075, 0.055), loc=(0, 0.035, 0.2), material=WALNUT,
                bevel=0.012, segments=1))
    part(pk.box("Ledge", (0.32, 0.08, 0.026), loc=(0, 0.095, -0.15), material=WOOD,
                bevel=0.008, segments=1))
    part(pk.box("Canvas", (0.27, 0.026, 0.215), loc=(0, 0.098, -0.03), material=CANVAS,
                bevel=0.008, segments=1))
    part(pk.box("Clamp", (0.08, 0.05, 0.034), loc=(0, 0.09, 0.09), material=WOOD,
                bevel=0.008, segments=1))
    # The painting: a big swoosh of paint on the canvas and a drip off its edge.
    blob = [(-0.1, -0.05), (-0.06, -0.075), (0.02, -0.06), (0.09, -0.075), (0.115, -0.03),
            (0.08, 0.02), (0.1, 0.07), (0.04, 0.08), (-0.03, 0.045), (-0.09, 0.07),
            (-0.115, 0.02)]
    part(flat("Painting", blob, 0.012, (0, 0.113, -0.03), FILL, bevel=0.004), 35)
    part(drip("CanvasDrip", (0.06, 0.106, -0.125), 0.05, 0.014, segments=6, squash=0.7), 80)
    # Straps around the legs: one rubber, one team colour.
    for z, half, mat in ((0.13, 0.075, TEAM), (-0.26, 0.135, STRAP)):
        path = [(-half - 0.02, -0.014), (-half, 0.082), (half, 0.082), (half + 0.02, -0.014)]
        part(pk.prism("Strap", thick_line(path, 0.013), 0.036, loc=(0, 0, z), material=mat))
    for obj, angle in built:
        add(lean(transform(obj, tilt)), angle)
    return finish("Back_EASEL_PACK")


# ---------------------------------------------------------------------------
# ROLLER_RIG: two crossed paint rollers dripping paint
# ---------------------------------------------------------------------------

def roller_rig():
    plate(0.17, 0.2, t=0.034, z=-0.04, material=FRAME)
    hub_z = -0.04
    add(rod("Hub", (0, 0.0, hub_z), (0, 0.128, hub_z), 0.058, material=STEEL, verts=12), 40)
    add(rod("HubCap", (0, 0.128, hub_z), (0, 0.142, hub_z), 0.04, material=TEAM, verts=12), 40)
    roll_z = 0.085
    for s, y in ((1, 0.075), (-1, 0.105)):
        bottom = Vector((-s * 0.178, y, -0.33))
        knee = Vector((s * 0.07, y, roll_z))
        d = (knee - bottom).normalized()
        grip_top = bottom + d * 0.13
        add(rod("Grip", bottom, grip_top, 0.024, 0.02, material=WOOD if s > 0 else BUTTER,
                verts=8), 50)
        add(ball("GripEnd", 0.026, bottom, FRAME, segments=6, rings=4), 80)
        add(rod("Shaft", grip_top - d * 0.01, knee, 0.012, material=STEEL, verts=6), 60)
        add(ball("Knee", 0.016, knee, STEEL, segments=6, rings=4), 80)
        add(rod("Axle", knee, (s * 0.19, y, roll_z), 0.012, material=STEEL, verts=6), 60)
        # The roller: a paint-soaked sleeve with metal end caps.
        r0, r1 = Vector((s * 0.1, y, roll_z)), Vector((s * 0.262, y, roll_z))
        add(rod("Roller", r0, r1, 0.05, material=FILL, verts=12), 40)
        for e in (r0, r1):
            add(rod("EndCap", e - Vector((s * 0.006, 0, 0)), e + Vector((s * 0.006, 0, 0)), 0.034,
                    material=TIN, verts=10), 40)
        for k, (fx, length) in enumerate(((0.3, 0.075), (0.72, 0.05))):
            at = r0.lerp(r1, fx) + Vector((0, 0, -0.042))
            add(drip("RollDrip%d" % k, at, length, 0.016, segments=6), 80)
    return finish("Back_ROLLER_RIG")


# ---------------------------------------------------------------------------
# Build everything
# ---------------------------------------------------------------------------

items = [mini_tank(), orb_pack(), paint_can(), wing_pack(), jet_pack(), bubble_pack(),
         pixel_pack(), splash_pack(), star_pack(), easel_pack(), roller_rig()]

bpy.context.view_layer.update()
over = False
for item in items:
    tris = pk.triangle_count([item])[0]
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for vtx in item.data.vertices:
        mins = Vector(map(min, mins, vtx.co))
        maxs = Vector(map(max, maxs, vtx.co))
    size = maxs - mins
    print("[backbling] %-18s %4d tris  size x %.3f z %.3f y %.3f  (y %.3f..%.3f, z %.3f..%.3f)"
          "  origin %s" % (item.name, tris, size.x, size.z, size.y, mins.y, maxs.y, mins.z,
                           maxs.z, tuple(round(c, 4) for c in item.matrix_world.translation)))
    if tris > 900:
        print("[backbling] ERROR: %s is over its 900-triangle budget" % item.name)
        over = True

if over:
    sys.exit(1)
pk.export("cosmetic_backbling.glb", budget=9000)
