"""
Cosmetic masks - the nine masks a Canvas Runner can wear (character select).

Output: models/generated/cosmetic_masks.glb

    Masks                root empty
      Mask_MINT_MASK     smooth mint face plate, eye slits, nose ridge
      Mask_SPLASH_MASK   a paint splat over the face, eye holes, flying drops
      Mask_PIXEL_MASK    blocky 8-bit face of raised squares
      Mask_BANDANA       cloth over the lower face, knot at the back
      Mask_VISOR_MASK    sleek tinted wraparound goggles with a strap
      Mask_STAR_MASK     two star-shaped eye rings joined over the nose
      Mask_GRID_MASK     fencing-mask grid with a padded bib
      Mask_HALF_MASK     masquerade mask over the left side, gold trim, feathers
      Mask_GLOW_MASK     dark plate with glowing eye and mouth lines

Every mask is ONE mesh, moulded in place onto the front of the runner's
helmet, so all nine overlap at the same spot in this file (that is intended).
Each mask's ORIGIN is exactly the runner's Socket_Face point,
Blender (0, -0.236, 1.425): Godot parents a mask to Socket_Face with a zero
offset and it sits right.

How the masks hug the helmet: the helmet (create_canvas_runner.py) is an
ellipsoid centred on (0, -0.065, 1.43) with radii (0.172, 0.168, 0.17). Its
dark visor band stands 12 mm off it over theta -84..84 and phi -27..15 degrees
(theta: round from the front toward the runner's left, +X; phi: latitude), and
the glowing team strip on the visor stands 20 mm off it. A mask's face sits
10 mm proud of whatever is under it (22 mm off the helmet over the visor, and
27 mm over the strip so it clears that by 7 mm), easing down where it leaves
the visor.
Its edges are walls that run down into the helmet, so it reads as a solid
moulded plate with no gap underneath. Eye holes are put over the team strip
so the wearer's team glow still shows through most masks.

Materials: each mask has its own named colours (PK_Mask...). PK_Team (repainted
by Godot in the wearer's team colour) is used for at most one small element
per mask: the goggle strap and the half mask's jewel.

Run:  blender -b --factory-startup --python tools/blender/create_cosmetic_masks.py
      ... -- --preview DIR/cosmetic_masks.png   also render one contact sheet
          per mask, worn by the runner: DIR/cosmetic_masks_<ID>.png (slow).
"""

import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

# paintkit's export() renders ONE sheet of everything when it sees --preview.
# Nine masks on one spot would be an unreadable pile, so take the option away
# from it here and render one sheet per mask after exporting instead.
PREVIEW = pk.args()["preview"]
if PREVIEW and "--preview" in sys.argv:
    k = sys.argv.index("--preview")
    del sys.argv[k:k + 2]

pk.begin("CosmeticMasks", seed=43)

HEAD = Vector((0.0, -0.065, 1.43))      # helmet centre (create_canvas_runner.py)
HEAD_R = (0.172, 0.168, 0.17)           # helmet radii x, y, z
SOCKET_FACE = Vector((0.0, -0.236, 1.425))
VISOR_OUT = 0.012                       # the visor band stands this far off the helmet
STRIP_OUT = 0.020                       # ...and its glowing team strip this far
PROUD = 0.010                           # a mask's face stands this far off what is under it
STRIP_CLEAR = 0.005                     # extra lift over the strip (visor + PROUD clears it by only 2 mm)
BURY = -0.006                           # mask walls run down to here (inside the helmet)
MASK_BUDGET = 300
TOTAL_BUDGET = 2700

team = pk.mat("PK_Team")
root = pk.empty("Masks")


# ---------------------------------------------------------------------------
# Local helpers (things the kit does not have)
# ---------------------------------------------------------------------------

def along(direction_vec, roll=0.0):
    """Rotation (degrees) that turns a part's local +Z to point along
    `direction_vec`, then spins it `roll` degrees about that axis."""
    q = Vector(direction_vec).to_track_quat("Z", "Y")
    if roll:
        q = q @ Matrix.Rotation(math.radians(roll), 3, "Z").to_quaternion()
    return tuple(math.degrees(a) for a in q.to_euler())


def direction(theta, phi):
    """Unit direction from the helmet centre. theta: degrees round from the
    front (-Y) toward the runner's left (+X); phi: latitude in degrees."""
    t, p = math.radians(theta), math.radians(phi)
    return Vector((math.cos(p) * math.sin(t), -math.cos(p) * math.cos(t), math.sin(p)))


def angles(d):
    """(theta, phi) in degrees of a direction - the inverse of direction()."""
    return (math.degrees(math.atan2(d.x, -d.y)),
            math.degrees(math.asin(max(-1.0, min(1.0, d.z)))))


def surface(d, offset):
    """Point on the helmet ellipsoid for direction d, pushed `offset` metres
    out along the surface normal (same maths as the runner's visor)."""
    rx, ry, rz = HEAD_R
    normal = Vector((d.x / rx, d.y / ry, d.z / rz)).normalized()
    return HEAD + Vector((d.x * rx, d.y * ry, d.z * rz)) + normal * offset


def normal_at(d):
    rx, ry, rz = HEAD_R
    return Vector((d.x / rx, d.y / ry, d.z / rz)).normalized()


def window(x, lo, hi, margin=3.0, ramp=6.0):
    """1 inside lo..hi (plus a safety margin), sloping to 0 over `ramp`."""
    if lo - margin <= x <= hi + margin:
        return 1.0
    dist = (lo - margin - x) if x < lo - margin else (x - hi - margin)
    return max(0.0, 1.0 - dist / ramp)


def over_visor(d):
    """How much of the visor band is under direction d (0..1)."""
    theta, phi = angles(d)
    return (window(theta, -84.0, 84.0, margin=1.5, ramp=4.5)
            * window(phi, -27.0, 15.0, margin=1.5, ramp=4.5))


def over_strip(d):
    """How much of the glowing team strip is under direction d (0..1)."""
    theta, phi = angles(d)
    return (window(theta, -64.0, 64.0, margin=1.5, ramp=3.0)
            * window(phi, -7.0, 1.0, margin=1.5, ramp=3.0))


def face_out(d):
    """How far out a mask's face sits: PROUD above the visor or the helmet,
    lifted a touch more over the team strip so coarse panels never touch it."""
    return PROUD + VISOR_OUT * over_visor(d) + STRIP_CLEAR * over_strip(d)


class Builder:
    """Collects vertices and faces for one custom mesh. Every face is turned
    to point along an `expect` direction, so winding never has to be worked
    out by hand (back-face culling in Godot hides wrongly wound faces)."""

    def __init__(self, name, materials):
        self.name = name
        self.materials = list(materials)
        self.bm = bmesh.new()
        self.keys = {}

    def vert(self, key, co):
        v = self.keys.get(key) if key is not None else None
        if v is None:
            v = self.bm.verts.new(co)
            if key is not None:
                self.keys[key] = v
        return v

    def face(self, verts, slot, expect):
        clean = []
        for v in verts:
            if not clean or clean[-1] is not v:
                clean.append(v)
        if len(clean) > 1 and clean[0] is clean[-1]:
            clean.pop()
        if len(set(clean)) < 3:
            return None
        try:
            f = self.bm.faces.new(clean)
        except ValueError:          # already exists
            return None
        f.material_index = slot
        f.normal_update()
        if f.normal.dot(expect) < 0.0:
            f.normal_flip()
        return f

    def build(self):
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        obj = bpy.data.objects.new(self.name, mesh)
        pk._collection.objects.link(obj)
        for m in self.materials:
            mesh.materials.append(m)
        return obj


def patch(name, pos, ni, nj, cell, materials, front=face_out, bottom=BURY, wrap=False,
          wall_slot=None, deep_steps=False):
    """A panel moulded onto the helmet from a grid of cells.

    pos(i, j)  -> (theta, phi) in degrees of grid corner (i, j)
    cell(i, j) -> None for no cell (a hole), or (level, material slot)
    front(d)   -> how far out (metres) the panel face sits in direction d;
                  a cell's face sits at front(d) + level.
    Edges with no cell (or a lower one) next to them get a wall that runs
    down to `bottom` (inside the helmet) or to the lower cell, so the panel
    reads as a solid moulded part with no gap underneath it.
    wall_slot  material slot for walls: None (the cell's own), a number, or
               a function (i, j, edge, other_cell) -> slot.
    deep_steps walls between a higher and a lower cell also run all the way
               down to `bottom` (for see-through lower cells, e.g. a lens, so
               nobody can look through it into the hollow under the higher one)."""
    b = Builder(name, materials)

    def corner(i, j, level):
        if wrap:
            i %= ni
        d = direction(*pos(i, j))
        key = (round(d.x, 6), round(d.y, 6), round(d.z, 6),
               "base" if level is None else round(level, 6))
        offset = bottom if level is None else front(d) + level
        return b.vert(key, surface(d, offset))

    def neighbour(i, j):
        if wrap:
            i %= ni
        elif not 0 <= i < ni:
            return None
        if not 0 <= j < nj:
            return None
        return cell(i, j)

    for i in range(ni):
        for j in range(nj):
            c = cell(i, j)
            if c is None:
                continue
            level, slot = c
            corners = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
            top = [corner(a, k, level) for a, k in corners]
            centre = sum((v.co for v in top), Vector()) / 4.0
            b.face(top, slot, centre - HEAD)
            for e, nb in ((0, (i, j - 1)), (1, (i + 1, j)), (2, (i, j + 1)), (3, (i - 1, j))):
                other = neighbour(*nb)
                if other is not None and other[0] >= level - 1e-9:
                    continue
                lower = None if (other is None or deep_steps) else other[0]
                ca, cb = corners[e], corners[(e + 1) % 4]
                ta, tb = corner(*ca, level), corner(*cb, level)
                if ta is tb:
                    continue
                ba, bb = corner(*ca, lower), corner(*cb, lower)
                if wall_slot is None:
                    ws = slot
                elif callable(wall_slot):
                    ws = wall_slot(i, j, e, other)
                else:
                    ws = wall_slot
                b.face([ta, tb, bb, ba], ws, (ta.co + tb.co) * 0.5 - centre)
    return b.build()


def blob(name, centre, outline, material, front=face_out, wall=None, squash=1.0):
    """A small flat blob moulded onto the helmet: a fan from `centre`
    (theta, phi) out to radii `outline` (degrees, evenly spaced round)."""
    count = len(outline)

    def pos(i, j):
        a = math.tau * i / count
        r = outline[i % count] * j
        return (centre[0] + r * math.cos(a), centre[1] + r * math.sin(a) * squash)

    return patch(name, pos, count, 1, lambda i, j: (0.0, 0), [material] + ([wall] if wall else []),
                 front=front, wrap=True, wall_slot=1 if wall else None)


def lerp_table(table, x):
    """Piecewise-linear lookup in a list of (x, value) pairs sorted by x."""
    if x <= table[0][0]:
        return table[0][1]
    for (x0, v0), (x1, v1) in zip(table, table[1:]):
        if x <= x1:
            return v0 + (v1 - v0) * (x - x0) / (x1 - x0)
    return table[-1][1]


def periodic(points, a):
    """Smooth (Catmull-Rom) loop through (angle_degrees, value) points."""
    a %= 360.0
    pts = sorted(points)
    n = len(pts)
    for k in range(n):
        a0, _ = pts[k]
        a1 = pts[(k + 1) % n][0] + (360.0 if k == n - 1 else 0.0)
        aa = a + (360.0 if a < a0 else 0.0)
        if a0 <= aa <= a1:
            t = (aa - a0) / (a1 - a0)
            p0, p1 = pts[(k - 1) % n][1], pts[k][1]
            p2, p3 = pts[(k + 1) % n][1], pts[(k + 2) % n][1]
            return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
    return pts[0][1]


# ---------------------------------------------------------------------------
# The masks. Each builder returns (parts, {part: smoothing angle}) - parts that
# need softer shading than the default 35 degrees say so.
# ---------------------------------------------------------------------------

def mask_mint():
    mint = pk.mat("PK_Body", name="PK_MaskMint", color="#9EE0C6", roughness=0.3)
    edge = pk.mat("PK_Body", name="PK_MaskMintEdge", color="#6DBF9F", roughness=0.4)
    us = [-1.0, -0.82, -0.62, -0.22, 0.0, 0.22, 0.62, 0.82, 1.0]
    phis = [-43.0, -35.0, -26.0, -15.0, -6.0, 0.0, 8.0, 15.0, 21.0]
    width = [(-43, 18), (-35, 33), (-26, 44), (-15, 52), (-6, 56), (0, 57), (8, 55), (15, 50), (21, 41)]

    def pos(i, j):
        u, phi = us[i], phis[j]
        if j == 0:
            phi += 8.0 * u * u                  # rounded chin
        elif j == len(phis) - 1:
            phi -= 5.0 * u * u                  # rounded brow
        return (u * lerp_table(width, phi), phi)

    slits = {(2, 4), (5, 4)}                    # eye slits right over the team strip
    nose = {(3, 1), (4, 1), (3, 2), (4, 2), (3, 3), (4, 3)}

    def cell(i, j):
        if (i, j) in slits:
            return None
        return (0.004 if (i, j) in nose else 0.0, 0)

    plate = patch("MintPlate", pos, len(us) - 1, len(phis) - 1, cell, [mint, edge], wall_slot=1)
    return [plate], {plate: 40.0}


def mask_splash():
    paint = pk.mat("PK_Body", name="PK_MaskSplash", color="#FF8A3D", roughness=0.18)
    edge = pk.mat("PK_Body", name="PK_MaskSplashEdge", color="#DE6620", roughness=0.25)
    count = 24
    outline = [34, 32, 45, 31, 30, 37, 46, 31, 30, 40, 32, 33,
               34, 32, 44, 30, 33, 47, 31, 29, 39, 45, 31, 32]
    rings = [0.0, 0.3, 0.62, 1.0]
    centre = (0.0, -4.0)

    def pos(i, j):
        a = math.tau * (i % count) / count
        r = outline[i % count] * rings[j]
        return (centre[0] + r * math.cos(a), centre[1] + 0.9 * r * math.sin(a))

    holes = {(23, 1), (0, 1), (11, 1), (12, 1)}  # eye holes over the team strip

    def cell(i, j):
        return None if (i, j) in holes else (0.0, 0)

    parts = [patch("Splash", pos, count, len(rings) - 1, cell, [paint, edge], wrap=True, wall_slot=1)]
    rng = random.Random(7)
    for n, (c, size) in enumerate((((50.0, 35.0), 5.5), ((-47.0, -37.0), 5.0), ((61.0, -27.0), 4.2))):
        outline_drop = [size * rng.uniform(0.8, 1.15) for _ in range(7)]
        parts.append(blob("SplashDrop%d" % n, c, outline_drop, paint, wall=edge))
    return parts, {}


def mask_pixel():
    base_a = pk.mat("PK_Body", name="PK_MaskPixelA", color="#7E6BD9", roughness=0.5)
    base_b = pk.mat("PK_Body", name="PK_MaskPixelB", color="#9282E6", roughness=0.5)
    raised = pk.mat("PK_Body", name="PK_MaskPixelRaised", color="#FFD45E", roughness=0.45)
    side = pk.mat("PK_Body", name="PK_MaskPixelSide", color="#5A49B0", roughness=0.5)
    # Top row first. '#' plate pixel, 'o' raised pixel, ' ' hole, '.' nothing.
    art = ["..######..",
           ".########.",
           "##########",
           "#  ####  #",                         # eye holes over the team strip
           "##########",
           "#o######o#",
           ".#oooooo#.",
           "..######.."]
    cols, rows = len(art[0]), len(art)
    step_t, step_p = 9.0, 8.0
    eye_row = 3                                  # its bottom edge sits at phi -7

    def pos(i, j):
        return ((i - cols / 2.0) * step_t, -7.0 + (j - (rows - 1 - eye_row)) * step_p)

    def cell(i, j):
        ch = art[rows - 1 - j][i]
        if ch in ". ":
            return None
        if ch == "o":
            return (0.007, 2)
        return (0.0, (i + j) % 2)               # checkerboard of two close shades

    plate = patch("Pixels", pos, cols, rows, cell, [base_a, base_b, raised, side], wall_slot=3)
    return [plate], {plate: 20.0}


def mask_bandana():
    cloth = pk.mat("PK_Canvas", name="PK_MaskBandana", color="#3E5BA9", roughness=0.85)
    knot_m = pk.mat("PK_Canvas", name="PK_MaskBandanaKnot", color="#33498C", roughness=0.85)
    thetas = [-180.0, -160.0, -135.0, -108.0, -86.0, -68.0, -50.0, -32.0, -15.0, 0.0,
              15.0, 32.0, 50.0, 68.0, 86.0, 108.0, 135.0, 160.0]
    cols = len(thetas)

    def top(theta):
        return -11.0 + 5.0 * (1.0 - math.cos(math.radians(theta))) * 0.5

    def bottom(theta):
        return -22.0 - 38.0 * (1.0 - abs(theta) / 180.0) ** 1.5

    def pos(i, j):
        theta = thetas[i % cols]
        t, b = top(theta), bottom(theta)
        if abs(theta) <= 90.0:                  # just below the visor, then onto the helmet
            mids = (-29.0, -29.0 + (b + 29.0) * 0.4)
        else:
            mids = (t + (b - t) * 0.33, t + (b - t) * 0.66)
        return (theta, (b, mids[1], mids[0], t)[j])

    def cloth_out(d):
        return 0.008 + VISOR_OUT * over_visor(d)  # thin cloth: 8 mm proud

    band = patch("Bandana", pos, cols, 3, lambda i, j: (0.0, 0), [cloth], front=cloth_out, wrap=True)
    parts = [band]
    back = direction(180.0, -15.0)
    n = normal_at(back)
    knot_at = surface(back, 0.014)
    parts.append(pk.sphere("BandanaKnot", 1.0, loc=tuple(knot_at), scale=(0.03, 0.026, 0.018),
                           rot=along(n), material=knot_m, segments=8, rings=4))
    for side in (-1.0, 1.0):
        tail_dir = (Vector((side * 0.55, 0.0, -1.0)) - n * Vector((side * 0.55, 0.0, -1.0)).dot(n)).normalized()
        p = knot_at + tail_dir * 0.045 + n * 0.004
        x = tail_dir
        z = (n - x * n.dot(x)).normalized()
        y = z.cross(x)
        rot = Matrix((x, y, z)).transposed().to_euler()
        parts.append(pk.sphere("BandanaTail%d" % (side > 0), 1.0, loc=tuple(p),
                               scale=(0.05, 0.02, 0.006), rot=tuple(math.degrees(r) for r in rot),
                               material=knot_m, segments=6, rings=3))
    return parts, {band: 50.0, parts[1]: 60.0}


def mask_visor():
    lens = pk.mat("PK_Glass", name="PK_MaskGoggleLens", color="#8A6CE8", roughness=0.05, alpha=0.55)
    frame = pk.mat("PK_Trim", name="PK_MaskGoggleFrame", color="#36324D", roughness=0.4, metallic=0.3)
    thetas = [-96.0 + 16.0 * k for k in range(13)]
    phis = [-17.0, -13.0, -3.0, 8.0, 12.0]

    def cell(i, j):
        if i in (0, len(thetas) - 2) or j in (0, len(phis) - 2):
            return (0.004, 1)                   # raised frame all round
        return (0.0, 0)                         # tinted lens, recessed

    goggles = patch("Goggles", lambda i, j: (thetas[i], phis[j]), len(thetas) - 1, len(phis) - 1,
                    cell, [lens, frame], wall_slot=1, deep_steps=True)
    # Strap round the back of the helmet (team colour), ends under the frame.
    strap_t = [92.0 + 22.0 * k for k in range(9)]

    def strap_out(d):
        return 0.006

    strap = patch("Strap", lambda i, j: (strap_t[i], (-6.0, 3.0)[j]), len(strap_t) - 1, 1,
                  lambda i, j: (0.0, 0), [team], front=strap_out)
    return [goggles, strap], {}


def mask_star():
    gold = pk.mat("PK_Body", name="PK_MaskStar", color="#FFD45E", roughness=0.35)
    edge = pk.mat("PK_Body", name="PK_MaskStarEdge", color="#E09F2E", roughness=0.4)
    parts = []
    tip, valley, hole = 20.0, 10.2, 6.4
    for side in (-1.0, 1.0):
        cx, cy = 23.0 * side, -3.0
        corners = []                            # star outline, 5 tips, one straight up
        for k in range(10):
            a = math.radians(90.0 + 36.0 * k)
            r = tip if k % 2 == 0 else valley
            corners.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        outline = []
        for k in range(10):                     # tip, edge middle, valley, edge middle ...
            p, q = corners[k], corners[(k + 1) % 10]
            outline += [p, ((p[0] + q[0]) * 0.5, (p[1] + q[1]) * 0.5)]

        def pos(i, j, outline=outline, cx=cx, cy=cy):
            ox, oy = outline[i % 20]
            if j == 1:
                return (ox, oy)
            a = math.atan2(oy - cy, ox - cx)
            return (cx + hole * math.cos(a), cy + hole * math.sin(a))

        parts.append(patch("Star%d" % (side > 0), pos, 20, 1, lambda i, j: (0.0, 0), [gold, edge],
                           wrap=True, wall_slot=1))
    # A bridge over the nose, tucked just under the two stars.
    bridge = patch("StarBridge", lambda i, j: ((-9.0, 0.0, 9.0)[i], (-2.0, 3.0)[j]), 2, 1,
                   lambda i, j: (-0.002, 0), [edge])
    parts.append(bridge)
    return parts, {}


def mask_grid():
    bars = pk.mat("PK_Metal", name="PK_MaskGridBars", color="#55577A", roughness=0.35, metallic=0.55)
    rim = pk.mat("PK_Body", name="PK_MaskGridRim", color="#F2B84B", roughness=0.45)
    bib = pk.mat("PK_Canvas", name="PK_MaskGridBib", color="#A99AD8", roughness=0.85)
    # Columns: rim, (hole, bar) x3, hole, rim. Rows (bottom up): bib, rim,
    # (hole, bar) x2, hole, rim. The middle row of holes sits on the team strip.
    us = [-1.0, -0.76, -0.47, -0.35, -0.06, 0.06, 0.35, 0.47, 0.76, 1.0]
    phis = [-38.0, -26.0, -19.0, -11.0, -7.0, 1.0, 5.0, 13.0, 20.0]
    width = [(-38, 30), (-26, 42), (-7, 47), (13, 45), (20, 38)]
    hole_cols, hole_rows = {1, 3, 5, 7}, {2, 4, 6}

    def pos(i, j):
        u, phi = us[i], phis[j]
        if j == 0:
            phi += 7.0 * u * u                  # rounded bib
        elif j == len(phis) - 1:
            phi -= 4.0 * u * u
        return (u * lerp_table(width, phi), phi)

    def cell(i, j):
        if j == 0:
            return (0.0, 2)
        if i in hole_cols and j in hole_rows:
            return None
        if i in (0, len(us) - 2) or j in (1, len(phis) - 2):
            return (0.0, 1)
        return (0.0, 0)

    grid = patch("Grid", pos, len(us) - 1, len(phis) - 1, cell, [bars, rim, bib])
    return [grid], {}


def mask_half():
    lilac = pk.mat("PK_Body", name="PK_MaskHalf", color="#9C7BD8", roughness=0.35)
    gold = pk.mat("PK_Brass", name="PK_MaskHalfGold", color="#E8C15A", roughness=0.3, metallic=0.65)
    plume = pk.mat("PK_Body", name="PK_MaskHalfFeather", color="#5E4AA8", roughness=0.6)
    plume2 = pk.mat("PK_Body", name="PK_MaskHalfFeather2", color="#F28C5B", roughness=0.6)
    inner = pk.mat("PK_Body", name="PK_MaskHalfInner", color="#7457B8", roughness=0.4)
    eye = (25.0, -3.0)                          # over the runner's LEFT (+X) side
    count = 20
    # Outline radius (degrees) by direction round the eye: 0 = outward (+theta),
    # 90 = up. A cat-eye: a swept flourish up and out, a smaller point down and
    # out, a low brow, and reaching the nose line on the inside.
    shape = [(0, 29), (22, 34), (45, 46), (68, 24), (92, 16), (125, 17), (155, 22),
             (180, 26), (205, 20), (240, 14), (270, 13), (305, 17), (332, 27)]
    rings = (0.0, 0.5, 0.8, 1.0)                # hole edge -> ... -> gold border -> outline

    def hole_r(a):
        return 1.0 / math.sqrt((math.cos(a) / 9.0) ** 2 + (math.sin(a) / 5.2) ** 2)

    def pos(i, j):
        a = math.tau * (i % count) / count
        r_in, r_out = hole_r(a), periodic(shape, math.degrees(a))
        r = r_in + (r_out - r_in) * rings[j]
        return (eye[0] + r * math.cos(a), eye[1] + r * math.sin(a))

    def cell(i, j):
        return (0.0, 1 if j == 2 else 0)        # outer ring of cells is the gold border

    def walls(i, j, edge, other):
        return 1 if j == 2 else 3

    mask = patch("HalfMask", pos, count, 3, cell, [lilac, gold, team, inner],
                 wrap=True, wall_slot=walls)
    parts = [mask]
    # Team-colour jewel at the root of the flourish.
    a = math.radians(40.0)
    jd = direction(eye[0] + 23.0 * math.cos(a), eye[1] + 23.0 * math.sin(a))
    jn = normal_at(jd)
    gem = pk.ico("HalfJewel", 0.017, loc=tuple(surface(jd, face_out(jd) + 0.002)), material=team, subdiv=1)
    for v in gem.data.vertices:
        v.co -= jn * (v.co.dot(jn) * 0.5)
    parts.append(gem)
    # Three plumes fanning up and out from the flourish tip.
    b = math.radians(45.0)
    base_d = direction(eye[0] + 41.0 * math.cos(b), eye[1] + 41.0 * math.sin(b))
    base = surface(base_d, face_out(base_d) - 0.004)
    n = normal_at(base_d)
    up = (Vector((0.0, 0.0, 1.0)) - n * n.z).normalized()
    out = n.cross(up).normalized()
    if out.x < 0.0:
        out = -out
    for k, (lean, length, mat) in enumerate(((12.0, 0.07, plume), (38.0, 0.08, plume2),
                                              (64.0, 0.062, plume))):
        x = (up * math.cos(math.radians(lean)) + out * math.sin(math.radians(lean)) + n * 0.25).normalized()
        z = (n - x * n.dot(x)).normalized()
        y = z.cross(x)
        rot = Matrix((x, y, z)).transposed().to_euler()
        parts.append(pk.sphere("Feather%d" % k, 1.0, loc=tuple(base + x * length * 0.85),
                               scale=(length, 0.017, 0.005), rot=tuple(math.degrees(r) for r in rot),
                               material=mat, segments=6, rings=3))
    return parts, {}


def mask_glow():
    plate_m = pk.mat("PK_Dark", name="PK_MaskGlowPlate", color="#272338", roughness=0.35)
    glow = pk.mat("PK_AccentGlow", name="PK_MaskGlowLine", color="#D4FF5A", emission=1.4)
    us = [-1.0, -0.66, -0.33, 0.0, 0.33, 0.66, 1.0]
    phis = [-34.0, -24.0, -14.0, -6.0, 2.0, 10.0, 18.0]
    width = [(-34, 26), (-24, 44), (-6, 58), (2, 58), (10, 54), (18, 40)]

    def pos(i, j):
        u, phi = us[i], phis[j]
        if j == 0:
            phi += 6.0 * abs(u)                 # a chin with a point
        elif j == len(phis) - 1:
            phi -= 6.0 * u * u
        return (u * lerp_table(width, phi), phi)

    plate = patch("GlowPlate", pos, len(us) - 1, len(phis) - 1, lambda i, j: (0.0, 0), [plate_m])
    parts = [plate]

    def line(name, a, b, half_width, segs):
        """A glowing strip raised 4 mm off the plate from (theta, phi) a to b."""
        dt, dp = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dt, dp)
        nt, np_ = -dp / length * half_width, dt / length * half_width

        def lpos(i, j):
            t = i / segs
            s = -1.0 if j == 0 else 1.0
            return (a[0] + dt * t + nt * s, a[1] + dp * t + np_ * s)

        return patch(name, lpos, segs, 1, lambda i, j: (0.0, 0), [glow],
                     front=lambda d: face_out(d) + 0.004, bottom=0.0)

    for side in (-1.0, 1.0):                    # slanted eyes over the strip
        parts.append(line("GlowEye%d" % (side > 0), (side * 10.0, -5.0), (side * 40.0, 0.5), 2.2, 3))
    parts.append(line("GlowMouth", (-16.0, -22.0), (16.0, -22.0), 1.8, 3))
    return parts, {}


MASKS = [
    ("MINT_MASK", mask_mint), ("SPLASH_MASK", mask_splash), ("PIXEL_MASK", mask_pixel),
    ("BANDANA", mask_bandana), ("VISOR_MASK", mask_visor), ("STAR_MASK", mask_star),
    ("GRID_MASK", mask_grid), ("HALF_MASK", mask_half), ("GLOW_MASK", mask_glow),
]


def finish(name, parts, soft):
    """Shade each part, join them into one mesh named `name` with clean
    transforms, put its origin on Socket_Face and hang it under the root."""
    for p in parts:
        pk.smooth(p, soft.get(p, 35.0))
    obj = pk.join(name, parts) if len(parts) > 1 else parts[0]
    obj.name = name
    obj.data.name = name
    pk.apply(obj, location=True, rotation=True, scale=True)
    pk.set_origin(obj, SOCKET_FACE)
    pk.parent(obj, root)
    return obj


items = [finish("Mask_" + mask_id, *build()) for mask_id, build in MASKS]

over = False
for obj in items:
    count = pk.triangle_count([obj])[0]
    origin = obj.matrix_world.translation
    print("[masks] %-18s %4d tris  origin (%.3f, %.3f, %.3f)" % (obj.name, count, *origin))
    if count > MASK_BUDGET:
        print("[masks] ERROR: %s is over its %d-triangle budget" % (obj.name, MASK_BUDGET))
        over = True
    if (origin - SOCKET_FACE).length > 1e-6:
        print("[masks] ERROR: %s origin is not on Socket_Face" % obj.name)
        over = True
if over:
    sys.exit(1)

pk.export("cosmetic_masks.glb", budget=TOTAL_BUDGET)


# ---------------------------------------------------------------------------
# Optional fit check: dress the runner in each mask and render a sheet.
# ---------------------------------------------------------------------------

def flag_backfaces():
    """Preview only: paint the BACK of every face bright red. Godot culls
    back faces, so any red showing in a sheet is a face Godot would not draw."""
    for m in bpy.data.materials:
        if not m.node_tree:
            continue
        nodes, links = m.node_tree.nodes, m.node_tree.links
        out = next((n for n in nodes if n.type == "OUTPUT_MATERIAL"), None)
        if out is None or not out.inputs["Surface"].links:
            continue
        shader = out.inputs["Surface"].links[0].from_socket
        geo = nodes.new("ShaderNodeNewGeometry")
        red = nodes.new("ShaderNodeEmission")
        red.inputs["Color"].default_value = (1.0, 0.0, 0.0, 1.0)
        mix = nodes.new("ShaderNodeMixShader")
        links.new(geo.outputs["Backfacing"], mix.inputs["Fac"])
        links.new(shader, mix.inputs[1])
        links.new(red.outputs["Emission"], mix.inputs[2])
        links.new(mix.outputs["Shader"], out.inputs["Surface"])


def fit_check(obj, head):
    """For every outward-facing face: is it buried under the helmet (or the
    visor), and how far does it stand off whatever is right under it?"""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    ev = head.evaluated_get(depsgraph)
    hm = ev.to_mesh()
    tree = BVHTree.FromPolygons([head.matrix_world @ v.co for v in hm.vertices],
                                [tuple(p.vertices) for p in hm.polygons])
    ev.to_mesh_clear()
    buried, gaps = 0, []
    for poly in obj.data.polygons:
        n = (obj.matrix_world.to_3x3() @ poly.normal).normalized()
        verts = [obj.matrix_world @ obj.data.vertices[k].co for k in poly.vertices]
        centre = sum(verts, Vector()) / len(verts)
        if n.dot((centre - HEAD).normalized()) < 0.5:
            continue
        # The face centre and points part-way to each corner (where chords sag).
        for c in [centre] + [centre.lerp(v, 0.7) for v in verts]:
            radial = (c - HEAD).normalized()
            if tree.ray_cast(c + radial * 1e-4, radial, 0.1)[0] is not None:
                buried += 1
                continue
            hit = tree.ray_cast(c, -radial, 0.3)
            if hit[0] is not None:
                gaps.append(hit[3])
    gaps.sort()
    print("[masks] fit %-18s buried samples %d   stand-off min %.1f mm  median %.1f mm  max %.1f mm" % (
        obj.name, buried, 1000 * gaps[0] if gaps else -1, 1000 * gaps[len(gaps) // 2] if gaps else -1,
        1000 * gaps[-1] if gaps else -1))


if PREVIEW:
    out_dir = os.path.dirname(os.path.abspath(PREVIEW))
    stem = os.path.splitext(os.path.basename(PREVIEW))[0]
    os.makedirs(out_dir, exist_ok=True)
    runner = bpy.data.collections.new("PreviewRunner")
    bpy.context.scene.collection.children.link(runner)
    work = bpy.context.view_layer.active_layer_collection
    bpy.context.view_layer.active_layer_collection = \
        bpy.context.view_layer.layer_collection.children["PreviewRunner"]
    bpy.ops.import_scene.gltf(filepath=os.path.join(pk.OUT_DIR, "canvas_runner.glb"))
    bpy.context.view_layer.active_layer_collection = work
    bpy.context.view_layer.update()
    socket = bpy.data.objects.get("Socket_Face")
    if socket is not None:
        print("[masks] runner Socket_Face at (%.3f, %.3f, %.3f)" % tuple(socket.matrix_world.translation))
    head_obj = bpy.data.objects.get("Head")
    for obj in items:
        fit_check(obj, head_obj)
    frame = pk.box("PreviewFrame", (0.40, 0.46, 0.50), loc=(0.0, -0.075, 1.42))
    frame.hide_render = True
    flag_backfaces()
    for obj in items:
        for other in items:
            other.hide_render = other is not obj
        pk.preview(os.path.join(out_dir, "%s_%s.png" % (stem, obj.name[5:])), size=480)
        for leftover in [o for o in bpy.data.objects if o.name.startswith(("PreviewSun", "PreviewCam"))]:
            bpy.data.objects.remove(leftover)
