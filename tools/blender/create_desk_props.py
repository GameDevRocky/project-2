"""
Desk dressing props - set-dressing models for the "top of a giant artist's
desk" arena, where the players are tiny and the art supplies are huge.

Like create_arena_props.py, this script builds SEVERAL assets in one run. For
each prop it starts a fresh scene (pk.begin), runs that prop's builder, checks
the result against the placement rules, and exports one GLB into
models/generated/:

    prop_crayon_cluster.glb  CrayonCluster   crayons poking out of a 2.4 m pillar
    prop_pinned_sheet.glb    PinnedSheets    four pinned sketch sheets Sheet_0..3
    prop_tape_strip.glb      TapeStrip       a 6 m strip of painter's tape

These are pure DECORATION: Godot never gives them collision, so each one must
stay inside exact size limits. Every limit below is checked with numbers, and a
prop that breaks one is NOT exported (the script exits with an error instead).

Placement conventions (all units are metres, Blender is Z-up):

  * CrayonCluster: the origin is the centre of the pillar's TOP face (z = 0).
    The crayons stand in the open top of the box-shaped 2.4 x 2.4 m pillar and
    reach 0.27 m down into it, so they look pushed in. Everything stays inside
    x, y in [-1.15, 1.15]. A flat dark square just above z = 0 is the open
    box's shadowy inside, seen between the crayons.
  * PinnedSheets: WALL-MOUNTED. The wall is the plane y = 0. Each sheet's back
    face lies on it, the sheet sticks out toward Blender -Y (Godot +Z, into
    the room), and its origin is the bottom centre of that back face. The four
    variants all sit on the same origin; Godot shows one of them.
  * TapeStrip: lies flat on the desk (the XY plane), bottom at z = 0, origin
    at its centre. It has no underside, because nothing ever sees it.

Materials are matte studio colours only. Nothing here uses the gameplay roles
(PK_Accent, PK_Team, PK_Fill, PK_Wet...) or their colours, and nothing glows.

Run (from the project folder):
    blender -b --factory-startup --python-exit-code 1 --python tools/blender/create_desk_props.py
Options after a bare "--":
    --only crayon_cluster,tape_strip   build only these props (keys from PROPS)
    --previews DIR                     also render preview pictures into DIR
"""

import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

TAU = math.tau

# Materials a decoration prop may never use: Godot swaps these for gameplay
# colours at runtime, or they glow.
RESERVED_MATERIALS = {"PK_Accent", "PK_AccentGlow", "PK_Team", "PK_TeamGlow", "PK_Fill", "PK_Wet"}
# Archetype, team and UI colours: set dressing must never be mistaken for them.
RESERVED_COLOURS = ["#FFB7C5", "#98FF98", "#00A896", "#2B2D42", "#FFFFFF", "#FF627E", "#58D7F2"]

# Dusty art-supply colours shared by the props.
STUDIO = {
    "Ochre": "#C9A45C",
    "Lilac": "#9C8FC4",
    "Clay": "#B7806E",
    "SeaGlass": "#7FA9A3",
    "DustyBlue": "#6D8FB5",
    "Terracotta": "#D98C6B",
    "Olive": "#8FB06E",
    "Rose": "#C7798F",
    "Slate": "#5C5876",
}
GRAPHITE = "#4A4560"     # pencil lines, crayon wrapper stripes, the box's dark inside
PAPER = "#EFE7D6"        # off-white sketch paper


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
    return opts


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

def make_mesh(name, verts, faces, mats, face_mats=None, face_dirs=None, parent_obj=None):
    """Build a mesh object straight from vertex and face lists.

    face_mats gives each face an index into `mats`. face_dirs gives each face
    the direction it must face (a vector); any face pointing the other way is
    flipped, so the outside of every surface is the side players see."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(float(c) for c in v) for v in verts], [], [tuple(f) for f in faces])
    for m in mats:
        mesh.materials.append(m)
    if face_mats is not None:
        assert len(face_mats) == len(mesh.polygons), name
        for poly, index in zip(mesh.polygons, face_mats):
            poly.material_index = index
    if face_dirs is not None:
        assert len(face_dirs) == len(mesh.polygons), name
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bm.normal_update()
        bm.faces.ensure_lookup_table()
        for face, want in zip(bm.faces, face_dirs):
            if face.normal.dot(Vector(want)) < 0.0:
                face.normal_flip()
        bm.to_mesh(mesh)
        bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    pk._collection.objects.link(obj)  # the working collection pk.begin() made
    if parent_obj is not None:
        pk.parent(obj, parent_obj)
    return obj


def lathe_loft(profile, n, phase=0.0):
    """Spin a (radius, height) profile around the local Z axis into rings and
    skin them. Radius 0 is a pole (a closed tip). Points run counter-clockwise
    seen from +Z, so every face already points outward.

    Returns (verts, faces, band_of_face, ring_starts)."""
    verts, starts = [], []
    for r, z in profile:
        starts.append((len(verts), 1 if r <= 1e-9 else n))
        if r <= 1e-9:
            verts.append(Vector((0.0, 0.0, z)))
        else:
            for j in range(n):
                a = phase + TAU * j / n
                verts.append(Vector((r * math.cos(a), r * math.sin(a), z)))
    faces, bands = [], []
    for i in range(len(profile) - 1):
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
            bands.append(i)
    return verts, faces, bands, starts


def mark_sharp_rings(obj, ring_vertex_sets):
    """Mark the edges running around the given rings as sharp creases."""
    mesh = obj.data
    attr = mesh.attributes.get("sharp_edge")
    if attr is None:
        attr = mesh.attributes.new("sharp_edge", "BOOLEAN", "EDGE")
    for edge in mesh.edges:
        a, b = edge.vertices
        for ring in ring_vertex_sets:
            if a in ring and b in ring:
                attr.data[edge.index].value = True


def shade(obj, angle):
    """Smooth shading, keeping edges sharper than `angle` (and any edges
    already marked sharp) crisp."""
    pk.select_only(obj)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle), keep_sharp_edges=True)


def ribbon(pts, widths, closed=False):
    """A flat 2D stroke of quads along a centre line: returns (verts, faces).
    widths gives the full width at each point."""
    n = len(pts)
    left, right = [], []
    for i, (x, z) in enumerate(pts):
        if closed:
            x0, z0 = pts[(i - 1) % n]
            x1, z1 = pts[(i + 1) % n]
        else:
            x0, z0 = pts[max(i - 1, 0)]
            x1, z1 = pts[min(i + 1, n - 1)]
        tx, tz = x1 - x0, z1 - z0
        length = math.hypot(tx, tz) or 1.0
        nx, nz = -tz / length, tx / length
        w = widths[i] * 0.5
        left.append((x + nx * w, z + nz * w))
        right.append((x - nx * w, z - nz * w))
    verts = right + left
    count = n if closed else n - 1
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(count)]
    return verts, faces


def scribble(x0, x1, z, points, amp, rng, slope=0.0):
    """A zig-zag line that reads as hand-written notes from a distance."""
    pts = []
    for i in range(points):
        t = i / (points - 1)
        x = x0 + (x1 - x0) * t
        if 0 < i < points - 1:
            x += rng.uniform(-0.015, 0.015)
        swing = (amp if i % 2 else -amp) * rng.uniform(0.6, 1.0)
        pts.append((x, z + slope * (x - x0) + swing + rng.uniform(-0.008, 0.008)))
    return pts


def ngon(cx, cz, rx, rz, n, rot=0.0, rng=None, wobble=0.0):
    pts = []
    for j in range(n):
        a = rot + TAU * j / n
        k = 1.0 + (rng.uniform(-wobble, wobble) if rng else 0.0)
        pts.append((cx + rx * k * math.cos(a), cz + rz * k * math.sin(a)))
    return pts


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def mesh_world_verts(obj):
    bpy.context.view_layer.update()
    mw = obj.matrix_world
    return [mw @ v.co for v in obj.data.vertices]


def bounds(objs=None):
    """World-space bounding box of the meshes."""
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for obj in objs or pk.objects():
        if obj.type != "MESH":
            continue
        for w in mesh_world_verts(obj):
            mins = Vector(map(min, mins, w))
            maxs = Vector(map(max, maxs, w))
    return mins, maxs


# Objects that are deliberately one-sided flat sheets. make_mesh already
# turned every one of their faces the way it must face, and a flat sheet has
# no 'outside' in the other direction, so check_normals skips them.
FLAT_SHEETS = {"BoxOpening"}


def check_normals():
    """Catch inside-out faces: the outermost faces of a shape in each axis
    direction must point outward."""
    bpy.context.view_layer.update()
    problems = []
    for obj in pk.objects():
        if obj.type != "MESH" or obj.name in FLAT_SHEETS:
            continue
        mw = obj.matrix_world
        normal_mat = mw.to_3x3().inverted().transposed()
        faces = [(mw @ p.center, (normal_mat @ p.normal).normalized()) for p in obj.data.polygons]
        if not faces:
            continue
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
    """No reserved roles or colours, nothing glowing, everything matte."""
    problems = []
    reserved = [pk.linear(h) for h in RESERVED_COLOURS]
    seen = set()
    for obj in pk.objects():
        if obj.type != "MESH":
            continue
        for m in obj.data.materials:
            if m is None or m.name in seen:
                continue
            seen.add(m.name)
            if m.name in RESERVED_MATERIALS:
                problems.append("%s uses reserved material %s" % (obj.name, m.name))
            bsdf = m.node_tree.nodes["Principled BSDF"]
            colour = tuple(bsdf.inputs["Base Color"].default_value)
            for hex_colour, r in zip(RESERVED_COLOURS, reserved):
                if all(abs(a - b) < 1e-4 for a, b in zip(colour[:3], r[:3])):
                    problems.append("%s uses the reserved colour %s" % (m.name, hex_colour))
            if bsdf.inputs["Emission Strength"].default_value > 0.0 and \
                    max(bsdf.inputs["Emission Color"].default_value[:3]) > 0.0:
                problems.append("%s is emissive" % m.name)
            if bsdf.inputs["Metallic"].default_value > 0.0:
                problems.append("%s is metallic (decor must be matte)" % m.name)
            if bsdf.inputs["Roughness"].default_value < 0.5:
                problems.append("%s is glossy (roughness %.2f < 0.5)" % (
                    m.name, bsdf.inputs["Roughness"].default_value))
    return problems


def check_transforms():
    """Every node must have scale exactly 1 (Godot must never see a squashed
    node), and no mesh may carry a hidden rotation."""
    problems = []
    for obj in pk.objects():
        if any(abs(s - 1.0) > 1e-6 for s in obj.scale):
            problems.append("%s has scale %s" % (obj.name, tuple(obj.scale)))
        if any(abs(a) > 1e-6 for a in obj.rotation_euler):
            problems.append("%s has rotation %s" % (obj.name, tuple(obj.rotation_euler)))
    return problems


def limit(problems, label, value, lo=None, hi=None, eps=1e-4):
    """Record a problem if value is outside [lo, hi]."""
    if lo is not None and value < lo - eps:
        problems.append("%s = %.4f, below the limit %.4f" % (label, value, lo))
    if hi is not None and value > hi + eps:
        problems.append("%s = %.4f, above the limit %.4f" % (label, value, hi))


# ---------------------------------------------------------------------------
# 1. Crayon cluster - 12 giant crayons standing in the open top of a pillar
# ---------------------------------------------------------------------------

CRAYON_BOTTOM = -0.27    # how far the crayons reach down into the box
WRAPPER_PROUD = 0.012    # the paper wrapper sits this far out from the wax
TIP_LENGTH = 0.28        # the sharpened cone
BARE_WAX = 0.075         # bare wax between the wrapper and the cone
OPENING_HALF = 1.1       # half-size of the dark open-box square
OPENING_Z = 0.01

# Three rows (y) by four columns (x). Each crayon: (colour, axial length from
# z = 0 to the tip, tilt in degrees, lean direction in degrees from +X).
CRAYON_ROWS_Y = (-0.66, 0.0, 0.66)
CRAYON_COLS_X = (-0.81, -0.27, 0.27, 0.81)
CRAYON_GRID = [
    [("Ochre", 0.96, 4, 225), ("Lilac", 1.30, 3, 262), ("Clay", 0.68, 0, 0),
     ("SeaGlass", 1.12, 5, 300)],
    [("DustyBlue", 1.22, 5, 178), ("Terracotta", 1.46, 0, 0), ("Olive", 1.02, 2, 35),
     ("Rose", 0.82, 6, 2)],
    [("Lilac", 0.62, 0, 0), ("Slate", 1.18, 4, 98), ("Ochre", 1.37, 3, 72),
     ("SeaGlass", 0.90, 4, 40)],
]


def make_crayon(name, base, r_wax, length, tilt, lean, wax, ink):
    """One crayon around its own axis: a wrapped body with a graphite stripe,
    a short band of bare wax, a sharpened cone and a small flat-ish tip.
    `base` is where the axis crosses z = 0; the crayon tilts about that point.
    10 sides, 130 triangles (the hidden bottom inside the box stays open)."""
    r_wrap = r_wax + WRAPPER_PROUD
    tip_end = length - 0.014
    cone_start = tip_end - TIP_LENGTH
    wrap_top = cone_start - BARE_WAX
    stripe_hi = wrap_top - 0.075
    stripe_lo = stripe_hi - 0.075
    profile = [
        (r_wrap, CRAYON_BOTTOM),
        (r_wrap, stripe_lo),
        (r_wrap, stripe_hi),
        (r_wrap, wrap_top),
        (r_wax, wrap_top),          # the step where the paper ends
        (r_wax, cone_start),
        (r_wax * 0.4, tip_end),
        (0.0, length),
    ]
    assert all(profile[i][1] < profile[i + 1][1] or i == 3 for i in range(len(profile) - 1)), name
    verts, faces, bands, starts = lathe_loft(profile, 10, phase=random.uniform(0, TAU))
    # Band 1 is the graphite stripe; the rest is the crayon's own colour.
    face_mats = [1 if b == 1 else 0 for b in bands]

    phi = math.radians(lean)
    axis = Vector((-math.sin(phi), math.cos(phi), 0.0))
    rot = Matrix.Rotation(math.radians(tilt), 3, axis)
    origin = Vector((base[0], base[1], 0.0))
    world = [origin + rot @ v for v in verts]
    obj = make_mesh(name, world, faces, [wax, ink], face_mats)
    # Crisp edges at the cone's shoulder and where the cone meets the tip.
    rings = [set(range(starts[i][0], starts[i][0] + starts[i][1])) for i in (5, 6)]
    mark_sharp_rings(obj, rings)
    return obj, dict(name=name, base=origin, axis=rot @ Vector((0, 0, 1)), length=length,
                     r_wax=r_wax, r_wrap=r_wrap, tilt=tilt, obj=obj)


def build_crayon_cluster():
    root = pk.empty("CrayonCluster")
    ink = pk.mat("PK_Dark", name="PK_CrayonInk", color=GRAPHITE, roughness=0.9)
    rng = random.Random(41)
    crayons = []
    for r, row in enumerate(CRAYON_GRID):
        for c, (colour, length, tilt, lean) in enumerate(row):
            wax = pk.mat("PK_Dry1", name="PK_Crayon" + colour, color=STUDIO[colour], roughness=0.75)
            base = (CRAYON_COLS_X[c] + rng.uniform(-0.03, 0.03),
                    CRAYON_ROWS_Y[r] + rng.uniform(-0.03, 0.03))
            obj, info = make_crayon("Crayon_%d_%d" % (r, c), base, rng.uniform(0.17, 0.177),
                                    length, tilt, lean, wax, ink)
            shade(obj, 50.0)
            pk.parent(obj, root)
            crayons.append(info)

    # The open box's dark inside, seen in the gaps between the crayons.
    h = OPENING_HALF
    opening = make_mesh("BoxOpening", [(-h, -h, OPENING_Z), (h, -h, OPENING_Z), (h, h, OPENING_Z),
                                       (-h, h, OPENING_Z)], [(0, 1, 2, 3)], [ink],
                        face_dirs=[(0, 0, 1)])
    pk.parent(opening, root)
    return dict(crayons=crayons)


def check_crayon_cluster(info):
    problems = []
    crayons = info["crayons"]
    limit(problems, "crayon count", len(crayons), 9, 12)
    tilted = 0
    for cr in crayons:
        tip_z = max(v.z for v in mesh_world_verts(cr["obj"]))
        low_z = min(v.z for v in mesh_world_verts(cr["obj"]))
        limit(problems, cr["name"] + " tip height", tip_z, 0.5, 1.5)
        limit(problems, cr["name"] + " bottom", low_z, -0.3, None)
        limit(problems, cr["name"] + " wax diameter", 2 * cr["r_wax"], 0.32, 0.38)
        limit(problems, cr["name"] + " wrapper diameter", 2 * cr["r_wrap"], 0.32, 0.38)
        limit(problems, cr["name"] + " tilt", cr["tilt"], 0.0, 8.0)
        tilted += cr["tilt"] > 0.5
    if tilted < 3:
        problems.append("only %d crayons are tilted" % tilted)
    # No two crayons may pass through each other above the box (sampled along
    # both axes, using the wider wrapper radius everywhere to be safe).
    for i in range(len(crayons)):
        for j in range(i + 1, len(crayons)):
            a, b = crayons[i], crayons[j]
            pa = [a["base"] + a["axis"] * (a["length"] * k / 40.0) for k in range(41)]
            pb = [b["base"] + b["axis"] * (b["length"] * k / 40.0) for k in range(41)]
            gap = min((p - q).length for p in pa for q in pb) - a["r_wrap"] - b["r_wrap"]
            if gap < 0.01:
                problems.append("%s and %s are only %.3f m apart" % (a["name"], b["name"], gap))
    mins, maxs = bounds()
    for axis, label in ((0, "x"), (1, "y")):
        limit(problems, "footprint %s min" % label, mins[axis], -1.15, None)
        limit(problems, "footprint %s max" % label, maxs[axis], None, 1.15)
    limit(problems, "lowest point z", mins.z, -0.3, None)
    limit(problems, "highest point z", maxs.z, None, 1.5)
    return problems


# ---------------------------------------------------------------------------
# 2. Pinned sheets - four giant sketch sheets pushpinned to a wall
# ---------------------------------------------------------------------------

PAPER_T = 0.012          # paper thickness
CURL_SIZE = 0.62         # the curled corner region, measured from the corner
CURL_LIFT = 0.10         # how far the very corner lifts off the wall (back face)
PIN_DROP = 0.25          # pin centre below the sheet's top edge
# Sketch layers: distance in front of the paper's face. Higher layers sit on
# top of lower ones, a millimetre or so apart so overlaps never flicker.
FILL, LINE, DETAIL, TOP = 0.003, 0.0045, 0.006, 0.0075
INK_MAX = 0.01           # strokes may stand at most this far off the paper
# Pushpin profile: (radius, distance from the wall). The first ring starts
# just inside the paper; the base disc, a narrow grip and a top flange.
PIN_PROFILE = [(0.175, 0.010), (0.175, 0.045), (0.08, 0.07), (0.068, 0.16),
               (0.125, 0.178), (0.125, 0.212), (0.0, 0.232)]


def make_paper(name, W, H, side, material):
    """The paper as a thin slab, 48 triangles. side +1 curls the
    bottom-right corner, -1 the bottom-left. Only the corner region bends;
    everywhere else the paper is perfectly flat, so the sketch strokes can
    float at an exact height above it. The back only exists where the corner
    lifts off the wall: anywhere else it is pressed flat against the wall,
    where nobody can ever see it."""
    hx = W * 0.5
    if side > 0:
        xs = [-hx, hx - CURL_SIZE, hx - CURL_SIZE * 0.5, hx]
    else:
        xs = [-hx, -hx + CURL_SIZE * 0.5, -hx + CURL_SIZE, hx]
    zs = [0.0, CURL_SIZE * 0.5, CURL_SIZE, H]

    def lift(x, z):
        u = min(1.0, max(0.0, (side * x - (hx - CURL_SIZE)) / CURL_SIZE))
        v = min(1.0, max(0.0, (CURL_SIZE - z) / CURL_SIZE))
        s = max(0.0, u + v - 1.0)
        return CURL_LIFT * s ** 1.6

    nx, nz = len(xs), len(zs)
    front = [[None] * nz for _ in range(nx)]
    back = [[None] * nz for _ in range(nx)]
    verts = []
    for i, x in enumerate(xs):
        for j, z in enumerate(zs):
            d = lift(x, z)
            front[i][j] = len(verts)
            verts.append((x, -(d + PAPER_T), z))
            back[i][j] = len(verts)
            verts.append((x, -d, z))
    faces, dirs = [], []
    for i in range(nx - 1):
        for j in range(nz - 1):
            faces.append((front[i][j], front[i + 1][j], front[i + 1][j + 1], front[i][j + 1]))
            dirs.append((0, -1, 0))
            quad = (back[i][j], back[i + 1][j], back[i + 1][j + 1], back[i][j + 1])
            if any(verts[q][1] < -1e-9 for q in quad):     # touches the lifted corner
                faces.append(quad)
                dirs.append((0, 1, 0))
    loop = [(i, 0) for i in range(nx)] + [(nx - 1, j) for j in range(1, nz)] + \
        [(i, nz - 1) for i in range(nx - 2, -1, -1)] + [(0, j) for j in range(nz - 2, 0, -1)]
    for k, (i, j) in enumerate(loop):
        i2, j2 = loop[(k + 1) % len(loop)]
        faces.append((front[i][j], front[i2][j2], back[i2][j2], back[i][j]))
        mx, mz = (xs[i] + xs[i2]) * 0.5, (zs[j] + zs[j2]) * 0.5
        dirs.append((mx, 0.0, mz - H * 0.5))       # outward from the sheet's centre
    obj = make_mesh(name, verts, faces, [material], face_dirs=dirs)
    curl_rect = ((hx - CURL_SIZE) if side > 0 else -hx, hx if side > 0 else -hx + CURL_SIZE,
                 0.0, CURL_SIZE)
    return obj, curl_rect


def make_pin(name, x, z, material):
    """A big push pin, lathed around an axis pointing out of the wall (132
    triangles). Built around +Z, then turned so +Z points at -Y (the room)."""
    verts, faces, _, starts = lathe_loft(PIN_PROFILE, 12)
    turn = Matrix.Rotation(math.radians(90), 3, "X")     # (x, y, z) -> (x, -z, y)
    world = [Vector((x, 0.0, z)) + turn @ v for v in verts]
    obj = make_mesh(name, world, faces, [material])
    shade(obj, 50.0)
    return obj


class Ink:
    """Draws one sheet's flat sketch strokes, floating just in front of the
    paper. Every stroke faces the room (-Y)."""

    def __init__(self, k):
        self.k = k
        self.objs = []

    def _mesh(self, verts2d, faces, material, layer):
        y = -(PAPER_T + layer)
        obj = make_mesh("Ink_%d_%d" % (self.k, len(self.objs)),
                        [(u, y, v) for u, v in verts2d], faces, [material],
                        face_dirs=[(0, -1, 0)] * len(faces))
        self.objs.append(obj)
        return obj

    def fill(self, pts, material, layer=FILL):
        return self._mesh(pts, [tuple(range(len(pts)))], material, layer)

    def line(self, pts, width, material, layer=LINE, closed=False, taper=0.6):
        widths = [width] * len(pts)
        if not closed:
            widths[0] *= taper
            widths[-1] *= taper
        verts, faces = ribbon(pts, widths, closed)
        return self._mesh(verts, faces, material, layer)

    def dot(self, cx, cz, rx, n, material, layer=DETAIL, rz=None, rot=0.0):
        return self.fill(ngon(cx, cz, rx, rz or rx, n, rot), material, layer)


def draw_monster(ink, m):
    """Variant 0: a doodled paint-splat monster with big eyes, a wobbly grin
    and two drips for legs, washed in lilac. Curl: bottom-right."""
    cx, cz = 0.0, 1.42
    body = [(0.66, 0.02), (0.62, 0.30), (0.44, 0.50), (0.20, 0.60), (-0.02, 0.55),
            (-0.22, 0.67), (-0.44, 0.50), (-0.62, 0.32), (-0.66, 0.08), (-0.80, -0.10),
            (-0.58, -0.26),
            # left drip: neck, round bead, neck
            (-0.42, -0.42), (-0.39, -0.60), (-0.45, -0.72), (-0.35, -0.83), (-0.25, -0.72),
            (-0.31, -0.60), (-0.26, -0.48),
            # right drip, longer
            (0.08, -0.54), (0.11, -0.76), (0.05, -0.90), (0.17, -1.02), (0.29, -0.90),
            (0.23, -0.76), (0.26, -0.54),
            (0.50, -0.40), (0.64, -0.20)]
    body = [(cx + x, cz + z) for x, z in body]
    ink.fill(body, m["Lilac"], FILL)
    ink.line(body, 0.05, m["graphite"], LINE, closed=True)
    # Eyes: paper-coloured ovals with graphite pupils glancing sideways.
    ink.dot(-0.20, 1.62, 0.15, 8, m["paper"], DETAIL, rz=0.17, rot=0.2)
    ink.dot(0.21, 1.67, 0.13, 8, m["paper"], DETAIL, rz=0.15, rot=0.1)
    ink.dot(-0.15, 1.60, 0.065, 6, m["graphite"], TOP)
    ink.dot(0.26, 1.645, 0.058, 6, m["graphite"], TOP)
    ink.line([(-0.25, 1.23), (-0.09, 1.15), (0.07, 1.21), (0.24, 1.13)], 0.045,
             m["graphite"], LINE)
    # Two flung paint drops.
    ink.dot(0.74, 2.12, 0.075, 5, m["Lilac"], FILL, rot=0.4)
    ink.dot(-0.86, 1.98, 0.05, 5, m["Lilac"], FILL, rot=1.1)


def draw_notes(ink, m, rng):
    """Variant 1: a heading, an underline, four bulleted lines of scribbled
    'notes' and a big curved arrow swooping down to a circled spot. No real
    letters. Curl: bottom-left."""
    g = m["graphite"]
    ink.line(scribble(-0.85, 0.30, 2.32, 9, 0.05, rng), 0.06, g)
    ink.line([(-0.88, 2.17), (-0.25, 2.14), (0.42, 2.16)], 0.04, g)
    for z, x_end in zip((1.95, 1.72, 1.49, 1.26), (0.55, 0.18, 0.68, 0.08)):
        ink.line(scribble(-0.78, x_end, z, 6, 0.03, rng, slope=-0.01), 0.04, g)
        ink.dot(-0.91, z, 0.035, 4, g, LINE, rot=math.pi / 4)
    arrow = [(0.74, 1.56), (0.84, 1.22), (0.74, 0.92), (0.50, 0.73), (0.22, 0.66)]
    ink.line(arrow, 0.065, g, taper=1.0)
    ink.fill([(0.03, 0.635), (0.26, 0.80), (0.25, 0.50)], g, DETAIL)    # arrowhead
    ink.line(ngon(-0.20, 0.78, 0.20, 0.155, 8, rot=0.3), 0.04, g, closed=True)
    ink.line([(-0.27, 0.71), (-0.13, 0.85)], 0.035, g)
    ink.line([(-0.27, 0.85), (-0.13, 0.71)], 0.035, g, DETAIL)


def draw_brush(ink, m):
    """Variant 2: a paintbrush sketched on the diagonal - clay handle, metal
    ferrule with crimp lines, a sea-glass tuft and paint flicked off the tip.
    Curl: bottom-right."""
    g = m["graphite"]
    p0, p1 = Vector((-0.62, 0.74)), Vector((0.50, 2.36))
    length = (p1 - p0).length
    a = (p1 - p0) / length
    n = Vector((-a.y, a.x))

    def at(t, s):
        p = p0 + a * (t * length) + n * s
        return (p.x, p.y)

    right = [at(0.0, -0.055), at(0.42, -0.085), at(0.6, -0.072), at(0.6, -0.10),
             at(0.77, -0.11), at(0.87, -0.145), at(0.95, -0.085)]
    left = [at(0.0, 0.055), at(0.42, 0.085), at(0.6, 0.072), at(0.6, 0.10),
            at(0.77, 0.11), at(0.87, 0.14), at(0.95, 0.09)]
    tip, cap = at(1.0, 0.01), at(-0.025, 0.0)
    ink.fill([cap, right[0], right[1], right[2], left[2], left[1], left[0]], m["Clay"], FILL)
    ink.fill([right[3], right[4], left[4], left[3]], m["Pewter"], FILL)
    ink.fill([right[4], right[5], right[6], tip, left[6], left[5], left[4]], m["SeaGlass"], FILL)
    outline = right + [tip] + left[::-1] + [cap]
    ink.line(outline, 0.04, g, closed=True)
    for t in (0.66, 0.71, 0.77):
        ink.line([at(t, -0.105), at(t, 0.105)], 0.03 if t < 0.75 else 0.035, g, taper=1.0)
    ink.line([at(0.80, -0.05), at(0.88, -0.07), at(0.96, -0.035)], 0.025, g)
    ink.line([at(0.80, 0.04), at(0.89, 0.06), at(0.965, 0.03)], 0.025, g)
    for t, s, r in ((1.08, 0.12, 0.05), (1.14, -0.09, 0.04), (1.21, 0.06, 0.03)):
        x, z = at(t, s)
        ink.dot(x, z, r, 5, m["SeaGlass"], FILL, rot=t * 3.0)


def draw_swatches(ink, m, rng):
    """Variant 3 (landscape): a hand-ruled colour-swatch chart, two rows of
    three painted squares with a scribbled label under each and a scribbled
    heading. Curl: bottom-left."""
    g = m["graphite"]
    cols = [-0.77, -0.07, 0.63, 1.33]
    rows = [0.25, 0.95, 1.65]
    for z in rows:
        tilt = rng.uniform(-0.012, 0.012)
        ink.line([(cols[0] - 0.04, z - tilt), (cols[-1] + 0.04, z + tilt)], 0.035, g, taper=1.0)
    for x in cols:
        lean = rng.uniform(-0.012, 0.012)
        ink.line([(x - lean, rows[0] - 0.04), (x + lean, rows[-1] + 0.04)], 0.035, g, DETAIL,
                 taper=1.0)
    colours = [["SeaGlass", "DustyBlue", "Rose"], ["Ochre", "Lilac", "Clay"]]
    for j in range(2):
        for i in range(3):
            cx = (cols[i] + cols[i + 1]) * 0.5
            cz = (rows[j] + rows[j + 1]) * 0.5
            sq = []
            for k in range(8):
                a = TAU * k / 8 + math.pi / 4
                reach = 0.29 if k % 2 == 0 else 0.215      # corners vs mid-edges
                sq.append((cx + reach * math.cos(a) + rng.uniform(-0.012, 0.012),
                           cz + 0.07 + reach * math.sin(a) + rng.uniform(-0.012, 0.012)))
            ink.fill(sq, m[colours[j][i]], FILL)
            ink.line(scribble(cx - 0.22, cx + 0.12, cz - 0.245, 4, 0.018, rng), 0.032, g)
    ink.line(scribble(-1.30, -0.42, 1.95, 7, 0.045, rng), 0.055, g)
    ink.line(scribble(-1.30, -0.80, 1.78, 5, 0.03, rng), 0.04, g)


SHEETS = [
    # width, height, curl side (+1 right, -1 left), pin colour, drawing
    (2.2, 3.0, +1, "Rose", "monster"),
    (2.2, 3.0, -1, "SeaGlass", "notes"),
    (2.2, 3.0, +1, "DustyBlue", "brush"),
    (3.0, 2.2, -1, "Ochre", "swatches"),
]


def build_pinned_sheets():
    root = pk.empty("PinnedSheets")
    m = {"paper": pk.mat("PK_Canvas", name="PK_SketchPaper", color=PAPER, roughness=0.95),
         "graphite": pk.mat("PK_Dark", name="PK_Graphite", color=GRAPHITE, roughness=0.9),
         "Pewter": pk.mat("PK_Body", name="PK_SketchPewter", color="#A8A3BB", roughness=0.8)}
    for key in ("Rose", "SeaGlass", "DustyBlue", "Ochre", "Lilac", "Clay"):
        m[key] = pk.mat("PK_Dry1", name="PK_Sketch" + key, color=STUDIO[key], roughness=0.8)
    rng = random.Random(77)
    sheets = []
    for k, (W, H, side, pin_colour, drawing) in enumerate(SHEETS):
        paper, curl_rect = make_paper("Paper_%d" % k, W, H, side, m["paper"])
        shade(paper, 30.0)
        pin = make_pin("Pin_%d" % k, 0.0, H - PIN_DROP, m[pin_colour])
        ink = Ink(k)
        if drawing == "monster":
            draw_monster(ink, m)
        elif drawing == "notes":
            draw_notes(ink, m, rng)
        elif drawing == "brush":
            draw_brush(ink, m)
        else:
            draw_swatches(ink, m, rng)
        record = dict(k=k, W=W, H=H, curl=curl_rect,
                      paper=mesh_world_verts(paper), pin=mesh_world_verts(pin),
                      ink=[v for o in ink.objs for v in mesh_world_verts(o)],
                      ink_normals=[p.normal.copy() for o in ink.objs for p in o.data.polygons])
        sheet = pk.join("Sheet_%d" % k, [paper, pin] + ink.objs)
        pk.parent(sheet, root)
        record["obj"] = sheet
        sheets.append(record)
    return dict(sheets=sheets)


def check_pinned_sheets(info):
    problems = []
    names = sorted(o.name for o in pk.objects() if o.type == "MESH")
    if names != ["Sheet_0", "Sheet_1", "Sheet_2", "Sheet_3"]:
        problems.append("sheet meshes are %s" % names)
    total = 0
    for s in info["sheets"]:
        tag = "Sheet_%d" % s["k"]
        obj = s["obj"]
        if obj.parent is None or obj.parent.name != "PinnedSheets":
            problems.append("%s is not under PinnedSheets" % tag)
        if obj.location.length > 1e-6:
            problems.append("%s origin is at %s, not the origin" % (tag, tuple(obj.location)))
        W, H = s["W"], s["H"]
        paper = s["paper"]
        # Paper size and placement: bottom centre of the back face on the origin.
        limit(problems, tag + " paper min x", min(v.x for v in paper), -W / 2, -W / 2)
        limit(problems, tag + " paper max x", max(v.x for v in paper), W / 2, W / 2)
        limit(problems, tag + " paper min z", min(v.z for v in paper), 0.0, 0.0)
        limit(problems, tag + " paper max z", max(v.z for v in paper), H, H)
        limit(problems, tag + " paper back (max y)", max(v.y for v in paper), 0.0, 0.0)
        limit(problems, tag + " paper thickness", PAPER_T, None, 0.03)
        curl = -min(v.y for v in paper)
        limit(problems, tag + " curl off the wall", curl, 0.03, 0.12)
        # Pushpin: ~0.35 m head, centred at the top, at most 0.25 m proud.
        pin = s["pin"]
        diameter = max(v.x for v in pin) - min(v.x for v in pin)
        limit(problems, tag + " pin head diameter", diameter, 0.30, 0.40)
        limit(problems, tag + " pin centre x", (max(v.x for v in pin) + min(v.x for v in pin)) / 2,
              0.0, 0.0, eps=1e-3)
        limit(problems, tag + " pin top z", max(v.z for v in pin), None, H)
        limit(problems, tag + " pin proud of the wall", -min(v.y for v in pin), None, 0.25)
        # Sketch strokes: flat, facing the room, at most INK_MAX off the paper,
        # on the flat part of the sheet (clear of the curl) and inside its edges.
        x0, x1, z0, z1 = s["curl"]
        for v in s["ink"]:
            off = -v.y - PAPER_T
            if not (0.0 < off <= INK_MAX + 1e-6):
                problems.append("%s stroke vertex %.4f m off the paper" % (tag, off))
                break
            if not (-W / 2 + 0.05 <= v.x <= W / 2 - 0.05 and 0.05 <= v.z <= H - 0.05):
                problems.append("%s stroke vertex %s too close to the edge" % (tag, tuple(v)))
                break
            if x0 - 0.03 <= v.x <= x1 + 0.03 and z0 <= v.z <= z1 + 0.03:
                problems.append("%s stroke vertex %s is on the curled corner" % (tag, tuple(v)))
                break
        if any(n.y > -0.999 for n in s["ink_normals"]):
            problems.append("%s has a stroke not facing the room" % tag)
        # Whole sheet stays within its footprint.
        mins, maxs = bounds([obj])
        limit(problems, tag + " max y", maxs.y, None, 0.0)
        limit(problems, tag + " min y", mins.y, -0.25, None)
        limit(problems, tag + " width", maxs.x - mins.x, None, W)
        limit(problems, tag + " height", maxs.z - mins.z, None, H)
        tris, _ = pk.triangle_count([obj])
        limit(problems, tag + " triangles", tris, None, 300)
        total += tris
    limit(problems, "total sheet triangles", total, None, 1200)
    return problems


# ---------------------------------------------------------------------------
# 3. Tape strip - 6 m of painter's tape with torn ends and soft wrinkles
# ---------------------------------------------------------------------------

TAPE_LEN, TAPE_WIDTH, TAPE_T = 6.0, 0.9, 0.02
WRINKLE_MAX = 0.02
TAPE_ROWS = (-0.45, -0.225, 0.0, 0.225, 0.45)
# Soft wrinkles: (centre x, slant (x per metre of y), half width, height, the
# edge it is strongest at). Each fades toward the other edge, like a crease
# that started where the tape was pulled.
WRINKLES = [(-1.55, 0.28, 0.075, 0.017, +1), (0.35, -0.22, 0.09, 0.020, -1),
            (1.85, 0.12, 0.07, 0.015, +1)]
# Torn ends: how far each point sits in from the very end of the tape. Rows
# are the teeth; the mid points between rows are the notches.
TORN_LEFT = ([0.03, 0.0, 0.05, 0.015, 0.06], [0.10, 0.075, 0.115, 0.09])
TORN_RIGHT = ([0.02, 0.055, 0.0, 0.04, 0.01], [0.085, 0.11, 0.07, 0.10])


def build_tape_strip():
    root = pk.empty("TapeStrip")
    tape = pk.mat("PK_Canvas", name="PK_PainterTape", color="#6C8FB0", roughness=0.85)
    half = TAPE_LEN * 0.5
    rows = TAPE_ROWS
    nr = len(rows)

    def fade(y, side):
        t = (y - rows[0]) / (rows[-1] - rows[0])
        return 0.25 + 0.75 * (t if side > 0 else 1.0 - t)

    verts = []
    # Interior columns: three per wrinkle (shoulder, ridge, shoulder), slanted.
    columns = []
    for x0, slant, hw, amp, side in WRINKLES:
        for k, off in enumerate((-hw, 0.0, hw)):
            col = []
            for y in rows:
                h = amp * fade(y, side) if k == 1 else 0.0
                col.append(len(verts))
                verts.append((x0 + off + slant * y, y, TAPE_T + h))
            columns.append(col)

    def torn_end(sign, offsets):
        teeth, notches = offsets
        col, mids = [], []
        for r, y in enumerate(rows):
            col.append(len(verts))
            verts.append((sign * (half - teeth[r]), y, TAPE_T))
        for r in range(nr - 1):
            mids.append(len(verts))
            y = (rows[r] + rows[r + 1]) * 0.5
            verts.append((sign * (half - notches[r]), y, TAPE_T))
        return col, mids

    left, left_mid = torn_end(-1, TORN_LEFT)
    right, right_mid = torn_end(+1, TORN_RIGHT)

    faces, dirs = [], []
    # Top: pentagons at the torn ends, quads between the interior columns.
    for r in range(nr - 1):
        faces.append((left[r], left_mid[r], left[r + 1], columns[0][r + 1], columns[0][r]))
        dirs.append((0, 0, 1))
        faces.append((columns[-1][r], columns[-1][r + 1], right[r + 1], right_mid[r], right[r]))
        dirs.append((0, 0, 1))
    for c in range(len(columns) - 1):
        for r in range(nr - 1):
            faces.append((columns[c][r], columns[c + 1][r], columns[c + 1][r + 1],
                          columns[c][r + 1]))
            dirs.append((0, 0, 1))
    # Sides: walk the outline (counter-clockwise from above) and drop a wall
    # from each top point to the desk.
    all_cols = [left] + columns + [right]
    outline = [col[0] for col in all_cols]
    for r in range(nr - 1):
        outline += [right_mid[r], right[r + 1]]
    outline += [col[-1] for col in reversed(all_cols[:-1])]
    for r in range(nr - 2, -1, -1):
        outline += [left_mid[r], left[r]]
    outline = outline[:-1]          # left[0] is already the first point
    bottom = {}
    for i in outline:
        x, y, _ = verts[i]
        bottom[i] = len(verts)
        verts.append((x, y, 0.0))
    for k, i in enumerate(outline):
        j = outline[(k + 1) % len(outline)]
        faces.append((i, j, bottom[j], bottom[i]))
        mx = (verts[i][0] + verts[j][0]) * 0.5
        my = (verts[i][1] + verts[j][1]) * 0.5
        dirs.append((mx, my, 0.0))          # outward from the tape's centre
    obj = make_mesh("Tape", verts, faces, [tape], face_dirs=dirs, parent_obj=root)
    shade(obj, 30.0)
    return dict(obj=obj)


def check_tape_strip(info):
    problems = []
    obj = info["obj"]
    if obj.name != "Tape" or obj.parent is None or obj.parent.name != "TapeStrip":
        problems.append("the mesh must be Tape under TapeStrip")
    if obj.location.length > 1e-6:
        problems.append("Tape origin is at %s" % tuple(obj.location))
    mins, maxs = bounds()
    limit(problems, "length", maxs.x - mins.x, TAPE_LEN, TAPE_LEN, eps=2e-3)
    limit(problems, "width", maxs.y - mins.y, TAPE_WIDTH, TAPE_WIDTH, eps=2e-3)
    limit(problems, "centre x", (maxs.x + mins.x) / 2, 0.0, 0.0, eps=0.03)
    limit(problems, "centre y", (maxs.y + mins.y) / 2, 0.0, 0.0, eps=1e-3)
    limit(problems, "bottom z", mins.z, 0.0, 0.0)
    top = [v.z for v in mesh_world_verts(obj) if v.z > 1e-4]
    limit(problems, "thinnest top", min(top), TAPE_T, TAPE_T)
    limit(problems, "wrinkle height", max(top) - min(top), 0.005, WRINKLE_MAX)
    return problems


# ---------------------------------------------------------------------------
# Previews (rendered AFTER export, so the extra helper objects added here -
# a mock pillar, wall or desk - never end up in a GLB)
# ---------------------------------------------------------------------------

def preview_box(name, size, loc, colour):
    material = pk.mat("PK_Body", name="Preview" + name, color=colour, roughness=0.9)
    return pk.box(name, size, loc=loc, material=material)


def render_view(png, target, direction, distance, ortho=None, lens=50.0, size=640):
    """One extra picture, after pk.preview() set up the renderer and light."""
    scene = bpy.context.scene
    cam = scene.camera
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.type = "PERSP"
        cam.data.lens = lens
    d = Vector(direction).normalized()
    cam.location = Vector(target) + d * distance
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.filepath = png
    bpy.ops.render.render(write_still=True)
    print("[desk] preview %s" % png)


def previews_crayon_cluster(folder):
    preview_box("MockPillar", (2.4, 2.4, 1.2), (0, 0, -0.6), "#D8CBB0")
    base = os.path.join(folder, "prop_crayon_cluster")
    pk.preview(base + ".png")
    render_view(base + "_eye.png", (0, 0, 0.3), (0.55, -1.0, 0.32), 7.5, lens=40)
    render_view(base + "_top.png", (0, 0, 0), (0, 0, 1), 10.0, ortho=2.7)


def previews_pinned_sheets(folder):
    sheets = sorted((o for o in pk.objects() if o.type == "MESH"), key=lambda o: o.name)
    for i, obj in enumerate(sheets):
        obj.location.x += (i - 1.5) * 3.6
    preview_box("MockWall", (15.0, 0.1, 4.0), (0, 0.052, 1.5), "#CFC6D8")
    base = os.path.join(folder, "prop_pinned_sheet")
    pk.preview(base + ".png")
    for i, obj in enumerate(sheets):
        W, H = SHEETS[i][0], SHEETS[i][1]
        centre = (obj.location.x, 0.0, H * 0.5)
        render_view(base + "_%d.png" % i, centre, (0, -1, 0), 10.0, ortho=max(W, H) * 1.08,
                    size=520)
    for i in (0, 3):
        obj = sheets[i]
        side = SHEETS[i][2]
        W = SHEETS[i][0]
        corner = (obj.location.x + side * W * 0.38, 0.0, 0.5)
        render_view(base + "_%d_curl.png" % i, corner, (side * 0.9, -1.0, 0.25), 4.0, lens=45,
                    size=520)
        render_view(base + "_%d_pin.png" % i, (obj.location.x, -0.1, SHEETS[i][1] - PIN_DROP),
                    (1.0, -0.6, 0.15), 3.0, lens=50, size=420)


def previews_tape_strip(folder):
    preview_box("MockDesk", (8.0, 3.0, 0.1), (0, 0, -0.05), "#D6C29C")
    base = os.path.join(folder, "prop_tape_strip")
    pk.preview(base + ".png")
    render_view(base + "_top.png", (0, 0, 0), (0, 0, 1), 10.0, ortho=6.4)
    render_view(base + "_end.png", (2.4, 0, 0.02), (1.0, -0.8, 0.35), 3.2, lens=40)
    render_view(base + "_wrinkle.png", (0.1, 0, 0.02), (-0.35, -1.0, 0.6), 2.6, lens=35)


# ---------------------------------------------------------------------------
# The prop table and the build loop
# ---------------------------------------------------------------------------

PROPS = [
    # key, root name, builder, checker, file, triangle budget, seed, previews
    ("crayon_cluster", "CrayonCluster", build_crayon_cluster, check_crayon_cluster,
     "prop_crayon_cluster.glb", 1600, 21, previews_crayon_cluster),
    ("pinned_sheet", "PinnedSheets", build_pinned_sheets, check_pinned_sheets,
     "prop_pinned_sheet.glb", 1200, 22, previews_pinned_sheets),
    ("tape_strip", "TapeStrip", build_tape_strip, check_tape_strip,
     "prop_tape_strip.glb", 200, 23, previews_tape_strip),
]


def main():
    opts = options()
    only = set(opts["only"].split(",")) if opts["only"] else None
    failed = []
    for key, root, builder, checker, filename, budget, seed, previewer in PROPS:
        if only and key not in only:
            continue
        pk.begin(root, seed=seed)
        info = builder()
        problems = checker(info) + check_normals() + check_materials() + check_transforms()
        total, per = pk.triangle_count()
        if total > budget:
            problems.append("%d triangles, over the %d budget" % (total, budget))
        mins, maxs = bounds()
        size = maxs - mins
        print("[desk] %s: %d tris, size %.3f x %.3f x %.3f m, x %.3f..%.3f y %.3f..%.3f "
              "z %.3f..%.3f" % (filename, total, size.x, size.y, size.z, mins.x, maxs.x,
                                mins.y, maxs.y, mins.z, maxs.z))
        if problems:
            for p in problems:
                print("[desk] PROBLEM %s: %s" % (filename, p))
            failed.append(filename)
            continue
        # The crayons never animate, so they export as ONE mesh node (fewer
        # nodes and draw calls). The sheets keep their four separate variants,
        # which Godot picks between; the tape is already one mesh.
        if key == "crayon_cluster":
            pk.merge_all("CrayonClusterMesh")
        pk.export(filename, budget=budget)
        for obj in pk.objects():
            parent = obj.parent.name if obj.parent else "-"
            print("[desk]    node %-20s %-6s parent %s" % (obj.name, obj.type, parent))
        if opts["previews"]:
            os.makedirs(opts["previews"], exist_ok=True)
            previewer(opts["previews"])

    if failed:
        print("[desk] FAILED: %s" % ", ".join(failed))
        sys.exit(1)
    print("[desk] all desk props built")


main()
