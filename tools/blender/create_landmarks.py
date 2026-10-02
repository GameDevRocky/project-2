"""
Landmarks - four giant set pieces that stand OUTSIDE the arena walls.

The arena is the top of a giant artist's desk: a 90 m square with 9 m walls.
One landmark stands beyond each wall and rises far above it, so a player can
glance up and know which way they are facing:

    lm_easel.glb        LandmarkEasel       NORTH  easel holding a painted canvas
    lm_brush_jar.glb    LandmarkBrushJar    SOUTH  ceramic jar full of brushes
    lm_paint_tubes.glb  LandmarkPaintTubes  EAST   pile of squeezed paint tubes
    lm_desk_lamp.glb    LandmarkDeskLamp    WEST   architect's desk lamp

Like create_arena_props.py, this script builds SEVERAL assets in one run: for
each landmark it starts a fresh scene (pk.begin), runs that landmark's builder,
checks it, joins it into ONE mesh with several materials, and exports a GLB
into models/generated/.

They are seen only from 50-120 m away, through distance haze, so everything
is big, chunky and low-poly: the smallest feature is about 0.5 m, and each
landmark stays under 2200 triangles.

Conventions shared by all four:
  * The root empty is named in CamelCase (LandmarkEasel...). Its one child is
    the joined mesh, named <Root>Mesh.
  * The ORIGIN is the bottom centre of the footprint's bounding box, at z = 0
    (the model sits on z = 0).
  * The FRONT, the side that faces the arena, faces Blender -Y, which the
    glTF exporter turns into Godot +Z. Place a landmark by putting its origin
    outside a wall and turning its +Z toward the arena centre.
  * Materials are named PK_Lm... and use muted studio colours. None of them is
    a gameplay role (PK_Accent, PK_Team, PK_Fill...) or an archetype/team
    colour. Only the lamp's bulb (PK_LmBulb) glows.

Run (from the project folder):
    blender -b --factory-startup --python-exit-code 1 --python tools/blender/create_landmarks.py
Options after a bare "--":
    --only easel,brush_jar     build only these landmarks (keys from LANDMARKS)
    --previews DIR             also render, per landmark, a 2x2 contact sheet
                               (DIR/lm_x.png), a player's view over a 9 m wall
                               from 30 m inside the arena (DIR/lm_x_wall.png)
                               and one from the far wall through haze
                               (DIR/lm_x_far.png)
    --preview PATH             what build_all.sh passes: the same previews,
                               written next to PATH
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

# Materials a landmark may never use (Godot swaps these for gameplay colours),
# and colours it may never use (archetype, team and UI colours).
RESERVED_MATERIALS = {"PK_Accent", "PK_AccentGlow", "PK_Team", "PK_TeamGlow", "PK_Fill", "PK_Wet"}
RESERVED_COLOURS = ["#FFB7C5", "#98FF98", "#00A896", "#2B2D42", "#FFFFFF", "#FF627E", "#58D7F2"]
# The only material allowed to glow.
GLOW_ALLOWED = {"PK_LmBulb"}

# The arena around a landmark, for the in-arena preview.
WALL_HEIGHT = 9.0
WALL_LENGTH = 90.0
WALL_DISTANCE = 25.0     # wall plane, in front of the landmark's origin
PLAYER_INSIDE = 30.0     # how far inside the wall the preview camera stands
EYE_HEIGHT = 1.6

# Objects that are deliberately one-sided flat sheets (the painted shapes).
_sheets = set()
# Objects re-smoothed at a wider angle than 35 degrees (name -> angle), for
# low-poly round parts whose few faces would otherwise look faceted.
_soft = {}


# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

def options():
    """Read our options after '--', then REMOVE --preview/--out from
    sys.argv. paintkit's export() reads those two itself and would write all
    four landmarks to the same single file; this script handles them per
    landmark instead."""
    if "--" not in sys.argv:
        return {"previews": os.environ.get("PK_PREVIEWS"), "only": None}
    cut = sys.argv.index("--")
    argv = sys.argv[cut + 1:]
    opts = {"previews": None, "only": None, "preview": None, "out": None}
    keep = []
    i = 0
    while i < len(argv):
        key = argv[i].lstrip("-")
        if key in opts and i + 1 < len(argv):
            opts[key] = argv[i + 1]
            if key in ("previews", "only"):
                keep += argv[i:i + 2]
            i += 2
        else:
            keep.append(argv[i])
            i += 1
    sys.argv[cut + 1:] = keep
    if opts["out"]:
        print("[landmarks] note: --out is ignored; this script writes four files")
    if opts["previews"] is None and opts["preview"]:
        opts["previews"] = os.path.dirname(os.path.abspath(opts["preview"]))
    if opts["previews"] is None:
        opts["previews"] = os.environ.get("PK_PREVIEWS")
    return opts


# ---------------------------------------------------------------------------
# Geometry helpers
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
    pk._collection.objects.link(obj)   # the working collection pk.begin() made
    if sheet_dir is not None:
        _sheets.add(name)
    if parent_obj is not None:
        pk.parent(obj, parent_obj)
    return obj


def loft(name, rings, mats, face_mat=None, parent_obj=None, recalc=False):
    """Skin a list of cross-section rings into one surface.

    Every ring lists its points counter-clockwise seen from the end the rings
    run toward, all with the same count. A ring of ONE point is a pole: the
    surface closes to a point there. face_mat(band, j) picks a material index
    per face (band = gap between ring `band` and the next)."""
    verts, starts = [], []
    for ring in rings:
        starts.append((len(verts), len(ring)))
        verts.extend(tuple(p) for p in ring)
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


def ring(z, half_w, half_d=None, n=12, power=2.0, phase=0.0, cx=0.0, cy=0.0, z_of=None):
    """One cross-section around the local Z axis: a circle (half_d=None), an
    ellipse (power 2) or a rounded rectangle (higher power). z_of(x, y) may
    lift each point (wavy paint lines, the arc on a fan brush's tip)."""
    if half_d is None:
        half_d = half_w
    if half_w <= 1e-9:
        return [(cx, cy, z)]
    pts = []
    for j in range(n):
        a = phase + TAU * j / n
        c, s = math.cos(a), math.sin(a)
        x = half_w * math.copysign(abs(c) ** (2.0 / power), c)
        y = half_d * math.copysign(abs(s) ** (2.0 / power), s)
        pts.append((cx + x, cy + y, z + (z_of(x, y) if z_of else 0.0)))
    return pts


def lathe_rings(profile, n, phase=0.0):
    """(radius, height) profile -> round rings for loft(). Radius 0 = pole."""
    return [ring(z, r, n=n, phase=phase) for r, z in profile]


def frame(origin, z_dir, y_hint=(0.0, 1.0, 0.0)):
    """A 4x4 matrix whose local Z runs along z_dir, placed at origin. Local Y
    stays as close to y_hint as it can, so a part built 'facing -Y' keeps
    facing the front after it is tilted."""
    z = Vector(z_dir).normalized()
    yh = Vector(y_hint).normalized()
    if abs(z.dot(yh)) > 0.98:
        yh = Vector((0.0, 0.0, 1.0)) if abs(z.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    x = yh.cross(z).normalized()
    y = z.cross(x)
    o = Vector(origin)
    return Matrix(((x.x, y.x, z.x, o.x),
                   (x.y, y.y, z.y, o.y),
                   (x.z, y.z, z.z, o.z),
                   (0.0, 0.0, 0.0, 1.0)))


def place(obj, matrix, parent_obj=None):
    """Put an object (built around its own origin) where `matrix` says."""
    obj.matrix_world = matrix
    if parent_obj is not None:
        pk.parent(obj, parent_obj)
    return obj


def beam(name, p0, p1, width, depth, material, bevel=0.25, segments=1, y_hint=(0, 1, 0),
         parent_obj=None, frame_m=None):
    """A square-section wooden beam from p0 to p1 (width along local X, depth
    along local Y). frame_m, if given, is the frame p0/p1 are written in."""
    p0, p1 = Vector(p0), Vector(p1)
    if frame_m is not None:
        p0, p1 = frame_m @ p0, frame_m @ p1
        y_hint = frame_m.to_3x3() @ Vector(y_hint)
    obj = pk.box(name, (width, depth, (p1 - p0).length), material=material, bevel=bevel,
                 segments=segments)
    return place(obj, frame((p0 + p1) * 0.5, p1 - p0, y_hint), parent_obj)


def block(name, size, centre, material, bevel=0.25, segments=1, frame_m=None, parent_obj=None):
    """An axis-aligned box in a frame (the world if frame_m is None)."""
    obj = pk.box(name, size, material=material, bevel=bevel, segments=segments)
    m = Matrix.Translation(Vector(centre))
    if frame_m is not None:
        m = frame_m @ m
    return place(obj, m, parent_obj)


def rod(name, p0, p1, radius, material, verts=8, radius_top=None, bevel=0.0, parent_obj=None,
        frame_m=None):
    """A cylinder (or cone, with radius_top) from p0 to p1."""
    p0, p1 = Vector(p0), Vector(p1)
    if frame_m is not None:
        p0, p1 = frame_m @ p0, frame_m @ p1
    obj = pk.cyl(name, radius, (p1 - p0).length, material=material, verts=verts,
                 radius_top=radius_top, bevel=bevel, segments=1)
    return place(obj, frame((p0 + p1) * 0.5, p1 - p0), parent_obj)


def sweep(name, path, radius, mats, n=6, profile=None, face_mat=None, cap_start=True,
          cap_end=True, parent_obj=None):
    """A tube along a path of points, with its own cross-section: hoses,
    springs, a rope of squeezed paint.

    radius(i) gives the tube's radius at path point i (0 closes it to a
    point). profile(j) scales cross-section point j (for ridges). The
    cross-section is carried along the path without twisting (parallel
    transport), so a coiled path does not corkscrew its ridges."""
    path = [Vector(p) for p in path]
    count = len(path)
    tangents = []
    for i in range(count):
        t = path[min(i + 1, count - 1)] - path[max(i - 1, 0)]
        tangents.append(t.normalized())
    # A starting normal at right angles to the first tangent.
    t0 = tangents[0]
    helper = Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))
    normal = (helper - t0 * helper.dot(t0)).normalized()
    rings = []
    if cap_start:
        rings.append([tuple(path[0] - t0 * radius(0) * 0.35)])
    for i in range(count):
        if i > 0:
            normal = tangents[i - 1].rotation_difference(tangents[i]) @ normal
            normal = (normal - tangents[i] * normal.dot(tangents[i])).normalized()
        binormal = tangents[i].cross(normal)
        r = radius(i)
        if r <= 1e-9:
            rings.append([tuple(path[i])])
            continue
        pts = []
        for j in range(n):
            a = TAU * j / n
            k = profile(j) if profile else 1.0
            pts.append(tuple(path[i] + (normal * math.cos(a) + binormal * math.sin(a)) * r * k))
        rings.append(pts)
    if cap_end and len(rings[-1]) > 1:
        rings.append([tuple(path[-1] + tangents[-1] * radius(count - 1) * 0.35)])
    return loft(name, rings, mats, face_mat=face_mat, parent_obj=parent_obj, recalc=True)


def outline_sheet(name, pts2d, material, frame_m, offset, parent_obj=None):
    """One flat face from a 2D outline (u, v), drawn on the plane y = offset
    of frame_m and facing that frame's -Y (its front)."""
    verts = [tuple(frame_m @ Vector((u, offset, v))) for u, v in pts2d]
    facing = frame_m.to_3x3() @ Vector((0.0, -1.0, 0.0))
    return mesh_obj(name, verts, [tuple(range(len(verts)))], [material],
                    parent_obj=parent_obj, sheet_dir=tuple(facing))


def stroke_sheet(name, centre_pts, widths, material, frame_m, offset, parent_obj=None):
    """A flat tapered brush stroke (quads along a 2D centre line), drawn on
    the plane y = offset of frame_m and facing its -Y."""
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
    verts = [tuple(frame_m @ Vector((u, offset, v))) for u, v in right + left]
    faces = [(i, i + 1, n + i + 1, n + i) for i in range(n - 1)]
    facing = frame_m.to_3x3() @ Vector((0.0, -1.0, 0.0))
    return mesh_obj(name, verts, faces, [material], parent_obj=parent_obj,
                    sheet_dir=tuple(facing))


def wobbly(cx, cy, rx, ry, n, rng, wobble=0.06, phase=0.0):
    """A hand-painted looking closed outline (counter-clockwise)."""
    pts = []
    for j in range(n):
        a = phase + TAU * j / n
        k = 1.0 + rng.uniform(-wobble, wobble)
        pts.append((cx + rx * k * math.cos(a), cy + ry * k * math.sin(a)))
    return pts


def soften(obj, angle):
    """Re-smooth at a wider angle. pk.smooth() can't do this after
    pk.smooth_all(35): Blender keeps edges an earlier pass marked sharp
    unless told not to."""
    pk.select_only(obj)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle), keep_sharp_edges=False)


# ---------------------------------------------------------------------------
# Checks and placement
# ---------------------------------------------------------------------------

def bounds(objs=None):
    """World-space bounding box of the evaluated meshes (bevels included)."""
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
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
        evaluated.to_mesh_clear()
    return mins, maxs


def settle(root):
    """Move every part so the footprint's bounding box is centred on the
    origin and the lowest point sits exactly on z = 0."""
    mins, maxs = bounds()
    shift = Vector((-(mins.x + maxs.x) * 0.5, -(mins.y + maxs.y) * 0.5, -mins.z))
    for child in root.children:
        child.location += shift
    bpy.context.view_layer.update()


def check_normals():
    """Catch inside-out faces: the outermost faces of a shape in each axis
    direction must point outward."""
    bpy.context.view_layer.update()
    problems = []
    for obj in pk.objects():
        if obj.type != "MESH" or obj.name in _sheets:
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
                tolerance = min(0.02, 0.2 * span)
                for c, n in faces:
                    if c.dot(d) >= extreme - tolerance and abs(n.dot(d)) > 0.6 and n.dot(d) < 0:
                        problems.append("%s: face at %s points inward" % (
                            obj.name, tuple(round(x, 2) for x in c)))
                        break
    return problems


def check_materials():
    problems = []
    reserved = [pk.linear(h) for h in RESERVED_COLOURS]
    for obj in pk.objects():
        if obj.type != "MESH":
            continue
        for m in obj.data.materials:
            if m.name in RESERVED_MATERIALS or not m.name.startswith("PK_Lm"):
                problems.append("%s uses material %s (landmarks use PK_Lm... only)" % (
                    obj.name, m.name))
            bsdf = m.node_tree.nodes["Principled BSDF"]
            colour = tuple(bsdf.inputs["Base Color"].default_value)
            for r in reserved:
                if all(abs(a - b) < 1e-4 for a, b in zip(colour[:3], r[:3])):
                    problems.append("%s uses a reserved colour" % m.name)
            glows = bsdf.inputs["Emission Strength"].default_value > 0.0 and \
                max(bsdf.inputs["Emission Color"].default_value[:3]) > 0.0
            if glows and m.name not in GLOW_ALLOWED:
                problems.append("%s is emissive" % m.name)
    return problems


def check_scale():
    """No node may keep a non-uniform (or any) scale."""
    problems = []
    for obj in pk.objects():
        if any(abs(s - 1.0) > 1e-5 for s in obj.scale):
            problems.append("%s keeps scale %s" % (obj.name, tuple(obj.scale)))
    return problems


# ---------------------------------------------------------------------------
# 1. Easel (NORTH) - A-frame easel, tray, canvas with a bold abstract painting
# ---------------------------------------------------------------------------

def build_easel():
    root = pk.empty("LandmarkEasel")
    wood = pk.mat("PK_Wood", name="PK_LmWood", color="#A87552")
    wood_dark = pk.mat("PK_Wood", name="PK_LmWoodDark", color="#7C5640", roughness=0.75)
    canvas = pk.mat("PK_Canvas", name="PK_LmCanvas", color="#EDE5D5")
    metal = pk.mat("PK_Metal", name="PK_LmIron", color="#8F8BA0", roughness=0.45, metallic=0.5)
    ochre = pk.mat("PK_Dry1", name="PK_LmOchre", color="#D6A447")
    lilac = pk.mat("PK_Dry2", name="PK_LmLilac", color="#9A88CC")
    clay = pk.mat("PK_Dry3", name="PK_LmClay", color="#C7735C")
    sea = pk.mat("PK_Dry4", name="PK_LmSeaGlass", color="#6FA89D")
    ink = pk.mat("PK_Dark", name="PK_LmInk", color="#465285", roughness=0.8)

    # The front of the easel (legs, mast, tray, canvas) lies in one plane that
    # leans back by LEAN. F is that plane's frame: local x = right, local -y =
    # out of the front, local z = up along the lean. Its origin is on the floor.
    LEAN = math.radians(9.0)
    F = Matrix.Translation((0.0, -2.0, 0.0)) @ Matrix.Rotation(-LEAN, 4, "X")

    APEX = 39.2          # where the legs meet the mast (local z)
    TOP = 41.2           # top of the mast, below its turned finial
    TRAY = 12.8          # top of the tray shelf (local z)
    CW, CH, CD = 26.0, 18.4, 1.3       # canvas width, height, depth
    CBACK = -0.75        # canvas back face (local y), just in front of the mast
    CFRONT = CBACK - CD

    def leg_x(z):
        """Half-spread of the front legs at local height z (the A shape)."""
        return 11.8 - (11.8 - 1.3) * z / APEX

    # Front legs: an A, meeting the mast under the apex block. The top third
    # stands clear above the canvas, so the A reads from across the arena.
    for i, s in enumerate((-1, 1)):
        beam("FrontLeg%d" % i, (s * leg_x(-0.4), 0, -0.4), (s * leg_x(APEX + 0.5), 0, APEX + 0.5),
             1.8, 1.2, wood, bevel=0.3, frame_m=F, parent_obj=root)
    # The mast: the centre post that carries the tray and the top clamp.
    beam("Mast", (0, 0, 5.0), (0, 0, TOP), 1.9, 1.3, wood, bevel=0.3, frame_m=F, parent_obj=root)
    # A turned finial on top of the mast.
    finial = loft("MastFinial", lathe_rings([(0.0, -0.2), (1.05, -0.2), (1.25, 0.25), (0.95, 0.75),
                                             (0.55, 1.0), (0.0, 1.05)], 10), [wood_dark])
    place(finial, F @ Matrix.Translation((0, 0, TOP)), root)
    _soft["MastFinial"] = 60.0
    # Apex block joining legs and mast, with a hinge pin for the back leg.
    block("ApexBlock", (3.6, 2.1, 2.6), (0, 0.3, APEX - 0.2), wood_dark, bevel=0.35, frame_m=F,
          parent_obj=root)
    rod("HingePin", (-2.4, 1.1, APEX - 0.5), (2.4, 1.1, APEX - 0.5), 0.7, metal, verts=10,
        frame_m=F, parent_obj=root)
    # Low crossbar between the front legs, the mast's foot standing on it.
    beam("Crossbar", (-leg_x(5.0) - 0.4, 0.05, 5.0), (leg_x(5.0) + 0.4, 0.05, 5.0), 1.2, 1.0,
         wood, bevel=0.25, frame_m=F, parent_obj=root)

    # Back leg, hinged at the apex and splayed out behind (world frame).
    hinge = F @ Vector((0, 1.3, APEX - 0.5))
    foot = Vector((0.0, 15.5, -0.3))
    beam("BackLeg", hinge, foot, 1.6, 1.2, wood, bevel=0.3, parent_obj=root)
    # A stay bar holding the back leg at a fixed spread.
    stay_front = F @ Vector((0, 0.6, 9.0))
    t = (stay_front.z - hinge.z) / (foot.z - hinge.z)
    stay_back = hinge.lerp(foot, t)
    beam("Stay", stay_front, stay_back, 0.7, 0.7, wood_dark, bevel=0.15, y_hint=(1, 0, 0),
         parent_obj=root)

    # Tray: a shelf in front of the mast, resting on the front legs, with a
    # raised front lip the canvas stands against.
    tray_depth = 3.4
    ty = CBACK - tray_depth * 0.5 + 0.2
    block("TrayShelf", (30.0, tray_depth, 0.9), (0, ty, TRAY - 0.45), wood, bevel=0.25,
          frame_m=F, parent_obj=root)
    block("TrayLip", (30.0, 0.8, 1.9), (0, CFRONT - 0.65, TRAY + 0.35), wood_dark, bevel=0.3,
          frame_m=F, parent_obj=root)
    block("TraySleeve", (3.2, 2.4, 2.6), (0, 0.15, TRAY - 1.3), wood_dark, bevel=0.3,
          frame_m=F, parent_obj=root)

    # Canvas: a deep stretched canvas standing on the tray.
    cz = TRAY + CH * 0.5
    block("Canvas", (CW, CD, CH), (0, CBACK - CD * 0.5, cz), canvas, bevel=0.3, frame_m=F,
          parent_obj=root)
    # Top clamp: a sleeve on the mast (behind the canvas) and a slim jaw that
    # hooks over the canvas's top edge, tightened by a knob at the back.
    ctop = TRAY + CH
    block("ClampSleeve", (2.8, 2.2, 2.4), (0, 0.15, ctop + 0.4), wood_dark, bevel=0.3,
          frame_m=F, parent_obj=root)
    block("ClampJaw", (3.4, CD + 1.9, 1.0), (0, CBACK - CD * 0.5 - 0.05, ctop + 0.5), wood_dark,
          bevel=0.25, frame_m=F, parent_obj=root)
    block("ClampLip", (3.4, 0.7, 2.0), (0, CFRONT - 0.35, ctop - 0.3), wood_dark, bevel=0.25,
          frame_m=F, parent_obj=root)
    knob = pk.cyl("ClampKnob", 0.9, 1.0, material=metal, verts=10, bevel=0.2, segments=1)
    place(knob, F @ frame((0, 1.7, ctop + 0.4), (0, 1, 0), (0, 0, 1)), root)

    # The painting: big flat shapes just in front of the canvas, each a
    # little further forward than the one it overlaps.
    rng = random.Random(42)
    face = CFRONT - 0.04
    u0, v0 = 0.0, cz           # canvas centre in (u, v) = (local x, local z)
    hw, hh = CW * 0.5 - 0.6, CH * 0.5 - 0.6

    # A sea-glass hill along the bottom with a wavy top edge.
    hill = [(-hw, v0 - hh)]
    for k in range(9):
        u = -hw + 2 * hw * k / 8
        hill.append((u, v0 - hh + 6.2 + 1.8 * math.sin(1.7 + 2.6 * k / 8 * math.pi * 0.62)
                     - 0.9 * (k / 8)))
    hill.append((hw, v0 - hh))
    outline_sheet("PaintHill", hill, sea, F, face - 0.0, root)
    # An ochre sun, upper right.
    outline_sheet("PaintSun", wobbly(u0 + 5.6, v0 + 3.2, 4.2, 4.2, 22, rng, 0.035), ochre, F,
                  face - 0.12, root)
    # A big lilac sweep across the middle.
    sweep_pts = [(-11.6 + 23.2 * i / 9, v0 - 1.2 + 3.4 * math.sin(math.pi * i / 9 * 1.15) - 1.6 * i / 9)
                 for i in range(10)]
    stroke_sheet("PaintSweep", sweep_pts,
                 [0.8 + 3.0 * math.sin(math.pi * (0.08 + 0.84 * i / 9)) ** 0.5 for i in range(10)],
                 lilac, F, face - 0.24, root)
    # A bold ink slash, upper left.
    slash = [(-10.4 + 2.0 * i, v0 + 6.9 - 1.7 * i - 0.12 * i * i) for i in range(5)]
    stroke_sheet("PaintSlash", slash, [1.2, 3.2, 3.6, 3.2, 1.4], ink, F, face - 0.36, root)
    # A clay block, lower right, and a few fat dots.
    outline_sheet("PaintBlock", [(3.6, v0 - 7.2), (10.8, v0 - 7.6), (11.2, v0 - 3.0),
                                 (4.2, v0 - 2.2)], clay, F, face - 0.3, root)
    for i, (u, v, r, m) in enumerate(((-4.6, 4.4, 1.3, clay), (-1.4, 6.0, 0.9, ochre),
                                      (-8.2, -6.0, 1.2, ochre), (1.6, -6.8, 1.0, ink))):
        outline_sheet("PaintDot%d" % i, wobbly(u0 + u, v0 + v, r, r, 10, rng, 0.08), m, F,
                      face - 0.42, root)
    return root


# ---------------------------------------------------------------------------
# 2. Brush jar (SOUTH) - a glazed ceramic jar holding seven giant brushes
# ---------------------------------------------------------------------------

def brush(name, base, direction, length, kind, handle_r, ferrule_len, tuft_len, tuft_w,
          tuft_d, mats, parent_obj):
    """One paintbrush, handle end at `base`, tip `length` further along
    `direction`. Built as ONE loft along its own Z axis (handle, metal
    ferrule, bristle tuft, paint-dipped tip), then tilted into place.

    kind: 'round' (pointed tuft), 'flat' (wide square tuft), 'fan' (spread
    tuft with an arched tip), 'mop' (fat domed tuft). tuft_w/tuft_d are the
    tuft's half width/half depth. mats = [handle, ferrule, bristle, paint].
    The bottom of the handle is left open: it sits inside the jar."""
    flat = kind in ("flat", "fan")
    n = 10 if flat else 8
    lh = length - ferrule_len - tuft_len           # handle length
    zf = lh + ferrule_len                          # top of the ferrule
    rf = handle_r * 1.18                           # ferrule radius where it grips
    # Each ring carries the material of the band BELOW it (ending at it).
    rings, mat_of_band = [], []

    def add(r, band_mat):
        rings.append(r)
        mat_of_band.append(band_mat)

    # Handle: a slow taper that swells just below the ferrule.
    add(ring(0.0, handle_r * 0.8, n=n), 0)
    add(ring(lh * 0.55, handle_r, n=n), 0)
    add(ring(lh * 0.9, handle_r * 1.12, n=n), 0)
    add(ring(lh, handle_r * 1.05, n=n), 0)          # step out onto the ferrule
    # Ferrule: round at the handle, pinched flat for flat and fan brushes.
    add(ring(lh, rf, n=n), 1)
    if flat:
        add(ring(lh + ferrule_len * 0.45, rf * 1.05, rf * 0.98, n=n), 1)
        add(ring(zf, tuft_w * 0.62, tuft_d * 1.25, n=n, power=3.0), 1)
    else:
        add(ring(lh + ferrule_len * 0.55, rf * 1.04, n=n), 1)
        add(ring(zf, max(rf * 0.98, tuft_w * 0.86), n=n), 1)
    # Tuft. The paint line is a little wavy, as if dipped by hand.
    def wavy(x, y):
        return 0.3 * math.sin(3.0 * math.atan2(y, x) + 0.6)

    t = tuft_len
    if kind == "round":
        add(ring(zf, tuft_w * 0.8, n=n), 1)
        add(ring(zf + t * 0.28, tuft_w * 1.08, n=n), 2)
        add(ring(zf + t * 0.48, tuft_w * 1.0, n=n, z_of=wavy), 2)
        add(ring(zf + t * 0.74, tuft_w * 0.7, n=n), 3)
        add(ring(zf + t * 0.92, tuft_w * 0.3, n=n), 3)
        add([(0.0, 0.0, zf + t)], 3)
    elif kind == "mop":
        add(ring(zf, tuft_w * 0.75, n=n), 1)
        add(ring(zf + t * 0.3, tuft_w * 1.05, n=n), 2)
        add(ring(zf + t * 0.5, tuft_w * 1.08, n=n, z_of=wavy), 2)
        add(ring(zf + t * 0.78, tuft_w * 0.85, n=n), 3)
        add(ring(zf + t * 0.95, tuft_w * 0.42, n=n), 3)
        add([(0.0, 0.0, zf + t)], 3)
    elif kind == "flat":
        add(ring(zf, tuft_w * 0.6, tuft_d * 1.1, n=n, power=3.0), 1)
        add(ring(zf + t * 0.3, tuft_w * 1.02, tuft_d * 1.15, n=n, power=3.0), 2)
        add(ring(zf + t * 0.52, tuft_w * 1.0, tuft_d, n=n, power=3.0, z_of=wavy), 2)
        add(ring(zf + t * 0.86, tuft_w * 0.94, tuft_d * 0.7, n=n, power=3.0), 3)
        add(ring(zf + t, tuft_w * 0.82, tuft_d * 0.32, n=n, power=3.0), 3)
        add([(0.0, 0.0, zf + t + 0.15)], 3)
    else:  # fan: spreads out wide and thin, its tip an arch
        def arch(x, y):
            return -t * 0.22 * (x / tuft_w) ** 2

        add(ring(zf, tuft_w * 0.38, tuft_d * 1.5, n=n, power=2.4), 1)
        add(ring(zf + t * 0.32, tuft_w * 0.66, tuft_d * 1.25, n=n, power=2.4), 2)
        add(ring(zf + t * 0.55, tuft_w * 0.86, tuft_d * 1.05, n=n, power=2.4,
                 z_of=lambda x, y: wavy(x, y) + arch(x * 0.86, y) * 0.5), 2)
        add(ring(zf + t * 0.86, tuft_w * 1.0, tuft_d * 0.85, n=n, power=2.4,
                 z_of=lambda x, y: arch(x, y) * 0.8), 3)
        add(ring(zf + t, tuft_w * 0.94, tuft_d * 0.4, n=n, power=2.4, z_of=arch), 3)
        add([(0.0, 0.0, zf + t + 0.1)], 3)
    obj = loft(name, rings, mats, face_mat=lambda band, j: mat_of_band[band + 1])
    _soft[name] = 60.0
    return place(obj, frame(base, direction), parent_obj)


def build_brush_jar():
    root = pk.empty("LandmarkBrushJar")
    glaze = pk.mat("PK_Body", name="PK_LmGlaze", color="#6F89A8", roughness=0.3)
    cream = pk.mat("PK_Body", name="PK_LmCreamGlaze", color="#E6DCC8", roughness=0.35)
    biscuit = pk.mat("PK_Dry3", name="PK_LmBiscuit", color="#C2A07E", roughness=0.9)
    rinse = pk.mat("PK_Body", name="PK_LmRinse", color="#8C83A0", roughness=0.15)
    ferrule = pk.mat("PK_Metal", name="PK_LmFerrule", color="#B3AEC0", roughness=0.35,
                     metallic=0.6)
    bristle = pk.mat("PK_Canvas", name="PK_LmBristle", color="#D8C49E", roughness=0.9)
    handles = {
        "lacquer": pk.mat("PK_Wood", name="PK_LmLacquer", color="#8E4E48", roughness=0.4),
        "wood": pk.mat("PK_Wood", name="PK_LmBrushWood", color="#C29466", roughness=0.7),
        "slate": pk.mat("PK_Dark", name="PK_LmSlate", color="#4E5266", roughness=0.45),
        "mustard": pk.mat("PK_Wood", name="PK_LmMustard", color="#C9A24E", roughness=0.45),
    }
    paints = {
        "ochre": pk.mat("PK_Dry1", name="PK_LmOchre", color="#D6A447"),
        "lilac": pk.mat("PK_Dry2", name="PK_LmLilac", color="#9A88CC"),
        "clay": pk.mat("PK_Dry3", name="PK_LmClay", color="#C7735C"),
        "sea": pk.mat("PK_Dry4", name="PK_LmSeaGlass", color="#6FA89D"),
        "ink": pk.mat("PK_Dark", name="PK_LmInk", color="#465285", roughness=0.8),
        "rose": pk.mat("PK_Dry3", name="PK_LmRose", color="#C48A9C"),
    }

    # The jar: a fat glazed crock 14 m across, an unglazed foot, a cream
    # stripe round the belly and a rolled cream lip. Inside, murky rinse water.
    WATER = 15.6
    profile = [
        (6.1, 0.0), (6.7, 0.5), (6.95, 1.6),                  # unglazed foot
        (7.0, 3.0), (7.0, 8.4), (7.0, 9.8),                   # belly, cream stripe
        (6.6, 13.6), (6.15, 14.9),                            # shoulder, neck
        (6.65, 15.6), (6.8, 16.4), (6.45, 17.0),              # rolled lip
        (5.85, 16.8), (5.7, WATER + 0.1), (0.0, WATER + 0.1),  # inner wall, water
    ]

    def jar_mat(band, j):
        if band < 2:
            return 2
        if band == 4 or 7 <= band <= 11:
            return 1
        if band == 12:
            return 3
        return 0

    loft("Jar", lathe_rings(profile, 18), [glaze, cream, biscuit, rinse], face_mat=jar_mat,
         parent_obj=root)
    _soft["Jar"] = 50.0

    # The brushes: (lean direction in degrees, 270 = front; lean from upright;
    # distance from the jar's axis where it leaves the water; tip height;
    # kind; handle radius; ferrule, tuft length; tuft half width, half depth;
    # handle colour; paint colour).
    specs = [
        (272, 4, 0.6, 38.0, "round", 0.85, 3.4, 7.0, 1.9, 1.9, "lacquer", "ochre"),
        (196, 29, 3.9, 33.5, "flat", 0.78, 3.2, 6.2, 2.5, 0.75, "wood", "lilac"),
        (340, 35, 3.9, 30.5, "fan", 0.72, 3.0, 5.8, 3.7, 0.42, "slate", "sea"),
        (236, 31, 4.1, 28.0, "round", 0.68, 2.6, 5.2, 1.45, 1.45, "mustard", "clay"),
        (35, 15, 3.6, 35.0, "round", 0.6, 2.6, 6.4, 0.95, 0.95, "slate", "ink"),
        (140, 24, 4.0, 31.5, "flat", 0.68, 2.8, 5.2, 1.8, 0.65, "lacquer", "rose"),
        (304, 40, 4.0, 24.0, "mop", 0.74, 2.6, 4.6, 2.2, 2.2, "wood", "ochre"),
    ]
    for i, (az, lean, q, tip, kind, hr, fl, tl, tw, td, hm, pm) in enumerate(specs):
        a, l = math.radians(az), math.radians(lean)
        d = Vector((math.sin(l) * math.cos(a), math.sin(l) * math.sin(a), math.cos(l)))
        wet = Vector((q * math.cos(a), q * math.sin(a), WATER))
        base = wet - d * (2.0 / math.cos(l))         # start 2 m under the water
        length = (tip - base.z) / d.z
        brush("Brush%d" % i, base, d, length, kind, hr, fl, tl, tw, td,
              [handles[hm], ferrule, bristle, paints[pm]], root)
    return root


# ---------------------------------------------------------------------------
# 3. Paint tubes (EAST) - three squeezed tubes in a pile, one oozing a curl
# ---------------------------------------------------------------------------

TUBE_LEN = 20.0
TUBE_R = 3.3


def paint_tube(name, origin, direction, mats, lying, dent=None, y_hint=(0, 0, 1),
               parent_obj=None):
    """One squeezed paint tube, crimped end at `origin`, nozzle TUBE_LEN
    further along `direction`. Cap off: the open nozzle shows the paint.

    mats = [tin, label cream, paint colour]. A cream label wraps the body
    and the shoulder below the nozzle is the paint colour, so the top of the
    tube says which colour it holds. lying=True keeps the underside flat on
    the ground (the flattened end droops onto the floor). dent=(z, depth)
    presses a thumb dent into the body's local +Y side. y_hint picks which
    way that side faces (the flat crimp spreads across it)."""
    R = TUBE_R
    # (z along the tube, half width, half thickness, material of the band below)
    rows = [
        (0.9, 3.75, 0.35, 0),        # tucked into the crimp
        (2.8, 3.7, 1.05, 0),
        (5.0, 3.55, 2.0, 0),
        (7.6, 3.42, 2.75, 0),
        (10.6, 3.36, 3.1, 1),        # cream label
        (14.2, 3.3, 3.28, 1),
        (16.7, 3.15, 3.15, 2),       # paint-colour band and shoulder
        (17.6, 2.3, 2.3, 2),
        (18.0, 1.35, 1.35, 2),
        (19.5, 1.3, 1.3, 0),         # neck
        (19.8, 1.5, 1.5, 0),         # lip
        (20.2, 1.32, 1.32, 0),
        (20.2, 0.85, 0.85, 0),       # rim of the opening
    ]
    n = 12
    rings, band_mats = [], []
    for z, hw, hd, m in rows:
        cy = (hd - R) if lying else 0.0
        pts = ring(z, hw, hd, n=n, cy=cy)
        if dent is not None:
            dz, depth = dent
            k = math.exp(-((z - dz) / 2.6) ** 2)
            pts = [(x, y - depth * k * max(0.0, (y - cy) / max(hd, 1e-6)) ** 2 *
                    math.exp(-(x / 2.2) ** 2), zz) for x, y, zz in pts]
        rings.append(pts)
        band_mats.append(m)
    rings.append([(0.0, 0.0, 19.7)])     # paint just inside the opening
    band_mats.append(2)
    obj = loft(name, rings, mats, face_mat=lambda band, j: band_mats[band + 1])
    _soft[name] = 50.0
    place(obj, frame(origin, direction, y_hint), parent_obj)
    # The crimped flat end.
    crimp = pk.box(name + "Crimp", (7.9, 0.9, 1.9), material=mats[0], bevel=0.3, segments=1)
    cy = (0.45 - R) if lying else 0.0
    place(crimp, frame(origin, direction, y_hint) @ Matrix.Translation((0, cy, 0.55)),
          parent_obj)
    return obj


def build_paint_tubes():
    root = pk.empty("LandmarkPaintTubes")
    tin = pk.mat("PK_Metal", name="PK_LmTin", color="#C9C5D3", roughness=0.4, metallic=0.45)
    cream = pk.mat("PK_Canvas", name="PK_LmLabel", color="#E8E0CF", roughness=0.7)
    lilac = pk.mat("PK_Dry2", name="PK_LmLilac", color="#9A88CC")
    ochre = pk.mat("PK_Dry1", name="PK_LmOchre", color="#D6A447")
    coral = pk.mat("PK_Dry3", name="PK_LmCoral", color="#D06A55", roughness=0.35)
    cap_mat = pk.mat("PK_Dark", name="PK_LmCapBlack", color="#3D3F52", roughness=0.5)

    # B and C stand on their flat crimped ends side by side at the front and
    # lean outward in a V, their backs resting on A, which lies behind them.
    # They stand steep so their coloured shoulders and nozzles (and C's curl)
    # clear the arena wall; their crimps face the arena.
    c_origin = Vector((7.2, -6.0, 0.6))
    c_dir = Vector((0.31, 0.16, 0.937)).normalized()
    paint_tube("TubeC", c_origin, c_dir, [tin, cream, coral], False, dent=(8.5, 1.0),
               y_hint=(0, -1, 0), parent_obj=root)
    paint_tube("TubeB", (-7.2, -6.0, 0.6), Vector((-0.31, 0.14, 0.94)).normalized(),
               [tin, cream, ochre], False, dent=(10.0, 1.1), y_hint=(0, -1, 0), parent_obj=root)
    # A lies along the back, nozzle to the right, holding B and C up.
    paint_tube("TubeA", (-12.0, 3.4, TUBE_R), (1.0, -0.05, 0.0), [tin, cream, lilac], True,
               dent=(9.0, 1.1), parent_obj=root)

    # The curl: a ridged rope of paint, like piped icing. It leaves the nozzle
    # along the tube, loops up, over to the right and down, in a plane facing
    # the arena (so it reads face-on), drifting a little toward the front so
    # its turns never pass through each other. Then it tapers off.
    nozzle = c_origin + c_dir * 19.4
    up = Vector((0.0, 0.0, 1.0))
    along = Vector((c_dir.x, c_dir.y, 0.0)).normalized()     # C's direction, flattened
    drift = along.cross(up).normalized()                      # toward the front
    alpha0 = math.atan2(c_dir.z, Vector((c_dir.x, c_dir.y)).length)
    path, steps = [nozzle.copy()], 30
    turn = math.radians(400.0)
    pos = nozzle.copy()
    for k in range(steps):
        t = (k + 0.5) / steps
        r = 3.0 * (1.0 - 0.5 * t)
        a = alpha0 - turn * t                                 # clockwise, seen from the front
        step = r * turn / steps
        pos = pos + (along * math.cos(a) + up * math.sin(a)) * step + drift * (2.6 / steps)
        path.append(pos.copy())
    path.insert(0, nozzle - c_dir * 1.2)           # starts inside the nozzle

    def rope_r(i):
        t = i / (len(path) - 1)
        return 1.15 if t < 0.72 else 1.15 * max(0.0, 1.0 - (t - 0.72) / 0.28) ** 0.7

    sweep("PaintCurl", path, rope_r, [coral], n=10,
          profile=lambda j: 1.0 if j % 2 == 0 else 0.8, cap_start=False, parent_obj=root)
    _soft["PaintCurl"] = 70.0

    # One of the unscrewed caps, lying on its side in front of the pile.
    def ribs(i, j, r):
        return r - 0.14 if (i in (1, 2) and j % 2) else r

    cap_rings = []
    for i, (r, z) in enumerate(((1.75, 0.0), (1.9, 0.25), (1.9, 2.4), (1.6, 2.7), (0.0, 2.75))):
        cap_rings.append([(x * (ribs(i, j, r) / r) if r else x, y * (ribs(i, j, r) / r) if r else y,
                           zz) for j, (x, y, zz) in enumerate(ring(z, r, n=12))])
    cap = loft("Cap", cap_rings, [cap_mat])
    place(cap, frame((-18.5, -5.0, 1.9), (0.8, -0.6, 0.0), (0, 0, 1)), root)
    return root


# ---------------------------------------------------------------------------
# 4. Desk lamp (WEST) - architect's lamp: heavy base, sprung arms, glowing shade
# ---------------------------------------------------------------------------

def spring(name, p0, p1, coil_r, wire_r, turns, material, parent_obj):
    """A coil spring from p0 to p1 (a 4-sided wire, smoothed round)."""
    p0, p1 = Vector(p0), Vector(p1)
    length = (p1 - p0).length
    per_turn = 6
    count = int(turns * per_turn) + 1
    pts = []
    for i in range(count):
        a = TAU * turns * i / (count - 1)
        pts.append((coil_r * math.cos(a), coil_r * math.sin(a), length * i / (count - 1)))
    obj = sweep(name, pts, lambda i: wire_r, [material], n=4)
    _soft[name] = 100.0          # 4 faces meet at 90 degrees: smooth them all
    return place(obj, frame(p0, p1 - p0), parent_obj)


def build_desk_lamp():
    root = pk.empty("LandmarkDeskLamp")
    enamel = pk.mat("PK_Body", name="PK_LmEnamel", color="#7E9E78", roughness=0.35)
    chrome = pk.mat("PK_Metal", name="PK_LmChrome", color="#B1ADBF", roughness=0.25,
                    metallic=0.7)
    steel = pk.mat("PK_Metal", name="PK_LmSpring", color="#8A8699", roughness=0.35,
                   metallic=0.6)
    joint = pk.mat("PK_Dark", name="PK_LmJoint", color="#4A4D61", roughness=0.45)
    lining = pk.mat("PK_Body", name="PK_LmLining", color="#F0E6D2", roughness=0.6)
    bulb = pk.mat("PK_Body", name="PK_LmBulb", color="#FFE9B8", emission=2.0)

    # The arm swings out sideways so that, seen from the arena, it makes the
    # lamp's zig-zag: up and right to the elbow, then back up and left to
    # the head, where the shade turns to look down at the arena.
    P0 = Vector((0.0, 0.0, 6.6))       # shoulder pivot on the base
    P1 = Vector((11.0, 3.0, 28.6))     # elbow
    P2 = Vector((-4.5, -3.5, 43.4))    # head
    lower, upper = (P1 - P0), (P2 - P1)
    normal = lower.cross(upper).normalized()      # sticks out of the arm's plane

    # Heavy round base, stepped like a turned weight, and a short post.
    loft("Base", lathe_rings([(8.7, 0.0), (9.1, 0.45), (9.1, 1.7), (8.6, 2.3), (6.4, 2.7),
                              (5.3, 3.5), (3.3, 3.9), (0.0, 4.0)], 20), [enamel],
         parent_obj=root)
    _soft["Base"] = 50.0
    rod("Post", (0, 0, 3.6), (0, 0, P0.z), 1.7, joint, verts=12, parent_obj=root)

    # Pivot hubs at shoulder, elbow and head: drums across the arm's plane,
    # each with a tension knob on the front face.
    for name, p, r, w in (("Shoulder", P0, 1.7, 4.6), ("Elbow", P1, 1.7, 4.8),
                          ("Head", P2, 1.4, 4.2)):
        rod(name + "Hub", p - normal * w * 0.5, p + normal * w * 0.5, r, joint, verts=12,
            bevel=0.25, parent_obj=root)
        rod(name + "Knob", p + normal * w * 0.5, p + normal * (w * 0.5 + 1.0), r * 0.62,
            chrome, verts=10, bevel=0.2, parent_obj=root)

    # Each arm is a pair of parallel rods, one either side of the hubs.
    for name, a, b, r in (("Lower", P0, P1, 0.6), ("Upper", P1, P2, 0.55)):
        for k, s in enumerate((-1, 1)):
            off = normal * s * 1.45
            rod("%sRod%d" % (name, k), a + off, b + off, r, chrome, verts=8, parent_obj=root)
    _soft.update({"LowerRod0": 60.0, "LowerRod1": 60.0, "UpperRod0": 60.0, "UpperRod1": 60.0})

    # Springs alongside the arms, in the arm's plane so they show from the
    # front: one from the base to the lower arm, one across the elbow.
    in_plane_l = normal.cross(lower).normalized()     # 'below' the lower arm
    in_plane_u = upper.cross(normal).normalized()     # 'below' the upper arm
    spring("SpringLower", P0 + in_plane_l * 2.4 + lower.normalized() * 1.5,
           P0 + lower * 0.55 + in_plane_l * 2.4, 0.8, 0.3, 7.0, steel, root)
    for k, t in enumerate((0.05, 0.55)):
        rod("SpringLowerTab%d" % k, P0 + lower * t + in_plane_l * 0.4,
            P0 + lower * t + in_plane_l * 2.6 + lower.normalized() * (1.5 if k == 0 else 0.0),
            0.32, steel, verts=6, parent_obj=root)
    spring("SpringUpper", P1 + upper * 0.12 + in_plane_u * 2.2,
           P1 + upper * 0.52 + in_plane_u * 2.2, 0.7, 0.28, 5.0, steel, root)
    for k, t in enumerate((0.12, 0.52)):
        rod("SpringUpperTab%d" % k, P1 + upper * t + in_plane_u * 0.4,
            P1 + upper * t + in_plane_u * 2.4, 0.3, steel, verts=6, parent_obj=root)

    # The shade: a flared cone hanging from the head, aimed down and out
    # toward the arena, turned a little to the side so the cone shows in
    # three-quarter view while its glowing bulb still faces the players.
    aim = Vector((-0.55, -0.68, -0.48)).normalized()
    shade_m = frame(P2 + aim * 0.3 - Vector((0, 0, 0.6)), aim, (0, 0, 1))
    shade_profile = [
        (0.0, -0.6), (1.9, -0.45), (2.7, 0.4), (2.9, 1.8),             # rounded back
        (3.5, 2.6), (5.2, 6.0), (6.4, 8.6), (6.95, 9.6), (7.0, 10.0),  # cone and flare
        (6.45, 9.9), (5.6, 8.4), (3.2, 4.4), (0.0, 4.2),              # lining inside
    ]
    shade = loft("Shade", lathe_rings(shade_profile, 16), [enamel, lining],
                 face_mat=lambda band, j: 1 if band >= 8 else 0)
    place(shade, shade_m, root)
    _soft["Shade"] = 50.0
    bulb_obj = loft("Bulb", lathe_rings([(2.5, 4.25), (2.55, 5.2), (2.0, 6.3), (1.1, 6.95),
                                         (0.0, 7.15)], 14), [bulb])
    place(bulb_obj, shade_m, root)
    _soft["Bulb"] = 80.0
    return root


# ---------------------------------------------------------------------------
# The landmark table and the build loop
# ---------------------------------------------------------------------------

LANDMARKS = [
    # key, builder, file, root name, budget, seed
    ("easel", build_easel, "lm_easel.glb", "LandmarkEasel", 2200, 1),
    ("brush_jar", build_brush_jar, "lm_brush_jar.glb", "LandmarkBrushJar", 2200, 2),
    ("paint_tubes", build_paint_tubes, "lm_paint_tubes.glb", "LandmarkPaintTubes", 2200, 3),
    ("desk_lamp", build_desk_lamp, "lm_desk_lamp.glb", "LandmarkDeskLamp", 2200, 4),
]


def preview_wall(png_path, vfov=66.0, pitch=16.0, size=(1280, 720)):
    """Render what a player sees: a 9 m wall WALL_DISTANCE in front of the
    landmark's origin, and the camera at eye height PLAYER_INSIDE metres
    inside that wall, looking at the landmark over it. Then a second view
    (<name>_far.png) from the far side of the arena through light haze, the
    farthest and murkiest a player ever sees it. Run after pk.preview(),
    which set up the renderer, sky and sun. Only for checking: nothing here
    is exported."""
    scene = bpy.context.scene
    plaster = pk.mat("PK_Body", name="PreviewWall", color="#D9D1C4", roughness=0.8)
    floor = pk.mat("PK_Body", name="PreviewFloor", color="#B9A88E", roughness=0.9)
    extra = []
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -WALL_DISTANCE, WALL_HEIGHT * 0.5))
    wall = bpy.context.active_object
    wall.scale = (WALL_LENGTH, 1.0, WALL_HEIGHT)
    wall.data.materials.append(plaster)
    extra.append(wall)
    bpy.ops.mesh.primitive_plane_add(size=600.0, location=(0, 0, -0.01))
    ground = bpy.context.active_object
    ground.data.materials.append(floor)
    extra.append(ground)
    for o in extra:   # keep them out of the asset's collection
        for c in list(o.users_collection):
            c.objects.unlink(o)
        scene.collection.objects.link(o)

    cam = bpy.data.objects.new("WallCam", bpy.data.cameras.new("WallCam"))
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(vfov)
    cam.data.clip_end = 2000.0
    cam.location = (0.0, -WALL_DISTANCE - PLAYER_INSIDE, EYE_HEIGHT)
    cam.rotation_euler = (math.radians(90.0 + pitch), 0.0, 0.0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    nodes = scene.world.node_tree.nodes
    nodes["Background"].inputs["Color"].default_value = pk.linear("#C9C3DA")
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.filepath = png_path
    bpy.ops.render.render(write_still=True)
    print("[landmarks] wall view %s" % png_path)

    # The far view: from just inside the opposite wall, through haze. The
    # haze is a box of 'fog' around everything that dims what is behind it
    # and glows in the fog colour by the same amount, which is what a game's
    # depth fog does. It casts no shadow, so the sun still lights the model.
    density = 0.006
    fog = bpy.data.materials.new("PreviewHaze")
    fog.use_nodes = True
    nt = fog.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    absorb = nt.nodes.new("ShaderNodeVolumeAbsorption")
    absorb.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    absorb.inputs["Density"].default_value = density
    glow = nt.nodes.new("ShaderNodeEmission")
    glow.inputs["Color"].default_value = pk.linear("#D8D2E4")
    glow.inputs["Strength"].default_value = density * 0.9
    mix = nt.nodes.new("ShaderNodeAddShader")
    nt.links.new(absorb.outputs[0], mix.inputs[0])
    nt.links.new(glow.outputs[0], mix.inputs[1])
    nt.links.new(mix.outputs[0], nt.nodes["Material Output"].inputs["Volume"])
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -60.0, 80.0))
    box = bpy.context.active_object
    box.scale = (600.0, 500.0, 220.0)
    box.data.materials.append(fog)
    box.visible_shadow = False
    for c in list(box.users_collection):
        c.objects.unlink(box)
    scene.collection.objects.link(box)
    cam.location = (0.0, -WALL_DISTANCE - WALL_LENGTH + 2.0, EYE_HEIGHT)
    cam.data.angle = math.radians(40.0)
    cam.rotation_euler = (math.radians(90.0 + 9.0), 0.0, 0.0)
    far = png_path.replace("_wall.png", "_far.png")
    scene.render.filepath = far
    bpy.ops.render.render(write_still=True)
    print("[landmarks] far view %s" % far)


def main():
    opts = options()
    only = set(opts["only"].split(",")) if opts["only"] else None
    failed = []
    for key, builder, filename, root_name, budget, seed in LANDMARKS:
        if only and key not in only:
            continue
        _sheets.clear()
        _soft.clear()
        pk.begin(root_name, seed=seed)
        root = builder()
        settle(root)
        pk.smooth_all(35.0)
        for obj in pk.objects():
            if obj.name in _soft:
                soften(obj, _soft[obj.name])

        problems = check_normals() + check_materials()
        total, _ = pk.triangle_count()
        if total > budget:
            problems.append("%d triangles, over the %d budget" % (total, budget))
        mins, maxs = bounds()
        size = maxs - mins
        print("[landmarks] %s: %d tris, size x %.2f  y %.2f  z %.2f m  "
              "(x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f)" % (
                  filename, total, size.x, size.y, size.z,
                  mins.x, maxs.x, mins.y, maxs.y, mins.z, maxs.z))
        if problems:
            for p in problems:
                print("[landmarks] PROBLEM %s: %s" % (filename, p))
            failed.append(filename)
            continue
        # A landmark never animates: one mesh node, one surface per material.
        pk.merge_all(root_name + "Mesh")
        problems = check_scale()
        if problems:
            for p in problems:
                print("[landmarks] PROBLEM %s: %s" % (filename, p))
            failed.append(filename)
            continue
        pk.export(filename, budget=budget)
        print("[landmarks] nodes: %s" % ", ".join(
            "%s(%s)" % (o.name, o.parent.name if o.parent else "-") for o in pk.objects()))

        if opts["previews"]:
            os.makedirs(opts["previews"], exist_ok=True)
            png = os.path.join(opts["previews"], filename.replace(".glb", ".png"))
            pk.preview(png)
            preview_wall(png.replace(".png", "_wall.png"))

    if failed:
        print("[landmarks] FAILED: %s" % ", ".join(failed))
        sys.exit(1)
    print("[landmarks] all landmarks built")


main()
