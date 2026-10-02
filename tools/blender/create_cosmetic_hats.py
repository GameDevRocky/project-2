"""
Cosmetic hats - the nine hats a Canvas Runner can wear (character select).

Output: models/generated/cosmetic_hats.glb

    Hats                 root empty
      Hat_VISOR          sporty sun visor: open band + big curved bill
      Hat_CROWN          chunky cartoon crown, ball tips, gem dots
      Hat_BUCKET_HAT     soft bucket hat with dried paint splotches
      Hat_BEANIE         ribbed knit beanie with a pompom
      Hat_ANTENNA        headband with two springy antennae and ball tips
      Hat_CAP            painter's / baseball cap, bill forward
      Hat_HALO           glowing ring floating above the helmet
      Hat_FLOWER         big daisy pinned on the top-left of the helmet
      Hat_TOP_HAT        short top hat with a paint-drip band

Every hat is ONE mesh, built in place on top of the runner's helmet, so all
nine overlap at the same spot in this file (that is intended). Each hat's
ORIGIN is exactly the runner's Socket_Head point, Blender (0, -0.065, 1.600),
the very top of the helmet: Godot parents a hat to Socket_Head with a zero
offset and it sits right.

The helmet (create_canvas_runner.py) is an ellipsoid centred on
(0, -0.065, 1.43) with radii (0.172, 0.168, 0.17). Its dark visor band covers
latitudes -27..15 degrees across the front, so at the front nothing here comes
lower than about 16 degrees. Hats face Blender -Y like the runner: peaks and
brims point -Y (Godot +Z).

Materials: each hat has its own named colours (PK_Hat...). PK_Team, which
Godot repaints in the wearer's team colour, is used for at most one small
element per hat: the visor's bill piping, the crown's centre gem, the bucket
hat's band, the beanie's pompom, the cap's button and the top hat's drip band.

Run:  blender -b --factory-startup --python tools/blender/create_cosmetic_hats.py
      ... -- --preview DIR/cosmetic_hats.png   also render one contact sheet
          per hat, worn by the runner: DIR/cosmetic_hats_<ID>.png (slow).
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
# Nine hats on one spot would be an unreadable pile, so take the option away
# from it here and render one sheet per hat after exporting instead.
PREVIEW = pk.args()["preview"]
if PREVIEW and "--preview" in sys.argv:
    k = sys.argv.index("--preview")
    del sys.argv[k:k + 2]

pk.begin("CosmeticHats", seed=41)

HEAD = Vector((0.0, -0.065, 1.43))      # helmet centre (create_canvas_runner.py)
HEAD_R = (0.172, 0.168, 0.17)           # helmet radii x, y, z
SOCKET_HEAD = Vector((0.0, -0.065, 1.600))
R0 = HEAD_R[2]
# Lathes are spun round with radius R0, then squeezed by this so they follow
# the helmet's slightly oval plan (wider side to side than front to back).
OVAL = Matrix.Diagonal((HEAD_R[0] / R0, HEAD_R[1] / R0, 1.0, 1.0))
HAT_BUDGET = 400
TOTAL_BUDGET = 3600

team = pk.mat("PK_Team")
root = pk.empty("Hats")


# ---------------------------------------------------------------------------
# Local helpers (things the kit does not have)
# ---------------------------------------------------------------------------

def along(direction, roll=0.0):
    """Rotation (degrees) that turns a part's local +Z to point along
    `direction`, then spins it `roll` degrees about that axis."""
    q = Vector(direction).to_track_quat("Z", "Y")
    if roll:
        q = q @ Matrix.Rotation(math.radians(roll), 3, "Z").to_quaternion()
    return tuple(math.degrees(a) for a in q.to_euler())


def dome(phi, offset):
    """Lathe profile point (radius, height above the helmet centre) on the
    helmet at latitude `phi` degrees, `offset` metres out from its surface."""
    p = math.radians(phi)
    return ((R0 + offset) * math.cos(p), (R0 + offset) * math.sin(p))


def head_lathe(name, profile, material, segments):
    """A lathe spun round the helmet's vertical axis and squeezed to its oval.
    `segments` is a multiple of 4 so one column of vertices sits dead front."""
    obj = pk.lathe(name, profile, loc=tuple(HEAD), material=material, segments=segments)
    obj.data.transform(OVAL)
    return obj


def tilt(obj, x_deg=0.0, y_deg=0.0):
    """Rotate a part's mesh about the helmet centre. Because the helmet is
    (nearly) a ball, a hat that hugs it still hugs it afterwards. Negative
    x_deg lifts the front and drops the back (worn pushed back)."""
    bpy.context.view_layer.update()
    rot = (Matrix.Rotation(math.radians(y_deg), 4, "Y")
           @ Matrix.Rotation(math.radians(x_deg), 4, "X"))
    world = Matrix.Translation(HEAD) @ rot @ Matrix.Translation(-HEAD)
    obj.data.transform(obj.matrix_world.inverted() @ world @ obj.matrix_world)


def direction(theta, phi):
    """Unit direction from the helmet centre. theta: degrees round from the
    front (-Y) toward the runner's left (+X); phi: latitude in degrees."""
    t, p = math.radians(theta), math.radians(phi)
    return Vector((math.cos(p) * math.sin(t), -math.cos(p) * math.cos(t), math.sin(p)))


def surface(d, offset):
    """Point on the helmet ellipsoid for direction d, pushed `offset` metres
    out along the surface normal (same maths as the runner's visor)."""
    rx, ry, rz = HEAD_R
    normal = Vector((d.x / rx, d.y / ry, d.z / rz)).normalized()
    return HEAD + Vector((d.x * rx, d.y * ry, d.z * rz)) + normal * offset


def normal_at(d):
    rx, ry, rz = HEAD_R
    return Vector((d.x / rx, d.y / ry, d.z / rz)).normalized()


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


def patch(name, pos, ni, nj, cell, materials, front, bottom=-0.006, wrap=False):
    """A panel moulded onto the helmet from a grid of cells.

    pos(i, j)  -> unit direction (from the helmet centre) of grid corner (i, j)
    cell(i, j) -> None for no cell, or (level, material slot)
    front(d)   -> how far out (metres) the panel face sits in direction d;
                  a cell's face sits at front(d) + level.
    Edges with no cell (or a lower one) next to them get a wall that runs
    down to `bottom` (inside the helmet) or to the lower cell, so the panel
    reads as a solid moulded part with no gap underneath it."""
    b = Builder(name, materials)

    def corner(i, j, level):
        if wrap:
            i %= ni
        d = pos(i, j)
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
                lower = None if other is None else other[0]
                ca, cb = corners[e], corners[(e + 1) % 4]
                ta, tb = corner(*ca, level), corner(*cb, level)
                if ta is tb:
                    continue
                ba, bb = corner(*ca, lower), corner(*cb, lower)
                b.face([ta, tb, bb, ba], slot, (ta.co + tb.co) * 0.5 - centre)
    return b.build()


def sweep(name, points, radius, sides, material):
    """A tube with `sides` flat sides following a path of points (open ends:
    both ends are buried in other parts)."""
    b = Builder(name, [material])
    pts = [Vector(p) for p in points]
    rings = []
    normal = None
    for k, p in enumerate(pts):
        if k == 0:
            t = pts[1] - pts[0]
        elif k == len(pts) - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[k + 1] - pts[k - 1]
        t.normalize()
        if normal is None:
            normal = t.orthogonal().normalized()
        normal = (normal - t * normal.dot(t)).normalized()
        binormal = t.cross(normal)
        rings.append([b.vert(None, p + (normal * math.cos(a) + binormal * math.sin(a)) * radius)
                      for a in (math.tau * s / sides for s in range(sides))])
    for k in range(len(pts) - 1):
        axis = (pts[k] + pts[k + 1]) * 0.5
        for s in range(sides):
            quad = [rings[k][s], rings[k][(s + 1) % sides],
                    rings[k + 1][(s + 1) % sides], rings[k + 1][s]]
            mid = sum((v.co for v in quad), Vector()) / 4.0
            b.face(quad, 0, mid - axis)
    return b.build()


def bill(name, root_r, top_z, half_angle, length, droop, curve, thick, materials, ns=8):
    """A cap peak: a fan-shaped slab growing forward (-Y) out of a crown.

    root_r      radius (round the helmet axis) where it starts, buried in the crown
    top_z       height of its top face at the root, above the helmet centre
    half_angle  how far round the head it wraps, degrees each side of front
    length      how far it sticks out at the front centre
    droop       downward tilt in degrees; curve: extra drop at the sides
    materials   [top, underside, rim]"""
    b = Builder(name, materials)
    ts = (0.0, 0.55, 1.0)
    top, bot = {}, {}
    for i in range(ns + 1):
        s = -1.0 + 2.0 * i / ns
        a = math.radians(-90.0 + s * half_angle)
        reach = length * math.sqrt(max(1.0 - 0.8 * s * s, 0.0))
        for j, t in enumerate(ts):
            r = root_r + t * reach
            z = top_z - t * reach * math.tan(math.radians(droop)) - curve * s * s * t
            p = HEAD + Vector((r * math.cos(a) * HEAD_R[0] / R0, r * math.sin(a) * HEAD_R[1] / R0, z))
            top[i, j] = b.vert(None, p)
            bot[i, j] = b.vert(None, p - Vector((0.0, 0.0, thick)))
    centre = HEAD + Vector((0.0, -root_r, top_z))
    up = Vector((0.0, 0.0, 1.0))
    last = len(ts) - 1
    for i in range(ns):
        for j in range(last):
            b.face([top[i, j], top[i + 1, j], top[i + 1, j + 1], top[i, j + 1]], 0, up)
            b.face([bot[i, j], bot[i + 1, j], bot[i + 1, j + 1], bot[i, j + 1]], 1, -up)
        quad = [top[i, last], top[i + 1, last], bot[i + 1, last], bot[i, last]]
        b.face(quad, 2, (quad[0].co + quad[1].co) * 0.5 - centre)
    for j in range(last):
        for i in (0, ns):
            quad = [top[i, j], top[i, j + 1], bot[i, j + 1], bot[i, j]]
            out = (quad[0].co + quad[1].co) * 0.5 - (top[ns // 2, j].co + top[ns // 2, j + 1].co) * 0.5
            b.face(quad, 2, out)
    return b.build()


def lathe_point(profile_a, profile_b, t, azimuth):
    """Point and outward normal on a head_lathe surface, part-way (t) along
    the profile segment a -> b, at `azimuth` degrees (from +X, counter-
    clockwise; -90 is the front)."""
    r = profile_a[0] + (profile_b[0] - profile_a[0]) * t
    z = profile_a[1] + (profile_b[1] - profile_a[1]) * t
    dr, dz = profile_b[0] - profile_a[0], profile_b[1] - profile_a[1]
    nr, nz = dz, -dr
    length = math.hypot(nr, nz)
    nr, nz = nr / length, nz / length
    a = math.radians(azimuth)
    p = HEAD + Vector((r * math.cos(a) * HEAD_R[0] / R0, r * math.sin(a) * HEAD_R[1] / R0, z))
    n = Vector((nr * math.cos(a), nr * math.sin(a), nz)).normalized()
    return p, n


# ---------------------------------------------------------------------------
# The hats. Each builder returns (parts, {part: smoothing angle}) - parts that
# need softer shading than the default 35 degrees say so.
# ---------------------------------------------------------------------------

def hat_visor():
    band_m = pk.mat("PK_Body", name="PK_HatVisorBand", color="#F28C5B", roughness=0.5)
    under_m = pk.mat("PK_Trim", name="PK_HatVisorUnder", color="#45405F", roughness=0.6, metallic=0.0)
    # An open band round the brow (no top), sitting just above the dark visor.
    band = head_lathe("VisorBand", [dome(16.5, -0.006), dome(17.5, 0.010), dome(20.0, 0.014),
                                    dome(33.0, 0.014), dome(35.5, 0.010), dome(36.5, -0.006)],
                      band_m, 24)
    peak = bill("VisorBill", root_r=0.166, top_z=0.066, half_angle=72.0, length=0.105,
                droop=9.0, curve=0.028, thick=0.009, materials=[band_m, under_m, team])
    return [band, peak], {}


def hat_crown():
    gold = pk.mat("PK_Brass", name="PK_HatCrownGold", color="#E8C15A", roughness=0.35, metallic=0.6)
    gem_m = pk.mat("PK_Body", name="PK_HatCrownGem", color="#9B6BE0", roughness=0.15)
    b = Builder("CrownRing", [gold])
    cols = 20                                   # 5 points x (tip, mid, valley, mid)
    tip_h = {0: 0.236, 1: 0.199, 2: 0.162, 3: 0.199}
    ring = []
    for k in range(cols):
        a = math.radians(-90.0 + 360.0 * k / cols)
        h = tip_h[k % 4]
        c, s = math.cos(a) * HEAD_R[0] / R0, math.sin(a) * HEAD_R[1] / R0
        ring.append({
            "ob": b.vert(None, HEAD + Vector((0.127 * c, 0.127 * s, 0.100))),   # outer bottom (buried)
            "ot": b.vert(None, HEAD + Vector((0.143 * c, 0.143 * s, h))),       # outer top
            "it": b.vert(None, HEAD + Vector((0.129 * c, 0.129 * s, h - 0.006))),
            "ib": b.vert(None, HEAD + Vector((0.114 * c, 0.114 * s, 0.108))),   # inner bottom (buried)
            "dir": Vector((c, s, 0.0)),
        })
    for k in range(cols):
        p, q = ring[k], ring[(k + 1) % cols]
        out = (p["dir"] + q["dir"]).normalized()
        b.face([p["ob"], q["ob"], q["ot"], p["ot"]], 0, out)
        b.face([p["ot"], q["ot"], q["it"], p["it"]], 0, out * 0.3 + Vector((0, 0, 1)))
        b.face([p["it"], q["it"], q["ib"], p["ib"]], 0, -out)
    tips = [(ring[k]["ot"].co + ring[k]["it"].co) * 0.5 + Vector((0, 0, 0.013))
            for k in range(0, cols, 4)]
    parts = [b.build()]
    for k, p in enumerate(tips):                # a ball on every tip
        parts.append(pk.sphere("CrownBall%d" % k, 0.0165, loc=tuple(p), material=gold,
                               segments=6, rings=4))
    # Gem dots on the band under the three front points; the middle one in team colour.
    for n, (az, mat) in enumerate(((-90.0, team), (-90.0 - 72.0, gem_m), (-90.0 + 72.0, gem_m))):
        p, nrm = lathe_point((0.127, 0.100), (0.143, 0.236), 0.29, az)
        gem = pk.ico("CrownGem%d" % n, 0.023 if n == 0 else 0.019, loc=tuple(p + nrm * 0.003),
                     material=mat, subdiv=1)
        for v in gem.data.vertices:             # flatten against the band
            v.co -= nrm * (v.co.dot(nrm) * 0.55)
        parts.append(gem)
    soft = {p: 60.0 for p in parts[1:6]}
    return parts, soft


def lathe_surface(profile, azimuth, s, offset):
    """Point and outward normal on a head_lathe surface, `s` metres along its
    profile (measured from the first point) at `azimuth` degrees, pushed
    `offset` metres out. Positions past either end stop at that end."""
    lengths = [math.hypot(r1 - r0, z1 - z0) for (r0, z0), (r1, z1) in zip(profile, profile[1:])]
    s = min(max(s, 0.0), sum(lengths) - 1e-6)
    for (a, b), seg in zip(zip(profile, profile[1:]), lengths):
        if s <= seg:
            p, n = lathe_point(a, b, s / seg, azimuth)
            return p + n * offset, n
        s -= seg
    raise ValueError("unreachable")


def splat_on_lathe(name, profile, azimuth, s, radius, material, verts=9, seed=0, stretch=1.0):
    """A flat blob of dried paint hugging a lathe: a fan of rim points at
    random radii, each placed on the surface, plus a skirt that tucks the edge
    under the surface so it never floats. `stretch` widens it round the hat."""
    rng = random.Random(seed)
    b = Builder(name, [material])
    centre, n = lathe_surface(profile, azimuth, s, 0.0035)
    mid = b.vert(None, centre)
    r_here = max((centre - HEAD).xy.length, 0.03)
    rim, skirt = [], []
    for i in range(verts):
        a = math.tau * i / verts + rng.uniform(-0.2, 0.2)
        r = radius * rng.uniform(0.68, 1.22)
        for ring, scale, lift in ((rim, 1.0, 0.003), (skirt, 1.15, -0.003)):
            ds = math.sin(a) * r * scale
            daz = math.degrees(math.cos(a) * r * scale * stretch / r_here)
            p, _ = lathe_surface(profile, azimuth + daz, s + ds, lift)
            ring.append(b.vert(None, p))
    for i in range(verts):
        k = (i + 1) % verts
        b.face([mid, rim[i], rim[k]], 0, n)
        b.face([rim[i], skirt[i], skirt[k], rim[k]], 0, n)
    return b.build()


def hat_bucket():
    fabric = pk.mat("PK_Canvas", name="PK_HatBucketFabric", color="#B9A7E3", roughness=0.9)
    paints = [pk.mat("PK_Dry1", name="PK_HatBucketPaintA", color="#F6C453", roughness=0.45),
              pk.mat("PK_Dry2", name="PK_HatBucketPaintB", color="#F28C5B", roughness=0.45),
              pk.mat("PK_Dry4", name="PK_HatBucketPaintC", color="#7FA6E8", roughness=0.45)]
    profile = [(0.150, 0.062), (0.168, 0.064),                   # tucked under the brim
               (0.237, 0.033), (0.233, 0.047),                   # drooping brim edge
               (0.173, 0.075), (0.171, 0.107),                   # band
               (0.154, 0.153), (0.122, 0.183), (0.0, 0.192)]     # soft crown
    hat = head_lathe("Bucket", profile, fabric, 20)
    hat.data.materials.append(team)
    for poly in hat.data.polygons:              # the band in team colour
        if 0.074 < poly.center.z < 0.108 and math.hypot(poly.center.x, poly.center.y) > 0.16:
            poly.material_index = 1
    crown = profile[5:]                         # from the top of the band up to the crown
    brim = profile[3:5]                         # brim top, edge -> crown
    parts = [hat]
    # (surface, azimuth, distance along it, size, stretch) - front-left crown,
    # top toward the back-right, and the brim at the back-left.
    for n, (prof, az, s, size, stretch) in enumerate((
            (crown, -118.0, 0.046, 0.036, 1.25), (crown, 40.0, 0.105, 0.04, 1.0),
            (brim, 150.0, 0.032, 0.03, 1.4))):
        parts.append(splat_on_lathe("BucketPaint%d" % n, prof, az, s, size, paints[n],
                                    seed=n + 3, stretch=stretch))
    return parts, {}


def hat_beanie():
    knit = pk.mat("PK_Canvas", name="PK_HatBeanieKnit", color="#E8B54E", roughness=0.95)
    rib_m = pk.mat("PK_Canvas", name="PK_HatBeanieRib", color="#D29C38", roughness=0.95)
    cuff_m = pk.mat("PK_Canvas", name="PK_HatBeanieCuff", color="#C48A2C", roughness=0.95)
    profile = [dome(6.5, -0.006), dome(7.5, 0.019), dome(21.0, 0.025), dome(23.5, 0.013),
               dome(26.0, 0.014), dome(48.0, 0.017), dome(70.0, 0.022), (0.0, R0 + 0.027)]
    cols = 24
    beanie = pk.lathe("Beanie", profile, loc=tuple(HEAD), material=knit, segments=cols)
    # Rib-knit: push alternate columns of vertices out and in.
    for v in beanie.data.vertices:
        r = math.hypot(v.co.x, v.co.y)
        if r < 1e-5:
            continue
        lat = math.degrees(math.atan2(v.co.z, r))
        if lat < 7.0:
            amp = 0.0
        elif lat < 24.0:
            amp = 0.006
        elif lat < 74.0:
            amp = 0.005
        else:
            amp = 0.0
        col = round(math.atan2(v.co.y, v.co.x) / (math.tau / cols))
        sign = 1.0 if col % 2 == 0 else -1.0
        v.co.x += sign * amp * v.co.x / r
        v.co.y += sign * amp * v.co.y / r
    beanie.data.materials.append(rib_m)
    beanie.data.materials.append(cuff_m)
    step = math.tau / cols
    for poly in beanie.data.polygons:
        c = poly.center
        lat = math.degrees(math.atan2(c.z, math.hypot(c.x, c.y)))
        if lat < 22.5:                          # folded-up cuff a shade darker
            poly.material_index = 2
        elif lat < 76.0 and math.floor(math.atan2(c.y, c.x) / step) % 2:
            poly.material_index = 1             # every other rib in shadow tone
    beanie.data.transform(OVAL)
    pom = pk.sphere("Pompom", 0.047, loc=tuple(HEAD + Vector((0, 0, R0 + 0.064))), material=team,
                    segments=8, rings=5)
    pk.displace_random(pom, 0.005, seed=5)
    for part in (beanie, pom):
        tilt(part, x_deg=-8.0)                  # worn pushed back
    return [beanie, pom], {beanie: 75.0, pom: 80.0}


def hat_antenna():
    band_m = pk.mat("PK_Body", name="PK_HatAntennaBand", color="#8A74D6", roughness=0.45)
    spring_m = pk.mat("PK_Metal", name="PK_HatAntennaSpring", color="#C9C4DA", roughness=0.3, metallic=0.7)
    ball_m = pk.mat("PK_AccentGlow", name="PK_HatAntennaGlow", color="#FFC23D", emission=1.0)
    forward = -0.06                             # band sits a little in front of the top

    def band_dir(i, j):
        beta = math.radians(-70.0 + 140.0 * i / 10)
        return Vector((math.sin(beta), forward + (-0.11 if j == 0 else 0.11), math.cos(beta))).normalized()

    band = patch("AntennaBand", band_dir, 10, 1, lambda i, j: (0.0, 0), [band_m],
                 front=lambda d: 0.012)
    parts = [band]
    for side in (-1.0, 1.0):
        beta = math.radians(32.0 * side)
        d = Vector((math.sin(beta), forward, math.cos(beta))).normalized()
        base = surface(d, 0.006)
        axis = (normal_at(d) + Vector((side * 0.3, -0.05, 0.0))).normalized()
        u = axis.cross(Vector((0, 1, 0))).normalized()
        w = axis.cross(u)
        pts = []
        turns, per_turn, height, coil = 2.0, 6, 0.102, 0.016
        count = int(turns * per_turn)
        for k in range(count + 1):
            a = math.tau * turns * k / count
            pts.append(base + axis * (height * k / count) + (u * math.cos(a) + w * math.sin(a)) * coil)
        tip = base + axis * 0.128
        pts.append(tip)
        parts.append(sweep("AntennaSpring%d" % (side > 0), pts, 0.0072, 4, spring_m))
        parts.append(pk.sphere("AntennaBall%d" % (side > 0), 0.027, loc=tuple(tip), material=ball_m,
                               segments=8, rings=4))
    soft = {p: 100.0 for p in parts[1:]}
    return parts, soft


def hat_cap():
    crown_m = pk.mat("PK_Body", name="PK_HatCapCrown", color="#6F8FD8", roughness=0.7)
    peak_m = pk.mat("PK_Body", name="PK_HatCapPeak", color="#F6C453", roughness=0.6)
    under_m = pk.mat("PK_Trim", name="PK_HatCapUnder", color="#3E4A86", roughness=0.7, metallic=0.0)
    crown = head_lathe("CapCrown", [dome(15.8, -0.006), dome(16.8, 0.011), dome(30.0, 0.015),
                                    dome(55.0, 0.022), dome(75.0, 0.027), (0.0, R0 + 0.029)],
                       crown_m, 20)
    peak = bill("CapPeak", root_r=0.166, top_z=dome(16.8, 0.011)[1] + 0.006, half_angle=56.0,
                length=0.102, droop=9.0, curve=0.018, thick=0.010, materials=[peak_m, under_m, peak_m])
    button = pk.cyl("CapButton", 0.02, 0.014, loc=tuple(HEAD + Vector((0, 0, R0 + 0.031))),
                    material=team, verts=8)
    return [crown, peak, button], {}


def hat_halo():
    glow = pk.mat("PK_AccentGlow", name="PK_HatHaloGlow", color="#FFD666", emission=1.4)
    ring = pk.torus("Halo", 0.098, 0.015, loc=tuple(HEAD + Vector((0.0, 0.018, R0 + 0.068))),
                    rot=(-12.0, 0.0, 0.0), material=glow, segments=24, ring_segments=6)
    return [ring], {ring: 60.0}


def hat_flower():
    petal_m = pk.mat("PK_Body", name="PK_HatFlowerPetal", color="#FFF4E2", roughness=0.55)
    heart_m = pk.mat("PK_Body", name="PK_HatFlowerHeart", color="#F5B731", roughness=0.6)
    leaf_m = pk.mat("PK_Body", name="PK_HatFlowerLeaf", color="#7BBF6A", roughness=0.6)
    d = direction(40.0, 50.0)                   # top-left of the helmet, toward the front
    n = normal_at(d)
    centre = surface(d, 0.0)
    u = Vector((0, 0, 1)).cross(n).normalized()
    v = n.cross(u)
    b = Builder("Petals", [petal_m])
    petals, per = 10, 4
    count = petals * per
    radius = {0: 0.030, 1: 0.074, 2: 0.088, 3: 0.074}   # valley, shoulder, tip, shoulder
    top_c = b.vert(None, centre + n * 0.007)
    bot_c = b.vert(None, centre - n * 0.003)
    inner, outer, under = [], [], []
    for k in range(count):
        a = math.tau * k / count
        radial = u * math.cos(a) + v * math.sin(a)
        r = radius[k % per]
        cup = 0.007 + 0.12 * r                  # petals curl up toward the tips
        inner.append(b.vert(None, centre + radial * 0.026 + n * (0.007 + 0.12 * 0.026)))
        outer.append(b.vert(None, centre + radial * r + n * cup))
        under.append(b.vert(None, centre + radial * r + n * (cup - 0.008)))
    for k in range(count):
        m = (k + 1) % count
        b.face([top_c, inner[k], inner[m]], 0, n)
        b.face([inner[k], outer[k], outer[m], inner[m]], 0, n)
        b.face([bot_c, under[m], under[k]], 0, -n)
        wall = [outer[k], outer[m], under[m], under[k]]
        b.face(wall, 0, (outer[k].co + outer[m].co) * 0.5 - centre)
    parts = [b.build()]
    parts.append(pk.sphere("Heart", 1.0, loc=tuple(centre + n * 0.014), scale=(0.032, 0.032, 0.016),
                           rot=along(n), material=heart_m, segments=10, rings=4))
    for n_leaf, a in enumerate((math.radians(140.0), math.radians(235.0))):
        out = u * math.cos(a) + v * math.sin(a)
        p = centre + out * 0.09 - n * 0.004
        x = out
        z = (n - x * n.dot(x)).normalized()
        y = z.cross(x)
        rot = Matrix((x, y, z)).transposed().to_euler()
        parts.append(pk.sphere("Leaf%d" % n_leaf, 1.0, loc=tuple(p), scale=(0.052, 0.022, 0.006),
                               rot=tuple(math.degrees(r) for r in rot), material=leaf_m,
                               segments=6, rings=3))
    return parts, {parts[1]: 60.0}


def hat_top_hat():
    felt = pk.mat("PK_Body", name="PK_HatTopFelt", color="#4E3F7A", roughness=0.55)
    profile = [(0.120, 0.104), (0.155, 0.106), (0.180, 0.110), (0.188, 0.119), (0.180, 0.127),
               (0.130, 0.125), (0.124, 0.130), (0.132, 0.255), (0.0, 0.259)]
    hat = pk.lathe("TopHat", profile, loc=tuple(HEAD), material=felt, segments=16)
    for v in hat.data.vertices:                 # brim curls up at the sides
        r = math.hypot(v.co.x, v.co.y)
        if r > 0.14 and v.co.z < 0.135:
            side = (v.co.x / r) ** 2
            v.co.z += 0.03 * side * ((r - 0.14) / 0.048) ** 2
    hat.data.transform(OVAL)

    # Paint-drip band round the crown: a ring whose lower edge runs down in drips.
    def crown_r(z):
        return 0.124 + (z - 0.130) * (0.008 / 0.125)

    b = Builder("DripBand", [team])
    cols = 24
    drop = {}
    for k, length in ((1, 0.036), (6, 0.022), (10, 0.042), (15, 0.03), (19, 0.038)):
        drop[k] = length
        for side in (-1, 1):
            drop[(k + side) % cols] = max(drop.get((k + side) % cols, 0.0), 0.3 * length)
    rows = []
    for k in range(cols):
        a = math.radians(-90.0 + 360.0 * k / cols + 5.0)
        c, s = math.cos(a) * HEAD_R[0] / R0, math.sin(a) * HEAD_R[1] / R0
        z_bot = 0.165 - drop.get(k, 0.0)
        rows.append([
            b.vert(None, HEAD + Vector((c * (crown_r(0.197) - 0.003), s * (crown_r(0.197) - 0.003), 0.198))),
            b.vert(None, HEAD + Vector((c * (crown_r(0.194) + 0.006), s * (crown_r(0.194) + 0.006), 0.194))),
            b.vert(None, HEAD + Vector((c * (crown_r(z_bot) + 0.006), s * (crown_r(z_bot) + 0.006), z_bot))),
            b.vert(None, HEAD + Vector((c * (crown_r(z_bot) - 0.003), s * (crown_r(z_bot) - 0.003), z_bot - 0.005))),
        ])
    for k in range(cols):
        p, q = rows[k], rows[(k + 1) % cols]
        out = Vector(((p[1].co + q[1].co) * 0.5 - HEAD).xy.to_3d()).normalized()
        b.face([p[0], q[0], q[1], p[1]], 0, out + Vector((0, 0, 1)))
        b.face([p[1], q[1], q[2], p[2]], 0, out)
        b.face([p[2], q[2], q[3], p[3]], 0, out - Vector((0, 0, 1)))
    band = b.build()
    for part in (hat, band):
        tilt(part, x_deg=-4.0, y_deg=6.0)       # a jaunty lean toward the runner's left
    return [hat, band], {}


HATS = [
    ("VISOR", hat_visor), ("CROWN", hat_crown), ("BUCKET_HAT", hat_bucket),
    ("BEANIE", hat_beanie), ("ANTENNA", hat_antenna), ("CAP", hat_cap),
    ("HALO", hat_halo), ("FLOWER", hat_flower), ("TOP_HAT", hat_top_hat),
]


def finish(name, parts, soft):
    """Shade each part, join them into one mesh named `name` with clean
    transforms, put its origin on Socket_Head and hang it under the root."""
    for p in parts:
        pk.smooth(p, soft.get(p, 35.0))
    obj = pk.join(name, parts) if len(parts) > 1 else parts[0]
    obj.name = name
    obj.data.name = name
    pk.apply(obj, location=True, rotation=True, scale=True)
    pk.set_origin(obj, SOCKET_HEAD)
    pk.parent(obj, root)
    return obj


items = [finish("Hat_" + hat_id, *build()) for hat_id, build in HATS]

over = False
for obj in items:
    count = pk.triangle_count([obj])[0]
    origin = obj.matrix_world.translation
    print("[hats] %-16s %4d tris  origin (%.3f, %.3f, %.3f)" % (obj.name, count, *origin))
    if count > HAT_BUDGET:
        print("[hats] ERROR: %s is over its %d-triangle budget" % (obj.name, HAT_BUDGET))
        over = True
    if (origin - SOCKET_HEAD).length > 1e-6:
        print("[hats] ERROR: %s origin is not on Socket_Head" % obj.name)
        over = True
if over:
    sys.exit(1)

pk.export("cosmetic_hats.glb", budget=TOTAL_BUDGET)


# ---------------------------------------------------------------------------
# Optional fit check: dress the runner in each hat and render a sheet.
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
    """For every outward-facing face: is it buried under the helmet, and how
    far does it stand off the helmet below it?"""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    ev = head.evaluated_get(depsgraph)
    hm = ev.to_mesh()
    tree = BVHTree.FromPolygons([head.matrix_world @ v.co for v in hm.vertices],
                                [tuple(p.vertices) for p in hm.polygons])
    ev.to_mesh_clear()
    buried, gaps = 0, []
    for poly in obj.data.polygons:
        c = obj.matrix_world @ poly.center
        n = (obj.matrix_world.to_3x3() @ poly.normal).normalized()
        radial = (c - HEAD).normalized()
        if n.dot(radial) < 0.5:
            continue
        if tree.ray_cast(c + radial * 1e-4, radial, 0.1)[0] is not None:
            buried += 1
            continue
        hit = tree.ray_cast(c, -radial, 0.3)
        if hit[0] is not None:
            gaps.append(hit[3])
    gaps.sort()
    print("[hats] fit %-16s buried faces %d   stand-off min %.1f mm  median %.1f mm  max %.1f mm" % (
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
    socket = bpy.data.objects.get("Socket_Head")
    if socket is not None:
        print("[hats] runner Socket_Head at (%.3f, %.3f, %.3f)" % tuple(socket.matrix_world.translation))
    head_obj = bpy.data.objects.get("Head")
    for obj in items:
        fit_check(obj, head_obj)
    frame = pk.box("PreviewFrame", (0.40, 0.46, 0.50), loc=(0.0, -0.075, 1.47))
    frame.hide_render = True
    flag_backfaces()
    for obj in items:
        for other in items:
            other.hide_render = other is not obj
        pk.preview(os.path.join(out_dir, "%s_%s.png" % (stem, obj.name[4:])), size=480)
        for leftover in [o for o in bpy.data.objects if o.name.startswith(("PreviewSun", "PreviewCam"))]:
            bpy.data.objects.remove(leftover)
