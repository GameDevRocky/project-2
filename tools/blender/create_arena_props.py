"""
Arena decoration props - ten set-dressing models for the studio arena.

Plan: docs/VISUAL_OVERHAUL_PLAN.md section 4.12.

Unlike the other create_*.py scripts, this one builds SEVERAL assets in one
run. For each prop it starts a fresh scene (pk.begin), runs that prop's
builder function, checks the result against the placement rules, and exports
one GLB into models/generated/:

    prop_paint_tube.glb     PaintTube      wall-mounted, stands on its cap
    prop_giant_brush.glb    GiantBrush     wall-mounted, tuft at the top
    prop_can_stack.glb      CanStack       sits on a wall top, base centre
    prop_mixing_vat.glb     MixingVat      sits on a wall top, base centre
    prop_frame.glb          PictureFrame   wall-mounted
    prop_banner.glb         Banner         hangs from its origin (top centre)
    prop_pipe_run.glb       PipeRun        wall-mounted, origin on the pipe axis
    prop_palette_inlay.glb  PaletteInlay   flat floor inlay, base centre
    prop_hub_mobile.glb     HubMobile      hangs from its origin (top centre)
    prop_splat_decor.glb    SplatDecor     four flat dried splats Decor_0..3

These are pure DECORATION: Godot never gives them collision, so each one must
stay inside the size limits of the plan's placement rules. The checks below
enforce those limits and refuse to export a prop that breaks them.

WALL-MOUNTED convention: the wall is the plane y = 0. The prop's back face
lies on it and everything else sits in front of it (toward Blender -Y, which
the exporter turns into Godot +Z, i.e. into the room). The origin is the
bottom centre of that back face, so Godot places a prop by putting its origin
on the wall at floor (or ledge) height and turning it to face the room.

Materials are matte dried-paint and studio colours only. Nothing here uses the
gameplay roles (PK_Accent, PK_Team, PK_Fill, PK_Wet...) and nothing glows.

Run (from the project folder):
    blender -b --factory-startup --python tools/blender/create_arena_props.py
Options after a bare "--":
    --only paint_tube,frame   build only these props (keys from PROPS below)
    --previews DIR            also render a 2x2 contact sheet per prop into DIR
                              (the PK_PREVIEWS environment variable works too)
"""

import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Euler, Vector, geometry

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

TAU = math.tau

# Materials a decoration prop may never use: these are swapped by Godot for
# gameplay colours at runtime, or glow.
RESERVED_MATERIALS = {"PK_Accent", "PK_AccentGlow", "PK_Team", "PK_TeamGlow", "PK_Fill", "PK_Wet"}
# Archetype and team colours: set dressing must never be mistaken for them.
RESERVED_COLOURS = ["#FFB7C5", "#98FF98", "#00A896", "#FF627E", "#58D7F2"]

# Objects that are deliberately one-sided flat sheets (canvas, painted
# strokes, stains). The normal check treats them differently.
_sheets = set()
# Objects smoothed at a wider angle than the usual 35 degrees (name -> angle),
# for small soft blobs whose few faces would otherwise look crumpled.
_soft = {}


# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

def options():
    """Our own options after '--' (paintkit reads --out/--preview itself)."""
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"previews": None, "only": None}
    i = 0
    while i < len(argv):
        key = argv[i].lstrip("-")
        if key in opts and i + 1 < len(argv):
            opts[key] = argv[i + 1]
            i += 2
        else:
            i += 1
    if opts["previews"] is None:
        opts["previews"] = os.environ.get("PK_PREVIEWS")
    return opts


# ---------------------------------------------------------------------------
# Geometry helpers (local to this script)
# ---------------------------------------------------------------------------

def mesh_obj(name, verts, faces, mats, face_mats=None, parent_obj=None, recalc=False,
             sheet_dir=None):
    """Build a mesh object straight from vertex and face lists.

    face_mats gives each face an index into `mats`. recalc=True lets Blender
    fix the face directions (only safe for closed shapes). sheet_dir marks a
    flat one-sided sheet and turns every face toward that direction."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    if recalc or sheet_dir is not None:
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bm.normal_update()
        if recalc:
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        if sheet_dir is not None:
            d = Vector(sheet_dir)
            for f in bm.faces:
                if f.normal.dot(d) < 0.0:
                    f.normal_flip()
        bm.to_mesh(mesh)
        bm.free()
    for m in mats:
        mesh.materials.append(m)
    if face_mats is not None:
        for poly, index in zip(mesh.polygons, face_mats):
            poly.material_index = index
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    pk._collection.objects.link(obj)  # the working collection pk.begin() made
    if sheet_dir is not None:
        _sheets.add(name)
    if parent_obj is not None:
        pk.parent(obj, parent_obj)
    return obj


def loft(name, rings, mats, face_mat=None, parent_obj=None, recalc=False):
    """Skin a list of cross-section rings into one surface.

    Every ring lists its points counter-clockwise seen from the end the
    rings run toward, all rings with the same count. A ring of ONE point is
    a pole: the surface closes to a point there. face_mat(band, j) picks a
    material index per face (band = gap between ring `band` and the next)."""
    verts, starts = [], []
    for ring in rings:
        starts.append((len(verts), len(ring)))
        verts.extend(ring)
    faces, fmats = [], []
    for i in range(len(rings) - 1):
        (a0, na), (b0, nb) = starts[i], starts[i + 1]
        count = max(na, nb)
        for j in range(count):
            j2 = (j + 1) % count
            if na == nb:
                faces.append((a0 + j, a0 + j2, b0 + j2, b0 + j))
            elif na == 1:
                faces.append((a0, b0 + j2, b0 + j))
            else:
                faces.append((a0 + j, a0 + j2, b0))
            fmats.append(face_mat(i, j) if face_mat else 0)
    return mesh_obj(name, verts, faces, mats, fmats, parent_obj, recalc=recalc)


def lathe_rings(profile, n, centre=(0.0, 0.0), z0=0.0, phase=0.0, radial=None):
    """(radius, height) profile -> rings for loft(), spun around a vertical
    axis at `centre`. radial(i, j, r) may nudge each point's radius (ribs)."""
    rings = []
    for i, (r, z) in enumerate(profile):
        if r <= 1e-9:
            rings.append([(centre[0], centre[1], z0 + z)])
            continue
        ring = []
        for j in range(n):
            a = phase + TAU * j / n
            rr = radial(i, j, r) if radial else r
            ring.append((centre[0] + rr * math.cos(a), centre[1] + rr * math.sin(a), z0 + z))
        rings.append(ring)
    return rings


def slab_ring(cx, cy, z, half_w, half_d, n, power=2.0, phase=0.0, z_of=None):
    """A rounded-rectangle ('superellipse') cross-section: power 2 is an
    ellipse, higher powers get boxier. Used for the flattened brush parts."""
    ring = []
    for j in range(n):
        a = phase + TAU * j / n
        c, s = math.cos(a), math.sin(a)
        x = half_w * math.copysign(abs(c) ** (2.0 / power), c)
        y = half_d * math.copysign(abs(s) ** (2.0 / power), s)
        ring.append((cx + x, cy + y, z + (z_of(j) if z_of else 0.0)))
    return ring


def wobbly_outline(cx, cy, rx, ry, n, rng, wobble=0.08, phase=0.0):
    """A hand-drawn looking closed outline (counter-clockwise)."""
    pts = []
    for j in range(n):
        a = phase + TAU * j / n
        k = 1.0 + rng.uniform(-wobble, wobble)
        pts.append((cx + rx * k * math.cos(a), cy + ry * k * math.sin(a)))
    return pts


def flat_shape(name, pts2d, material, plane="XZ", offset=0.0, facing=(0, -1, 0), parent_obj=None):
    """One flat face from a 2D outline. plane 'XZ' puts (u, v) at (x, z) with
    y = offset (wall shapes); plane 'XY' puts them at (x, y) with z = offset
    (floor shapes)."""
    if plane == "XZ":
        verts = [(u, offset, v) for u, v in pts2d]
    else:
        verts = [(u, v, offset) for u, v in pts2d]
    return mesh_obj(name, verts, [tuple(range(len(verts)))], [material],
                    parent_obj=parent_obj, sheet_dir=facing)


def stroke_2d(centre_pts, widths):
    """Left/right edge outline of a painted stroke along a 2D centre line."""
    left, right = [], []
    n = len(centre_pts)
    for i, (x, y) in enumerate(centre_pts):
        x0, y0 = centre_pts[max(i - 1, 0)]
        x1, y1 = centre_pts[min(i + 1, n - 1)]
        tx, ty = x1 - x0, y1 - y0
        length = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / length, tx / length
        w = widths[i] * 0.5
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left, right


def stroke_sheet(name, centre_pts, widths, material, plane="XZ", offset=0.0,
                 facing=(0, -1, 0), parent_obj=None):
    """A flat tapered brush stroke made of quads along its centre line."""
    left, right = stroke_2d(centre_pts, widths)
    n = len(centre_pts)
    if plane == "XZ":
        verts = [(u, offset, v) for u, v in right + left]
    else:
        verts = [(u, v, offset) for u, v in right + left]
    faces = [(i, i + 1, n + i + 1, n + i) for i in range(n - 1)]
    return mesh_obj(name, verts, faces, [material], parent_obj=parent_obj, sheet_dir=facing)


def rod(name, p0, p1, radius, verts, material, parent_obj=None, bevel=0.0):
    """A cylinder running from point p0 to point p1."""
    p0, p1 = Vector(p0), Vector(p1)
    direction = (p1 - p0).normalized()
    euler = Vector((0, 0, 1)).rotation_difference(direction).to_euler()
    return pk.cyl(name, radius, (p1 - p0).length, loc=tuple((p0 + p1) * 0.5),
                  rot=tuple(math.degrees(a) for a in euler), material=material,
                  verts=verts, bevel=bevel, segments=1, parent_obj=parent_obj)


def drip(name, anchor, facing_deg, top_z, length, width, thick, material, parent_obj=None):
    """A dried paint run down a vertical surface: wide where it spills over
    an edge, a thinner run below, and a fat bead at the bottom (36 tris).

    anchor is the (x, y) point on the surface, facing_deg the direction the
    surface faces (degrees from +X). It sticks out about 0.7 x thick."""
    a = math.radians(facing_deg)
    nx, ny = math.cos(a), math.sin(a)        # out of the surface
    tx, ty = -ny, nx                         # along the surface
    bottom = top_z - length
    rows = [(bottom + 0.022, width * 0.6, thick * 0.5),     # the bead
            (bottom + 0.06, width * 0.36, thick * 0.36),    # the thin run
            (top_z - 0.012, width * 0.5, thick * 0.3)]      # where it spills over
    rings = [[(anchor[0] + nx * 0.004, anchor[1] + ny * 0.004, bottom)]]
    for z, half_w, half_t in rows:
        cx, cy = anchor[0] + nx * half_t * 0.4, anchor[1] + ny * half_t * 0.4
        ring = []
        for j in range(6):
            b = TAU * j / 6
            c, s = math.cos(b), math.sin(b)
            ring.append((cx + nx * half_t * c + tx * half_w * s,
                         cy + ny * half_t * c + ty * half_w * s, z))
        rings.append(ring)
    rings.append([(anchor[0], anchor[1], top_z + 0.01)])
    _soft[name] = 90.0
    return loft(name, rings, [material], parent_obj=parent_obj, recalc=True)


def drip_on_cylinder(name, cx, cy, r, angle_deg, top_z, length, material, width=0.05,
                     thick=0.035, parent_obj=None):
    """A drip running down the outside of a vertical cylinder of radius r."""
    a = math.radians(angle_deg)
    return drip(name, (cx + r * math.cos(a), cy + r * math.sin(a)), angle_deg, top_z, length,
                width, thick, material, parent_obj)


def soften(obj, angle):
    """Re-smooth at a wider angle. pk.smooth() can't do this after
    pk.smooth_all(35): Blender keeps edges an earlier pass marked sharp
    unless told not to."""
    pk.select_only(obj)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle), keep_sharp_edges=False)


def shift_children(root, dx, dy, dz=0.0):
    for child in root.children:
        child.location.x += dx
        child.location.y += dy
        child.location.z += dz


def recentre_xy(root):
    """Move the model so its footprint is centred on the origin."""
    mins, maxs, _ = bounds()
    shift_children(root, -(mins.x + maxs.x) * 0.5, -(mins.y + maxs.y) * 0.5)


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def bounds(objs=None):
    """World-space bounding box of the evaluated meshes (bevels included),
    plus the largest horizontal distance from the Z axis."""
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    rmax = 0.0
    for obj in objs or pk.objects():
        if obj.type != "MESH":
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mw = obj.matrix_world
        for v in mesh.vertices:
            w = mw @ v.co
            mins = Vector(map(min, mins, w))
            maxs = Vector(map(max, maxs, w))
            rmax = max(rmax, math.hypot(w.x, w.y))
        evaluated.to_mesh_clear()
    return mins, maxs, rmax


def check_normals():
    """Catch inside-out faces: the outermost faces of a shape in each axis
    direction must point outward. Flat sheets must all face their way."""
    bpy.context.view_layer.update()
    problems = []
    for obj in pk.objects():
        if obj.type != "MESH":
            continue
        mw = obj.matrix_world
        normal_mat = mw.to_3x3().inverted().transposed()
        faces = [(mw @ p.center, (normal_mat @ p.normal).normalized()) for p in obj.data.polygons]
        if not faces:
            continue
        if obj.name in _sheets:
            continue   # mesh_obj already turned every face of a sheet its way
        for axis in range(3):
            for sign in (1.0, -1.0):
                d = Vector((0, 0, 0))
                d[axis] = sign
                extreme = max(c.dot(d) for c, _ in faces)
                span = extreme - min(c.dot(d) for c, _ in faces)
                tolerance = min(0.005, 0.2 * span)
                for c, n in faces:
                    if c.dot(d) >= extreme - tolerance and abs(n.dot(d)) > 0.6 and n.dot(d) < 0:
                        problems.append("%s: face at %s points inward (%s)" % (
                            obj.name, tuple(round(x, 3) for x in c), tuple(round(x, 2) for x in n)))
                        break
    return problems


def check_materials():
    problems = []
    reserved = [pk.linear(h) for h in RESERVED_COLOURS]
    for obj in pk.objects():
        if obj.type != "MESH":
            continue
        for m in obj.data.materials:
            if m.name in RESERVED_MATERIALS:
                problems.append("%s uses reserved material %s" % (obj.name, m.name))
            bsdf = m.node_tree.nodes["Principled BSDF"]
            colour = tuple(bsdf.inputs["Base Color"].default_value)
            for r in reserved:
                if all(abs(a - b) < 1e-4 for a, b in zip(colour[:3], r[:3])):
                    problems.append("%s uses a reserved colour" % m.name)
            if bsdf.inputs["Emission Strength"].default_value > 0.0 and \
                    max(bsdf.inputs["Emission Color"].default_value[:3]) > 0.0:
                problems.append("%s is emissive" % m.name)
    return problems


def check_limits(limits):
    """limits: 'min'/'max' (x, y, z) tuples with None for 'no limit', 'rmax'."""
    mins, maxs, rmax = bounds()
    problems = []
    eps = 1e-4
    for axis, label in enumerate("xyz"):
        lo = limits.get("min", (None, None, None))[axis]
        hi = limits.get("max", (None, None, None))[axis]
        if lo is not None and mins[axis] < lo - eps:
            problems.append("%s min %.4f < limit %.4f" % (label, mins[axis], lo))
        if hi is not None and maxs[axis] > hi + eps:
            problems.append("%s max %.4f > limit %.4f" % (label, maxs[axis], hi))
    if "rmax" in limits and rmax > limits["rmax"] + eps:
        problems.append("footprint radius %.4f > limit %.4f" % (rmax, limits["rmax"]))
    return problems, mins, maxs, rmax


# ---------------------------------------------------------------------------
# 1. Paint tube - 3 m squeezed tube standing on its cap against a wall
# ---------------------------------------------------------------------------

def build_paint_tube():
    root = pk.empty("PaintTube")
    tin = pk.mat("PK_Metal", name="PK_TubeTin", color="#C8C4D4", roughness=0.5, metallic=0.3)
    label = pk.mat("PK_Canvas")
    paint = pk.mat("PK_Dry2")                 # the tube holds lilac
    cap_mat = pk.mat("PK_Trim")

    CAP_Y = -0.175       # the cap's axis: 0.35 m deep cap touching the wall
    CAP_H = 0.26

    # Cross-section: a 'D' shape - a nearly flat back against the wall and a
    # rounded front belly. Sparse points on the hidden back, dense on the front.
    angles = [0, 45, 90, 135, 180] + [180 + 22.5 * k for k in range(1, 8)]

    def dent(x, z):
        """The squeeze: a thumb-press pushing the front toward the wall."""
        return 0.12 * math.exp(-((x - 0.13) / 0.26) ** 2 - ((z - 1.62) / 0.24) ** 2)

    def section(z, half_w, yc, back, front):
        ring = []
        for deg in angles:
            a = math.radians(deg)
            c, s = math.cos(a), math.sin(a)
            x = half_w * c
            if s > 1e-6:
                y = yc + back * s
            else:
                y = yc + front * s
                if s < -1e-6:
                    y = min(y + dent(x, z), yc - 0.03)
            ring.append((x, y, z))
        return ring

    # (height, half width, back/front split line, back bulge, front bulge)
    rows = [
        (0.20, 0.115, CAP_Y, 0.115, 0.115),     # neck, hidden in the cap
        (0.30, 0.115, CAP_Y, 0.115, 0.115),     # neck just above the cap
        (0.36, 0.33, -0.12, 0.09, 0.20),        # shoulder
        (0.46, 0.505, -0.035, 0.035, 0.29),
        (0.60, 0.53, -0.03, 0.03, 0.31),        # label bottom
        (0.86, 0.54, -0.03, 0.03, 0.305),       # colour stripe bottom
        (1.18, 0.545, -0.03, 0.03, 0.295),      # colour stripe top
        (1.44, 0.545, -0.03, 0.03, 0.275),      # label top
        (1.62, 0.545, -0.03, 0.03, 0.26),       # the squeeze dent
        (1.82, 0.545, -0.03, 0.03, 0.245),
        (2.08, 0.545, -0.028, 0.028, 0.21),
        (2.36, 0.545, -0.025, 0.025, 0.15),     # flattening toward the crimp
        (2.58, 0.545, -0.022, 0.022, 0.085),
        (2.74, 0.54, -0.02, 0.02, 0.035),       # tucked inside the crimp
    ]
    rings = [section(*row) for row in rows]

    def body_mat(band, j):
        if band in (4, 6):
            return 1      # canvas label
        if band == 5:
            return 2      # colour stripe on the label
        return 0

    loft("Body", rings, [tin, label, paint], face_mat=body_mat, parent_obj=root)

    # Crimped flat end at the top, with three pressed ridges.
    pk.box("Crimp", (1.1, 0.075, 0.30), loc=(0, -0.0375, 3.0 - 0.15), material=tin,
           bevel=0.02, segments=1, parent_obj=root)
    for i, z in enumerate((2.78, 2.86, 2.94)):
        pk.box("CrimpRidge%d" % i, (1.02, 0.02, 0.035), loc=(0, -0.083, z), material=tin,
               parent_obj=root)

    # Round screw cap it stands on, with chunky grip ribs.
    def ribs(i, j, r):
        return r - 0.013 if (i in (1, 2) and j % 2) else r

    cap_rings = lathe_rings([(0.148, 0.0), (0.165, 0.022), (0.165, CAP_H - 0.035),
                             (0.148, CAP_H - 0.005), (0.10, CAP_H)], 16,
                            centre=(0.0, CAP_Y), radial=ribs)
    loft("Cap", cap_rings, [cap_mat], parent_obj=root)

    # Dried paint that leaked out of the cap and pooled on the floor.
    drip_on_cylinder("CapDrip", 0.0, CAP_Y, 0.165, -50.0, CAP_H - 0.012, 0.24, paint,
                     width=0.08, thick=0.04, parent_obj=root)
    rng = random.Random(3)
    puddle = wobbly_outline(0.06, -0.2, 0.33, 0.125, 12, rng, wobble=0.1)
    pk.prism("Puddle", puddle, 0.012, loc=(0, 0, 0.006), material=paint, parent_obj=root)


# ---------------------------------------------------------------------------
# 2. Giant brush - 4 m flat artist's brush, tuft up, against a wall
# ---------------------------------------------------------------------------

def build_giant_brush():
    root = pk.empty("GiantBrush")
    lacquer = pk.mat("PK_Wood", name="PK_BrushLacquer", color="#8A4F4B", roughness=0.55)
    wood = pk.mat("PK_Wood")
    metal = pk.mat("PK_Metal")
    bristle = pk.mat("PK_Canvas", name="PK_Bristle", color="#D6C29C", roughness=0.9)
    paint = pk.mat("PK_Dry4")          # dipped in sea-glass

    AX, AY = 0.0, -0.14    # the brush's axis; its widest round part touches the wall

    # Handle: a bare-wood end, then a long lacquered taper that swells just
    # below the ferrule, like a real artist's brush.
    handle = lathe_rings([(0.0, 0.0), (0.04, 0.012), (0.06, 0.05), (0.07, 0.14),
                          (0.072, 0.30), (0.086, 1.1), (0.106, 1.9), (0.126, 2.30),
                          (0.128, 2.40), (0.12, 2.47)], 12, centre=(AX, AY))
    loft("Handle", handle, [wood, lacquer], face_mat=lambda band, j: 0 if band < 4 else 1,
         parent_obj=root)

    # Ferrule: round where it grips the handle, pinched flat at the top, with
    # a groove and a crimp line pressed into it.
    ferrule_rows = [  # (z, half width, half depth, squareness)
        (2.43, 0.118, 0.118, 2.0),
        (2.46, 0.137, 0.137, 2.0),
        (2.56, 0.137, 0.137, 2.0),
        (2.60, 0.126, 0.126, 2.0),     # groove
        (2.66, 0.14, 0.132, 2.2),
        (2.84, 0.18, 0.12, 2.6),
        (2.88, 0.168, 0.11, 2.6),      # crimp line
        (2.92, 0.185, 0.115, 2.8),
        (3.03, 0.205, 0.112, 3.0),
        (3.07, 0.188, 0.094, 3.0),     # lip where the bristles come out
    ]
    loft("Ferrule", [slab_ring(AX, AY, z, w, d, 16, p) for z, w, d, p in ferrule_rows],
         [metal], parent_obj=root)

    # Tuft: a flat 'filbert' tuft, bristle-coloured below, dipped in dried
    # paint above a wavy paint line, with a slightly ragged tip.
    rng = random.Random(21)
    tip_noise = [rng.uniform(-0.025, 0.025) for _ in range(16)]
    tuft_rows = [
        (3.00, 0.18, 0.088, 3.0, None),
        (3.12, 0.215, 0.10, 2.8, None),
        (3.34, 0.238, 0.106, 2.6, None),
        (3.55, 0.236, 0.10, 2.5, lambda j: 0.03 * math.sin(3 * TAU * j / 16 + 0.7)),
        (3.72, 0.218, 0.088, 2.4, None),
        (3.86, 0.18, 0.068, 2.2, lambda j: tip_noise[j] * 0.6),
        (3.95, 0.115, 0.045, 2.0, lambda j: tip_noise[j]),
    ]
    rings = [slab_ring(AX, AY, z, w, d, 16, p, z_of=zf) for z, w, d, p, zf in tuft_rows]
    rings.append([(AX, AY, 4.0)])
    loft("Tuft", rings, [bristle, paint], face_mat=lambda band, j: 0 if band < 3 else 1,
         parent_obj=root)
    _soft["Tuft"] = 70.0

    # Runs of paint down the front of the tuft, below the paint line.
    for i, (x, length) in enumerate(((-0.13, 0.17), (0.02, 0.24), (0.14, 0.13))):
        hw, hd, p = 0.237, 0.103, 2.55
        front = hd * max(0.0, 1.0 - (abs(x) / hw) ** p) ** (1.0 / p)
        drip("TuftDrip%d" % i, (AX + x, AY - front + 0.004), -90.0, 3.57, length, 0.07, 0.04,
             paint, parent_obj=root)


# ---------------------------------------------------------------------------
# 3. Can stack - four lidded paint cans with dried drips
# ---------------------------------------------------------------------------

def build_can_stack():
    root = pk.empty("CanStack")
    tin = pk.mat("PK_Metal", name="PK_CanTin", color="#B5B1C2", roughness=0.5, metallic=0.4)
    N = 12

    def can(name, cx, cy, z0, r, h, paint, painted, drips):
        """One can: tin body, a label band in the paint it holds, a rolled
        rim bead and a domed lid. `painted` lists the 30-degree sectors where
        paint has spilled over the rim; `drips` = [(sector, length)]."""
        profile = [(r * 0.93, 0.0), (r, 0.025), (r, h * 0.25), (r, h * 0.78),
                   (r, h - 0.035), (r + 0.014, h - 0.014), (r * 0.86, h), (0.0, h + 0.012)]

        def fm(band, j):
            if band == 2:
                return 1
            if band >= 4 and j in painted:
                return 1
            return 0

        loft(name, lathe_rings(profile, N, centre=(cx, cy), z0=z0), [tin, paint],
             face_mat=fm, parent_obj=root)
        for k, (sector, length) in enumerate(drips):
            angle = (sector + 0.5) * 360.0 / N
            drip_on_cylinder("%sDrip%d" % (name, k), cx, cy, r, angle, z0 + h - 0.012, length,
                             paint, width=0.055, thick=0.035, parent_obj=root)

    dry1, dry2, dry3, dry4 = (pk.mat("PK_Dry%d" % i) for i in (1, 2, 3, 4))
    # Big can and a medium can on the floor, a medium can on the big one and
    # a small can on top. Heights are chosen so each sits on the lid below.
    can("CanA", -0.10, 0.06, 0.0, 0.20, 0.42, dry1, {6, 7, 9}, [(7, 0.15), (9, 0.1)])
    can("CanB", 0.21, -0.14, 0.0, 0.15, 0.30, dry4, {8, 9, 10}, [(9, 0.13)])
    can("CanC", -0.07, 0.04, 0.425, 0.16, 0.28, dry3, {1, 2, 10}, [(10, 0.12)])
    can("CanD", -0.03, 0.02, 0.713, 0.105, 0.18, dry2, {7, 8}, [(8, 0.09)])
    recentre_xy(root)


# ---------------------------------------------------------------------------
# 4. Mixing vat - ribbed vat full of dried paint with a paddle stuck in it
# ---------------------------------------------------------------------------

def build_mixing_vat():
    root = pk.empty("MixingVat")
    enamel = pk.mat("PK_Body", name="PK_VatEnamel", color="#D8D0C4", roughness=0.6)
    trim = pk.mat("PK_Trim")
    paint = pk.mat("PK_Dry2")          # NE mixing room = lilac
    wood = pk.mat("PK_Wood")
    N = 16

    profile = [
        (0.305, 0.0), (0.325, 0.03),
        (0.328, 0.10), (0.35, 0.115), (0.35, 0.185), (0.33, 0.20),       # hoop 1
        (0.338, 0.44), (0.358, 0.455), (0.358, 0.525), (0.34, 0.54),     # hoop 2
        (0.347, 0.73), (0.366, 0.745), (0.366, 0.815), (0.349, 0.83),    # hoop 3
        (0.355, 0.955), (0.372, 0.97), (0.372, 0.995), (0.355, 1.005),   # rolled rim
        (0.338, 0.99), (0.332, 0.90),                                    # inner wall
        (0.0, 0.905),                                                    # paint surface
    ]
    trim_bands = {2, 3, 4, 6, 7, 8, 10, 11, 12, 14, 15, 16}
    spilled = {3, 4, 11}           # rim sectors where paint slopped over

    def fm(band, j):
        if band == 19:
            return 2
        if band in (14, 15, 16, 17) and j in spilled:
            return 2
        if band in trim_bands:
            return 1
        return 0

    loft("Vat", lathe_rings(profile, N), [enamel, trim, paint], face_mat=fm, parent_obj=root)

    for k, (sector, length) in enumerate(((3, 0.12), (4, 0.09), (11, 0.11))):
        angle = (sector + 0.5) * 360.0 / N
        drip_on_cylinder("VatDrip%d" % k, 0.0, 0.0, 0.35, angle, 0.955, length, paint,
                         width=0.065, thick=0.03, parent_obj=root)

    # The paddle: a paint-caked blade poking out of the dried paint, a thick
    # wooden shaft, and a T-grip. Built along a tilted axis.
    base = Vector((-0.07, 0.04, 0.905))
    tilt = Euler((math.radians(5), math.radians(13), 0.0), "XYZ")
    axis = tilt.to_matrix() @ Vector((0, 0, 1))
    tilt_deg = tuple(math.degrees(a) for a in tilt)
    pk.box("PaddleBlade", (0.2, 0.05, 0.36), loc=tuple(base + axis * 0.04), rot=tilt_deg,
           material=paint, bevel=0.018, segments=1, parent_obj=root)
    rod("PaddleShaft", base + axis * 0.2, base + axis * 0.45, 0.036, 8, wood, parent_obj=root)
    grip = tilt.to_matrix() @ Euler((0, math.radians(90), 0)).to_matrix()
    pk.cyl("PaddleGrip", 0.036, 0.19, loc=tuple(base + axis * 0.45),
           rot=tuple(math.degrees(a) for a in grip.to_euler()), material=wood, verts=8,
           parent_obj=root)


# ---------------------------------------------------------------------------
# 5. Picture frame - ornate frame around a canvas with bold abstract strokes
# ---------------------------------------------------------------------------

def build_frame():
    root = pk.empty("PictureFrame")
    gilt = pk.mat("PK_Metal", name="PK_Gilt", color="#B08A45", roughness=0.45, metallic=0.5)
    liner = pk.mat("PK_Trim")
    canvas = pk.mat("PK_Canvas")
    dry = [pk.mat("PK_Dry%d" % i) for i in (1, 2, 3, 4)]

    W, H, BORDER = 2.4, 1.6, 0.2
    IX, IZ, ZC = W * 0.5 - BORDER, H * 0.5 - BORDER, H * 0.5   # opening half-size, centre

    # The moulding's cross-section as (distance out from the opening, depth
    # off the wall): a dark sight-edge liner, a cove, a fat rounded bead and a
    # bevelled outer edge. Swept around the rectangle with mitred corners.
    profile = [(0.0, 0.022), (0.0, 0.046), (0.03, 0.058), (0.05, 0.053), (0.075, 0.07),
               (0.10, 0.084), (0.13, 0.088), (0.155, 0.08), (0.18, 0.066), (0.2, 0.045),
               (0.2, 0.0)]
    corners = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
    verts = [(sx * (IX + u), -d, ZC + sz * (IZ + u)) for u, d in profile for sx, sz in corners]
    faces, fmats = [], []
    for i in range(len(profile) - 1):
        for k in range(4):
            k2 = (k + 1) % 4
            faces.append((i * 4 + k, (i + 1) * 4 + k, (i + 1) * 4 + k2, i * 4 + k2))
            fmats.append(1 if i < 2 else 0)
    mesh_obj("Moulding", verts, faces, [gilt, liner], fmats, parent_obj=root)

    # Ornaments: corner rosettes, side bosses and crests on the rails.
    for i, (x, z) in enumerate(((IX + 0.1, ZC + IZ + 0.1), (-IX - 0.1, ZC + IZ + 0.1),
                                (-IX - 0.1, ZC - IZ - 0.1), (IX + 0.1, ZC - IZ - 0.1))):
        pk.sphere("Rosette%d" % i, 1.0, loc=(x, -0.078, z), scale=(0.1, 0.042, 0.1),
                  material=gilt, segments=8, rings=4, parent_obj=root)
    pk.sphere("CrestTop", 1.0, loc=(0, -0.08, ZC + IZ + 0.1), scale=(0.22, 0.038, 0.085),
              material=gilt, segments=8, rings=4, parent_obj=root)
    pk.sphere("CrestBottom", 1.0, loc=(0, -0.08, ZC - IZ - 0.1), scale=(0.16, 0.038, 0.075),
              material=gilt, segments=8, rings=4, parent_obj=root)
    for i, x in enumerate((IX + 0.1, -IX - 0.1)):
        pk.sphere("Boss%d" % i, 1.0, loc=(x, -0.08, ZC), scale=(0.075, 0.038, 0.12),
                  material=gilt, segments=8, rings=4, parent_obj=root)
    for name in ("Rosette0", "Rosette1", "Rosette2", "Rosette3", "CrestTop", "CrestBottom",
                 "Boss0", "Boss1"):
        _soft[name] = 90.0

    # The canvas, tucked behind the moulding.
    cw, ch = IX + 0.03, IZ + 0.03
    flat_shape("Canvas", [(-cw, ZC - ch), (cw, ZC - ch), (cw, ZC + ch), (-cw, ZC + ch)],
               canvas, offset=-0.03, parent_obj=root)

    # Bold abstract painting: flat shapes just in front of the canvas, each a
    # few millimetres further forward so overlaps never flicker.
    rng = random.Random(55)
    flat_shape("PaintSun", wobbly_outline(0.52, 1.0, 0.27, 0.27, 20, rng, 0.05), dry[0],
               offset=-0.034, parent_obj=root)
    flat_shape("PaintPool", wobbly_outline(-0.5, 0.42, 0.34, 0.17, 14, rng, 0.09), dry[3],
               offset=-0.035, parent_obj=root)
    sweep = []
    for i in range(12):
        t = i / 11.0
        sweep.append((-0.86 + 1.72 * t,
                      0.55 + 0.38 * math.sin(math.pi * t * 1.1) - 0.15 * t))
    stroke_sheet("PaintSweep", sweep,
                 [0.05 + 0.17 * math.sin(math.pi * (0.08 + 0.84 * i / 11.0)) ** 0.6
                  for i in range(12)], dry[1], offset=-0.038, parent_obj=root)
    slash = [(-0.78 + 0.13 * i, 1.26 - 0.025 * i - 0.006 * i * i) for i in range(6)]
    stroke_sheet("PaintSlash", slash, [0.06, 0.15, 0.17, 0.16, 0.13, 0.05], dry[2],
                 offset=-0.042, parent_obj=root)
    for i, (x, z, r) in enumerate(((0.12, 1.2, 0.05), (0.2, 1.07, 0.035), (0.1, 0.33, 0.05))):
        flat_shape("PaintDot%d" % i, wobbly_outline(x, z, r, r, 6, rng, 0.12),
                   dry[0] if i < 2 else dry[3], offset=-0.037, parent_obj=root)


# ---------------------------------------------------------------------------
# 6. Banner - hanging canvas strip on a rod, painted hem, big brush mark
# ---------------------------------------------------------------------------

def build_banner():
    root = pk.empty("Banner")
    canvas = pk.mat("PK_Canvas")
    wood = pk.mat("PK_Wood")
    cord = pk.mat("PK_Dark")
    hem = pk.mat("PK_Dry3")
    mark = pk.mat("PK_Dry2")

    ROD_Z, ROD_Y = -0.30, -0.045
    # A V-shaped cord from the hang point (the origin) to the rod ends.
    for i, x in enumerate((-0.44, 0.44)):
        rod("Cord%d" % i, (0.0, -0.02, -0.02), (x, ROD_Y, ROD_Z), 0.015, 6, cord, parent_obj=root)
    pk.cyl("Rod", 0.035, 1.1, loc=(0, ROD_Y, ROD_Z), rot=(0, 90, 0), material=wood, verts=8,
           parent_obj=root)
    for i, x in enumerate((-0.555, 0.555)):
        pk.sphere("Finial%d" % i, 0.045, loc=(x, ROD_Y, ROD_Z), material=wood, segments=6,
                  rings=4, parent_obj=root)

    # The cloth: a grid hanging from the rod with soft vertical folds that
    # deepen toward the bottom, a hem dipped in paint and a ragged lower edge.
    cols = [-0.52 + 0.13 * c for c in range(9)]
    row_z = [ROD_Z, -0.62, -1.02, -1.45, -1.90, -2.30, -2.55]
    hem_wave = [0.04 * math.sin(2.1 * c + 0.4) for c in range(9)]
    ragged = [-2.80, -2.97, -2.84, -3.0, -2.78, -2.93, -2.86, -2.99, -2.82]

    def fold(x, z):
        depth = min(1.0, (ROD_Z - z) / 2.2)
        return ROD_Y - (0.006 + 0.024 * depth) * math.sin(TAU * x / 0.52 + 0.6)

    grid = []
    for r, z in enumerate(row_z + [None]):
        row = []
        for c, x in enumerate(cols):
            zz = ragged[c] if z is None else (z + hem_wave[c] if r == len(row_z) - 1 else z)
            row.append((x, fold(x, zz), zz))
        grid.append(row)
    verts = [v for row in grid for v in row]
    faces, fmats = [], []
    nc = len(cols)
    for r in range(len(grid) - 1):
        for c in range(nc - 1):
            faces.append((r * nc + c, r * nc + c + 1, (r + 1) * nc + c + 1, (r + 1) * nc + c))
            fmats.append(1 if r >= len(row_z) - 1 else 0)
    mesh_obj("Cloth", verts, faces, [canvas, hem], fmats, parent_obj=root, sheet_dir=(0, -1, 0))

    # One big diagonal brush mark, sitting on the cloth's folds. Its points
    # share the cloth's columns so it follows the folds exactly.
    centre = [-1.95 + 1.05 * (c / 8.0) + 0.12 * math.sin(math.pi * c / 8.0) for c in range(9)]
    half = [0.05 + 0.2 * math.sin(math.pi * (0.06 + 0.88 * c / 8.0)) ** 0.5 for c in range(9)]
    mverts = [(x, fold(x, centre[c] - half[c]) - 0.012, centre[c] - half[c]) for c, x in enumerate(cols)]
    mverts += [(x, fold(x, centre[c] + half[c]) - 0.012, centre[c] + half[c]) for c, x in enumerate(cols)]
    mfaces = [(c, c + 1, nc + c + 1, nc + c) for c in range(nc - 1)]
    mesh_obj("BrushMark", mverts, mfaces, [mark], parent_obj=root, sheet_dir=(0, -1, 0))


# ---------------------------------------------------------------------------
# 7. Pipe run - 4 m pipe on two wall brackets, valve wheel, drip stains
# ---------------------------------------------------------------------------

def build_pipe_run():
    root = pk.empty("PipeRun")
    pipe_mat = pk.mat("PK_Metal", name="PK_PipePaint", color="#8391A3", roughness=0.55,
                      metallic=0.3)
    trim = pk.mat("PK_Trim")
    wheel_mat = pk.mat("PK_Dry3")
    stain_a = pk.mat("PK_Dry4")
    stain_b = pk.mat("PK_Dry1")

    PY = -0.15          # pipe axis: 0.15 m off the wall, at height 0
    R = 0.12
    pk.cyl("Pipe", R, 3.84, loc=(0, PY, 0), rot=(0, 90, 0), material=pipe_mat, verts=12,
           parent_obj=root)
    for i, x in enumerate((-1.96, 1.96)):
        pk.cyl("Flange%d" % i, 0.148, 0.08, loc=(x, PY, 0), rot=(0, 90, 0), material=trim,
               verts=10, parent_obj=root)
    pk.cyl("Coupling", 0.14, 0.12, loc=(-0.35, PY, 0), rot=(0, 90, 0), material=trim,
           verts=10, parent_obj=root)

    # Brackets: a plate on the wall and a clamp collar around the pipe.
    for i, x in enumerate((-1.25, 1.25)):
        pk.box("BracketPlate%d" % i, (0.17, 0.03, 0.4), loc=(x, -0.015, 0), material=trim,
               bevel=0.012, segments=1, parent_obj=root)
        pk.cyl("BracketClamp%d" % i, 0.137, 0.08, loc=(x, PY, 0), rot=(0, 90, 0),
               material=trim, verts=10, parent_obj=root)

    # A valve on top of the pipe with a horizontal hand wheel.
    VX = 0.55
    pk.cyl("ValveBody", 0.075, 0.16, loc=(VX, PY, 0.16), material=pipe_mat, verts=8,
           parent_obj=root)
    pk.cyl("ValveStem", 0.035, 0.08, loc=(VX, PY, 0.27), material=trim, verts=6,
           parent_obj=root)
    pk.torus("ValveWheel", 0.11, 0.024, loc=(VX, PY, 0.29), material=wheel_mat, segments=10,
             ring_segments=4, parent_obj=root)
    for i, angle in enumerate((0, 90)):
        pk.box("WheelSpoke%d" % i, (0.22, 0.03, 0.03), loc=(VX, PY, 0.29), rot=(0, 0, angle),
               material=wheel_mat, parent_obj=root)

    # Dried runoff stains down the wall below the pipe (flat, on the wall).
    def stain(cx, top, width, tongues):
        pts = [(cx - width * 0.5, top), (cx - width * 0.5 + 0.01, top - 0.18)]
        for i, (dx, length, w) in enumerate(tongues):
            x = cx + dx
            pts += [(x - w * 0.5, -length + w * 0.7), (x - w * 0.15, -length),
                    (x + w * 0.3, -length + 0.02), (x + w * 0.5, -length + w * 0.9)]
            if i < len(tongues) - 1:
                nx = cx + tongues[i + 1][0]
                pts.append(((x + nx) * 0.5, -0.24 - 0.04 * i))
        pts += [(cx + width * 0.5, top - 0.14), (cx + width * 0.5, top)]
        return pts

    flat_shape("StainA", stain(-0.8, -0.05, 0.4, [(-0.13, 0.62, 0.08), (0.0, 0.85, 0.09),
                                                  (0.13, 0.48, 0.07)]),
               stain_a, offset=-0.004, parent_obj=root)
    flat_shape("StainB", stain(1.55, -0.05, 0.3, [(-0.08, 0.5, 0.08), (0.08, 0.7, 0.08)]),
               stain_b, offset=-0.004, parent_obj=root)


# ---------------------------------------------------------------------------
# 8. Palette inlay - a 5.5 m flat wooden palette with paint dollops
# ---------------------------------------------------------------------------

def build_palette_inlay():
    root = pk.empty("PaletteInlay")
    wood = pk.mat("PK_Wood")
    THICK = 0.02

    def ellipse_r(a, b, th):
        return a * b / math.sqrt((b * math.cos(th)) ** 2 + (a * math.sin(th)) ** 2)

    def angle_gap(a, b):
        return (a - b + math.pi) % TAU - math.pi

    # Kidney outline: an oval with a thumb notch bitten out of the left side.
    NOTCH = math.radians(192)
    outer = []
    for j in range(48):
        # Uneven spacing: points bunch up around the notch so it stays round.
        u = -math.pi + TAU * j / 48
        th = NOTCH + u - 0.5 * math.sin(u)
        r = ellipse_r(2.75, 2.0, th)
        r *= 1.0 + 0.05 * math.cos(th) - 0.035 * math.cos(2 * (th - 0.4))
        r *= 1.0 - 0.3 * math.exp(-(angle_gap(th, NOTCH) / 0.2) ** 2)
        outer.append(Vector((r * math.cos(th), r * math.sin(th), 0.0)))
    hole_c = Vector((1.38 * math.cos(NOTCH), 1.38 * math.sin(NOTCH), 0.0))
    hole = [hole_c + Vector((0.27 * math.cos(TAU * j / 10), 0.21 * math.sin(TAU * j / 10), 0.0))
            for j in range(10)]

    # Scale to 5.5 m across and centre the outline on the origin.
    xs = [p.x for p in outer]
    ys = [p.y for p in outer]
    k = 5.5 / (max(xs) - min(xs))
    off = Vector(((max(xs) + min(xs)) * 0.5, (max(ys) + min(ys)) * 0.5, 0.0))
    outer = [(p - off) * k for p in outer]
    hole = [(p - off) * k for p in hole]

    no, nh = len(outer), len(hole)
    verts = [(p.x, p.y, 0.0) for p in outer] + [(p.x, p.y, THICK) for p in outer]
    verts += [(p.x, p.y, 0.0) for p in hole] + [(p.x, p.y, THICK) for p in hole]
    top_outer = [no + j for j in range(no)]
    top_hole = [2 * no + nh + j for j in range(nh)]
    faces = []
    # Top: the outline with a hole, cut into triangles.
    for tri in geometry.tessellate_polygon([[tuple(p) for p in outer], [tuple(p) for p in hole]]):
        idx = [top_outer[t] if t < no else top_hole[t - no] for t in tri]
        a, b, c = (Vector(verts[i]) for i in idx)
        if (b - a).cross(c - a).z < 0.0:
            idx.reverse()
        faces.append(tuple(idx))
    # Edge walls (no underside: it lies on the platform).
    for j in range(no):
        j2 = (j + 1) % no
        faces.append((j, j2, no + j2, no + j))
    base_h = 2 * no
    for j in range(nh):
        j2 = (j + 1) % nh
        faces.append((base_h + j, base_h + nh + j, base_h + nh + j2, base_h + j2))
    mesh_obj("Palette", verts, faces, [wood], parent_obj=root)

    # Dollops of dried paint around the rim, each a low dome.
    rng = random.Random(8)
    paints = [pk.mat("PK_Dry1"), pk.mat("PK_Dry2"), pk.mat("PK_Dry3"), pk.mat("PK_Dry4"),
              pk.mat("PK_Canvas", name="PK_DryWhite", color="#E4DED2", roughness=0.85),
              pk.mat("PK_Dark", name="PK_DryInk", color="#4D5170", roughness=0.85)]
    spots = [(1.65, 1.05, 0.42), (0.35, 1.45, 0.38), (-1.1, 1.25, 0.36),
             (1.9, -0.35, 0.4), (0.75, -1.3, 0.44), (-0.75, -1.2, 0.34)]
    for i, (x, y, r) in enumerate(spots):
        ring = wobbly_outline(x, y, r, r * rng.uniform(0.75, 0.95), 11, rng, 0.07,
                              phase=rng.uniform(0, TAU))
        n = len(ring)
        dv = [(px, py, THICK) for px, py in ring] + [(px, py, THICK + 0.01) for px, py in ring]
        dv.append((x, y, THICK + 0.016))
        df = [(n + j, n + (j + 1) % n, 2 * n) for j in range(n)]
        df += [(j, (j + 1) % n, n + (j + 1) % n, n + j) for j in range(n)]
        mesh_obj("Dollop%d" % i, dv, df, [paints[i]], parent_obj=root)


# ---------------------------------------------------------------------------
# 9. Hub mobile - a hoop hung from one point with five twisted paint ribbons
# ---------------------------------------------------------------------------

def build_hub_mobile():
    root = pk.empty("HubMobile")
    trim = pk.mat("PK_Trim")
    dark = pk.mat("PK_Dark")
    colours = [pk.mat("PK_Dry1"), pk.mat("PK_Dry2"), pk.mat("PK_Dry3"), pk.mat("PK_Dry4"),
               pk.mat("PK_Dry1", name="PK_DryRose", color="#B88A95", roughness=0.85)]

    RING_Z, RING_R = -0.62, 1.25
    pk.cyl("Hanger", 0.06, 0.12, loc=(0, 0, -0.06), material=trim, verts=8, bevel=0.015,
           parent_obj=root)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        rod("Cable%d" % k, (0, 0, -0.1), (RING_R * math.cos(a), RING_R * math.sin(a), RING_Z + 0.04),
            0.018, 6, dark, parent_obj=root)
    pk.torus("Ring", RING_R, 0.065, loc=(0, 0, RING_Z), material=trim, segments=28,
             ring_segments=6, parent_obj=root)

    # Each ribbon: (start angle, drop, flare outward, swirl, twist turns, width)
    specs = [(10, 1.45, 0.74, 25, 1.0, 0.36), (82, 1.2, 0.66, -20, 0.75, 0.32),
             (154, 1.5, 0.72, 30, 1.25, 0.34), (226, 1.1, 0.64, -25, 0.9, 0.36),
             (298, 1.35, 0.7, 20, 1.1, 0.33)]
    STEPS = 20
    THICK = 0.03
    for k, (start, drop, flare, swirl, turns, wmax) in enumerate(specs):
        path, widths = [], []
        for i in range(STEPS + 1):
            t = i / STEPS
            a = math.radians(start + swirl * t)
            r = RING_R + flare * t ** 1.5
            path.append(Vector((r * math.cos(a), r * math.sin(a), RING_Z + 0.04 - drop * t)))
            widths.append(0.03 + (wmax - 0.03) * max(0.0, math.sin(math.pi * (0.25 + 0.75 * t))) ** 0.8)
        verts, faces = [], []
        for i, p in enumerate(path):
            tangent = (path[min(i + 1, STEPS)] - path[max(i - 1, 0)]).normalized()
            radial = Vector((p.x, p.y, 0.0)).normalized()
            n = (radial - tangent * radial.dot(tangent)).normalized()
            b = tangent.cross(n)
            twist = TAU * turns * i / STEPS
            wdir = b * math.cos(twist) + n * math.sin(twist)
            ddir = -b * math.sin(twist) + n * math.cos(twist)
            w, d = widths[i] * 0.5, THICK * 0.5
            verts += [p + wdir * w + ddir * d, p - wdir * w + ddir * d,
                      p - wdir * w - ddir * d, p + wdir * w - ddir * d]
        for i in range(STEPS):
            for c in range(4):
                c2 = (c + 1) % 4
                faces.append((i * 4 + c, i * 4 + c2, (i + 1) * 4 + c2, (i + 1) * 4 + c))
        last = STEPS * 4
        faces += [(3, 2, 1, 0), (last, last + 1, last + 2, last + 3)]
        obj = mesh_obj("Ribbon%d" % k, verts, faces, [colours[k]], parent_obj=root, recalc=True)
        length = sum((path[i + 1] - path[i]).length for i in range(STEPS))
        print("[props]    %s length %.2f m" % (obj.name, length))


# ---------------------------------------------------------------------------
# 10. Splat decor - four flat dried paint splats
# ---------------------------------------------------------------------------

def build_splat_decor():
    root = pk.empty("SplatDecor")
    THICK = 0.008
    targets = [0.7, 0.85, 1.0, 1.15]     # overall size across, satellites included
    for k in range(4):
        rng = random.Random(100 + k * 17)
        material = pk.mat("PK_Dry%d" % (k + 1))
        n = 24

        # Split the circle into 6-7 lobes of uneven width. Each lobe bulges
        # out by its own amount; one or two become long splash fingers.
        count = rng.randint(6, 7)
        cuts = sorted(rng.uniform(0, TAU) for _ in range(count))
        widths = [(cuts[(i + 1) % count] - cuts[i]) % TAU for i in range(count)]
        heights = [rng.uniform(0.12, 0.34) for _ in range(count)]
        for f in rng.sample(range(count), 2):
            heights[f] = rng.uniform(0.45, 0.65) if widths[f] < 1.2 else heights[f]

        def radius(th):
            for i in range(count):
                phase = ((th - cuts[i]) % TAU) / widths[i]
                if phase <= 1.0:
                    return 0.55 + heights[i] * math.sin(math.pi * phase) ** 0.8
            return 0.55

        start_angle = rng.uniform(0, TAU)
        outline = []
        for j in range(n):
            th = start_angle + TAU * j / n + rng.uniform(-0.05, 0.05)
            outline.append((radius(th) * math.cos(th), radius(th) * math.sin(th)))
        # Three satellite drops flung past the tips of the three biggest
        # lobes, tails pointing back at the splat and never touching it.
        drops = []
        for i in sorted(range(count), key=lambda i: -heights[i])[:3]:
            th = cuts[i] + widths[i] * rng.uniform(0.35, 0.65)
            size = rng.uniform(0.05, 0.08)
            dist = 0.55 + heights[i] + 2.2 * size + rng.uniform(0.05, 0.12)
            ux, uy = math.cos(th), math.sin(th)
            vx, vy = -uy, ux
            shape = [(-2.2, 0.0), (-0.2, -0.8), (0.9, -0.55), (0.9, 0.55), (-0.2, 0.8)]
            drops.append([(dist * ux + size * (a * ux + b * vx), dist * uy + size * (a * uy + b * vy))
                          for a, b in shape])
        # Fit to the target size, centred on the origin.
        pts = outline + [p for d in drops for p in d]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        scale = targets[k] / max(max(xs) - min(xs), max(ys) - min(ys))
        cx, cy = (max(xs) + min(xs)) * 0.5, (max(ys) + min(ys)) * 0.5

        def fit(p):
            return ((p[0] - cx) * scale, (p[1] - cy) * scale)

        outline = [fit(p) for p in outline]
        drops = [[fit(p) for p in d] for d in drops]
        verts = [(x, y, 0.0) for x, y in outline] + [(x, y, THICK) for x, y in outline]
        faces = [tuple(range(n, 2 * n))]
        faces += [(j, (j + 1) % n, n + (j + 1) % n, n + j) for j in range(n)]
        for d in drops:
            start = len(verts)
            verts += [(x, y, THICK) for x, y in d]
            faces.append(tuple(range(start, start + len(d))))
        mesh_obj("Decor_%d" % k, verts, faces, [material], parent_obj=root)


# ---------------------------------------------------------------------------
# The prop table and the build loop
# ---------------------------------------------------------------------------

WALL = 0.0
PROPS = [
    # key, builder, file, budget, seed, limits
    ("paint_tube", build_paint_tube, "prop_paint_tube.glb", 700, 1,
     dict(min=(-0.55, -0.35, 0.0), max=(0.55, WALL, 3.0))),
    ("giant_brush", build_giant_brush, "prop_giant_brush.glb", 900, 2,
     dict(min=(None, -0.35, 0.0), max=(None, WALL, 4.0))),
    ("can_stack", build_can_stack, "prop_can_stack.glb", 900, 3,
     dict(min=(-0.35, -0.35, 0.0), max=(0.35, 0.35, 0.95))),
    ("mixing_vat", build_mixing_vat, "prop_mixing_vat.glb", 900, 4,
     dict(min=(None, None, 0.0), max=(None, None, 1.4), rmax=0.375)),
    ("frame", build_frame, "prop_frame.glb", 600, 5,
     dict(min=(-1.2, -0.12, 0.0), max=(1.2, WALL, 1.6))),
    ("banner", build_banner, "prop_banner.glb", 300, 6,
     dict(min=(-0.6, -0.1, -3.0), max=(0.6, WALL, 0.0))),
    ("pipe_run", build_pipe_run, "prop_pipe_run.glb", 500, 7,
     dict(min=(-2.0, -0.3, None), max=(2.0, WALL, None))),
    ("palette_inlay", build_palette_inlay, "prop_palette_inlay.glb", 400, 8,
     dict(min=(-2.75, None, 0.0), max=(2.75, None, 0.04))),
    ("hub_mobile", build_hub_mobile, "prop_hub_mobile.glb", 1500, 9,
     dict(min=(-2.1, -2.1, -2.2), max=(2.1, 2.1, 0.0))),
    ("splat_decor", build_splat_decor, "prop_splat_decor.glb", 320, 10,
     dict(min=(-0.6, -0.6, 0.0), max=(0.6, 0.6, 0.01))),
]


def root_name(builder):
    return {
        build_paint_tube: "PaintTube", build_giant_brush: "GiantBrush",
        build_can_stack: "CanStack", build_mixing_vat: "MixingVat",
        build_frame: "PictureFrame", build_banner: "Banner", build_pipe_run: "PipeRun",
        build_palette_inlay: "PaletteInlay", build_hub_mobile: "HubMobile",
        build_splat_decor: "SplatDecor",
    }[builder]


def preview_top(png_path, size=520):
    """Extra top-down render for the flat props (after pk.preview set up the
    renderer, light and camera)."""
    scene = bpy.context.scene
    cam = scene.camera
    mins, maxs, _ = bounds()
    cam.data.ortho_scale = max(maxs.x - mins.x, maxs.y - mins.y) * 1.08
    cam.location = ((mins.x + maxs.x) * 0.5, (mins.y + maxs.y) * 0.5, maxs.z + 10.0)
    cam.rotation_euler = (0.0, 0.0, 0.0)
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.filepath = png_path
    bpy.ops.render.render(write_still=True)
    print("[props] top view %s" % png_path)


def main():
    opts = options()
    only = set(opts["only"].split(",")) if opts["only"] else None
    failed = []
    for key, builder, filename, budget, seed, limits in PROPS:
        if only and key not in only:
            continue
        _sheets.clear()
        _soft.clear()
        pk.begin(root_name(builder), seed=seed)
        builder()
        pk.smooth_all(35.0)
        for obj in pk.objects():
            if obj.name in _soft:
                soften(obj, _soft[obj.name])

        problems, mins, maxs, rmax = check_limits(limits)
        problems += check_normals() + check_materials()
        total, _ = pk.triangle_count()
        if total > budget:
            problems.append("%d triangles, over the %d budget" % (total, budget))
        size = maxs - mins
        print("[props] %s: %d tris, size %.3f x %.3f x %.3f m, x %.3f..%.3f y %.3f..%.3f "
              "z %.3f..%.3f, footprint radius %.3f" % (filename, total, size.x, size.y, size.z,
                                                       mins.x, maxs.x, mins.y, maxs.y, mins.z,
                                                       maxs.z, rmax))
        if key == "splat_decor":
            for obj in pk.objects():
                if obj.type == "MESH":
                    a, b, _ = bounds([obj])
                    print("[props]    %s %.3f x %.3f x %.4f m" % (obj.name, b.x - a.x, b.y - a.y,
                                                                b.z - a.z))
        if problems:
            for p in problems:
                print("[props] PROBLEM %s: %s" % (filename, p))
            failed.append(filename)
            continue
        # Props never animate, so each exports as ONE mesh node: far fewer
        # nodes and draw calls in the arena (the splat decor keeps its four
        # separate variants, which Godot picks between).
        if key != "splat_decor":
            pk.merge_all(root_name(builder) + "Mesh")
        pk.export(filename, budget=budget)

        if opts["previews"]:
            os.makedirs(opts["previews"], exist_ok=True)
            if key == "splat_decor":
                # The four variants all sit on the origin; spread them out
                # for the picture only (the GLB is already written).
                for i, obj in enumerate(o for o in pk.objects() if o.type == "MESH"):
                    obj.location.x += (i - 1.5) * 1.3
            png = os.path.join(opts["previews"], filename.replace(".glb", ".png"))
            pk.preview(png)
            if key in ("palette_inlay", "splat_decor"):
                preview_top(png.replace(".png", "_top.png"))

    if failed:
        print("[props] FAILED: %s" % ", ".join(failed))
        sys.exit(1)
    print("[props] all props built")


main()
