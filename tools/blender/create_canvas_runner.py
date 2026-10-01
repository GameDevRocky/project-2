"""
Canvas Runner - the body of every TDM combatant.

Plan: docs/VISUAL_OVERHAUL_PLAN.md section 4.2.

A chunky arena painter, 1.60 m tall: a big rounded ceramic helmet with a wide
dark visor band and a glowing team strip, broad padded shoulders, a padded
off-white jumpsuit with dried paint on it, big rubber boots and gloves, and a
slight forward athletic lean. The arms are posed holding the Paint Blaster
across the body, right hand on the grip, left hand under the paint chamber.

Axes: the runner faces BLENDER -Y (the exporter turns that into Godot +Z, the
direction enemy._face() turns toward a target). Z is up. Blender's usual
character convention applies: the runner's LEFT side is +X and its RIGHT side
is -X, so the front camera (looking at the visor) sees the right hand on the
left of the picture. The origin is on the floor between the feet, matching the
collision capsule (radius 0.40, height 1.60) whose base is at the body origin.

Nodes Godot relies on (names must not change):
    CanvasRunner   root empty at the origin.
    Body           everything that does not move on its own: torso, helmet,
                   visor, shoulder pads, arms posed on the blaster, team marks.
    Leg_L, Leg_R   one object per leg (thigh, knee pad, shin, boot). ORIGIN AT
                   THE HIP JOINT (x = +0.11 / -0.11, z = 0.78) so Godot swings
                   each leg by rotating it about X.
    Socket_Back    empty on the upper back where chromatic_reservoir.glb
                   clips on. No rotation.
    Socket_Hand_R  empty in the right hand where paint_blaster.glb's origin
                   goes. Rotated 180 degrees about Z, so the blaster (built
                   pointing +Y) points forward (-Y).

Material roles: PK_Canvas suit, PK_Body helmet and shoulder pads, PK_Dark
visor, PK_TeamGlow visor strip, PK_Team armbands / chest chevron / knee pads,
PK_Rubber boots, gloves and belt, PK_Dry1..4 dried paint splotches. Team
colour appears only in PK_Team and PK_TeamGlow.

Run:  blender -b --factory-startup --python tools/blender/create_canvas_runner.py
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

pk.begin("CanvasRunner", seed=21)

canvas = pk.mat("PK_Canvas")
ceramic = pk.mat("PK_Body")
rubber = pk.mat("PK_Rubber")
dark = pk.mat("PK_Dark")
team = pk.mat("PK_Team")
team_glow = pk.mat("PK_TeamGlow")
dried = [pk.mat("PK_Dry%d" % i) for i in range(1, 5)]

# The runner's right side is -X (it faces -Y). Flip this one number to mirror
# which hand holds the blaster.
RIGHT = -1.0
LEFT = -RIGHT

root = pk.empty("CanvasRunner")


# ---------------------------------------------------------------------------
# Local helpers (things the kit does not have)
# ---------------------------------------------------------------------------

def degrees(euler):
    return tuple(math.degrees(a) for a in euler)


def along(direction):
    """Rotation (degrees) that turns a part's local +Z to point along `direction`."""
    return degrees(Vector(direction).to_track_quat("Z", "Y").to_euler())


def capsule(name, p0, p1, r0, r1=None, material=None, segments=10, cap=2):
    """A (optionally tapered) capsule from point p0 to point p1: a lathe with a
    round cap at each end, turned to lie along p0 -> p1. Arms and legs."""
    r1 = r0 if r1 is None else r1
    p0, p1 = Vector(p0), Vector(p1)
    length = (p1 - p0).length
    profile = []
    for i in range(cap + 1):                      # bottom cap, pole -> equator
        a = -math.pi / 2 + (math.pi / 2) * i / cap
        profile.append((r0 * math.cos(a) if i else 0.0, r0 * math.sin(a)))
    for i in range(cap + 1):                      # top cap, equator -> pole
        a = (math.pi / 2) * i / cap
        profile.append((r1 * math.cos(a) if i < cap else 0.0, length + r1 * math.sin(a)))
    obj = pk.lathe(name, profile, loc=tuple(p0), rot=along(p1 - p0), material=material,
                   segments=segments)
    pk.apply(obj, location=False, rotation=True, scale=True)
    return obj


def band(name, p0, p1, r_in, r_out, material, segments=10):
    """A ring hugging a limb from p0 to p1 (armband, cuff): an open lathe whose
    edges tuck in to r_in, so it needs no end caps hidden inside the arm."""
    p0, p1 = Vector(p0), Vector(p1)
    length = (p1 - p0).length
    profile = [(r_in, 0.0), (r_out, length * 0.25), (r_out, length * 0.75), (r_in, length)]
    obj = pk.lathe(name, profile, loc=tuple(p0), rot=along(p1 - p0), material=material,
                   segments=segments)
    pk.apply(obj, location=False, rotation=True, scale=True)
    return obj


def ellipsoid_patch(name, centre, radii, theta, phi, steps, out, inset, material):
    """A raised panel wrapped onto an ellipsoid (the helmet): the visor band
    and its glowing strip. `theta` is the azimuth range in degrees measured
    from the front (-Y) toward +X, `phi` the latitude range. The panel stands
    `out` metres proud of the surface and its walls sink `inset` below it."""
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
    # Winding is written out so every face points away from the helmet.
    for i in range(nth):
        for j in range(nph):
            bm.faces.new((o[i][j], o[i + 1][j], o[i + 1][j + 1], o[i][j + 1]))
        bm.faces.new((o[i][0], n[i][0], n[i + 1][0], o[i + 1][0]))              # bottom wall
        bm.faces.new((o[i][nph], o[i + 1][nph], n[i + 1][nph], n[i][nph]))      # top wall
    for j in range(nph):
        bm.faces.new((o[0][j], o[0][j + 1], n[0][j + 1], n[0][j]))              # end walls
        bm.faces.new((o[nth][j], n[nth][j], n[nth][j + 1], o[nth][j + 1]))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    pk._collection.objects.link(obj)
    mesh.materials.append(material)
    return obj


def hit(obj, origin, direction):
    """Where a ray from `origin` along `direction` first meets obj's surface
    (modifiers included). Returns (point, normal) in world space, or None."""
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(obj, depsgraph)
    inv = obj.matrix_world.inverted()
    o = inv @ Vector(origin)
    d = (inv.to_3x3() @ Vector(direction)).normalized()
    loc, normal, _, _ = tree.ray_cast(o, d)
    if loc is None:
        return None
    world_normal = (obj.matrix_world.inverted().transposed().to_3x3() @ normal).normalized()
    return obj.matrix_world @ loc, world_normal


def splotch(name, target, origin, direction, radius, material, verts=9, seed=0):
    """A flattened blob of dried paint shrink-wrapped onto `target`: every rim
    point is ray-cast onto the surface, then a skirt tucks the edge under it."""
    rng = random.Random(seed)
    found = hit(target, origin, direction)
    if found is None:
        print("[runner] splotch %s missed its target" % name)
        return None
    centre, normal = found
    tangent = normal.orthogonal().normalized()
    bitangent = normal.cross(tangent)
    bm = bmesh.new()
    mid = bm.verts.new(centre + normal * 0.012)
    rim, skirt = [], []
    for i in range(verts):
        a = math.tau * i / verts + rng.uniform(-0.15, 0.15)
        r = radius * rng.uniform(0.72, 1.18)
        d = tangent * math.cos(a) + bitangent * math.sin(a)
        for ring, scale, lift in ((rim, 1.0, 0.007), (skirt, 1.18, -0.006)):
            probe = centre + d * r * scale
            got = hit(target, probe + normal * 0.08, -normal)
            p, nrm = got if got else (probe, normal)
            ring.append(bm.verts.new(p + nrm * lift))
    for i in range(verts):
        k = (i + 1) % verts
        bm.faces.new((mid, rim[i], rim[k]))
        bm.faces.new((rim[i], skirt[i], skirt[k], rim[k]))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    pk._collection.objects.link(obj)
    mesh.materials.append(material)
    return obj


def elbow(shoulder, hand, upper, lower, pole):
    """Two-bone reach: where the elbow goes so an upper arm of length `upper`
    and a forearm of length `lower` connect shoulder to hand, bending toward
    `pole`. If the hand is out of reach the arm points straight at it."""
    s, h = Vector(shoulder), Vector(hand)
    to_hand = h - s
    dist = to_hand.length
    if dist >= upper + lower:
        print("[runner] warning: hand out of reach by %.3f m" % (dist - upper - lower))
        return s + to_hand.normalized() * upper
    a = (upper * upper - lower * lower + dist * dist) / (2 * dist)
    rise = math.sqrt(max(upper * upper - a * a, 0.0))
    axis = to_hand.normalized()
    side = Vector(pole) - axis * Vector(pole).dot(axis)
    return s + axis * a + side.normalized() * rise


def world_join(name, parts):
    """Join parts into one mesh whose vertices are in world space and whose
    transform is clean (origin at the world origin, no rotation or scale)."""
    obj = pk.join(name, parts)
    pk.apply(obj, location=True, rotation=True, scale=True)
    return obj


# ---------------------------------------------------------------------------
# Proportions (metres)
# ---------------------------------------------------------------------------

HIP_Z = 0.78
HIP_X = 0.11
LEAN = 7.0                          # forward lean of the upper body, degrees
LEAN_PIVOT = Vector((0.0, 0.0, 0.84))
LEAN_M = (Matrix.Translation(LEAN_PIVOT) @ Matrix.Rotation(math.radians(LEAN), 4, "X")
          @ Matrix.Translation(-LEAN_PIVOT))


def lean(p):
    """Where an upright upper-body point ends up after the forward lean."""
    return LEAN_M @ Vector(p)


HEAD = Vector((0.0, -0.065, 1.43))  # helmet centre (already leaned forward)
HEAD_R = (0.172, 0.168, 0.17)       # top of the helmet = 1.60
HAND_SOCKET = Vector((RIGHT * 0.17, -0.31, 0.95))


# ---------------------------------------------------------------------------
# Legs: thigh, knee pad, shin, boot. Built one per side, origin at the hip.
# ---------------------------------------------------------------------------

# Side outline of a boot in (world Y, world Z): a high-top with a rounded,
# slightly upturned toe pointing -Y and an ankle collar the shin drops into.
BOOT_OUTLINE = [(0.10, 0.03), (-0.18, 0.03), (-0.215, 0.06), (-0.21, 0.098),
                (-0.17, 0.128), (-0.10, 0.148), (-0.085, 0.26), (0.09, 0.26),
                (0.108, 0.2), (0.112, 0.07)]


def build_leg(side, tag):
    x = side * HIP_X
    foot_x = side * 0.125
    hip = Vector((x, 0.0, HIP_Z))
    knee = Vector((side * 0.12, -0.035, 0.45))
    ankle = Vector((foot_x, 0.0, 0.17))
    parts = [
        capsule("Thigh" + tag, hip, knee, 0.105, 0.086, canvas),
        capsule("Shin" + tag, knee, ankle, 0.084, 0.07, canvas),
        pk.box("KneePad" + tag, (0.135, 0.05, 0.15), loc=(knee.x, knee.y - 0.065, knee.z + 0.01),
               rot=(-8, 0, 0), material=team, bevel=0.022, segments=1),
        # rot (90, 0, 90) stands the (Y, Z) outline up with its thickness on X.
        pk.prism("Boot" + tag, BOOT_OUTLINE, 0.17, loc=(foot_x, 0.0, 0.0), rot=(90, 0, 90),
                 material=rubber, bevel=0.03, segments=1),
        pk.box("Sole" + tag, (0.18, 0.335, 0.04), loc=(foot_x, -0.052, 0.02),
               material=dark, bevel=0.014, segments=1),
    ]
    return world_join("Leg" + tag, parts)


leg_l = build_leg(LEFT, "_L")
leg_r = build_leg(RIGHT, "_R")


# ---------------------------------------------------------------------------
# Hips (upright) and the leaning upper body
# ---------------------------------------------------------------------------

pelvis = pk.box("Pelvis", (0.36, 0.24, 0.18), loc=(0, 0.01, 0.8), material=canvas,
                bevel=0.07, segments=2)

upper = []

torso = pk.box("Torso", (0.46, 0.27, 0.45), loc=(0, 0.005, 1.075), material=canvas,
               bevel=0.1, segments=3)
for v in torso.data.vertices:          # taper: narrower waist, broad chest
    if v.co.z < 0:
        v.co.x *= 0.8
        v.co.y *= 0.92
upper.append(torso)


def rounded_rect(hx, hy, r, per_corner=2):
    pts = []
    for cx, cy, start in ((hx - r, hy - r, 0), (-hx + r, hy - r, 90),
                          (-hx + r, -hy + r, 180), (hx - r, -hy + r, 270)):
        for i in range(per_corner + 1):
            a = math.radians(start + 90 * i / per_corner)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


upper.append(pk.prism("Belt", rounded_rect(0.2, 0.135, 0.085), 0.06, loc=(0, 0.004, 0.875),
                      material=rubber, bevel=0.012, segments=1))

# Chest chevron: a thick V on the upper chest, point down.
upper.append(pk.prism("Chevron", [(0.0, -0.07), (0.13, 0.03), (0.13, 0.085), (0.0, -0.015),
                                  (-0.13, 0.085), (-0.13, 0.03)],
                      0.03, loc=(0, -0.136, 1.15), rot=(90, 0, 0), material=team,
                      bevel=0.007, segments=1))

# Broad padded shoulders: flattened ceramic domes tipped outward.
for side, tag in ((LEFT, "L"), (RIGHT, "R")):
    upper.append(pk.sphere("ShoulderPad" + tag, 1.0, loc=(side * 0.265, 0.0, 1.255),
                           scale=(0.13, 0.155, 0.085), rot=(0, side * 24, 0),
                           material=ceramic, segments=12, rings=6))

bpy.context.view_layer.update()
for obj in upper:
    obj.matrix_world = LEAN_M @ obj.matrix_world


# ---------------------------------------------------------------------------
# Arms posed on the blaster. The blaster's grip sits just below and behind
# the hand socket; its paint chamber runs forward from the socket.
# ---------------------------------------------------------------------------

UPPER_ARM, FOREARM = 0.28, 0.3
grip = HAND_SOCKET + Vector((0.0, 0.055, -0.11))           # right glove centre
support = HAND_SOCKET + Vector((LEFT * 0.045, -0.07, -0.04))  # left glove centre

arms = []
joints = {}
forearms = {}
for side, tag, hand, pole in ((RIGHT, "R", grip, (RIGHT * 1.0, 0.6, -0.4)),
                              (LEFT, "L", support, (LEFT * 0.5, 0.0, -1.0))):
    shoulder = lean((side * 0.245, 0.0, 1.2))
    el = elbow(shoulder, hand, UPPER_ARM, FOREARM, pole)
    joints[tag] = (shoulder, el, hand)
    forearms[tag] = capsule("Forearm" + tag, el, hand, 0.066, 0.058, canvas)
    arms.append(capsule("UpperArm" + tag, shoulder, el, 0.076, 0.066, canvas))
    arms.append(forearms[tag])
    up_dir = (el - shoulder).normalized()
    arms.append(band("Armband" + tag, shoulder + up_dir * 0.085, shoulder + up_dir * 0.15,
                     0.066, 0.083, team))
    fore_dir = (hand - el).normalized()
    arms.append(band("Cuff" + tag, hand - fore_dir * 0.11, hand - fore_dir * 0.04,
                     0.056, 0.074, rubber, segments=9))
    arms.append(pk.sphere("Glove" + tag, 1.0, loc=tuple(hand), scale=(0.064, 0.074, 0.07),
                          rot=along(fore_dir), material=rubber, segments=8, rings=6))


# ---------------------------------------------------------------------------
# Helmet: a big ceramic dome with a wide dark visor and a glowing team strip
# ---------------------------------------------------------------------------

helmet = pk.sphere("Helmet", 1.0, loc=tuple(HEAD), scale=HEAD_R, material=ceramic,
                   segments=18, rings=10)
visor = ellipsoid_patch("Visor", HEAD, HEAD_R, (-84, 84), (-27, 15), (10, 2), 0.012, 0.012,
                        dark)
strip = ellipsoid_patch("VisorStrip", HEAD, HEAD_R, (-64, 64), (-7, 1), (10, 1), 0.02, 0.0,
                        team_glow)


# ---------------------------------------------------------------------------
# Join the body, drop the dried paint on, place the sockets
# ---------------------------------------------------------------------------

# Dried paint goes on the suit only (torso, thighs, shins, sleeves), so each
# splotch is ray-cast onto one particular part before the parts are joined.
splotches = [
    splotch("Dry0", torso, (LEFT * 0.1, -1.0, 0.97), (0, 1, 0), 0.05, dried[1], seed=1),
    splotch("Dry1", torso, (RIGHT * 1.0, 0.03, 1.02), (1, 0, 0), 0.045, dried[0], seed=2),
    splotch("Dry2", torso, (RIGHT * 0.15, 1.0, 0.9), (0, -1, 0), 0.042, dried[2], seed=3),
    splotch("Dry3", pelvis, (LEFT * 0.12, 1.0, 0.78), (0, -1, 0), 0.04, dried[3], seed=4),
    splotch("Dry4", torso, (LEFT * 0.16, -1.0, 1.21), (0, 1, 0), 0.02, dried[1], verts=6, seed=5),
]
leg_splotches = {
    "L": [splotch("Dry5", leg_l, (LEFT * 1.0, -0.02, 0.3), (-LEFT, 0, 0), 0.045, dried[3], seed=6),
          splotch("Dry6", leg_l, (LEFT * 0.1, 1.0, 0.6), (0, -1, 0), 0.04, dried[0], seed=7)],
    "R": [splotch("Dry7", leg_r, (RIGHT * 0.12, -1.0, 0.62), (0, 1, 0), 0.047, dried[0], seed=8),
          splotch("Dry8", leg_r, (RIGHT * 0.13, -1.0, 0.55), (0, 1, 0), 0.018, dried[2], verts=6,
                  seed=9)],
}
_, right_elbow, right_hand = joints["R"]
forearm_mid = (right_elbow + right_hand) * 0.5
arm_splotch = splotch("Dry9", forearms["R"], forearm_mid + Vector((RIGHT * 0.4, 0.0, 0.15)),
                      (-RIGHT, 0.0, -0.35), 0.032, dried[1], seed=10)

body_parts = ([pelvis] + upper + arms + [helmet, visor, strip]
              + [s for s in splotches + [arm_splotch] if s is not None])
body = world_join("Body", body_parts)
pk.parent(body, root)

for leg, tag in ((leg_l, "L"), (leg_r, "R")):
    extras = [s for s in leg_splotches[tag] if s is not None]
    joined = world_join(leg.name, [leg] + extras) if extras else leg
    joined.name = "Leg_" + tag
    joined.data.name = "Leg_" + tag
    side = LEFT if tag == "L" else RIGHT
    pk.set_origin(joined, (side * HIP_X, 0.0, HIP_Z))
    pk.parent(joined, root)

# Socket_Back: straight behind the torso at z = 1.12, on its surface.
back = hit(body, (0.0, 1.0, 1.12), (0, -1, 0))
if back is None:
    print("[runner] warning: Socket_Back ray missed the torso; using a default")
back_point = back[0] if back else Vector((0.0, 0.1, 1.12))
pk.empty("Socket_Back", loc=tuple(back_point), parent_obj=root)
pk.empty("Socket_Hand_R", loc=tuple(HAND_SOCKET), rot=(0, 0, 180), parent_obj=root)

pk.smooth_all(35.0)
pk.export("canvas_runner.glb", budget=3000)
