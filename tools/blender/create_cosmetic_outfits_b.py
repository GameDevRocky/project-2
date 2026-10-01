"""
Cosmetic outfits B - seven full-body outfit kits laid over the Canvas Runner.

Three can be picked on the customize screen (GHOST, SAMURAI, CYBERPUNK) and
four are worn only by computer players (ART_CRITIC, JANITOR, MIME,
INK_GOLEM), so a bot can look like nobody a human is allowed to be.

Every outfit is built in the runner's own rest pose and coordinates (see
create_canvas_runner.py: it faces BLENDER -Y, its LEFT side is +X, its upper
body leans 7 degrees forward about z = 0.84). All seven sit on top of each
other in this file; Godot shows one at a time.

Nodes Godot relies on (names must not change):
    OutfitsB                 root empty at the origin.
    Outfit_<ID>              one empty per outfit, at the origin.
        <ID>_Body            every static piece on the body, one mesh.
        <ID>_Head            the outfit's own head, only for outfits that hide
                             the runner's Head (GHOST, INK_GOLEM).
        OnLeg_L / OnLeg_R    empties EXACTLY on the runner's hip pivots
                             (+0.11, 0, 0.78) / (-0.11, 0, 0.78). Godot copies
                             the leg swing onto them. Present only when the
                             outfit has leg pieces.
            <ID>_LegL / _LegR   the leg pieces, origin on the pivot.
Blender cannot give two objects the same name, so the second OnLeg_L becomes
"OnLeg_L.001"; after export this script renames those nodes inside the .glb
back to plain OnLeg_L / OnLeg_R (they are unique within their own outfit).

Material roles: PK_Team / PK_TeamGlow are repainted RED or BLUE by Godot, and
every outfit shows at least one of them from the front AND the back. Every
other colour is a named variant (PK_SamuraiLacquer, PK_GhostSheet...) that
keeps its exported look. The runner's own suit (PK_Canvas) and helmet
(PK_Body) are recoloured in code per outfit; the colours each outfit was
designed with are in SUIT_AND_HELMET below.

The upper back between z 0.85 and 1.45 is left clear: the backpack
(chromatic_reservoir.glb) clips on there.

Run:  blender -b --factory-startup --python-exit-code 1 \
          --python tools/blender/create_cosmetic_outfits_b.py
Look: add  -- --preview-dir DIR  (one front/side/back/3-4 sheet per outfit,
      worn by the runner with its pack and gun, imported after the export so
      it never ends up in the .glb). Also: --team HEX (preview team colour,
      default red), --only ID (build one outfit), --out PATH.
"""

import json
import math
import os
import random
import re
import struct
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("OutfitsB", seed=58)
TAU = math.tau

# The colours each outfit was designed with. Godot paints the runner's suit
# (PK_Canvas) and helmet (PK_Body) in these; "hide_head" hides its Head.
SUIT_AND_HELMET = {
    "GHOST":      dict(suit="#A9BFCB", helmet="#E3F1EF", hide_head=True),
    "SAMURAI":    dict(suit="#4E4670", helmet="#2E2638", hide_head=False),
    "CYBERPUNK":  dict(suit="#3A3650", helmet="#5C6178", hide_head=False),
    "ART_CRITIC": dict(suit="#34303F", helmet="#ECE2CF", hide_head=False),
    "JANITOR":    dict(suit="#A8996F", helmet="#E4DAC2", hide_head=False),
    "MIME":       dict(suit="#F2EFE9", helmet="#F5F2EC", hide_head=False),
    "INK_GOLEM":  dict(suit="#352C52", helmet="#352C52", hide_head=True),
}


# ---------------------------------------------------------------------------
# The runner's proportions (copied from create_canvas_runner.py)
# ---------------------------------------------------------------------------

RIGHT, LEFT = -1.0, 1.0
HIP_Z, HIP_X = 0.78, 0.11
LEAN_PIVOT = Vector((0.0, 0.0, 0.84))
LEAN_M = (Matrix.Translation(LEAN_PIVOT) @ Matrix.Rotation(math.radians(7.0), 4, "X")
          @ Matrix.Translation(-LEAN_PIVOT))
LEAN_R = LEAN_M.to_3x3()
HEAD = Vector((0.0, -0.065, 1.43))
HEAD_R = (0.172, 0.168, 0.17)
HAND_SOCKET = Vector((RIGHT * 0.17, -0.31, 0.95))
UPPER_ARM, FOREARM = 0.28, 0.3
PIVOT = {"L": Vector((HIP_X, 0.0, HIP_Z)), "R": Vector((-HIP_X, 0.0, HIP_Z))}


def lean(p):
    return LEAN_M @ Vector(p)


def elbow(shoulder, hand, upper, lower, pole):
    s, h = Vector(shoulder), Vector(hand)
    to_hand = h - s
    dist = to_hand.length
    a = (upper * upper - lower * lower + dist * dist) / (2 * dist)
    rise = math.sqrt(max(upper * upper - a * a, 0.0))
    axis = to_hand.normalized()
    side = Vector(pole) - axis * Vector(pole).dot(axis)
    return s + axis * a + side.normalized() * rise


_grip = HAND_SOCKET + Vector((0.0, 0.055, -0.11))
_support = HAND_SOCKET + Vector((LEFT * 0.045, -0.07, -0.04))
ARM = {}      # tag -> (shoulder, elbow, hand)
for _side, _tag, _hand, _pole in ((RIGHT, "R", _grip, (RIGHT * 1.0, 0.6, -0.4)),
                                  (LEFT, "L", _support, (LEFT * 0.5, 0.0, -1.0))):
    _sh = lean((_side * 0.245, 0.0, 1.2))
    ARM[_tag] = (_sh, elbow(_sh, _hand, UPPER_ARM, FOREARM, _pole), _hand)
ARM_R = {"upper": (0.076, 0.066), "fore": (0.066, 0.058)}   # capsule radii

LEG = {}      # tag -> (hip, knee, ankle)
for _side, _tag in ((LEFT, "L"), (RIGHT, "R")):
    LEG[_tag] = (Vector((_side * HIP_X, 0.0, HIP_Z)), Vector((_side * 0.12, -0.035, 0.45)),
                 Vector((_side * 0.125, 0.0, 0.17)))
LEG_R = {"thigh": (0.105, 0.086), "shin": (0.084, 0.07)}


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

def M(name, role, color, **kw):
    return pk.mat(role, name=name, color=color, **kw)


TEAM = pk.mat("PK_Team")
GLOW = pk.mat("PK_TeamGlow")
DARK = pk.mat("PK_Dark")
RUBBER = pk.mat("PK_Rubber")
BRASS = pk.mat("PK_Brass")
METAL = pk.mat("PK_Metal")
WOOD = pk.mat("PK_Wood")
TRIM = pk.mat("PK_Trim")


# ---------------------------------------------------------------------------
# Mesh helpers
# ---------------------------------------------------------------------------

def new_obj(name, bm, mats):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    pk._collection.objects.link(obj)
    for m in mats:
        mesh.materials.append(m)
    return obj


def connect(bm, rings, closed=True, mats=None, cap_first=False, cap_last=False):
    """Faces between consecutive rings of verts (a ring of one vert is a pole).
    Returns the faces strip by strip; `mats` gives a material index per strip."""
    strips = []
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        n = max(len(a), len(b))
        row = []
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            if len(a) == 1:
                f = bm.faces.new((a[0], b[j], b[i]))
            elif len(b) == 1:
                f = bm.faces.new((a[i], a[j], b[0]))
            else:
                f = bm.faces.new((a[i], a[j], b[j], b[i]))
            if mats:
                f.material_index = mats[k]
            row.append(f)
        strips.append(row)
    if cap_first and len(rings[0]) > 2:
        f = bm.faces.new(list(reversed(rings[0])))
        if mats:
            f.material_index = mats[0]
    if cap_last and len(rings[-1]) > 2:
        f = bm.faces.new(rings[-1])
        if mats:
            f.material_index = mats[-1]
    return strips


def point_out(bm, face, outward):
    """Make every face point the way `face` should: if its normal runs against
    `outward`, flip the whole (consistently wound) mesh."""
    bm.normal_update()
    if face.normal.dot(outward) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])


def closed_normals(bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])


def frames_along(pts, up):
    """Tangent / normal / binormal at each path point (parallel transport), the
    first normal as close to `up` as the path allows."""
    n = len(pts)
    tans = [(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized() for i in range(n)]
    upv = Vector(up)
    nrm = upv - tans[0] * upv.dot(tans[0])
    if nrm.length < 1e-6:
        nrm = tans[0].orthogonal()
    nrm.normalize()
    out = []
    for i in range(n):
        if i:
            axis = tans[i - 1].cross(tans[i])
            if axis.length > 1e-8:
                nrm = Matrix.Rotation(tans[i - 1].angle(tans[i]), 3, axis.normalized()) @ nrm
            nrm = (nrm - tans[i] * nrm.dot(tans[i])).normalized()
        out.append((tans[i], nrm, tans[i].cross(nrm).normalized()))
    return out


def loft(name, pts, radii, mats, sides=6, up=(0, 0, 1), flat=1.0, seg_mats=None):
    """A tube along `pts` with a radius per point (0 = pointed end), closed at
    both ends. `flat` squashes the section along the frame normal (scarves)."""
    pts = [Vector(p) for p in pts]
    bm = bmesh.new()
    rings = []
    for p, r, (t, nrm, b) in zip(pts, radii, frames_along(pts, up)):
        if r < 1e-5:
            rings.append([bm.verts.new(p)])
        else:
            rings.append([bm.verts.new(p + (nrm * math.cos(a) * flat + b * math.sin(a)) * r)
                          for a in (TAU * k / sides for k in range(sides))])
    connect(bm, rings, True, seg_mats, cap_first=True, cap_last=True)
    closed_normals(bm)
    return new_obj(name, bm, mats)


def lathe_axis(name, p0, p1, prof, mats, strip_mats=None, segments=12, front=(0, -1, 0)):
    """Rings around the axis p0 -> p1. prof is (radius, t) pairs with t measured
    along the axis as a fraction of |p1 - p0| (radius 0 = a pole). Open ends
    are fine: the outermost strip decides which way the faces point."""
    p0, p1 = Vector(p0), Vector(p1)
    axis = p1 - p0
    u = axis.normalized()
    f = Vector(front) - u * Vector(front).dot(u)
    if f.length < 1e-6:
        f = u.orthogonal()
    f.normalize()
    s = u.cross(f)
    bm = bmesh.new()
    rings = []
    for r, t in prof:
        c = p0 + axis * t
        if r < 1e-6:
            rings.append([bm.verts.new(c)])
        else:
            rings.append([bm.verts.new(c + (f * math.cos(a) + s * math.sin(a)) * r)
                          for a in (TAU * k / segments for k in range(segments))])
    strips = connect(bm, rings, True, strip_mats)
    k = max(range(len(prof) - 1), key=lambda i: prof[i][0] + prof[i + 1][0])
    probe = strips[k][0]
    bm.normal_update()
    c = probe.calc_center_median()
    radial = (c - p0) - u * (c - p0).dot(u)
    point_out(bm, probe, radial)
    return new_obj(name, bm, mats)


def vlathe(name, base, prof, mats, strip_mats=None, segments=14):
    """lathe_axis around a vertical axis through `base`; prof is (radius, height)."""
    b = Vector(base)
    return lathe_axis(name, b, b + Vector((0, 0, 1)), prof, mats, strip_mats, segments)


def arc_plate(name, origin, axis, front, a0, a1, rows, thick, mats, steps=4, scale=(1.0, 1.0),
              row_mats=None):
    """A curved armour plate: a slice of a (tapered) tube around `axis` from angle
    a0 to a1 (degrees, 0 = `front`, positive toward axis x front). `rows` is a
    list of (radius, height) down the outer face, or a function of the angle
    returning one. The inner face sits `thick` closer to the axis. row_mats
    gives a material index for each outer strip (lacing bands)."""
    o = Vector(origin)
    u = Vector(axis).normalized()
    f = (Vector(front) - u * Vector(front).dot(u)).normalized()
    s = u.cross(f)

    def at(a, r, h):
        ar = math.radians(a)
        return o + u * h + (f * math.cos(ar) * scale[1] + s * math.sin(ar) * scale[0]) * r

    angles = [a0 + (a1 - a0) * i / steps for i in range(steps + 1)]
    bm = bmesh.new()
    outer, inner = [], []
    for a in angles:
        rs = rows(a) if callable(rows) else rows
        outer.append([bm.verts.new(at(a, r, h)) for r, h in rs])
        inner.append([bm.verts.new(at(a, r - thick, h)) for r, h in rs])
    nk = len(outer[0])
    for i in range(steps):
        for k in range(nk - 1):
            fo = bm.faces.new((outer[i][k], outer[i + 1][k], outer[i + 1][k + 1], outer[i][k + 1]))
            if row_mats:
                fo.material_index = row_mats[k]
            bm.faces.new((inner[i][k], inner[i][k + 1], inner[i + 1][k + 1], inner[i + 1][k]))
        for k in (0, nk - 1):
            bm.faces.new((outer[i][k], inner[i][k], inner[i + 1][k], outer[i + 1][k]))
    for i in (0, steps):
        for k in range(nk - 1):
            bm.faces.new((outer[i][k], outer[i][k + 1], inner[i][k + 1], inner[i][k]))
    closed_normals(bm)
    return new_obj(name, bm, mats)


def disc(name, centre, normal, up, rx, ry, depth, mats, verts=10, front_mat=0):
    """A flat oval puck: eyes, buttons, lenses. Its front face can take its
    own material (front_mat)."""
    n = Vector(normal).normalized()
    u = Vector(up)
    u = (u - n * u.dot(n)).normalized()
    s = u.cross(n)
    c = Vector(centre)
    bm = bmesh.new()
    ring = [s * math.cos(a) * rx + u * math.sin(a) * ry
            for a in (TAU * k / verts for k in range(verts))]
    fr = [bm.verts.new(c + n * depth * 0.5 + p) for p in ring]
    bk = [bm.verts.new(c - n * depth * 0.5 + p) for p in ring]
    face = bm.faces.new(fr)
    face.material_index = front_mat
    bm.faces.new(list(reversed(bk)))
    for i in range(verts):
        j = (i + 1) % verts
        bm.faces.new((bk[i], bk[j], fr[j], fr[i]))
    closed_normals(bm)
    return new_obj(name, bm, mats)


def ellipsoid_patch(name, centre, radii, theta, phi, steps, out, inset, mats):
    """A raised panel wrapped onto an ellipsoid (the helmet), like the runner's
    visor. theta = azimuth range from the front (-Y) toward +X, phi = latitude."""
    c = Vector(centre)
    rx, ry, rz = radii

    def point(th, ph, offset):
        t, p = math.radians(th), math.radians(ph)
        d = Vector((math.cos(p) * math.sin(t), -math.cos(p) * math.cos(t), math.sin(p)))
        surface = Vector((d.x * rx, d.y * ry, d.z * rz))
        normal = Vector((d.x / rx, d.y / ry, d.z / rz)).normalized()
        return c + surface + normal * offset

    nth, nph = steps
    ths = [theta[0] + (theta[1] - theta[0]) * i / nth for i in range(nth + 1)]
    phs = [phi[0] + (phi[1] - phi[0]) * j / nph for j in range(nph + 1)]
    bm = bmesh.new()
    o = [[bm.verts.new(point(t, p, out)) for p in phs] for t in ths]
    n = [[bm.verts.new(point(t, p, -inset)) for p in phs] for t in ths]
    for i in range(nth):
        for j in range(nph):
            bm.faces.new((o[i][j], o[i + 1][j], o[i + 1][j + 1], o[i][j + 1]))
            bm.faces.new((n[i][j], n[i][j + 1], n[i + 1][j + 1], n[i + 1][j]))
        bm.faces.new((o[i][0], n[i][0], n[i + 1][0], o[i + 1][0]))
        bm.faces.new((o[i][nph], o[i + 1][nph], n[i + 1][nph], n[i][nph]))
    for j in range(nph):
        bm.faces.new((o[0][j], o[0][j + 1], n[0][j + 1], n[0][j]))
        bm.faces.new((o[nth][j], n[nth][j], n[nth][j + 1], o[nth][j + 1]))
    closed_normals(bm)
    return new_obj(name, bm, mats)


def helmet_point(theta, phi, out=0.0):
    """A point `out` metres off the runner's helmet, and the helmet normal there."""
    t, p = math.radians(theta), math.radians(phi)
    d = Vector((math.cos(p) * math.sin(t), -math.cos(p) * math.cos(t), math.sin(p)))
    rx, ry, rz = HEAD_R
    nrm = Vector((d.x / rx, d.y / ry, d.z / rz)).normalized()
    return HEAD + Vector((d.x * rx, d.y * ry, d.z * rz)) + nrm * out, nrm


def pad_point(side, lon, lat, out=0.0):
    """A point on a shoulder pad (lon 0 = outward, 90 = forward; lat 90 = its
    top) and the pad's normal there, after the pad's tilt and the lean."""
    lo, la = math.radians(lon), math.radians(lat)
    radii = (0.13, 0.155, 0.085)
    d = Vector((side * math.cos(la) * math.cos(lo), -math.cos(la) * math.sin(lo), math.sin(la)))
    p = Vector((d.x * radii[0], d.y * radii[1], d.z * radii[2]))
    nloc = Vector((d.x / radii[0], d.y / radii[1], d.z / radii[2])).normalized()
    rot = Matrix.Rotation(math.radians(side * 24), 3, "Y")
    pw = lean(Vector((side * 0.265, 0.0, 1.255)) + rot @ p)
    nw = (LEAN_R @ rot @ nloc).normalized()
    return pw + nw * out, nw


def limb(tag, part, f, legs=False):
    """(axis point, axis direction, radius) at fraction f along an arm or leg."""
    if legs:
        hip, knee, ankle = LEG[tag]
        a, b = (hip, knee) if part == "thigh" else (knee, ankle)
        r0, r1 = LEG_R[part]
    else:
        sh, el, hand = ARM[tag]
        a, b = (sh, el) if part == "upper" else (el, hand)
        r0, r1 = ARM_R[part]
    return a.lerp(b, f), (b - a).normalized(), r0 + (r1 - r0) * f


def limb_band(name, tag, part, f0, f1, lift, mats, legs=False, segments=8, strip_mats=None,
              prof=None):
    """A ring hugging an arm or leg between fractions f0 and f1 of one bone:
    sleeves, stripes, cuffs. Edges tuck into the limb so it needs no caps."""
    p0, _, r0 = limb(tag, part, f0, legs)
    p1, _, r1 = limb(tag, part, f1, legs)
    if prof is None:
        prof = [(r0 - 0.004, 0.0), (r0 + lift, 0.2), (r1 + lift, 0.8), (r1 - 0.004, 1.0)]
    else:
        prof = [(r0 + (r1 - r0) * t + dr, t) for dr, t in prof]
    return lathe_axis(name, p0, p1, prof, mats, strip_mats, segments)


def tilt(obj, pivot, rx=0.0, ry=0.0, rz=0.0):
    """Rotate a world-space mesh (identity transform) about a pivot, X then Y then Z."""
    rot = (Matrix.Rotation(math.radians(rz), 4, "Z") @ Matrix.Rotation(math.radians(ry), 4, "Y")
           @ Matrix.Rotation(math.radians(rx), 4, "X"))
    pv = Vector(pivot)
    obj.data.transform(Matrix.Translation(pv) @ rot @ Matrix.Translation(-pv))
    obj.data.update()
    return obj


def bake(obj):
    """Bake a primitive's transform into its mesh (origin at the world origin)."""
    pk.apply(obj, location=True, rotation=True, scale=True)
    return obj


def lumpy(obj, amount, seed, keep_below=None):
    """Hand-made lumps: low-frequency waves plus a little noise on every vertex."""
    r = random.Random(seed)
    ph = [r.uniform(0, TAU) for _ in range(3)]
    for v in obj.data.vertices:
        c = v.co
        w = (math.sin(c.x * 31 + ph[0]) + math.sin(c.y * 27 + ph[1]) + math.sin(c.z * 23 + ph[2])) / 3
        if keep_below is not None and c.z < keep_below:
            continue
        v.co = c + Vector((r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(-1, 1))) * amount * 0.4 \
            + Vector((c.x, c.y, 0)).normalized() * w * amount
    obj.data.update()
    return obj


def catmull(points, n):
    """Smooth a guide polyline and resample it to n evenly spaced points."""
    pts = [Vector(p) for p in points]
    ext = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    dense = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for k in range(12):
            t = k / 12
            dense.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                                + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
    dense.append(pts[-1])
    lengths = [0.0]
    for i in range(1, len(dense)):
        lengths.append(lengths[-1] + (dense[i] - dense[i - 1]).length)
    out = []
    for k in range(n):
        target = lengths[-1] * k / (n - 1)
        j = max(1, min(len(dense) - 1, next((i for i, l in enumerate(lengths) if l >= target),
                                             len(dense) - 1)))
        seg = lengths[j] - lengths[j - 1]
        t = (target - lengths[j - 1]) / seg if seg > 1e-9 else 0.0
        out.append(dense[j - 1].lerp(dense[j], t))
    return out


# ---------------------------------------------------------------------------
# Reference body: the runner's torso, hips, belt and shoulder pads rebuilt
# from the same numbers, so panels, stripes and straps can be shrink-wrapped
# onto them by ray casting. Deleted again before export.
# ---------------------------------------------------------------------------

def rounded_rect(hx, hy, r, per_corner=2):
    pts = []
    for cx, cy, start in ((hx - r, hy - r, 0), (-hx + r, hy - r, 90),
                          (-hx + r, -hy + r, 180), (hx - r, -hy + r, 270)):
        for i in range(per_corner + 1):
            a = math.radians(start + 90 * i / per_corner)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def build_refs():
    torso = pk.box("RefTorso", (0.46, 0.27, 0.45), loc=(0, 0.005, 1.075), bevel=0.1, segments=3)
    for v in torso.data.vertices:
        if v.co.z < 0:
            v.co.x *= 0.8
            v.co.y *= 0.92
    pelvis = pk.box("RefPelvis", (0.36, 0.24, 0.18), loc=(0, 0.01, 0.8), bevel=0.07, segments=2)
    belt = pk.prism("RefBelt", rounded_rect(0.2, 0.135, 0.085), 0.06, loc=(0, 0.004, 0.875),
                    bevel=0.012, segments=1)
    chevron = pk.prism("RefChevron", [(0.0, -0.07), (0.13, 0.03), (0.13, 0.085), (0.0, -0.015),
                                      (-0.13, 0.085), (-0.13, 0.03)], 0.03, loc=(0, -0.136, 1.15),
                       rot=(90, 0, 0), bevel=0.007, segments=1)
    pads = [pk.sphere("RefPad" + t, 1.0, loc=(s * 0.265, 0, 1.255), scale=(0.13, 0.155, 0.085),
                      rot=(0, s * 24, 0), segments=12, rings=6) for s, t in ((LEFT, "L"), (RIGHT, "R"))]
    bpy.context.view_layer.update()
    for o in [torso, belt, chevron] + pads:
        o.matrix_world = LEAN_M @ o.matrix_world
    refs = [torso, pelvis, belt, chevron] + pads
    for o in refs:
        pk.select_only(o)
        for mod in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        bake(o)
    return refs


def bvh_of(objs):
    verts, polys = [], []
    for o in objs:
        base = len(verts)
        verts.extend(o.matrix_world @ v.co for v in o.data.vertices)
        polys.extend([base + i for i in p.vertices] for p in o.data.polygons)
    return BVHTree.FromPolygons(verts, polys)


REFS = build_refs()
BVH_TORSO = bvh_of(REFS[:4])          # torso + hips + belt + chest chevron
BVH_UPPER = bvh_of(REFS)              # ... + shoulder pads
STRAP_CENTRE = Vector((0.0, -0.02, 1.06))


def torso_frame(theta, zu):
    """Axis point and outward direction for azimuth theta (0 = front, +90 =
    the runner's left) at upright height zu, in the leaning torso's frame."""
    t = math.radians(theta)
    return lean((0.0, 0.005, zu)), LEAN_R @ Vector((math.sin(t), -math.cos(t), 0.0))


def on_torso(theta, zu, bvh=None):
    o, d = torso_frame(theta, zu)
    hit = (bvh or BVH_TORSO).ray_cast(o + d * 0.8, -d, 1.6)
    return (hit[0] if hit[0] is not None else o + d * 0.15), d


def wrap(name, thetas, zs, lift, thick, mats, face_mat=None, bvh=None):
    """A panel shrink-wrapped onto the torso: a thick slab over the azimuth
    range `thetas` and upright heights `zs`. face_mat(i, j) picks the material
    of each outer face (strips, trims)."""
    surf = [[on_torso(th, z, bvh) for th in thetas] for z in zs]
    bm = bmesh.new()
    outer = [[bm.verts.new(p + d * (lift + thick)) for p, d in row] for row in surf]
    inner = [[bm.verts.new(p + d * lift) for p, d in row] for row in surf]
    nj, ni = len(zs), len(thetas)
    for j in range(nj - 1):
        for i in range(ni - 1):
            f = bm.faces.new((outer[j][i], outer[j][i + 1], outer[j + 1][i + 1], outer[j + 1][i]))
            if face_mat:
                f.material_index = face_mat(i, j)
            bm.faces.new((inner[j][i], inner[j + 1][i], inner[j + 1][i + 1], inner[j][i + 1]))
        for i in (0, ni - 1):
            bm.faces.new((outer[j][i], outer[j + 1][i], inner[j + 1][i], inner[j][i]))
    for i in range(ni - 1):
        for j in (0, nj - 1):
            bm.faces.new((outer[j][i], inner[j][i], inner[j][i + 1], outer[j][i + 1]))
    closed_normals(bm)
    return new_obj(name, bm, mats)


def ring_band(name, z0, z1, lift, mats, n=14, bvh=None, span=None):
    """A stripe round the torso between upright heights z0 and z1, standing
    `lift` proud; its edges tuck into the body. With `span` (degrees) it only
    runs from -span to +span through the front, leaving the back to the pack."""
    if span is None:
        thetas = [360.0 * i / n for i in range(n)]
    else:
        thetas = [-span + 2.0 * span * i / (n - 1) for i in range(n)]
    lo = [on_torso(t, z0, bvh) for t in thetas]
    hi = [on_torso(t, z1, bvh) for t in thetas]
    bm = bmesh.new()
    rings = [[bm.verts.new(p - d * 0.004) for p, d in lo], [bm.verts.new(p + d * lift) for p, d in lo],
             [bm.verts.new(p + d * lift) for p, d in hi], [bm.verts.new(p - d * 0.004) for p, d in hi]]
    strips = connect(bm, rings, span is None)
    caps = []
    if span is not None:
        for i, sign in ((0, -1.0), (n - 1, 1.0)):
            caps.append((bm.faces.new([r[i] for r in rings]), i, sign))
    point_out(bm, strips[1][0], lo[0][1])
    for face, i, sign in caps:
        along_band = (lo[min(i + 1, n - 1)][0] - lo[max(i - 1, 0)][0]) * sign
        bm.normal_update()
        if face.normal.dot(along_band) < 0:
            face.normal_flip()
    return new_obj(name, bm, mats)


def strap(name, guide, width, thick, lift, mats, n=12, bvh=None, seg_mats=None):
    """A flat strap lying on the body along a guide path. Guide points are
    (x, y, z) or (x, y, z, False); False points float free (not pressed onto
    the body), e.g. where a sling leaves the body for a mop handle."""
    pts = catmull([g[:3] for g in guide], n)
    free = [len(g) > 3 and not g[3] for g in guide]
    bvh = bvh or BVH_UPPER
    surf = []
    for k, p in enumerate(pts):
        d = (p - STRAP_CENTRE).normalized()
        g = min(int(round(k * (len(guide) - 1) / (n - 1))), len(guide) - 1)
        hit = None if free[g] else bvh.ray_cast(STRAP_CENTRE + d * 1.2, -d, 2.0)[0]
        surf.append(((hit + d * lift) if hit is not None else p, d))
    bm = bmesh.new()
    rings = []
    for k, (s, d) in enumerate(surf):
        t = (surf[min(k + 1, n - 1)][0] - surf[max(k - 1, 0)][0]).normalized()
        side = t.cross(d).normalized()
        nrm = side.cross(t).normalized()
        w = side * width * 0.5
        rings.append([bm.verts.new(v) for v in (s - w, s + w, s + w + nrm * thick, s - w + nrm * thick)])
    connect(bm, rings, True, seg_mats, cap_first=True, cap_last=True)
    closed_normals(bm)
    return new_obj(name, bm, mats)


# ---------------------------------------------------------------------------
# Outfit bookkeeping: every piece is added to one of four groups; at the end
# each group is smoothed, joined into one mesh and hung on the right node.
# ---------------------------------------------------------------------------

OUTFITS = {}          # id -> {"body": [], "head": [], "L": [], "R": []}
_current = None


def outfit(oid):
    global _current
    _current = OUTFITS.setdefault(oid, {"body": [], "head": [], "L": [], "R": []})


def add(obj, where="body", smooth=35.0):
    """smooth: an angle (sharper edges stay crisp), -1 = fully smooth, 0 = flat."""
    obj["pk_smooth"] = smooth
    _current[where].append(obj)
    return obj


def finalize(obj):
    pk.select_only(obj)
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bake(obj)
    s = obj.get("pk_smooth", 35.0)
    pk.select_only(obj)
    if s < 0:
        bpy.ops.object.shade_smooth(keep_sharp_edges=False)
    elif s == 0:
        bpy.ops.object.shade_flat()
    else:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(s))


def world_join(name, parts):
    for p in parts:
        finalize(p)
    obj = pk.join(name, parts) if len(parts) > 1 else parts[0]
    bake(obj)
    obj.name = name
    obj.data.name = name
    return obj


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def interp(table, z):
    """Linear interpolation in a table of (z, values...) rows sorted by falling z."""
    if z >= table[0][0]:
        return table[0][1:]
    for a, b in zip(table, table[1:]):
        if b[0] <= z <= a[0]:
            t = (a[0] - z) / (a[0] - b[0])
            return tuple(x + (y - x) * t for x, y in zip(a[1:], b[1:]))
    return table[-1][1:]


# ===========================================================================
# GHOST (player-selectable). A bedsheet thrown over the head and shoulders:
# a rounded cone over the head with two big glowing eyes, flaring over the
# shoulders. In front it stops at the chest so the arms and the gun stay in
# view; behind the arms it falls to mid-thigh with a ragged zig-zag hem, a
# team-coloured stripe along the hem (like a bedsheet's border) and a hole
# cut for the backpack. A translucent fringe hangs under the hem. Head hidden.
# ===========================================================================

SEAM_NORMALS = {}     # GHOST sheet: vertex position -> normal across the head/body seam


def seam_key(co):
    return tuple(round(c, 4) for c in co)


def build_ghost():
    outfit("GHOST")
    sheet_m = M("PK_GhostSheet", "PK_Body", "#E6F4F1", roughness=0.75, double_sided=True)
    veil_m = pk.mat("PK_Glass", name="PK_GhostVeil", color="#DDF6F4", alpha=0.5, double_sided=True)
    rng = random.Random(11)
    n_cols, n_drape = 28, 5
    seam_z = 1.40
    dome = [(1.612, 0.075, 0.073), (1.58, 0.135, 0.13), (1.535, 0.182, 0.172),
            (1.48, 0.218, 0.205), (1.43, 0.248, 0.232), (seam_z, 0.27, 0.245)]
    #        z     rx     ry front ry back
    drape = [(seam_z, 0.27, 0.245, 0.245), (1.36, 0.30, 0.258, 0.248), (1.30, 0.37, 0.275, 0.245),
             (1.22, 0.432, 0.295, 0.238), (1.12, 0.462, 0.31, 0.228), (0.95, 0.475, 0.32, 0.228),
             (0.80, 0.478, 0.33, 0.25), (0.45, 0.48, 0.34, 0.31)]

    def axis_y(z):
        if z >= seam_z:
            return -0.065
        if z >= 1.10:
            return -0.065 + 0.03 * (seam_z - z) / (seam_z - 1.10)
        return -0.035 + 0.035 * min(1.0, (1.10 - z) / 0.55)

    def at(z, th):
        t = math.radians(th)
        if z >= seam_z:
            rx, ry = interp([(d[0], d[1], d[2]) for d in dome], z)
        else:
            rx, ryf, ryb = interp(drape, z)
            w = (1 - math.cos(t)) * 0.5
            ry = ryf * (1 - w) + ryb * w
        amp = 0.0 if z >= 1.30 else min(1.0, (1.30 - z) / 0.4) * 0.035
        fold = 1.0 + amp * math.sin(7 * t + 0.6)
        return Vector((rx * math.sin(t) * fold, axis_y(z) - ry * math.cos(t) * fold, z))

    def hem_base(a):
        if a <= 40:
            return 1.13
        if a <= 88:
            return 1.13 - 0.13 * smoothstep((a - 40) / 48)
        if a <= 110:
            return 1.0 - 0.44 * smoothstep((a - 88) / 22)
        return 0.56

    bm = bmesh.new()
    part = bm.faces.layers.int.new("part")
    pole = bm.verts.new((0.0, -0.065, 1.625))
    cols, hems = [], []
    for i in range(n_cols):
        th = 360.0 * i / n_cols
        hem = hem_base(min(th, 360 - th)) + (0.032 if i % 2 == 0 else -0.032) + rng.uniform(-0.012, 0.012)
        zs = ([d[0] for d in dome]
              + [seam_z + (hem + 0.105 - seam_z) * k / n_drape for k in range(1, n_drape + 1)]
              + [hem + 0.05, hem])
        cols.append([bm.verts.new(at(z, th)) for z in zs])
        hems.append(hem)
    n_rows = len(cols[0])
    rings = [[pole]] + [[cols[i][r] for i in range(n_cols)] for r in range(n_rows)]
    seam_ring = len(dome)                          # rings index of the z = 1.40 row
    stripe = seam_ring + n_drape                   # strip from hem+0.105 to hem+0.05
    mats = [0] * (len(rings) - 1)
    mats[stripe] = 1
    strips = connect(bm, rings, True, mats)
    for k, row in enumerate(strips):
        for f in row:
            f[part] = 0 if k < seam_ring else 1      # 0 = head, 1 = body
    point_out(bm, strips[seam_ring + 2][0], Vector((0, -1, 0)))
    # The hole the backpack pokes out of.
    hole = [f for f in bm.faces if (lambda c: c.y > 0.0 and abs(c.x) < 0.265 and 0.79 < c.z < 1.41)
            (f.calc_center_median())]
    bmesh.ops.delete(bm, geom=hole, context="FACES")
    bm.normal_update()
    for v in rings[seam_ring]:
        if v.is_valid and v.link_faces:
            SEAM_NORMALS[seam_key(v.co)] = v.normal.copy()

    def piece(name, keep):
        b = bm.copy()
        lay = b.faces.layers.int.get("part")
        bmesh.ops.delete(b, geom=[f for f in b.faces if f[lay] != keep], context="FACES")
        return new_obj(name, b, [sheet_m, TEAM])

    head = piece("GhostHood", 0)
    body = piece("GhostDrape", 1)
    bm.free()
    add(head, "head", -1)
    add(body, "body", -1)

    # Translucent fringe under the hem, its zig-zag out of step with the hem's.
    vb = bmesh.new()
    vrings = [[], [], []]
    for i in range(n_cols):
        th = 360.0 * i / n_cols
        for ring, dz, push in ((vrings[0], 0.042, 0.010), (vrings[1], -0.02, 0.018),
                               (vrings[2], -0.085 - (0.03 if i % 2 else -0.01), 0.03)):
            p = at(hems[i] + dz, th)
            ax = Vector((0.0, axis_y(p.z), p.z))
            ring.append(vb.verts.new(p + (p - ax).normalized() * push))
    vstrips = connect(vb, vrings, True)
    point_out(vb, vstrips[0][0], Vector((0, -1, 0)))
    add(new_obj("GhostVeil", vb, [veil_m]), "body", -1)

    # Face: big glowing team eyes in dark sockets, and a small round "oo" mouth.
    def surface(z, th):
        p = at(z, th)
        t1 = at(z, th + 1.0) - at(z, th - 1.0)
        t2 = at(z + 0.01, th) - at(z - 0.01, th)
        n = t2.cross(t1).normalized()
        if n.dot(p - Vector((0, -0.065, z))) < 0:
            n = -n
        return p, n

    for side, tag in ((LEFT, "L"), (RIGHT, "R")):
        p, n = surface(1.478, side * 17.0)
        add(disc("GhostSocket" + tag, p + n * 0.001, n, (0, 0, 1), 0.041, 0.058, 0.012, [DARK]),
            "head", 30)
        add(disc("GhostEye" + tag, p + n * 0.005, n, (0, 0, 1), 0.029, 0.045, 0.02, [GLOW]), "head", 30)
    p, n = surface(1.418, 0.0)
    add(disc("GhostMouth", p + n * 0.002, n, (0, 0, 1), 0.022, 0.028, 0.014, [DARK]), "head", 30)


def apply_seam_normals(obj):
    """Give the hood/drape seam the normals the unbroken sheet had, so the cut
    between GHOST_Head and GHOST_Body does not show as a shading line."""
    me = obj.data
    normals = [Vector(c.vector) for c in me.corner_normals]
    names = {"PK_GhostSheet"}
    sheet_slots = {i for i, m in enumerate(me.materials) if m and m.name in names}
    changed = 0
    for poly in me.polygons:
        if poly.material_index not in sheet_slots:
            continue
        for li in poly.loop_indices:
            key = seam_key(me.vertices[me.loops[li].vertex_index].co)
            if key in SEAM_NORMALS:
                normals[li] = SEAM_NORMALS[key]
                changed += 1
    me.normals_split_custom_set([tuple(n) for n in normals])
    return changed



# ===========================================================================
# SAMURAI (player-selectable). Black-lacquer armour laced in team colour:
# a kabuto bowl over the helmet with a sloped brim, a flared two-lame neck
# guard (lifted at the back to clear the pack), turn-backs with team crests
# and a big team-coloured crescent moon on the brow; layered sode on both
# shoulders, a do chest plate, six tasset plates hanging from the belt (on
# the body) and shin guards (on the legs). Keeps the runner's Head.
# ===========================================================================

def build_samurai():
    outfit("SAMURAI")
    lac = M("PK_SamuraiLacquer", "PK_Body", "#2E2638", roughness=0.25)
    mats = [lac, TEAM, BRASS]

    # Kabuto bowl: a lathe round the helmet, its bottom lip tucked into it.
    add(vlathe("SamKabuto", HEAD, [(0.0, 0.198), (0.065, 0.192), (0.12, 0.172), (0.162, 0.132),
                                   (0.19, 0.08), (0.2, 0.05), (0.197, 0.04), (0.165, 0.034)],
               mats, strip_mats=[0, 0, 0, 0, 0, 2, 0], segments=12), smooth=40)
    add(pk.cyl("SamTehen", 0.026, 0.02, loc=(HEAD.x, HEAD.y, HEAD.z + 0.198), material=BRASS,
               verts=6), smooth=30)
    # Brim over the visor.
    add(arc_plate("SamBrim", HEAD, (0, 0, 1), (0, -1, 0), -64, 64,
                  [(0.198, 0.054), (0.258, 0.014)], 0.016, [lac], steps=4), smooth=40)

    # Neck guard: two lames. At the sides they hang down; toward the back they
    # flare out flatter so they stay above the backpack (z > 1.45).
    def lame(top, bot_side, bot_back, r0, r1_side, r1_back):
        def rows(a):
            b = smoothstep((abs(((a + 180) % 360) - 180) - 90) / 90)   # 0 sides .. 1 back
            hb = bot_side + (bot_back - bot_side) * b
            r1 = r1_side + (r1_back - r1_side) * b
            ht = top + (0.0 if top > 0.04 else 0.046 * b)
            return [(r0, ht), (r0 + (r1 - r0) * 0.7, ht + (hb - ht) * 0.7), (r1, hb)]
        return rows
    for k, rows in enumerate((lame(0.05, -0.012, 0.04, 0.199, 0.236, 0.255),
                              lame(0.004, -0.05, 0.034, 0.232, 0.272, 0.305))):
        add(arc_plate("SamShikoro%d" % k, HEAD, (0, 0, 1), (0, -1, 0), 64, 296, rows, 0.016,
                      mats, steps=5, row_mats=[0, 1]), smooth=40)
    # Fukigaeshi: the turned-back ears of the neck guard, each with a team crest.
    for side, tag in ((LEFT, "L"), (RIGHT, "R")):
        a = math.radians(side * 70)
        radial = Vector((math.sin(a), -math.cos(a), 0.0))
        face = (radial + Vector((0, -1.1, 0))).normalized()
        c = HEAD + radial * 0.255 + Vector((0, 0, 0.012))
        add(disc("SamFuki" + tag, c, face, (0, 0, 1), 0.045, 0.052, 0.016, [lac], verts=7), smooth=30)
        add(disc("SamMon" + tag, c + face * 0.01, face, (0, 0, 1), 0.022, 0.022, 0.01, [TEAM],
                 verts=6), smooth=30)
    # Crescent moon crest (maedate), team coloured, on a brass mount.
    outline = []
    for k in range(10):
        t = k / 9
        a = math.radians(196 + 148 * t)
        outline.append((0.205 * math.cos(a), 0.205 + 0.205 * math.sin(a)))
    for k in range(9, -1, -1):
        t = k / 9
        a = math.radians(196 + 148 * t)
        r = 0.205 - (0.018 + 0.05 * math.sin(math.pi * t))
        outline.append((r * math.cos(a), 0.205 + r * math.sin(a) + 0.006))
    add(bake(pk.prism("SamCrest", outline, 0.022, loc=(0, -0.283, 1.488), rot=(90 - 14, 0, 0),
                      material=TEAM)), smooth=30)
    add(pk.box("SamMount", (0.06, 0.03, 0.05), loc=(0, -0.262, 1.49), rot=(-14, 0, 0),
               material=BRASS), smooth=30)

    # Sode: three curved lames per shoulder, each laced along its lower edge.
    for side, tag in ((LEFT, "L"), (RIGHT, "R")):
        for k in range(3):
            zt = 1.305 - 0.074 * k
            rt = 0.245 + 0.036 * k
            add(arc_plate("SamSode%s%d" % (tag, k), (side * 0.14, -0.05, 0), (0, 0, 1), (0, -1, 0),
                          side * 90 - 30, side * 90 + 30,
                          [(rt, zt), (rt + 0.036, zt - 0.068), (rt + 0.046, zt - 0.092)], 0.018,
                          mats, steps=2, row_mats=[0, 1]), smooth=40)

    # Do: the chest plate, shrink-wrapped onto the torso, with a team lacing row.
    add(wrap("SamDo", [-100, -66, -40, -14, 14, 40, 66, 100], [0.93, 1.0, 1.05, 1.15, 1.22, 1.27], 0.01, 0.02,
             mats, face_mat=lambda i, j: 1 if j == 1 else 0), smooth=40)

    # Kusazuri: six tasset plates hanging from the belt, two lacing rows each.
    for k, centre in enumerate((-150, -90, -30, 30, 90, 150)):
        add(arc_plate("SamTasset%d" % k, (0, 0.01, 0), (0, 0, 1), (0, -1, 0), centre - 25, centre + 25,
                      [(0.232, 0.85), (0.258, 0.72), (0.27, 0.685), (0.282, 0.635)],
                      0.016, mats, steps=2, scale=(1.0, 0.76), row_mats=[0, 1, 0]), smooth=40)

    # Suneate: shin guards on the legs, tied on with a team band.
    for tag in ("L", "R"):
        _, knee, ankle = LEG[tag]
        add(arc_plate("SamShin" + tag, ankle, knee - ankle, (0, -1, 0), -72, 72,
                      [(0.104, 0.235), (0.101, 0.205), (0.097, 0.18), (0.09, 0.07)], 0.016,
                      mats, steps=3, row_mats=[1, 0, 0]), tag, smooth=40)


# ===========================================================================
# CYBERPUNK (player-selectable). A black leather jacket shrink-wrapped onto
# the torso: open front with neon-yellow zip edges, a team-glow hem line all
# round (it shows under the backpack too), sleeves with glowing team cuffs
# and a popped collar. A mohawk of glowing team spikes over the helmet,
# small round tech goggles over the visor and steel spikes on the shoulder
# pads. Keeps the runner's Head.
# ===========================================================================

def spike(name, base, direction, length, radius, mats, sides=6):
    d = Vector(direction).normalized()
    return loft(name, [Vector(base), Vector(base) + d * length], [radius, 0.0], mats, sides=sides,
                up=d.orthogonal())


def build_cyberpunk():
    outfit("CYBERPUNK")
    jacket = M("PK_CyberJacket", "PK_Body", "#1C1A26", roughness=0.35)
    neon = M("PK_CyberNeon", "PK_TeamGlow", "#F4E04D", emission=1.5)
    mats = [jacket, GLOW, neon]
    zs = [0.795, 0.825, 0.92, 1.04, 1.16, 1.22, 1.27]
    # Front panels; the column at the zip edge is neon, the bottom row team glow.
    add(wrap("CyJacketL", [8, 14, 40, 66, 92, 114], zs, 0.012, 0.02, mats,
             face_mat=lambda i, j: 1 if j == 0 else (2 if i == 0 else 0)), smooth=40)
    add(wrap("CyJacketR", [-114, -92, -66, -40, -14, -8], zs, 0.012, 0.02, mats,
             face_mat=lambda i, j: 1 if j == 0 else (2 if i == 4 else 0)), smooth=40)
    # Back of the hem, below the backpack.
    add(wrap("CyJacketBack", [114, 147, 180, 213, 246], [0.765, 0.795, 0.825], 0.016, 0.02, mats,
             face_mat=lambda i, j: 1 if j == 0 else 0), smooth=40)
    # Popped collar, front and sides only (the hose and the pack own the back).
    for side, tag in ((LEFT, "L"), (RIGHT, "R")):
        a0, a1 = sorted((side * 40, side * 84))
        add(arc_plate("CyCollar" + tag, (0, -0.045, 0), (0, 0, 1), (0, -1, 0), a0, a1,
                      [(0.205, 1.385), (0.17, 1.262)], 0.016, mats, steps=2), smooth=40)
    # Sleeves with a glowing team cuff above the elbow.
    for tag in ("L", "R"):
        add(limb_band("CySleeve" + tag, tag, "upper", 0.05, 1.0, 0.0, mats, segments=10,
                      prof=[(-0.004, 0.0), (0.017, 0.12), (0.017, 0.82), (0.022, 0.86),
                            (0.022, 0.96), (-0.004, 1.0)], strip_mats=[0, 0, 0, 1, 0]), smooth=40)

    # Mohawk: a ridge over the helmet's centre line and six glowing spikes.
    ridge = [helmet_point(0, p, 0.004)[0] for p in (42, 58, 74, 90)]
    ridge += [helmet_point(180, p, 0.004)[0] for p in (74, 58, 42)]
    add(loft("CyRidge", ridge, [0.0] + [0.024] * 5 + [0.0], [jacket], sides=6, up=(1, 0, 0),
             flat=0.55), smooth=-1)
    for k, (th, ph, length) in enumerate(((0, 50, 0.09), (0, 66, 0.12), (0, 82, 0.145),
                                          (180, 82, 0.145), (180, 66, 0.12), (180, 50, 0.09))):
        p, n = helmet_point(th, ph, 0.0)
        add(spike("CySpike%d" % k, p, n + Vector((0, 0.45, 0)), length, 0.03, [GLOW]), smooth=30)

    # Goggles: two round lenses on a bridge and a strap round the helmet.
    for side, tag in ((LEFT, "L"), (RIGHT, "R")):
        p, n = helmet_point(side * 21, -3, 0.03)
        add(disc("CyGoggle" + tag, p, n, (0, 0, 1), 0.044, 0.038, 0.04, [TRIM, neon], verts=10,
                 front_mat=1), smooth=30)
    p, n = helmet_point(0, -3, 0.034)
    add(pk.box("CyBridge", (0.05, 0.02, 0.02), loc=tuple(p), material=TRIM), smooth=30)
    add(ellipsoid_patch("CyStrap", HEAD, HEAD_R, (30, 330), (-8, 3), (10, 1), 0.026, 0.004, [TRIM]),
        smooth=40)

    # Steel spikes on the shoulder pads.
    for side, tag in ((LEFT, "L"), (RIGHT, "R")):
        for k, (lon, lat, length) in enumerate(((0, 52, 0.1), (45, 46, 0.08), (-45, 46, 0.08))):
            p, n = pad_point(side, lon, lat, -0.008)
            add(spike("CyPadSpike%s%d" % (tag, k), p, n + Vector((0, 0, 0.45)), length, 0.028,
                      [METAL]), smooth=30)


# ===========================================================================
# ART_CRITIC (bot only). A floppy wine-red beret slumped to one side, a brass
# monocle over the right eye on a chain, a long team-coloured scarf wound
# round the neck with one short end on the chest and one long end flung back
# over the left shoulder to hang beside the backpack, and a clipboard on a
# leather chest strap carrying the verdict: a team-coloured tick. Keeps the
# runner's Head.
# ===========================================================================

def along(direction):
    """Euler rotation (degrees) that turns local +Z toward `direction`."""
    e = Vector(direction).to_track_quat("Z", "Y").to_euler()
    return tuple(math.degrees(a) for a in e)


def framed(obj, centre, normal, up, roll=0.0):
    """Stand a part built round the origin (its face toward -Y, top toward +Z)
    at `centre`, its face toward `normal`, rolled `roll` degrees, and bake it."""
    n = Vector(normal).normalized()
    u = Vector(up)
    u = (u - n * u.dot(n)).normalized()
    u = Matrix.Rotation(math.radians(roll), 3, n) @ u
    x = u.cross(n).normalized()
    rot = Matrix((x, -n, u)).transposed().to_4x4()
    bpy.context.view_layer.update()
    obj.matrix_world = Matrix.Translation(Vector(centre)) @ rot @ obj.matrix_world
    return bake(obj)


def build_art_critic():
    outfit("ART_CRITIC")
    beret_m = M("PK_CriticBeret", "PK_Body", "#8C2B48", roughness=0.8)
    leather = M("PK_CriticLeather", "PK_Body", "#6B4430", roughness=0.55)
    paper = M("PK_CriticPaper", "PK_Body", "#F5EEDC", roughness=0.9)
    cream = M("PK_CriticCream", "PK_Body", "#F2E6C9", roughness=0.85)
    glass = pk.mat("PK_Glass", name="PK_MonocleGlass", color="#DDEBF5", alpha=0.45)

    # Beret: a fat felt disc whose underside follows the helmet, its rim
    # sagging toward the runner's right, the whole thing slumped that way.
    base = Vector((-0.02, -0.07, 1.592))
    beret = vlathe("CriticBeret", base, [(0.0, 0.074), (0.09, 0.071), (0.165, 0.052), (0.214, 0.014),
                                         (0.206, -0.016), (0.16, -0.03), (0.11, -0.042),
                                         (0.055, -0.014), (0.0, -0.006)], [beret_m], segments=14)
    for v in beret.data.vertices:
        rel = v.co - base
        r = rel.xy.length
        if r > 0.13:
            a = math.atan2(rel.y, rel.x)
            v.co.z -= 0.035 * (r - 0.13) / 0.085 * (1 + math.cos(a - math.pi)) * 0.5
    stalk = loft("CriticStalk", [base + Vector((0, 0, 0.068)), base + Vector((0.006, 0, 0.1))],
                 [0.014, 0.011], [beret_m], sides=6)
    for o in (beret, stalk):
        add(tilt(o, base, rx=7, ry=-15), smooth=50)

    # Monocle over the right eye, with a chain down to the clipboard.
    p, n = helmet_point(RIGHT * 22, 2, 0.026)
    add(bake(pk.torus("CriticMonocle", 0.04, 0.009, loc=tuple(p), rot=along(n), material=BRASS,
                      segments=12, ring_segments=5)), smooth=-1)
    add(disc("CriticLens", p, n, (0, 0, 1), 0.036, 0.036, 0.005, [glass], verts=10), smooth=30)
    chain = [p + Vector((RIGHT * 0.035, 0, -0.022)), Vector((-0.14, -0.29, 1.37)),
             Vector((-0.15, -0.29, 1.29)), Vector((-0.12, -0.27, 1.23)), Vector((-0.085, -0.25, 1.205))]
    add(loft("CriticChain", catmull(chain, 7), [0.008] * 7, [BRASS], sides=4), smooth=-1)

    # Scarf: a lumpy team-coloured ring round the neck, tilted so it sits on
    # the chest in front and above the backpack behind, plus a knot and ends.
    ring = bake(pk.torus("CriticScarf", 0.19, 0.05, loc=(0, -0.055, 1.367), rot=(22, 0, 0),
                         material=TEAM, segments=14, ring_segments=6))
    add(lumpy(ring, 0.008, 3), smooth=-1)
    add(bake(pk.sphere("CriticKnot", 1.0, loc=(0.055, -0.245, 1.285), scale=(0.055, 0.04, 0.045),
                       material=TEAM, segments=8, rings=5)), smooth=-1)
    add(loft("CriticScarfFront", [(0.05, -0.25, 1.28), (0.064, -0.236, 1.21), (0.06, -0.228, 1.16),
                                  (0.056, -0.226, 1.125)], [0.044, 0.046, 0.045, 0.043], [TEAM, cream],
             sides=6, up=(0, -1, 0), flat=0.34, seg_mats=[0, 0, 1]), smooth=-1)
    back_end = catmull([(0.15, -0.04, 1.392), (0.23, 0.04, 1.40), (0.285, 0.13, 1.33), (0.30, 0.185, 1.2),
                        (0.31, 0.205, 1.07), (0.32, 0.22, 0.95)], 8)
    add(loft("CriticScarfBack", back_end, [0.044, 0.046, 0.047, 0.047, 0.047, 0.047, 0.046, 0.044],
             [TEAM, cream], sides=6, up=(0, 0, 1), flat=0.34, seg_mats=[0, 0, 0, 0, 0, 1, 0]), smooth=-1)

    # Leather strap from the right shoulder across the chest to the left hip.
    add(strap("CriticStrap", [(-0.12, 0.09, 1.25), (-0.135, 0.0, 1.33), (-0.12, -0.11, 1.27),
                              (-0.02, -0.17, 1.14), (0.10, -0.15, 0.98), (0.19, -0.07, 0.88),
                              (0.19, 0.06, 0.85)], 0.045, 0.01, 0.006, [leather], n=14), smooth=40)

    # Clipboard clipped onto the strap on the upper right chest.
    surf, d = on_torso(-24, 1.11, BVH_UPPER)
    facing = (LEAN_R @ Vector((-0.18, -1.0, 0.0))).normalized()
    up = LEAN_R @ Vector((0, 0, 1))
    centre = surf + facing * 0.03
    roll = -10.0
    add(framed(pk.box("CriticBoard", (0.13, 0.016, 0.175), material=WOOD, bevel=0.005, segments=1),
               centre, facing, up, roll), smooth=30)
    add(framed(pk.box("CriticPaper", (0.11, 0.006, 0.14), loc=(0, -0.01, -0.012), material=paper),
               centre, facing, up, roll), smooth=30)
    add(framed(pk.box("CriticClip", (0.056, 0.02, 0.03), loc=(0, -0.012, 0.082), material=BRASS),
               centre, facing, up, roll), smooth=30)
    for k, (w, z) in enumerate(((0.075, 0.042), (0.06, 0.018))):
        add(framed(pk.box("CriticLine%d" % k, (w, 0.006, 0.016), loc=(-0.005, -0.014, z), material=DARK),
                   centre, facing, up, roll), smooth=30)
    tick = [(-0.036, -0.012), (-0.024, 0.0), (-0.01, -0.018), (0.03, 0.026), (0.043, 0.014),
            (-0.01, -0.042)]
    add(framed(pk.prism("CriticTick", tick, 0.008, loc=(0, -0.016, -0.02), rot=(90, 0, 0), material=TEAM),
               centre, facing, up, roll), smooth=30)


# ===========================================================================
# JANITOR (bot only). Denim overall bib and straps over a khaki work suit,
# a bib pocket with a team-coloured rag stuffed in it, an olive bucket hat
# with a team hat band, big yellow rubber glove cuffs, and a string mop slung
# diagonally beside the backpack: handle from the left hip up past the left
# shoulder, its head dunked in team paint, held by a sling across the chest.
# Keeps the runner's Head.
# ===========================================================================

def build_janitor():
    outfit("JANITOR")
    denim = M("PK_JanitorDenim", "PK_Body", "#3F5878", roughness=0.85)
    pocket = M("PK_JanitorPocket", "PK_Body", "#4E6C93", roughness=0.85)
    yellow = M("PK_JanitorGlove", "PK_Body", "#F2C230", roughness=0.35)
    hat_m = M("PK_JanitorHat", "PK_Body", "#6F7B52", roughness=0.85)
    cotton = M("PK_MopCotton", "PK_Body", "#D9D3C2", roughness=0.95)

    # Overalls: bib, pocket, straps over the shoulders, brass buttons.
    add(wrap("JanBib", [-40, -20, 0, 20, 40], [0.90, 0.98, 1.08, 1.18], 0.01, 0.018, [denim]), smooth=40)
    add(wrap("JanPocket", [-34, -20, -6], [1.0, 1.06, 1.12], 0.03, 0.012, [pocket]), smooth=40)
    p, d = on_torso(-20, 1.125)
    rag = bake(pk.sphere("JanRag", 1.0, loc=tuple(p + d * 0.05 + Vector((0, 0, 0.012))),
                         scale=(0.042, 0.028, 0.034), material=TEAM, segments=8, rings=5))
    add(lumpy(rag, 0.008, 5), smooth=-1)
    add(loft("JanRagCorner", [p + d * 0.05 + Vector((0.01, 0, 0.03)), p + d * 0.075 + Vector((0.03, 0, 0.02)),
                              p + d * 0.08 + Vector((0.04, 0, -0.03))], [0.026, 0.02, 0.0], [TEAM], sides=5),
        smooth=-1)
    for side, tag in ((LEFT, "L"), (RIGHT, "R")):
        add(strap("JanStrap" + tag, [(side * 0.105, -0.17, 1.165), (side * 0.12, -0.13, 1.26),
                                     (side * 0.13, -0.03, 1.32), (side * 0.128, 0.065, 1.305)],
                  0.045, 0.012, 0.012, [denim], n=8),
            smooth=40)
        p, d = on_torso(side * 36, 1.16)
        add(disc("JanButton" + tag, p + d * 0.034, d, LEAN_R @ Vector((0, 0, 1)), 0.018, 0.018, 0.014,
                 [BRASS], verts=8), smooth=30)

    # Bucket hat with a team band.
    hat = vlathe("JanHat", (HEAD.x, HEAD.y, 0.0),
                 [(0.0, 1.655), (0.12, 1.652), (0.148, 1.635), (0.163, 1.565), (0.167, 1.515),
                  (0.27, 1.47), (0.268, 1.457), (0.165, 1.497)], [hat_m, TEAM],
                 strip_mats=[0, 0, 0, 1, 0, 0, 0], segments=14)
    add(tilt(hat, HEAD, rx=5, ry=4), smooth=40)

    # Yellow rubber glove cuffs flaring toward the hands.
    for tag in ("L", "R"):
        add(limb_band("JanCuff" + tag, tag, "fore", 0.45, 0.88, 0.0, [yellow], segments=10,
                      prof=[(-0.004, 0.0), (0.018, 0.1), (0.024, 0.72), (0.036, 0.94), (0.012, 1.0)]),
            smooth=40)

    # The mop, beside the backpack (which ends at x = 0.2), head up.
    a, b = Vector((0.16, 0.175, 0.70)), Vector((0.48, 0.21, 1.55))
    u = (b - a).normalized()
    add(loft("JanMopHandle", [a, b], [0.019, 0.019], [WOOD], sides=8), smooth=40)
    add(loft("JanMopFerrule", [b - u * 0.012, b + u * 0.06], [0.03, 0.032], [METAL], sides=8), smooth=40)
    # Mop head: a bell of cotton strands flopping down round the ferrule, its
    # ragged ends dunked in team paint.
    c = b + u * 0.07
    f = (Vector((0, -1, 0)) - u * Vector((0, -1, 0)).dot(u)).normalized()
    s = u.cross(f)
    segs = 12
    head = lathe_axis("JanMopHead", c, c + u, [(0.0, 0.08), (0.06, 0.07), (0.1, 0.03), (0.12, -0.04),
                                              (0.13, -0.11), (0.135, -0.16), (0.13, -0.2), (0.0, -0.17)],
                      [cotton, TEAM], strip_mats=[0, 0, 0, 0, 1, 1, 1], segments=segs, front=f)
    for v in head.data.vertices:
        rel = v.co - c
        h = rel.dot(u)
        radial = rel - u * h
        if radial.length < 1e-4 or h > 0.05:
            continue
        ang = math.atan2(radial.dot(s), radial.dot(f))
        k = int(round(ang / (TAU / segs))) % segs
        groove = 1.0 + (0.22 if k % 2 == 0 else -0.14) * min(1.0, (0.05 - h) / 0.08)
        v.co = c + u * h + radial * groove
        if h < -0.19:
            v.co += u * (-0.05 if k % 2 == 0 else 0.02)
    head.data.update()
    add(head, smooth=-1)
    for k in range(4):
        ang = TAU * (k * 3 + 1.0) / segs
        radial = f * math.cos(ang) + s * math.sin(ang)
        st = c + radial * 0.115 - u * 0.12
        add(loft("JanMopStrand%d" % k, [st, st + radial * 0.05 + Vector((0, 0, -0.1)),
                                       st + radial * 0.065 + Vector((0, 0, -0.17 - 0.03 * (k % 2)))],
                 [0.024, 0.021, 0.017], [TEAM], sides=5), smooth=-1)
    # Sling: from the handle over the left shoulder, across the chest, round
    # the right hip and under the backpack back to the foot of the handle.
    add(strap("JanSling", [(0.383, 0.19, 1.30, False), (0.3, 0.11, 1.37, False), (0.2, 0.0, 1.38),
                           (0.14, -0.11, 1.27), (0.02, -0.17, 1.12), (-0.11, -0.16, 0.97),
                           (-0.19, -0.07, 0.87), (-0.18, 0.06, 0.82), (0.0, 0.14, 0.80),
                           (0.15, 0.15, 0.785), (0.194, 0.172, 0.79, False)],
              0.04, 0.012, 0.032, [RUBBER], n=18), smooth=40)


# ===========================================================================
# MIME (bot only). A Breton shirt whose stripes are team-coloured bands
# round the torso and arms, a white face plate over the visor painted with
# glowing team eyes, arched brows, small dark lips and a teardrop, a small
# black beret tipped to the left, and dark suspenders. Keeps the runner's
# Head (painted white).
# ===========================================================================

def build_mime():
    outfit("MIME")
    face_m = M("PK_MimeFace", "PK_Body", "#FAF8F3", roughness=0.35)
    beret_m = M("PK_MimeBeret", "PK_Body", "#1F1D25", roughness=0.85)
    braces = M("PK_MimeBraces", "PK_Body", "#2A2633", roughness=0.6)

    # Stripes: four bands round the torso, three on each arm.
    for k, z in enumerate((0.935, 1.03, 1.125, 1.22)):
        add(ring_band("MimeStripe%d" % k, z, z + 0.042, 0.012, [TEAM], n=11, span=118), smooth=40)
    for tag in ("L", "R"):
        for k, (part, f0, f1) in enumerate((("upper", 0.66, 0.82), ("fore", 0.1, 0.24),
                                            ("fore", 0.38, 0.52))):
            add(limb_band("MimeArmStripe%s%d" % (tag, k), tag, part, f0, f1, 0.012, [TEAM]), smooth=40)

    # Face plate and its painted features.
    add(ellipsoid_patch("MimeFace", HEAD, HEAD_R, (-88, 88), (-36, 24), (8, 3), 0.03, 0.03, [face_m]),
        smooth=40)
    for side, tag in ((LEFT, "L"), (RIGHT, "R")):
        lo, hi = sorted((side * 12, side * 34))
        add(ellipsoid_patch("MimeEye" + tag, HEAD, HEAD_R, (lo, hi), (-3, 11), (3, 2), 0.037, 0.0,
                            [GLOW]), smooth=40)
        brow = [helmet_point(side * t, p, 0.035)[0] for t, p in ((8, 15), (17, 20), (27, 21), (37, 17))]
        add(loft("MimeBrow" + tag, brow, [0.0, 0.01, 0.01, 0.0], [DARK], sides=4, up=(0, -1, 0)),
            smooth=-1)
    add(ellipsoid_patch("MimeLips", HEAD, HEAD_R, (-11, 11), (-27, -21), (2, 1), 0.036, 0.0, [DARK]),
        smooth=40)
    p, n = helmet_point(RIGHT * 24, -11, 0.036)
    add(disc("MimeTear", p, n, (0, 0, 1), 0.011, 0.018, 0.008, [DARK], verts=6), smooth=30)

    # Small black beret tipped toward the runner's left.
    base = Vector((0.03, -0.072, 1.592))
    beret = vlathe("MimeBeret", base, [(0.0, 0.05), (0.07, 0.048), (0.118, 0.032), (0.143, 0.008),
                                       (0.136, -0.012), (0.1, -0.024), (0.05, -0.01), (0.0, -0.004)],
                   [beret_m], segments=12)
    stalk = loft("MimeStalk", [base + Vector((0, 0, 0.045)), base + Vector((0.004, 0, 0.074))],
                 [0.012, 0.01], [beret_m], sides=6)
    for o in (beret, stalk):
        add(tilt(o, base, rx=5, ry=18), smooth=50)

    # Suspenders from the belt over the shoulders, with brass clips.
    for side, tag in ((LEFT, "L"), (RIGHT, "R")):
        add(strap("MimeBrace" + tag, [(side * 0.09, -0.15, 0.885), (side * 0.1, -0.178, 1.0),
                                      (side * 0.115, -0.152, 1.18), (side * 0.13, -0.03, 1.32),
                                      (side * 0.128, 0.065, 1.305)],
                  0.04, 0.012, 0.016, [braces], n=9), smooth=40)
        p, d = on_torso(side * 30, 0.905)
        add(disc("MimeClip" + tag, p + d * 0.03, d, LEAN_R @ Vector((0, 0, 1)), 0.022, 0.016, 0.014,
                 [BRASS], verts=6), smooth=30)


# ===========================================================================
# INK_GOLEM (bot only). The runner "made of ink": a lumpy, melting blob for
# a head with a glowing team eye slit and a glowing crack down the back of
# it, ink pooled on the shoulders, glossy drips running down the chest,
# sides, arms and legs (some ending in glowing team droplets) and puddle
# blobs on the boots. The suit is painted ink-dark. Head hidden.
# ===========================================================================

def drip_path(points, r, bulb=1.5):
    """Radii for a drip along `points`: thin run, fat bulb, pointed tip."""
    n = len(points)
    radii = [r * (1.0 - 0.2 * k / max(1, n - 3)) for k in range(n - 2)] + [r * bulb, 0.0]
    return radii


def torso_drip(name, theta, z0, z1, r, mats, steps=3, seg_mats=None):
    pts = []
    for k in range(steps + 1):
        p, d = on_torso(theta, z0 + (z1 - z0) * k / steps, BVH_UPPER)
        pts.append(p + d * r * 0.3)
    p, d = on_torso(theta, z1 - 0.035, BVH_UPPER)
    pts.insert(-1, p + d * r * 0.6)
    pts[-1] = pts[-1] + d * r * 0.6 + Vector((0, 0, -0.045))
    return loft(name, pts, drip_path(pts, r, 1.6), mats, sides=5, up=d, seg_mats=seg_mats)


def hang_drip(name, tag, part, f, length, r, mats, legs=False, seg_mats=None, sides=5):
    """A drop hanging off the underside of an arm (or the back of a leg)."""
    a, u, rad = limb(tag, part, f, legs)
    down = Vector((0, 0, -1)) if not legs else Vector((0, 1, -0.2))
    dp = (down - u * down.dot(u)).normalized()
    st = a + dp * rad * 0.55
    g = Vector((0, 0, -1))
    pts = [st, st + dp * 0.03 + g * length * 0.35, st + dp * 0.036 + g * length * 0.7,
           st + dp * 0.04 + g * length]
    return loft(name, pts, [r * 1.1, r * 0.75, r * 1.25, 0.0], mats, sides=sides, up=u,
                seg_mats=seg_mats)


def leg_drip(name, tag, angle, f0, f1, r, mats, seg_mats=None):
    """A drip running down the outside of a thigh and shin."""
    pts = []
    for part, f in (("thigh", f0), ("thigh", (f0 + 1) / 2), ("shin", 0.0), ("shin", f1 * 0.6), ("shin", f1)):
        a, u, rad = limb(tag, part, f, True)
        ref = Vector((math.sin(math.radians(angle)), -math.cos(math.radians(angle)), 0))
        d = (ref - u * ref.dot(u)).normalized()
        pts.append(a + d * (rad + r * 0.25))
    pts.append(pts[-1] + d * r * 0.5 + Vector((0, 0, -0.04)))
    return loft(name, pts, drip_path(pts, r, 1.6), mats, sides=5, up=d, seg_mats=seg_mats)


def build_ink_golem():
    outfit("INK_GOLEM")
    ink = M("PK_InkGloss", "PK_Wet", "#14112A", roughness=0.06)
    mats = [ink, GLOW]

    # Blob head: a sphere that sags and spreads at the bottom like it is
    # melting onto the shoulders (but stays off the backpack behind).
    c = Vector((0.0, -0.07, 1.445))
    head = bake(pk.sphere("InkHead", 1.0, loc=tuple(c), scale=(0.205, 0.198, 0.2), material=ink,
                          segments=12, rings=8))
    rng = random.Random(7)
    for v in head.data.vertices:
        rel = v.co - c
        az = math.atan2(rel.y, rel.x)
        el = math.asin(max(-1.0, min(1.0, rel.z / max(rel.length, 1e-6))))
        lump = (1.0 + 0.075 * math.sin(3 * az + 1.0) * math.cos(2 * el) + 0.04 * math.sin(5 * az + 2.0)
                + 0.03 * math.sin(4 * el + az) + rng.uniform(-0.02, 0.02))
        if rel.z < 0:
            sag = -rel.z / 0.2
            back = max(0.0, rel.y / 0.198)
            rel.z *= 1.0 + 0.55 * sag * (1 - back)
            rel.x *= 1.0 + 0.26 * sag
            rel.y *= 1.0 + 0.12 * sag * (1 - back) - 0.15 * sag * back
        v.co = c + rel * lump
    head.data.update()
    add(head, "head", -1)
    for k, (off, rad) in enumerate((((0.155, 0.02, 0.135), 0.045), ((-0.095, -0.075, 0.175), 0.028))):
        add(bake(pk.sphere("InkBubble%d" % k, rad, loc=tuple(c + Vector(off)), material=ink,
                           segments=6, rings=4)), "head", -1)
    hdr = bvh_of([head])

    def on_head(theta, z, out):
        t = math.radians(theta)
        d = Vector((math.sin(t), -math.cos(t), 0.0))
        o = Vector((c.x, c.y, z))
        hit = hdr.ray_cast(o + d * 0.6, -d, 1.2)
        return (hit[0] if hit[0] is not None else o + d * 0.2) + d * out

    slit = [on_head(t, 1.462 + 0.012 * math.cos(math.radians(t * 2.2)), 0.004) for t in
            (-44, -30, -15, 0, 15, 30, 44)]
    add(loft("InkEye", slit, [0.0, 0.017, 0.023, 0.025, 0.023, 0.017, 0.0], [GLOW], sides=6,
             up=(0, 0, 1), flat=0.55), "head", -1)
    crack = [on_head(180 + dx, z, 0.003) for dx, z in ((-4, 1.6), (5, 1.55), (-5, 1.5), (4, 1.455),
                                                      (0, 1.42))]
    add(loft("InkCrack", crack, [0.0, 0.016, 0.018, 0.016, 0.0], [GLOW], sides=5, up=(0, 1, 0)),
        "head", -1)

    # Ink running off the head onto the chest.
    for k, (th, z0, z1) in enumerate(((-28, 1.33, 1.2), (22, 1.32, 1.22))):
        top = on_head(th, z0, -0.01)
        p1, d1 = on_torso(th * 0.8, z1 + 0.04, BVH_UPPER)
        p2, d2 = on_torso(th * 0.8, z1, BVH_UPPER)
        pts = [top, p1 + d1 * 0.012, p2 + d2 * 0.016, p2 + d2 * 0.02 + Vector((0, 0, -0.04))]
        add(loft("InkHeadDrip%d" % k, pts, [0.03, 0.024, 0.036, 0.0], mats, sides=5, up=d1), "head", -1)

    # Ink pooled on the shoulder pads.
    for side, tag in ((LEFT, "L"), (RIGHT, "R")):
        p, n = pad_point(side, 10, 70, -0.02)
        blob = bake(pk.sphere("InkPool" + tag, 1.0, loc=tuple(p), scale=(0.115, 0.13, 0.045),
                              rot=(0, side * 24, 0), material=ink, segments=8, rings=5))
        add(lumpy(blob, 0.01, 20 + int(side)), smooth=-1)

    # Drips down the chest and sides (the back is the backpack's).
    for k, (th, z0, z1, r, glow) in enumerate(((-32, 1.27, 0.99, 0.025, False),
                                                (-8, 1.28, 1.13, 0.022, False),
                                                (40, 1.27, 1.11, 0.024, False),
                                                (-64, 1.25, 1.04, 0.022, True),
                                                (-100, 1.24, 0.94, 0.026, True),
                                                (100, 1.24, 0.9, 0.026, True))):
        add(torso_drip("InkDrip%d" % k, th, z0, z1, r, mats, seg_mats=[0] * 4 + [1 if glow else 0]),
            smooth=-1)
    # Drops hanging under the arms; the outer ones glow.
    for k, (tag, part, f, length, glow) in enumerate((("R", "upper", 0.5, 0.15, True),
                                                      ("R", "upper", 0.92, 0.11, False),
                                                      ("R", "fore", 0.35, 0.12, False),
                                                      ("L", "upper", 0.6, 0.14, True),
                                                      ("L", "fore", 0.3, 0.1, False))):
        add(hang_drip("InkArmDrip%d" % k, tag, part, f, length, 0.024, mats,
                      seg_mats=[0, 0, 1 if glow else 0]), smooth=-1)

    # Legs: a drip down the outside of each leg ending in a glowing droplet,
    # one off the back of each calf, and an ink puddle on each boot.
    for side, tag in ((LEFT, "L"), (RIGHT, "R")):
        add(leg_drip("InkLegDrip" + tag, tag, side * 70, 0.15, 0.85, 0.022, mats,
                     seg_mats=[0, 0, 0, 0, 1]), tag, -1)
        add(hang_drip("InkCalfDrip" + tag, tag, "shin", 0.3, 0.07, 0.02, mats, legs=True,
                      seg_mats=[0, 0, 1]), tag, -1)
        puddle = bake(pk.sphere("InkPuddle" + tag, 1.0, loc=(side * 0.125, -0.09, 0.105),
                                scale=(0.13, 0.155, 0.045), rot=(-10, 0, 0), material=ink,
                                segments=8, rings=5))
        add(lumpy(puddle, 0.012, 30 + int(side)), tag, -1)

# ===========================================================================
# Assemble, export, preview
# ===========================================================================

BUILDERS = [("GHOST", build_ghost), ("SAMURAI", build_samurai),
            ("CYBERPUNK", build_cyberpunk), ("ART_CRITIC", build_art_critic),
            ("JANITOR", build_janitor), ("MIME", build_mime),
            ("INK_GOLEM", build_ink_golem)]


def cli(flag):
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return argv[argv.index(flag) + 1] if flag in argv and argv.index(flag) + 1 < len(argv) else None


def assemble(root):
    nodes = {}
    for oid, parts in OUTFITS.items():
        holder = pk.empty("Outfit_" + oid, parent_obj=root)
        nodes[oid] = {"empty": holder}
        for where, suffix in (("body", "_Body"), ("head", "_Head")):
            if parts[where]:
                mesh = world_join(oid + suffix, parts[where])
                pk.parent(mesh, holder)
                nodes[oid][where] = mesh
        for tag in ("L", "R"):
            if parts[tag]:
                pivot = pk.empty("OnLeg_" + tag, loc=tuple(PIVOT[tag]), parent_obj=holder)
                mesh = world_join("%s_Leg%s" % (oid, tag), parts[tag])
                pk.set_origin(mesh, PIVOT[tag])
                pk.parent(mesh, pivot)
                nodes[oid][tag] = mesh
    return nodes


def fix_glb_names(path):
    """Rename OnLeg_L.001 / OnLeg_R.002 ... back to OnLeg_L / OnLeg_R inside
    the .glb's JSON chunk (they are unique within their own outfit)."""
    with open(path, "rb") as fh:
        data = fh.read()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    chunks, off = [], 12
    while off < len(data):
        length, kind = struct.unpack_from("<II", data, off)
        chunks.append([kind, data[off + 8:off + 8 + length]])
        off += 8 + length
    gltf = json.loads(chunks[0][1].decode("utf-8"))
    renamed = 0
    for node in gltf.get("nodes", []):
        m = re.match(r"^(OnLeg_[LR])\.\d+$", node.get("name", ""))
        if m:
            node["name"] = m.group(1)
            renamed += 1
    raw = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    chunks[0][1] = raw + b" " * ((4 - len(raw) % 4) % 4)
    body = b"".join(struct.pack("<II", len(c[1]), c[0]) + c[1] for c in chunks)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<III", magic, version, 12 + len(body)) + body)
    print("[outfits_b] renamed %d OnLeg nodes in %s" % (renamed, os.path.basename(path)))


def import_glb(name, loc=(0, 0, 0), rot_z=0.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(pk.OUT_DIR, name))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.parent is None:
            o.location = loc
            o.rotation_euler = (0, 0, math.radians(rot_z))
    return new


def set_colour(material, hex_colour, emission=None):
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        return
    bsdf.inputs["Base Color"].default_value = pk.linear(hex_colour)
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = pk.linear(hex_colour)


def previews(folder, nodes, team_hex):
    """One contact sheet per outfit, worn by the real runner (imported, never
    exported) with its backpack and gun, the suit/helmet recoloured as Godot
    will, other outfits hidden."""
    os.makedirs(folder, exist_ok=True)
    runner = import_glb("canvas_runner.glb")
    extras = import_glb("chromatic_reservoir.glb", loc=(0, 0.102, 1.12))
    extras += import_glb("paint_blaster_prop.glb", loc=tuple(HAND_SOCKET), rot_z=180)
    runner_mats = {m for o in runner if o.type == "MESH" for m in o.data.materials}
    for m in bpy.data.materials:
        if m.name.startswith(("PK_Team", "PK_Fill")):
            set_colour(m, team_hex, emission=True if "Glow" in m.name or "Fill" in m.name else None)
    head = next(o for o in runner if o.name.startswith("Head"))
    for oid, parts in nodes.items():
        look = SUIT_AND_HELMET[oid]
        for m in runner_mats:
            if m.name.startswith("PK_Canvas"):
                set_colour(m, look["suit"])
            elif m.name.startswith("PK_Body"):
                set_colour(m, look["helmet"])
        mine = {o for k, o in parts.items() if k != "empty"}
        for other in nodes.values():
            for k, o in other.items():
                if k != "empty":
                    o.hide_render = o not in mine
        head.hide_render = look["hide_head"]
        pk.preview(os.path.join(os.path.abspath(folder), "%s.png" % oid.lower()), size=520)
        for o in list(bpy.data.objects):
            if o.name.startswith(("PreviewSun", "PreviewCam")):
                bpy.data.objects.remove(o, do_unlink=True)


def main():
    only = cli("--only")
    for oid, build in BUILDERS:
        if only is None or only == oid:
            build()
    for o in REFS:
        bpy.data.objects.remove(o, do_unlink=True)
    root = pk.empty("OutfitsB")
    nodes = assemble(root)
    if "GHOST" in nodes:
        for key in ("head", "body"):
            if key in nodes["GHOST"]:
                print("[outfits_b] seam normals set on %d corners of GHOST_%s" % (
                    apply_seam_normals(nodes["GHOST"][key]), key))
    for oid, parts in nodes.items():
        total, _ = pk.triangle_count([o for k, o in parts.items() if k != "empty"])
        print("[outfits_b] %-11s %5d triangles" % (oid, total))
    out = pk.export("cosmetic_outfits_b.glb", budget=9100)
    fix_glb_names(out)
    folder = cli("--preview-dir")
    if folder:
        previews(folder, nodes, cli("--team") or "#FF627E")


main()
