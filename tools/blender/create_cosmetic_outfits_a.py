"""
Cosmetic outfits A - seven full-body outfit kits for the Canvas Runner.

Output: models/generated/cosmetic_outfits_a.glb

WHAT THIS BUILDS
The Canvas Runner (create_canvas_runner.py) is the body every TDM combatant
uses. An "outfit" is a set of extra pieces laid OVER that body - bone plates,
a cape, a robot head... Godot loads this one file, keeps the outfit the
player picked and throws the others away, then:
  * recolours the runner's suit (material PK_Canvas) and helmet + shoulder
    pads (PK_Body) to the outfit's SUIT and HELMET colours (the OUTFITS table
    below - Godot keeps its own copy of these numbers),
  * hides the runner's Head when the outfit brings its own head,
  * moves the children of each OnLeg_L / OnLeg_R empty onto the runner's
    real legs, so leg pieces swing with the legs when the runner walks.

FILE LAYOUT (node names Godot relies on)
    OutfitsA                       root empty at the origin
      Outfit_<ID>                  one empty per outfit, at the origin
        <ID>_Body                  everything that does not move on its own
        <ID>_Head                  head pieces (own head, or mask/band/goggles)
        OnLeg_L  (0.11, 0, 0.78)   = the runner's left hip pivot
          <ID>_LegL                pieces that ride on the left leg
        OnLeg_R  (-0.11, 0, 0.78)  = the runner's right hip pivot
          <ID>_LegR
All seven outfits sit in the same place (they overlap in the file on purpose:
each one is built in the runner's rest-pose coordinates).

Blender cannot give two objects the same name, so it calls the second
outfit's leg empty "OnLeg_L.001". After exporting, this script rewrites those
names in the .glb back to exactly "OnLeg_L" / "OnLeg_R". (Godot's importer
then makes node names unique across the whole file - OnLeg_L, OnLeg_L2, ...
- so look the leg empties up by their "OnLeg_L" / "OnLeg_R" prefix.)

Axes: Blender Z is up and the runner faces -Y. The runner's LEFT is +X.

TEAM COLOUR: every outfit shows PK_Team / PK_TeamGlow (repainted red or blue
by Godot) on something clearly visible from the front AND from the back.

HOW PIECES ARE FITTED TO THE BODY
Most pieces are flat shapes (an outline drawn in 2D) that get "shrink-wrapped"
onto the runner: every corner of the shape is shot as a ray at an exact copy
of the runner's torso / arm / leg / helmet and lands on its surface. That copy
is rebuilt here from the same numbers create_canvas_runner.py uses, used only
for aiming, and deleted before export. Rings round arms and legs are spun
round the limb's own axis (like a lathe), a little wider than the limb.

Run:
    blender -b --factory-startup --python-exit-code 1 \
        --python tools/blender/create_cosmetic_outfits_a.py
Optional, after "--":
    --out PATH              export somewhere else
    --outfit-previews DIR   also render each outfit worn by the runner (with
                            a backpack, team colours red/blue) into DIR
    --draft                 skip the triangle budgets and print a per-part
                            triangle breakdown (for working on the designs)
"""

import json
import math
import os
import random
import struct
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("OutfitsA", seed=31)

RUNNER_GLB = os.path.join(pk.REPO, "models", "generated", "canvas_runner.glb")
PACK_GLB = os.path.join(pk.REPO, "models", "generated", "chromatic_reservoir.glb")
_ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DRAFT = "--draft" in _ARGV

# One row per outfit: the colours Godot paints the runner's suit and its
# helmet + shoulder pads, and whether the runner's own Head is hidden (the
# outfit wears its own head instead).
OUTFITS = {
    "SKELETON":           dict(suit="#2F2B3D", helmet="#EDE6D4", hide_head=True),
    "SUPERHERO":          dict(suit="#7B4FD0", helmet="#F4C430", hide_head=False),
    "ZOMBIE":             dict(suit="#8F80AE", helmet="#776A93", hide_head=True),
    "ASTRONAUT":          dict(suit="#ECE9E1", helmet="#F2A541", hide_head=True),
    "NINJA":              dict(suit="#383B5E", helmet="#26283E", hide_head=False),
    "ROBOT":              dict(suit="#7D8796", helmet="#E3B23C", hide_head=True),
    "PAINTBALL_SPLATTER": dict(suit="#F1ECF7", helmet="#B9A7F2", hide_head=False),
}
BUDGET_EACH = 1300


# ---------------------------------------------------------------------------
# Materials. PK_Team / PK_TeamGlow are repainted red or blue by Godot; every
# other material here is a named variant with its own fixed colour.
# ---------------------------------------------------------------------------

team = pk.mat("PK_Team")
team_glow = pk.mat("PK_TeamGlow")
dark = pk.mat("PK_Dark")
glass = pk.mat("PK_Glass")

bone = pk.mat("PK_Body", name="PK_SkelBone", color="#EDE6D4", roughness=0.55)
socket_dark = pk.mat("PK_Dark", name="PK_SkelSocket", color="#2A2333", roughness=0.7)

hero_gold = pk.mat("PK_Brass", name="PK_HeroGold", color="#F4C430", roughness=0.3, metallic=0.55)
hero_mask = pk.mat("PK_Body", name="PK_HeroMask", color="#46309A", roughness=0.4)

zombie_skin = pk.mat("PK_Body", name="PK_ZombieSkin", color="#9CC285", roughness=0.75)
zombie_rag = pk.mat("PK_Canvas", name="PK_ZombieRag", color="#655782", roughness=0.95)
zombie_cap = pk.mat("PK_Canvas", name="PK_ZombieCap", color="#56708A", roughness=0.95)
zombie_patch = pk.mat("PK_Canvas", name="PK_ZombiePatch", color="#D9A066", roughness=0.95)
zombie_patch2 = pk.mat("PK_Canvas", name="PK_ZombiePatch2", color="#7FB3A8", roughness=0.95)
stitch = pk.mat("PK_Dark", name="PK_Stitch", color="#2C2433", roughness=0.8)
ooze = pk.mat("PK_Wet", name="PK_Ooze", color="#9BC53D", roughness=0.15)

astro_box = pk.mat("PK_Shell", name="PK_AstroBox", color="#C9CDD8", roughness=0.5)
astro_metal = pk.mat("PK_Metal", name="PK_AstroMetal", color="#AEB4C4", roughness=0.3,
                     metallic=0.7)
astro_dial = pk.mat("PK_Body", name="PK_AstroDial", color="#F2A541", roughness=0.35)

ninja_wrap = pk.mat("PK_Canvas", name="PK_NinjaWrap", color="#CFC8D8", roughness=0.9)
ninja_cloth = pk.mat("PK_Canvas", name="PK_NinjaCloth", color="#4E5487", roughness=0.9)
ninja_plate = pk.mat("PK_Metal", name="PK_NinjaPlate", color="#B9BCCB", roughness=0.3,
                     metallic=0.7)

robo_plate = pk.mat("PK_Metal", name="PK_RoboPlate", color="#D6DAE2", roughness=0.35,
                    metallic=0.55)
robo_rivet = pk.mat("PK_Metal", name="PK_RoboRivet", color="#6E7684", roughness=0.3,
                    metallic=0.75)
robo_screen = pk.mat("PK_Dark", name="PK_RoboScreen", color="#1E2233", roughness=0.25)

splat_orange = pk.mat("PK_Wet", name="PK_SplatOrange", color="#FF8C42", roughness=0.2)
splat_yellow = pk.mat("PK_Wet", name="PK_SplatYellow", color="#FFD23F", roughness=0.2)
splat_violet = pk.mat("PK_Wet", name="PK_SplatViolet", color="#9B5DE5", roughness=0.2)
splat_green = pk.mat("PK_Wet", name="PK_SplatGreen", color="#5CC97B", roughness=0.2)
goggle_frame = pk.mat("PK_Rubber", name="PK_GoggleFrame", color="#3B3F58", roughness=0.6)
goggle_lens = pk.mat("PK_Body", name="PK_GoggleLens", color="#FF9F45", roughness=0.08,
                     metallic=0.3)


# ---------------------------------------------------------------------------
# The runner's rest pose. These numbers are copied from
# create_canvas_runner.py - if the runner changes, change them here too.
# ---------------------------------------------------------------------------

RIGHT, LEFT = -1.0, 1.0
HIP_Z, HIP_X = 0.78, 0.11
LEAN = 7.0
LEAN_PIVOT = Vector((0.0, 0.0, 0.84))
LEAN_M = (Matrix.Translation(LEAN_PIVOT) @ Matrix.Rotation(math.radians(LEAN), 4, "X")
          @ Matrix.Translation(-LEAN_PIVOT))
LEAN_R = Matrix.Rotation(math.radians(LEAN), 3, "X")
HEAD = Vector((0.0, -0.065, 1.43))
HEAD_R = (0.172, 0.168, 0.17)
HAND_SOCKET = Vector((RIGHT * 0.17, -0.31, 0.95))
UPPER_ARM, FOREARM = 0.28, 0.3
LEG_PIVOT = {"L": Vector((LEFT * HIP_X, 0.0, HIP_Z)), "R": Vector((RIGHT * HIP_X, 0.0, HIP_Z))}

TORSO_C = LEAN_M @ Vector((0.0, 0.005, 1.075))   # centre of the leaning torso
TORSO_UP = LEAN_R @ Vector((0.0, 0.0, 1.0))       # its "up", tipped 7 degrees forward
TORSO_FWD = LEAN_R @ Vector((0.0, -1.0, 0.0))     # straight out of its chest

# Where the backpack (chromatic_reservoir.glb at Socket_Back) sits: capes and
# tails must stay out of this box.
PACK_X = (-0.262, 0.195)
PACK_Z = (0.861, 1.408)


def lean(p):
    return LEAN_M @ Vector(p)


def degrees(euler):
    return tuple(math.degrees(a) for a in euler)


def along(direction):
    """Rotation (degrees) that turns a part's local +Z to point along `direction`."""
    return degrees(Vector(direction).to_track_quat("Z", "Y").to_euler())


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
ARM = {}   # "L"/"R" -> (shoulder, elbow, hand)
for _side, _tag, _hand, _pole in ((RIGHT, "R", _grip, (RIGHT * 1.0, 0.6, -0.4)),
                                  (LEFT, "L", _support, (LEFT * 0.5, 0.0, -1.0))):
    _shoulder = lean((_side * 0.245, 0.0, 1.2))
    ARM[_tag] = (_shoulder, elbow(_shoulder, _hand, UPPER_ARM, FOREARM, _pole), _hand)

LEG = {}   # "L"/"R" -> (hip, knee, ankle)
for _side, _tag in ((LEFT, "L"), (RIGHT, "R")):
    LEG[_tag] = (Vector((_side * HIP_X, 0.0, HIP_Z)), Vector((_side * 0.12, -0.035, 0.45)),
                 Vector((_side * 0.125, 0.0, 0.17)))

# Radii of the runner's limb capsules at their two ends.
LIMB_R = {"uarm": (0.076, 0.066), "farm": (0.066, 0.058),
          "thigh": (0.105, 0.086), "shin": (0.084, 0.07)}


def limb_ends(part, tag):
    if part == "uarm":
        return ARM[tag][0], ARM[tag][1]
    if part == "farm":
        return ARM[tag][1], ARM[tag][2]
    if part == "thigh":
        return LEG[tag][0], LEG[tag][1]
    return LEG[tag][1], LEG[tag][2]


def limb_len(part, tag):
    p0, p1 = limb_ends(part, tag)
    return (p1 - p0).length


def limb_radius(part, tag, t):
    """Radius of the runner's limb `t` metres along it from its upper joint."""
    r0, r1 = LIMB_R[part]
    return r0 + (r1 - r0) * max(0.0, min(1.0, t / limb_len(part, tag)))


# ---------------------------------------------------------------------------
# Small geometry helpers
# ---------------------------------------------------------------------------

def rounded_rect(hx, hy, r, per_corner=2):
    pts = []
    for cx, cy, start in ((hx - r, hy - r, 0), (-hx + r, hy - r, 90),
                          (-hx + r, -hy + r, 180), (hx - r, -hy + r, 270)):
        for i in range(per_corner + 1):
            a = math.radians(start + 90 * i / per_corner)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def capsule(name, p0, p1, r0, r1=None, material=None, segments=10, cap=2):
    """Same as the runner's capsule(): its arms and legs are made of these."""
    r1 = r0 if r1 is None else r1
    p0, p1 = Vector(p0), Vector(p1)
    length = (p1 - p0).length
    profile = []
    for i in range(cap + 1):
        a = -math.pi / 2 + (math.pi / 2) * i / cap
        profile.append((r0 * math.cos(a) if i else 0.0, r0 * math.sin(a)))
    for i in range(cap + 1):
        a = (math.pi / 2) * i / cap
        profile.append((r1 * math.cos(a) if i < cap else 0.0, length + r1 * math.sin(a)))
    obj = pk.lathe(name, profile, loc=tuple(p0), rot=along(p1 - p0), material=material,
                   segments=segments)
    pk.apply(obj, location=False, rotation=True, scale=True)
    return obj


def band(name, p0, p1, r_in, r_out, material=None, segments=10):
    """Same as the runner's band() (its armbands)."""
    p0, p1 = Vector(p0), Vector(p1)
    length = (p1 - p0).length
    profile = [(r_in, 0.0), (r_out, length * 0.25), (r_out, length * 0.75), (r_in, length)]
    obj = pk.lathe(name, profile, loc=tuple(p0), rot=along(p1 - p0), material=material,
                   segments=segments)
    pk.apply(obj, location=False, rotation=True, scale=True)
    return obj


def bm_object(name, bm, material):
    """Turn a bmesh (Blender's editable mesh) into an object in the asset."""
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    pk._collection.objects.link(obj)
    if material is not None:
        mesh.materials.append(material)
    return obj


def world_join(name, parts):
    """Join parts into one mesh with a clean transform at the world origin."""
    parts = [p for p in parts if p is not None]
    if DRAFT:
        _total, per = pk.triangle_count(parts)
        groups = {}
        for part_name, count in per.items():
            key = part_name.split(".")[0]
            groups[key] = groups.get(key, 0) + count
        print("[parts] %s: %s" % (name, ", ".join("%s %d" % kv for kv in
                                                  sorted(groups.items(), key=lambda kv: -kv[1]))))
    obj = pk.join(name, parts) if len(parts) > 1 else parts[0]
    obj.name = name
    obj.data.name = name
    pk.apply(obj, location=True, rotation=True, scale=True)
    return obj


# ---------------------------------------------------------------------------
# An exact copy of the runner's surfaces, used only to aim pieces at.
# ---------------------------------------------------------------------------

def bvh_of(objs):
    """One ray-cast tree (in world space) for a group of reference parts."""
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    verts, polys = [], []
    for obj in objs:
        ev = obj.evaluated_get(depsgraph)
        mesh = ev.to_mesh()
        base = len(verts)
        verts.extend(obj.matrix_world @ v.co for v in mesh.vertices)
        polys.extend(tuple(base + i for i in p.vertices) for p in mesh.polygons)
        ev.to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys)


def build_reference():
    ref = []
    torso = pk.box("RefTorso", (0.46, 0.27, 0.45), loc=(0, 0.005, 1.075), bevel=0.1, segments=3)
    for v in torso.data.vertices:
        if v.co.z < 0:
            v.co.x *= 0.8
            v.co.y *= 0.92
    belt = pk.prism("RefBelt", rounded_rect(0.2, 0.135, 0.085), 0.06, loc=(0, 0.004, 0.875),
                    bevel=0.012, segments=1)
    pads = {}
    for side, tag in ((LEFT, "L"), (RIGHT, "R")):
        pads[tag] = pk.sphere("RefPad" + tag, 1.0, loc=(side * 0.265, 0.0, 1.255),
                              scale=(0.13, 0.155, 0.085), rot=(0, side * 24, 0),
                              segments=12, rings=6)
    bpy.context.view_layer.update()
    for obj in [torso, belt] + list(pads.values()):
        obj.matrix_world = LEAN_M @ obj.matrix_world
    pelvis = pk.box("RefPelvis", (0.36, 0.24, 0.18), loc=(0, 0.01, 0.8), bevel=0.07, segments=2)
    ref += [torso, belt, pelvis] + list(pads.values())

    trees = {"torso": bvh_of([torso]), "pelvis": bvh_of([pelvis])}
    for tag in ("L", "R"):
        shoulder, el, hand = ARM[tag]
        up = capsule("RefUpper" + tag, shoulder, el, 0.076, 0.066)
        up_dir = (el - shoulder).normalized()
        armband = band("RefArmband" + tag, shoulder + up_dir * 0.085, shoulder + up_dir * 0.15,
                       0.066, 0.083)
        fore = capsule("RefFore" + tag, el, hand, 0.066, 0.058)
        hip, knee, ankle = LEG[tag]
        thigh = capsule("RefThigh" + tag, hip, knee, 0.105, 0.086)
        shin = capsule("RefShin" + tag, knee, ankle, 0.084, 0.07)
        ref += [up, armband, fore, thigh, shin]
        trees["uarm" + tag] = bvh_of([up, armband])
        trees["farm" + tag] = bvh_of([fore])
        trees["thigh" + tag] = bvh_of([thigh])
        trees["shin" + tag] = bvh_of([shin])
        trees["pad" + tag] = bvh_of([pads[tag]])
    for obj in ref:
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(mesh)
    return trees


TREES = build_reference()


# ---------------------------------------------------------------------------
# Surfaces: turn flat (a, b, h) coordinates into points on the runner.
#   a = sideways (toward the runner's LEFT, +X, on its front)
#   b = "up" along the surface
#   h = height above the surface (negative = sunk into it)
# A flat outline drawn counter-clockwise in (a, b) comes out facing outward.
# ---------------------------------------------------------------------------

class Surface:
    """Shoots a ray for every (a, b) and lands on a reference part."""

    def __init__(self, ray, tree, eps=0.006):
        self.ray = ray
        self.tree = tree
        self.eps = eps
        self.cache = {}

    def hit(self, a, b):
        key = (round(a, 5), round(b, 5))
        if key not in self.cache:
            origin, direction = self.ray(a, b)
            loc = self.tree.ray_cast(origin, direction, 3.0)[0]
            if loc is None:
                # The outline hangs off the edge of the part: use the closest
                # point of the part instead (designs keep this rare).
                loc = self.tree.find_nearest(origin + direction * 0.3)[0]
            self.cache[key] = loc
        return self.cache[key]

    def frame(self, a, b):
        """(surface point, outward normal) - the normal is measured across a
        centimetre of surface, so it is smooth rather than per-facet."""
        e = self.eps
        p = self.hit(a, b)
        du = self.hit(a + e, b) - self.hit(a - e, b)
        dv = self.hit(a, b + e) - self.hit(a, b - e)
        n = du.cross(dv)
        direction = self.ray(a, b)[1]
        if n.length < 1e-9:
            n = -direction
        n.normalize()
        if n.dot(direction) > 0:
            n = -n
        return p, n

    def __call__(self, a, b, h):
        p, n = self.frame(a, b)
        return p + n * h


class Ellipsoid:
    """The same idea on a perfect ellipsoid (the helmet, a skull): no rays.
    a and b are arc lengths in metres on a ball of radius R; a = 0, b = 0 is
    the middle of the face."""

    def __init__(self, centre, radii, R=0.17):
        self.c = Vector(centre)
        self.r = radii
        self.R = R

    def frame(self, a, b):
        th, ph = a / self.R, b / self.R
        d = Vector((math.cos(ph) * math.sin(th), -math.cos(ph) * math.cos(th), math.sin(ph)))
        rx, ry, rz = self.r
        p = self.c + Vector((d.x * rx, d.y * ry, d.z * rz))
        n = Vector((d.x / rx, d.y / ry, d.z / rz)).normalized()
        return p, n

    def __call__(self, a, b, h):
        p, n = self.frame(a, b)
        return p + n * h


def planar(origin, normal, u, tree, back=0.35):
    """Rays shot straight in along -normal (like a slide projector)."""
    N = Vector(normal).normalized()
    U = Vector(u)
    U = (U - N * U.dot(N)).normalized()
    V = N.cross(U)
    O = Vector(origin)
    return Surface(lambda a, b: (O + U * a + V * b + N * back, -N), tree)


def wrap(base, axis, ref, tree, arc_r, cast_r=0.45):
    """Rays shot in toward an axis (round a torso or a limb). a is the arc
    length on a circle of radius arc_r, starting at `ref`; b runs up the axis."""
    A = Vector(axis).normalized()
    R0 = Vector(ref)
    R0 = (R0 - A * R0.dot(A)).normalized()
    B = Vector(base)

    def ray(a, b):
        radial = Matrix.Rotation(a / arc_r, 3, A) @ R0
        return B + A * b + radial * cast_r, -radial
    return Surface(ray, tree)


def limb_surface(part, tag, ref):
    """A limb's surface: b = metres along it from its upper joint, a = round
    it, starting on the side that `ref` points to."""
    p0, p1 = limb_ends(part, tag)
    r = sum(LIMB_R[part]) * 0.5
    return wrap(p0, p1 - p0, ref, TREES[part + tag], arc_r=r, cast_r=0.25)


CHEST = planar(TORSO_C, TORSO_FWD, (1, 0, 0), TREES["torso"])
TORSO_WRAP = wrap(TORSO_C, TORSO_UP, TORSO_FWD, TREES["torso"], arc_r=0.2)
PELVIS_BACK = planar((0, 0.01, 0.79), (0, 1, 0), (-1, 0, 0), TREES["pelvis"])
HELMET = Ellipsoid(HEAD, HEAD_R)
BACK_OF_HEAD = math.pi * 0.17      # the a value straight behind, on an Ellipsoid

# The runner's chest chevron (PK_Team) sticks up to 2.7 cm out of the chest
# at CHEST a = -0.13..0.13, b = 0.005..0.16 (measured against the real
# model). Chest pieces that cover it are this thick, so they bury it cleanly.
OVER_CHEVRON = 0.036


def leg_surfaces(tag):
    return {
        "thigh_front": limb_surface("thigh", tag, (0, -1, 0)),
        "thigh_back": limb_surface("thigh", tag, (0, 1, 0)),
        "shin_front": limb_surface("shin", tag, (0, -1, 0)),
    }


# ---------------------------------------------------------------------------
# Flat outlines (lists of (a, b) points)
# ---------------------------------------------------------------------------

def ccw(points):
    """Return the outline counter-clockwise (so the plate faces outward)."""
    area = 0.0
    for i in range(len(points)):
        x0, y0 = points[i]
        x1, y1 = points[(i + 1) % len(points)]
        area += x0 * y1 - x1 * y0
    return list(points) if area > 0 else list(reversed(points))


def place(points, cx=0.0, cy=0.0, angle=0.0, sx=1.0, sy=1.0):
    """Scale, turn (degrees) and move an outline."""
    ca, sa = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    out = []
    for x, y in points:
        x, y = x * sx, y * sy
        out.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return ccw(out)


def ellipse(cx, cy, rx, ry=None, n=10, angle=0.0):
    ry = rx if ry is None else ry
    pts = [(rx * math.cos(math.tau * i / n), ry * math.sin(math.tau * i / n)) for i in range(n)]
    return place(pts, cx, cy, angle)


def ribbon(path, hw, n_cap=2):
    """A strip `2*hw` wide following a polyline, with round ends."""
    path = [Vector((p[0], p[1])) for p in path]
    left, right = [], []
    for i, p in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        n = Vector((-t.y, t.x))
        left.append(p + n * hw)
        right.append(p - n * hw)
    pts = list(right)
    t_end = (path[-1] - path[-2]).normalized()
    n_end = Vector((-t_end.y, t_end.x))
    for i in range(1, n_cap + 1):            # end cap: -n -> +n through +t
        ang = -math.pi / 2 + math.pi * i / (n_cap + 1)
        pts.append(path[-1] + (t_end * math.cos(ang) + n_end * math.sin(ang)) * hw)
    pts += list(reversed(left))
    t0 = (path[1] - path[0]).normalized()
    n0 = Vector((-t0.y, t0.x))
    for i in range(1, n_cap + 1):            # start cap: +n -> -n through -t
        ang = math.pi / 2 + math.pi * i / (n_cap + 1)
        pts.append(path[0] + (t0 * math.cos(ang) + n0 * math.sin(ang)) * hw)
    return ccw([(p.x, p.y) for p in pts])


def bone_shape(cx, cy, length, angle, w=0.009, k=0.016, n_arc=3):
    """A cartoon bone: a shaft 2*w wide with two round knobs (radius k) at
    each end. `angle` turns it (0 = lying along a, 90 = along b)."""
    hl = length * 0.5
    yk = k * 0.72
    xe = hl - k
    inner = math.sqrt(max(k * k - (yk - w) ** 2, 1e-8))
    notch = math.sqrt(max(k * k - yk * yk, 1e-8))
    half = []
    a0 = math.atan2(yk - w, -inner)                 # lower knob: shaft -> notch
    a1 = math.atan2(yk, notch) + math.tau
    for i in range(n_arc):
        a = a0 + (a1 - a0) * i / (n_arc - 1)
        half.append((xe + k * math.cos(a), -yk + k * math.sin(a)))
    b0 = math.atan2(-yk, notch)                     # upper knob: notch -> shaft
    b1 = math.atan2(-(yk - w), -inner)
    if b1 < b0:
        b1 += math.tau
    for i in range(1, n_arc):
        a = b0 + (b1 - b0) * i / (n_arc - 1)
        half.append((xe + k * math.cos(a), yk + k * math.sin(a)))
    pts = half + [(-x, -y) for x, y in half]        # the other end is the same, turned round
    return place(pts, cx, cy, angle)


def blob_shape(cx, cy, R, seed, n=12):
    """A rounded, lumpy paint blob."""
    rng = random.Random(seed)
    ph = [rng.uniform(0, math.tau) for _ in range(3)]
    pts = []
    for i in range(n):
        a = math.tau * i / n
        r = R * (0.84 + 0.1 * math.sin(2 * a + ph[0]) + 0.07 * math.sin(3 * a + ph[1])
                 + 0.05 * math.sin(5 * a + ph[2]))
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return ccw(pts)


def drip_shape(cx, cy, w, length, bulb):
    """A paint drip hanging straight down from (cx, cy)."""
    pts = [(-w, 0.0), (-w * 0.8, w * 0.6), (0.0, w * 0.85), (w * 0.8, w * 0.6), (w, 0.0),
           (w * 0.45, -length * 0.45), (w * 0.38, -length + bulb * 0.6)]
    for i in range(1, 6):
        a = -math.pi * i / 6
        pts.append((bulb * math.cos(a), -length + bulb * math.sin(a)))
    pts += [(-w * 0.38, -length + bulb * 0.6), (-w * 0.45, -length * 0.45)]
    return place(pts, cx, cy)


# ---------------------------------------------------------------------------
# Building blocks that fit the body
# ---------------------------------------------------------------------------

def plate(name, outline, surface, thick, material, chamfer=0.0, sink=0.008,
          cut_a=None, cut_b=None):
    """A raised plate: the outline is extruded `thick` metres up from the
    surface (and `sink` into it, so no gap shows at the edge), optionally with
    a 45-degree chamfer round its top, then bent onto the surface. cut_a /
    cut_b slice it every so many metres so it can follow the curve."""
    bm = bmesh.new()
    verts = [bm.verts.new((a, b, -sink)) for a, b in ccw(outline)]
    face = bm.faces.new(verts)
    res = bmesh.ops.extrude_face_region(bm, geom=[face])
    top_verts = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
    top_faces = [g for g in res["geom"] if isinstance(g, bmesh.types.BMFace)]
    bmesh.ops.translate(bm, verts=top_verts, vec=(0, 0, thick - chamfer + sink))
    bm.normal_update()
    if chamfer > 0:
        bmesh.ops.inset_region(bm, faces=top_faces, thickness=chamfer, depth=chamfer,
                               use_even_offset=True)
    # The bottom face is buried in the body - nobody sees it, so drop it.
    bottom = [f for f in bm.faces if all(v.co.z < -sink + 1e-6 for v in f.verts)]
    bmesh.ops.delete(bm, geom=bottom, context="FACES_ONLY")
    for axis, step in ((0, cut_a), (1, cut_b)):
        if not step:
            continue
        lo = min(v.co[axis] for v in bm.verts)
        hi = max(v.co[axis] for v in bm.verts)
        k = math.floor(lo / step) + 1
        while k * step < hi - 1e-4:
            co = [0.0, 0.0, 0.0]
            co[axis] = k * step
            no = [0.0, 0.0, 0.0]
            no[axis] = 1.0
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no)
            k += 1
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    for v in bm.verts:
        v.co = surface(v.co.x, v.co.y, v.co.z)
    return bm_object(name, bm, material)


def limb_shell(name, part, tag, rings, material, segs=10, ref=(0, -1, 0), jag=None,
               tilt=0.0, tilt_dir=0.0):
    """A sleeve or ring spun round one of the runner's limbs.

    rings: (t, extra) pairs - t metres along the limb from its upper joint,
    radius = the limb's own radius there + extra (negative = tucked inside,
    so the open ends never show). jag(i, k, angle) moves vertex k of ring i
    along the limb (torn edges). tilt slants every ring (bandage wraps)."""
    p0, p1 = limb_ends(part, tag)
    A = (p1 - p0).normalized()
    R0 = Vector(ref)
    R0 = (R0 - A * R0.dot(A)).normalized()
    T0 = A.cross(R0)
    bm = bmesh.new()
    grid = []
    for i, (t, extra) in enumerate(rings):
        row = []
        for k in range(segs):
            ang = math.tau * k / segs
            dt = tilt * math.cos(ang - tilt_dir)
            if jag is not None:
                dt += jag(i, k, ang)
            r = limb_radius(part, tag, t + dt) + extra
            radial = R0 * math.cos(ang) + T0 * math.sin(ang)
            row.append(bm.verts.new(p0 + A * (t + dt) + radial * r))
        grid.append(row)
    for i in range(len(rings) - 1):
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((grid[i][k], grid[i][k2], grid[i + 1][k2], grid[i + 1][k]))
    return bm_object(name, bm, material)


def ring_profile(t0, t1, out, tuck=-0.012, bulge=0.0):
    """A chunky ring from t0 to t1 along a limb: tucked-in edges, a flat (or
    slightly bulging) outer face."""
    e = min(0.008, (t1 - t0) * 0.2)
    if bulge:
        return [(t0, tuck), (t0 + e, out), ((t0 + t1) * 0.5, out + bulge), (t1 - e, out),
                (t1, tuck)]
    return [(t0, tuck), (t0 + e, out), (t1 - e, out), (t1, tuck)]


def sweep(name, points, ups, width, thick, material, taper=1.0):
    """A flat ribbon (`width` wide, `thick` thick) along a path of points.
    ups[i] is roughly which way the ribbon's width points at point i."""
    pts = [Vector(p) for p in points]
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        w = Vector(ups[i])
        w = (w - t * w.dot(t)).normalized()
        n = t.cross(w)
        s = 1.0 + (taper - 1.0) * i / (len(pts) - 1)
        hw, ht = width * 0.5 * s, thick * 0.5
        rings.append([bm.verts.new(p + w * hw + n * ht), bm.verts.new(p - w * hw + n * ht),
                      bm.verts.new(p - w * hw - n * ht), bm.verts.new(p + w * hw - n * ht)])
    for i in range(len(rings) - 1):
        for k in range(4):
            k2 = (k + 1) % 4
            bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm_object(name, bm, material)


def sheet(name, grid, keep, thick, material):
    """A thick cloth sheet (a cape) through a grid of points grid[row][col].
    keep(row, col) says which cells exist, so the sheet can have a hole. It is
    `thick` thick and closed all round (both sides and the rim)."""
    rows, cols = len(grid), len(grid[0])

    def normal(j, i):
        dj = grid[min(j + 1, rows - 1)][i] - grid[max(j - 1, 0)][i]
        di = grid[j][min(i + 1, cols - 1)] - grid[j][max(i - 1, 0)]
        n = di.cross(dj)
        return n.normalized() if n.length > 1e-9 else Vector((0, 1, 0))

    cells = [(j, i) for j in range(rows - 1) for i in range(cols - 1) if keep(j, i)]
    used = {(j + dj, i + di) for j, i in cells for dj in (0, 1) for di in (0, 1)}
    bm = bmesh.new()
    outer, inner = {}, {}
    for j, i in used:
        n = normal(j, i)
        outer[(j, i)] = bm.verts.new(grid[j][i] + n * thick * 0.5)
        inner[(j, i)] = bm.verts.new(grid[j][i] - n * thick * 0.5)
    edge_count = {}
    for j, i in cells:
        quad = [(j, i), (j, i + 1), (j + 1, i + 1), (j + 1, i)]
        bm.faces.new([outer[q] for q in quad])
        bm.faces.new([inner[q] for q in reversed(quad)])
        for a, b in zip(quad, quad[1:] + quad[:1]):
            key = tuple(sorted((a, b)))
            edge_count[key] = edge_count.get(key, 0) + 1
    for (a, b), count in edge_count.items():
        if count == 1:      # an edge of the sheet: close it with a rim face
            bm.faces.new((outer[a], outer[b], inner[b], inner[a]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm_object(name, bm, material)


def head_band(name, phi0, phi1, out, material, segs=20, centre=HEAD, radii=HEAD_R,
              tuck=0.006):
    """A band all the way round an ellipsoid head, between two latitudes
    (degrees above the middle of the face)."""
    R = 0.17
    prof = []
    for ph, dz, o in ((phi0, -0.002, -tuck), (phi0, 0.004, out), (phi1, -0.004, out),
                      (phi1, 0.002, -tuck)):
        p = math.radians(ph)
        prof.append(((R + o) * math.cos(p), (R + o) * math.sin(p) + dz))
    obj = pk.lathe(name, prof, loc=tuple(centre), material=material, segments=segs)
    obj.scale = (radii[0] / R, radii[1] / R, radii[2] / R)
    pk.apply(obj, location=False, rotation=True, scale=True)
    return obj


def on_surface(surface, a, b, h=0.0):
    """(point, rotation in degrees) for a primitive standing on a surface,
    its local +Z pointing straight out of it."""
    p, n = surface.frame(a, b)
    return tuple(p + n * h), along(n)


def stitches(surface, a0, b0, a1, b1, count, length=0.04, thick=0.02, name="Stitch"):
    """Short dark bars across a seam running from (a0, b0) to (a1, b1)."""
    out = []
    d = Vector((a1 - a0, b1 - b0))
    n = Vector((-d.y, d.x)).normalized()
    for i in range(count):
        c = Vector((a0, b0)) + d * ((i + 0.5) / count)
        out.append(plate(name, ribbon([tuple(c - n * length * 0.5), tuple(c + n * length * 0.5)],
                                      0.0075, n_cap=1), surface, thick, stitch, sink=0.004))
    return out


# ---------------------------------------------------------------------------
# SKELETON - bone plates on a near-black suit, a skull for a head.
# Team colour: glowing eyes (front), a glowing crack round the back of the
# skull (back).
# ---------------------------------------------------------------------------

def build_skeleton():
    body, head, legs = [], [], {"L": [], "R": []}
    # Collarbones in a V that buries the runner's chest chevron, the sternum
    # below them, and three pairs of ribs arching round the sides.
    for side in (1, -1):
        body.append(plate("SkCollar", bone_shape(side * 0.075, 0.085, 0.215, side * 37.0,
                                                 w=0.025, k=0.026),
                          CHEST, OVER_CHEVRON, bone, cut_a=0.06))
    body.append(plate("SkSternum", ribbon([(0, -0.15), (0, 0.0)], 0.021), CHEST, 0.026, bone,
                      cut_b=0.05))
    for b0 in (-0.025, -0.08, -0.135):
        for side in (1, -1):
            path = []
            for k in range(4):
                u = 0.27 * k / 3
                path.append((side * (0.03 + u), b0 + 0.3 * u - 1.4 * u * u))
            body.append(plate("SkRib", ribbon(path, 0.016, n_cap=1), TORSO_WRAP, 0.022, bone,
                              cut_a=0.08))
    # Tailbone at the back of the pelvis, under the backpack.
    sacrum = [(-0.05, 0.035), (0.05, 0.035), (0.035, -0.025), (0.0, -0.065), (-0.035, -0.025)]
    body.append(plate("SkSacrum", sacrum, PELVIS_BACK, 0.02, bone, cut_b=0.05))
    # Arm bones: one cartoon bone along each upper arm and forearm.
    for tag, side in (("L", LEFT), ("R", RIGHT)):
        up_ref = (side * 1.0, -0.5, 0.3) if tag == "R" else (0.3, -1.0, 0.8)
        L = limb_len("uarm", tag)
        body.append(plate("SkHumerus" + tag, bone_shape(0.0, L * 0.6, L * 0.62, 90),
                          limb_surface("uarm", tag, up_ref), 0.018, bone, cut_b=0.06))
        fore_ref = (-0.6, -1.0, 0.8) if tag == "R" else (0.2, -0.6, 1.0)
        L = limb_len("farm", tag)
        body.append(plate("SkRadius" + tag, bone_shape(0.0, L * 0.38, L * 0.56, 90),
                          limb_surface("farm", tag, fore_ref), 0.018, bone, cut_b=0.06))
    # Leg bones: thigh bone on the front and the back of each leg.
    for tag in ("L", "R"):
        s = leg_surfaces(tag)
        legs[tag].append(plate("SkFemur" + tag, bone_shape(0.0, 0.155, 0.17, 90, w=0.011, k=0.019),
                               s["thigh_front"], 0.02, bone, cut_b=0.06))
        legs[tag].append(plate("SkFemurB" + tag, bone_shape(0.0, 0.19, 0.24, 90, w=0.011, k=0.019),
                               s["thigh_back"], 0.02, bone, cut_b=0.06))

    # The skull, worn instead of the runner's helmet.
    cran_c = Vector((0.0, -0.058, 1.452))
    cran_r = (0.166, 0.168, 0.152)
    skull = Ellipsoid(cran_c, cran_r)
    head.append(pk.sphere("SkCranium", 1.0, loc=tuple(cran_c), scale=cran_r, material=bone,
                          segments=12, rings=8))
    head.append(pk.sphere("SkCheeks", 1.0, loc=(0.0, -0.125, 1.35), scale=(0.125, 0.095, 0.07),
                          material=bone, segments=8, rings=4))
    head.append(pk.box("SkJaw", (0.16, 0.12, 0.055), loc=(0.0, -0.13, 1.287), material=bone,
                       bevel=0.022, segments=1))
    head.append(pk.box("SkMouth", (0.13, 0.04, 0.034), loc=(0.0, -0.18, 1.318),
                       material=socket_dark))
    for x in (-0.045, -0.015, 0.015, 0.045):
        head.append(pk.box("SkTooth", (0.024, 0.03, 0.044), loc=(x, -0.206 + abs(x) * 0.35, 1.316),
                           rot=(0, 0, -x * 6), material=bone))
    for side in (1, -1):
        head.append(plate("SkSocket", ellipse(side * 0.072, -0.01, 0.034, 0.03, n=8,
                                              angle=side * 12), skull, 0.006, socket_dark,
                          sink=0.006))
        head.append(plate("SkEye", ellipse(side * 0.07, -0.014, 0.018, 0.018, n=6), skull, 0.012,
                          team_glow, sink=0.004))
    nose = [(0.0, -0.075), (0.02, -0.05), (0.014, -0.038), (0.0, -0.045), (-0.014, -0.038),
            (-0.02, -0.05)]
    head.append(plate("SkNose", nose, skull, 0.006, socket_dark, sink=0.006))
    a = BACK_OF_HEAD
    crack = [(a - 0.075, 0.12), (a - 0.025, 0.075), (a - 0.06, 0.035), (a + 0.01, -0.005),
             (a - 0.02, -0.045)]
    head.append(plate("SkCrack", ribbon(crack, 0.012, n_cap=1), skull, 0.008, team_glow,
                      sink=0.006))
    head.append(plate("SkCrack", ribbon([(a - 0.045, 0.05), (a + 0.035, 0.07), (a + 0.075, 0.04)],
                                        0.01, n_cap=1), skull, 0.008, team_glow, sink=0.006))
    return body, head, legs


# ---------------------------------------------------------------------------
# SUPERHERO - chest emblem, cape, gold cuffs, domino mask.
# Team colour: the paint drop on the emblem and the mask's eyes (front), the
# cape (back, and peeking out at the sides from the front).
# ---------------------------------------------------------------------------

def build_superhero():
    body, head, legs = [], [], {"L": [], "R": []}
    shield = [(0.0, -0.045), (0.145, 0.065), (0.15, 0.15), (0.125, 0.185), (-0.125, 0.185),
              (-0.15, 0.15), (-0.145, 0.065)]
    body.append(plate("HeroShield", shield, CHEST, OVER_CHEVRON, hero_gold, chamfer=0.008,
                      cut_a=0.07, cut_b=0.07))
    drop = [(0.0, 0.16)]
    for i in range(9):
        a = math.radians(35 - 250 * i / 8)
        drop.append((0.046 * math.cos(a), 0.065 + 0.046 * math.sin(a)))
    body.append(plate("HeroDrop", ccw(drop), CHEST, OVER_CHEVRON + 0.01, team, chamfer=0.006,
                      cut_b=0.06))

    # The cape hangs from the tops of the shoulder pads, round both sides of
    # the backpack, and joins into one piece below it. Columns are x positions
    # (at the top), rows are heights; cells in the backpack's box are left out.
    cols = [-0.37, -0.33, -0.29, -0.17, -0.04, 0.09, 0.22, 0.30, 0.37]
    hole = (2, 6)                 # cells in columns 2..5 make way for the pack
    tops = {0: 1.28, 1: 1.33, 2: 1.345, 6: 1.34, 7: 1.345, 8: 1.28}
    rows = 9
    grid = []
    for j in range(rows):
        v = j / (rows - 1)
        row = []
        for i, x0 in enumerate(cols):
            top = tops.get(i, 1.335)
            hem = 0.5 + (0.04 if i % 2 else 0.0)        # a scalloped hem
            z = top + (hem - top) * v
            x = x0 * (1.0 + 0.25 * v)                   # flares out toward the hem
            # Depth behind the body: on the pad at the top, out past the pad's
            # back by the next row, then swinging out toward the hem.
            y = {0: 0.035, 1: 0.145}.get(j, 0.145 + 0.155 * (1.34 - z) / 0.84)
            y += (0.03 if i % 2 else -0.012) * v        # pleats, deeper at the hem
            if i in (0, len(cols) - 1):
                y -= 0.03 * (1 - v)                     # outer edges wrap forward a little
            row.append(Vector((x, y, z)))
        grid.append(row)

    def keep(j, i):
        z_mid = (grid[j][i].z + grid[j + 1][i].z) * 0.5
        return not (hole[0] <= i < hole[1] and z_mid > PACK_Z[0] - 0.02)
    body.append(sheet("HeroCape", grid, keep, 0.022, team))
    # Gold brooches where the cape meets the front of each shoulder pad.
    for side, tag in ((LEFT, "L"), (RIGHT, "R")):
        pad = planar((side * 0.25, -0.05, 1.3), (0, -0.6, 1.0), (1, 0, 0), TREES["pad" + tag])
        loc, rot = on_surface(pad, 0.0, 0.0, 0.004)
        body.append(pk.cyl("HeroBrooch", 0.034, 0.016, loc=loc, rot=rot, material=hero_gold,
                           verts=10))
    # Gold cuffs over the runner's rubber ones.
    for tag in ("L", "R"):
        L = limb_len("farm", tag)
        rings = [(L - 0.15, -0.012), (L - 0.145, 0.018), (L - 0.07, 0.024), (L - 0.035, 0.034),
                 (L - 0.035, -0.01)]
        body.append(limb_shell("HeroCuff" + tag, "farm", tag, rings, hero_gold, segs=10))

    # Domino mask across the visor, with glowing team eyes.
    mask = [(0.0, 0.045), (-0.05, 0.052), (-0.13, 0.056), (-0.2, 0.062), (-0.25, 0.075),
            (-0.245, 0.02), (-0.215, -0.04), (-0.17, -0.075), (-0.11, -0.088), (-0.05, -0.084),
            (0.0, -0.058), (0.05, -0.084), (0.11, -0.088), (0.17, -0.075), (0.215, -0.04),
            (0.245, 0.02), (0.25, 0.075), (0.2, 0.062), (0.13, 0.056), (0.05, 0.052)]
    head.append(plate("HeroMask", mask, HELMET, 0.03, hero_mask, chamfer=0.006, sink=0.006,
                      cut_a=0.06))
    for side in (1, -1):
        eye = place([(-0.042, -0.004), (-0.02, -0.022), (0.02, -0.024), (0.045, -0.006),
                     (0.03, 0.017), (-0.02, 0.02)], side * 0.085, -0.01, sx=side)
        head.append(plate("HeroEye", eye, HELMET, 0.036, team_glow, sink=0.0, cut_a=0.05))
    return body, head, legs


# ---------------------------------------------------------------------------
# ZOMBIE - torn sleeves over green arms, stitched patches, ooze drips, torn
# trouser cuffs, and a green head under a stitched patchwork cap.
# Team colour: glowing eyes and the big chest patch (front), the back panel
# of the cap and a patch on the back of the right thigh (back).
# ---------------------------------------------------------------------------

def torn(seed, depth):
    """A ragged edge: every other vertex of the last ring hangs further."""
    rng = random.Random(seed)
    teeth = [rng.uniform(0.45, 1.0) * depth for _ in range(32)]

    def jag(i, k, ang):
        if i < 2:
            return 0.0
        return teeth[k] if k % 2 == 0 else teeth[k] * 0.12
    return jag


def build_zombie():
    body, head, legs = [], [], {"L": [], "R": []}
    for tag in ("L", "R"):
        # Green skin over the forearm, from the elbow to the glove cuff.
        L = limb_len("farm", tag)
        body.append(limb_shell("ZSkin" + tag, "farm", tag,
                               [(-0.01, -0.02), (0.0, 0.006), (L - 0.12, 0.006), (L - 0.11, -0.012)],
                               zombie_skin, segs=10))
        # Torn sleeve end on the upper arm, below the team armband.
        U = limb_len("uarm", tag)
        body.append(limb_shell("ZSleeve" + tag, "uarm", tag,
                               [(0.16, -0.012), (0.165, 0.013), (U - 0.045, 0.03)],
                               zombie_rag, segs=10, jag=torn(7 if tag == "L" else 9, 0.06)))
    # A big team-colour patch sewn over the chest (it buries the chevron).
    chest_patch = [(-0.155, -0.005), (0.15, -0.02), (0.16, 0.185), (-0.145, 0.195)]
    body.append(plate("ZPatchChest", chest_patch, CHEST, OVER_CHEVRON, team, cut_a=0.1, cut_b=0.1))
    body += stitches(CHEST, -0.14, 0.205, 0.0, 0.2, 2, thick=OVER_CHEVRON + 0.006)
    body += stitches(CHEST, -0.17, 0.02, -0.16, 0.16, 2, thick=OVER_CHEVRON + 0.006)
    body.append(plate("ZPatchSide", place(rounded_rect(0.05, 0.045, 0.01, 1), -0.12, -0.11,
                                          angle=-12), CHEST, 0.016, zombie_patch, cut_a=0.06))
    body += stitches(CHEST, -0.18, -0.07, -0.08, -0.165, 2)
    body.append(plate("ZDrip", drip_shape(0.135, 0.215, 0.02, 0.1, 0.017), CHEST, 0.042, ooze,
                      cut_b=0.05))
    # Ragged trouser cuffs over the boot tops, a patch on each thigh.
    for tag in ("L", "R"):
        S = limb_len("shin", tag)
        legs[tag].append(limb_shell("ZCuff" + tag, "shin", tag,
                                    [(S - 0.15, -0.012), (S - 0.145, 0.013), (S - 0.1, 0.034)],
                                    zombie_rag, segs=10, jag=torn(3 if tag == "L" else 5, 0.05)))
        s = leg_surfaces(tag)
        if tag == "L":
            legs[tag].append(plate("ZPatchThigh", place(rounded_rect(0.06, 0.055, 0.012, 1), 0.0,
                                                        0.15, angle=-10),
                                   s["thigh_front"], 0.016, zombie_patch2, cut_a=0.05, cut_b=0.06))
            legs[tag] += stitches(s["thigh_front"], -0.065, 0.1, -0.055, 0.21, 2)
        else:
            legs[tag].append(plate("ZPatchBack", place(rounded_rect(0.07, 0.065, 0.012, 1), 0.0,
                                                       0.17, angle=6),
                                   s["thigh_back"], 0.016, team, cut_a=0.05, cut_b=0.06))
            legs[tag] += stitches(s["thigh_back"], -0.072, 0.11, -0.064, 0.23, 2)

    # Head: green skin, mismatched glowing eyes, a stitched mouth...
    face_c = Vector((0.0, -0.062, 1.425))
    face_r = (0.158, 0.16, 0.162)
    face = Ellipsoid(face_c, face_r)
    head.append(pk.sphere("ZFace", 1.0, loc=tuple(face_c), scale=face_r, material=zombie_skin,
                          segments=12, rings=7))
    for side, r in ((1, 0.025), (-1, 0.018)):
        head.append(plate("ZSocket", ellipse(side * 0.066, -0.008, r + 0.012, r + 0.01, n=8), face,
                          0.004, stitch, sink=0.006))
        head.append(plate("ZEye", ellipse(side * 0.066, -0.008, r, r * 0.9, n=8), face, 0.011,
                          team_glow, sink=0.004))
    head.append(plate("ZMouth", ribbon([(-0.065, -0.078), (0.065, -0.072)], 0.008, n_cap=1), face,
                      0.008, stitch, sink=0.004))
    head += stitches(face, -0.06, -0.075, 0.06, -0.075, 3, thick=0.012)
    # ...and a patchwork cap pulled low: three cloth panels sewn together,
    # the back one in the team colour, with a rolled brim.
    R = 0.17
    cap_r = (face_r[0] + 0.012, face_r[1] + 0.012, face_r[2] + 0.012)
    prof = [(math.cos(math.radians(14)) * R - 0.02, math.sin(math.radians(14)) * R - 0.02),
            (math.cos(math.radians(10)) * R + 0.01, math.sin(math.radians(10)) * R - 0.008),
            (math.cos(math.radians(17)) * R + 0.012, math.sin(math.radians(17)) * R + 0.004)]
    for i in range(1, 5):
        ph = math.radians(22 + 68 * i / 4)
        prof.append((math.cos(ph) * R if i < 4 else 0.0, math.sin(ph) * R))
    cap = pk.lathe("ZCap", prof, loc=tuple(face_c), material=zombie_cap, segments=12)
    cap.scale = (cap_r[0] / R, cap_r[1] / R, cap_r[2] / R)
    pk.apply(cap, location=False, rotation=True, scale=True)
    cap.data.materials.append(zombie_patch)
    cap.data.materials.append(team)
    for poly in cap.data.polygons:
        c = poly.center
        theta = math.degrees(math.atan2(c.x, -(c.y - face_c.y)))
        if -15.0 <= theta < 110.0:
            poly.material_index = 1          # front-left panel: mustard
        elif theta >= 110.0 or theta < -140.0:
            poly.material_index = 2          # back panel: team colour
    head.append(cap)
    capsurf = Ellipsoid(face_c, (cap_r[0] + 0.004, cap_r[1] + 0.004, cap_r[2] + 0.004))
    for theta, count in ((-15.0, 2), (110.0, 1), (-140.0, 1)):
        a = math.radians(theta) * R
        head += stitches(capsurf, a, 0.06, a, 0.16, count, length=0.045, thick=0.012)
    head.append(plate("ZDrip", drip_shape(-0.1, 0.05, 0.018, 0.07, 0.014), face, 0.012, ooze,
                      sink=0.006, cut_b=0.05))
    return body, head, legs


# ---------------------------------------------------------------------------
# ASTRONAUT - chest control box, life-support rings, fishbowl dome.
# Team colour: the rings at wrists and ankles, the dome's collar stripe and
# the box's buttons + screen; the glowing visor line inside the dome.
# ---------------------------------------------------------------------------

def build_astronaut():
    body, head, legs = [], [], {"L": [], "R": []}
    # Chest control box, tipped with the torso's lean.
    loc, _rot = on_surface(CHEST, -0.01, 0.085, 0.03)
    body.append(pk.box("AstroBox", (0.285, 0.08, 0.17), loc=loc, rot=(LEAN, 0, 0),
                       material=astro_box, bevel=0.016, segments=2))
    front = Vector(loc) + TORSO_FWD * 0.04

    def on_box(dx, dz, out=0.0):
        return tuple(front + Vector((dx, 0, 0)) + TORSO_UP * dz + TORSO_FWD * out)
    face_rot = (LEAN + 90, 0, 0)
    for dx in (-0.08, -0.01):
        body.append(pk.cyl("AstroDial", 0.03, 0.024, loc=on_box(dx, 0.022, 0.006), rot=face_rot,
                           material=astro_dial, verts=10))
        body.append(pk.box("AstroNeedle", (0.015, 0.01, 0.034), loc=on_box(dx, 0.028, 0.019),
                           rot=(LEAN, 0, 25), material=dark))
    body.append(pk.box("AstroScreen", (0.07, 0.012, 0.05), loc=on_box(0.075, 0.022, 0.003),
                       rot=(LEAN, 0, 0), material=team_glow))
    for dx in (-0.09, -0.045, 0.0, 0.045, 0.09):
        mat = team if dx in (-0.045, 0.045) else dark
        body.append(pk.box("AstroButton", (0.026, 0.016, 0.022), loc=on_box(dx, -0.048, 0.004),
                           rot=(LEAN, 0, 0), material=mat))
    # Life-support rings at the wrists (over the glove cuffs) and ankles.
    for tag in ("L", "R"):
        L = limb_len("farm", tag)
        body.append(limb_shell("AstroWrist" + tag, "farm", tag,
                               ring_profile(L - 0.125, L - 0.05, 0.026, bulge=0.01), team,
                               segs=10))
        S = limb_len("shin", tag)
        legs[tag].append(limb_shell("AstroAnkle" + tag, "shin", tag,
                                    ring_profile(S - 0.15, S - 0.075, 0.028, bulge=0.01), team,
                                    segs=10))

    # Fishbowl dome over a dark face plate with a glowing visor line.
    dome_c = Vector((0.0, -0.088, 1.448))
    Rd = 0.196
    open_r = 0.15
    z0 = -math.sqrt(Rd * Rd - open_r * open_r)
    ph0 = math.asin(z0 / Rd)
    prof = []
    for i in range(9):
        ph = ph0 + (math.pi / 2 - ph0) * i / 8
        prof.append((Rd * math.cos(ph) if i < 8 else 0.0, Rd * math.sin(ph)))
    head.append(pk.lathe("AstroDome", prof, loc=tuple(dome_c), material=glass, segments=18))
    collar_z = dome_c.z + z0
    collar = [(open_r - 0.012, -0.045), (open_r + 0.018, -0.04), (open_r + 0.022, -0.005),
              (open_r + 0.012, 0.012), (open_r - 0.006, 0.014)]
    head.append(pk.lathe("AstroCollar", collar, loc=(0, dome_c.y, collar_z), material=astro_metal,
                         segments=14))
    stripe = [(open_r + 0.017, -0.034), (open_r + 0.027, -0.03), (open_r + 0.027, -0.012),
              (open_r + 0.018, -0.008)]
    head.append(pk.lathe("AstroCollarTeam", stripe, loc=(0, dome_c.y, collar_z), material=team,
                         segments=14))
    face_c = Vector((0.0, -0.08, 1.425))
    face_r = (0.122, 0.118, 0.13)
    head.append(pk.sphere("AstroFace", 1.0, loc=tuple(face_c), scale=face_r, material=dark,
                          segments=10, rings=6))
    inner = Ellipsoid(face_c, face_r, R=0.122)
    head.append(plate("AstroVisorLine", rounded_rect(0.105, 0.016, 0.014, 2), inner, 0.012,
                      team_glow, sink=0.004, cut_a=0.05))
    return body, head, legs


# ---------------------------------------------------------------------------
# NINJA - team sash and headband (tails stream back above the pack), arm and
# shin wraps, face wrap.
# Team colour: headband and sash (front), band knot + tails and sash (back);
# the runner's chevron stays on show.
# ---------------------------------------------------------------------------

def rr_band(name, hx, hy, r, rings, material, centre=(0, 0.004), per_corner=2):
    """A band round the waist: rounded-rectangle rings (z, grow) stacked up,
    then leaned like the runner's torso."""
    bm = bmesh.new()
    grid = []
    for z, grow in rings:
        pts = rounded_rect(hx + grow, hy + grow, r + grow, per_corner)
        grid.append([bm.verts.new((centre[0] + x, centre[1] + y, z)) for x, y in pts])
    n = len(grid[0])
    for i in range(len(grid) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            bm.faces.new((grid[i][k], grid[i][k2], grid[i + 1][k2], grid[i + 1][k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    obj = bm_object(name, bm, material)
    obj.data.transform(LEAN_M)
    return obj


def build_ninja():
    body, head, legs = [], [], {"L": [], "R": []}
    # Team sash (obi) round the waist, over the runner's belt, knotted at the
    # left hip with two tails hanging down outside the leg.
    body.append(rr_band("NinjaSash", 0.2, 0.135, 0.085,
                        [(0.828, -0.03), (0.838, 0.02), (0.912, 0.02), (0.926, -0.03)], team))
    knot = Vector((0.232, -0.035, 0.872))
    body.append(pk.ico("NinjaKnot", 1.0, loc=tuple(knot), scale=(0.032, 0.04, 0.036),
                       material=team, subdiv=1))
    for dy, end_z, sway in ((-0.025, 0.66, 0.015), (0.025, 0.7, -0.02)):
        pts = [knot + Vector((0.004, dy * 0.5, -0.02)), knot + Vector((0.012, dy, -0.09)),
               knot + Vector((0.016 + sway * 0.5, dy * 1.3, -0.16)),
               Vector((knot.x + 0.02 + sway, knot.y + dy * 1.6, end_z))]
        body.append(sweep("NinjaSashTail", pts, [(0, 1, 0)] * 4, 0.045, 0.016, team, taper=0.85))
    # Arm wraps: three slanted bandage bands on each forearm.
    for tag in ("L", "R"):
        for i, t in enumerate((0.03, 0.085, 0.14)):
            rings = [(t, -0.01), (t + 0.006, 0.012), (t + 0.04, 0.012), (t + 0.046, -0.01)]
            body.append(limb_shell("NinjaArmWrap" + tag, "farm", tag, rings, ninja_wrap, segs=8,
                                   tilt=0.012, tilt_dir=i * 1.3))
    # Shin wraps.
    for tag in ("L", "R"):
        for i, t in enumerate((0.1, 0.145)):
            rings = [(t, -0.01), (t + 0.006, 0.012), (t + 0.04, 0.012), (t + 0.046, -0.01)]
            legs[tag].append(limb_shell("NinjaShinWrap" + tag, "shin", tag, rings, ninja_wrap,
                                        segs=10, tilt=0.012, tilt_dir=1.0 + i * 1.7))

    # Headband round the helmet above the visor, a metal plate on the front,
    # a knot at the back whose two long tails stream out behind - high enough
    # to clear the top of the backpack (z 1.41).
    head.append(head_band("NinjaBand", 17.0, 34.0, 0.018, team, segs=20))
    head.append(plate("NinjaPlate", place(rounded_rect(0.068, 0.025, 0.012, 2), 0.0, 0.0755),
                      HELMET, 0.03, ninja_plate, chamfer=0.006, sink=0.0, cut_a=0.05))
    knot_c = HEAD + Vector((0.0, HEAD_R[1] * math.cos(math.radians(25)) + 0.02,
                            HEAD_R[2] * math.sin(math.radians(25))))
    head.append(pk.ico("NinjaBandKnot", 1.0, loc=tuple(knot_c), scale=(0.036, 0.03, 0.032),
                       material=team, subdiv=1))
    for side in (1, -1):
        pts = [knot_c + Vector((side * 0.012, 0.01, -0.005)),
               knot_c + Vector((side * 0.05, 0.09, 0.0)),
               knot_c + Vector((side * 0.09, 0.18, -0.02)),
               knot_c + Vector((side * 0.13, 0.27, -0.01)),
               knot_c + Vector((side * 0.17, 0.36, -0.03))]
        ups = [(side * 0.3, 0, 1), (side * 0.5, 0, 1), (side * 0.8, 0, 1), (side * 1.0, 0, 0.6),
               (side * 1.0, 0, 0.2)]
        head.append(sweep("NinjaTail", pts, ups, 0.05, 0.016, team, taper=0.8))
    # Face wrap over the lower half of the helmet, pointed at the chin, with
    # a fold across it.
    wrap_pts = [(-0.24, -0.074), (-0.24, -0.135), (-0.15, -0.16), (-0.06, -0.175), (0.0, -0.19),
                (0.06, -0.175), (0.15, -0.16), (0.24, -0.135), (0.24, -0.074), (0.12, -0.072),
                (0.0, -0.071), (-0.12, -0.072)]
    head.append(plate("NinjaFaceWrap", wrap_pts, HELMET, 0.018, ninja_cloth, chamfer=0.005,
                      sink=0.006, cut_a=0.06))
    head.append(plate("NinjaFold", ribbon([(-0.2, -0.105), (-0.05, -0.122), (0.08, -0.115),
                                           (0.2, -0.1)], 0.008, n_cap=1),
                      HELMET, 0.024, ninja_cloth, sink=0.0))
    return body, head, legs


# ---------------------------------------------------------------------------
# ROBOT - riveted chest plate, segmented limb plates, boxy head.
# Team colour: glowing eyes, chest core and antenna tip (front), the panel
# on the back of the head, the antenna tip and the thigh rings (back).
# ---------------------------------------------------------------------------

def build_robot():
    body, head, legs = [], [], {"L": [], "R": []}
    chest_outline = place(rounded_rect(0.15, 0.135, 0.035, 2), 0.0, 0.035)
    body.append(plate("RoboChest", chest_outline, CHEST, OVER_CHEVRON, robo_plate, chamfer=0.01,
                      cut_a=0.08, cut_b=0.08))
    for a, b in ((-0.115, 0.14), (0.115, 0.14), (-0.115, -0.07), (0.115, -0.07)):
        loc, _rot = on_surface(CHEST, a, b, OVER_CHEVRON)
        body.append(pk.ico("RoboRivet", 1.0, loc=loc, scale=(0.015, 0.015, 0.015),
                           material=robo_rivet, subdiv=1))
    body.append(plate("RoboCore", ellipse(0.0, 0.09, 0.038, n=10), CHEST, OVER_CHEVRON + 0.012,
                      team_glow))
    for b in (-0.005, -0.04):
        body.append(plate("RoboVent", place(rounded_rect(0.07, 0.009, 0.008, 1), 0.0, b), CHEST,
                          OVER_CHEVRON + 0.008, robo_screen))
    # Segmented plates: octagonal rings round the limbs (the thigh ones carry
    # the team colour so the legs read from behind).
    for tag in ("L", "R"):
        U = limb_len("uarm", tag)
        body.append(limb_shell("RoboUpper" + tag, "uarm", tag, ring_profile(0.16, U - 0.02, 0.022),
                               robo_plate, segs=8))
        for t0, t1 in ((0.01, 0.085), (0.095, 0.17)):
            body.append(limb_shell("RoboFore" + tag, "farm", tag, ring_profile(t0, t1, 0.02),
                                   robo_plate, segs=8))
        legs[tag].append(limb_shell("RoboThigh" + tag, "thigh", tag,
                                    ring_profile(0.08, 0.16, 0.022), robo_plate, segs=8))
        legs[tag].append(limb_shell("RoboThighTeam" + tag, "thigh", tag,
                                    ring_profile(0.17, 0.235, 0.022), team, segs=8))
        legs[tag].append(limb_shell("RoboShin" + tag, "shin", tag, ring_profile(0.095, 0.175, 0.02),
                                    robo_plate, segs=8))

    # Boxy head: dark screen face, two glowing round eyes, antenna, ear bolts.
    hc = Vector((0.0, -0.065, 1.445))
    head.append(pk.box("RoboHead", (0.32, 0.29, 0.28), loc=tuple(hc), material=robo_plate,
                       bevel=0.04, segments=2))
    fy = hc.y - 0.145
    head.append(pk.box("RoboFace", (0.25, 0.02, 0.15), loc=(0.0, fy, hc.z + 0.01),
                       material=robo_screen, bevel=0.012, segments=1))
    for side in (1, -1):
        head.append(pk.cyl("RoboEye", 0.034, 0.02, loc=(side * 0.062, fy - 0.009, hc.z + 0.025),
                           rot=(90, 0, 0), material=team_glow, verts=12))
        head.append(pk.cyl("RoboEar", 0.042, 0.03, loc=(side * 0.165, hc.y, hc.z),
                           rot=(0, 90, 0), material=robo_rivet, verts=10))
    head.append(pk.box("RoboMouth", (0.11, 0.012, 0.018), loc=(0.0, fy - 0.008, hc.z - 0.04),
                       material=robo_rivet))
    head.append(pk.cyl("RoboAntenna", 0.009, 0.1, loc=(0.045, hc.y + 0.02, hc.z + 0.185),
                       rot=(0, 8, 0), material=robo_rivet, verts=6))
    head.append(pk.ico("RoboAntennaTip", 0.026, loc=(0.052, hc.y + 0.02, hc.z + 0.24),
                       material=team_glow, subdiv=1))
    head.append(pk.box("RoboBackPanel", (0.2, 0.016, 0.075), loc=(0.0, hc.y + 0.146, hc.z + 0.055),
                       material=team))
    return body, head, legs


# ---------------------------------------------------------------------------
# PAINTBALL_SPLATTER - big raised splats in several colours, chunky goggles.
# Team colour: the biggest splats front and back, the goggle strap.
# ---------------------------------------------------------------------------

def build_paintball():
    body, head, legs = [], [], {"L": [], "R": []}
    colours = {"T": team, "O": splat_orange, "Y": splat_yellow, "V": splat_violet,
               "G": splat_green}

    def splat(parts, surf, a, b, R, col, seed, thick=0.018, streaks=2, drops=1):
        """A splat: a lumpy blob, streaks flung out of it, a stray droplet.
        Streaks are a touch lower than the blob so the two never flicker
        where they overlap."""
        rng = random.Random(seed)
        mat = colours[col]
        parts.append(plate("Splat", blob_shape(a, b, R, seed, n=12 if R > 0.07 else 10), surf,
                           thick, mat, cut_a=0.08, cut_b=0.08))
        start = rng.uniform(0, math.tau)
        for i in range(streaks):
            ang = start + math.tau * (i + rng.uniform(-0.15, 0.15)) / max(streaks, 1)
            d = R * rng.uniform(0.95, 1.1)
            length = R * rng.uniform(0.45, 0.65)
            parts.append(plate("SplatStreak", ellipse(a + d * math.cos(ang), b + d * math.sin(ang),
                                                      length, max(R * 0.2, 0.01), n=6,
                                                      angle=math.degrees(ang)),
                               surf, thick * 0.75, mat))
        for i in range(drops):
            ang = start + math.pi / max(streaks, 1) + rng.uniform(-0.3, 0.3) + i * 2.2
            d = R * rng.uniform(1.55, 1.75)
            parts.append(plate("SplatDrop", ellipse(a + d * math.cos(ang), b + d * math.sin(ang),
                                                    max(R * 0.16, 0.009), n=6),
                               surf, thick * 0.75, mat))

    splat(body, CHEST, 0.0, 0.085, 0.13, "T", 1, thick=OVER_CHEVRON)
    splat(body, CHEST, -0.12, -0.11, 0.07, "O", 2, streaks=1)
    splat(body, TORSO_WRAP, -0.31, 0.03, 0.085, "Y", 3)
    splat(body, TORSO_WRAP, 0.33, -0.05, 0.08, "V", 4, streaks=1)
    splat(body, PELVIS_BACK, 0.03, 0.0, 0.075, "T", 5, streaks=1, drops=0)
    splat(body, limb_surface("uarm", "R", (RIGHT, -0.4, 0.4)), 0.0, 0.2, 0.055, "V", 7,
          streaks=1, drops=0)
    splat(body, limb_surface("farm", "L", (0.2, -0.6, 1.0)), 0.0, 0.1, 0.055, "Y", 8, streaks=1,
          drops=0)
    for tag, cols in (("L", ("G", "T")), ("R", ("O", "T"))):
        s = leg_surfaces(tag)
        splat(legs[tag], s["thigh_front"], 0.01, 0.17, 0.068, cols[0], 10 + ord(tag), streaks=1)
        splat(legs[tag], s["thigh_back"], -0.01, 0.15, 0.078, cols[1], 20 + ord(tag), streaks=2,
              drops=0)

    # Chunky goggles over the visor; the strap round the helmet is team colour.
    head.append(head_band("GoggleStrap", -16.0, 2.0, 0.02, team, segs=16))
    for side in (1, -1):
        p, n = HELMET.frame(side * 0.075, -0.012)
        centre = p + n * 0.016
        rot = along(n)
        rim = [(0.042, -0.02), (0.06, -0.012), (0.058, 0.026), (0.04, 0.026)]
        head.append(pk.lathe("GoggleRim", rim, loc=tuple(centre), rot=rot, material=goggle_frame,
                             segments=12))
        head.append(pk.cyl("GoggleLens", 0.044, 0.01, loc=tuple(centre + n * 0.016), rot=rot,
                           material=goggle_lens, verts=12))
    p, n = HELMET.frame(0.0, -0.012)
    head.append(pk.box("GoggleBridge", (0.05, 0.03, 0.025), loc=tuple(p + n * 0.025),
                       material=goggle_frame))
    return body, head, legs


BUILDERS = {
    "SKELETON": build_skeleton,
    "SUPERHERO": build_superhero,
    "ZOMBIE": build_zombie,
    "ASTRONAUT": build_astronaut,
    "NINJA": build_ninja,
    "ROBOT": build_robot,
    "PAINTBALL_SPLATTER": build_paintball,
}


# ---------------------------------------------------------------------------
# Assemble: one empty per outfit, joined meshes under it, leg pieces under
# OnLeg_L / OnLeg_R at the runner's hip pivots.
# ---------------------------------------------------------------------------

root = pk.empty("OutfitsA")
built = {}
for outfit_id, builder in BUILDERS.items():
    body_parts, head_parts, leg_parts = builder()
    holder = pk.empty("Outfit_" + outfit_id, parent_obj=root)
    meshes = []
    body = world_join(outfit_id + "_Body", body_parts)
    pk.parent(body, holder)
    meshes.append(body)
    if head_parts:
        head = world_join(outfit_id + "_Head", head_parts)
        pk.parent(head, holder)
        meshes.append(head)
    for tag in ("L", "R"):
        if not leg_parts[tag]:
            continue
        pivot = pk.empty("OnLeg_" + tag, loc=tuple(LEG_PIVOT[tag]), parent_obj=holder)
        leg = world_join(outfit_id + "_Leg" + tag, leg_parts[tag])
        pk.set_origin(leg, tuple(LEG_PIVOT[tag]))     # origin on the hip, like the runner's leg
        pk.parent(leg, pivot)
        meshes.append(leg)
    built[outfit_id] = (holder, meshes)

pk.smooth_all(35.0)

# Budget per outfit (the export then checks the total).
over = []
for outfit_id, (holder, meshes) in built.items():
    total, per = pk.triangle_count(meshes)
    print("[outfits] %-20s %5d triangles  %s" % (outfit_id, total,
                                                 ", ".join("%s %d" % kv for kv in per.items())))
    if total > BUDGET_EACH:
        over.append(outfit_id)
if over and not DRAFT:
    print("[outfits] ERROR: over the %d-triangle budget: %s" % (BUDGET_EACH, ", ".join(over)))
    sys.exit(1)

out_path = pk.export("cosmetic_outfits_a.glb", budget=99999 if DRAFT else 9100)


def fix_leg_names(path):
    """Blender had to call the extra leg empties 'OnLeg_L.001' etc.; give them
    their real name back inside the .glb (a JSON chunk, then a binary one)."""
    with open(path, "rb") as f:
        data = f.read()
    magic, version, _length = struct.unpack_from("<4sII", data, 0)
    json_len, json_type = struct.unpack_from("<I4s", data, 12)
    doc = json.loads(data[20:20 + json_len].decode("utf-8"))
    rest = data[20 + json_len:]
    renamed = 0
    for node in doc.get("nodes", []):
        name = node.get("name", "")
        for base in ("OnLeg_L", "OnLeg_R"):
            if name.startswith(base + "."):
                node["name"] = base
                renamed += 1
    text = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    text += b" " * ((4 - len(text) % 4) % 4)
    out = struct.pack("<I4s", len(text), json_type) + text + rest
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", magic, version, 12 + len(out)) + out)
    print("[outfits] renamed %d leg empties back to OnLeg_L / OnLeg_R" % renamed)


fix_leg_names(out_path)

for holder, meshes in built.values():
    print("[outfits] %s at %s" % (holder.name,
                                  tuple(round(v, 3) for v in holder.matrix_world.translation)))
    for child in holder.children:
        print("[outfits]    %s (%s) at %s" % (child.name, child.type,
                                              tuple(round(v, 3) for v in child.matrix_world.translation)))
        for sub in child.children:
            print("[outfits]       %s (%s) local %s" % (sub.name, sub.type,
                                                        tuple(round(v, 3) for v in sub.location)))


# ---------------------------------------------------------------------------
# Optional: render each outfit on the runner (never exported - the runner and
# backpack are imported only after the export above).
# ---------------------------------------------------------------------------

def outfit_previews(folder):
    os.makedirs(folder, exist_ok=True)
    scene = bpy.context.scene
    ref = bpy.data.collections.new("PreviewRunner")
    pk._collection.children.link(ref)
    layer = bpy.context.view_layer.layer_collection.children[pk._collection.name].children[ref.name]
    bpy.context.view_layer.active_layer_collection = layer
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=RUNNER_GLB)
    runner = set(bpy.data.objects) - before
    bpy.ops.import_scene.gltf(filepath=PACK_GLB)
    pack_root = bpy.data.objects.get("ChromaticReservoir")
    if pack_root is not None:
        pack_root.location = (0.0, 0.102, 1.12)
    runner_head = [o for o in runner if o.name.startswith("Head")]

    # Invisible boxes that pk.preview frames on, for the close-ups.
    framers = {}
    for tag, loc, scale in (("_upper", (0, -0.05, 1.25), (0.5, 0.5, 0.42)),
                            ("_head", (0, -0.03, 1.43), (0.3, 0.3, 0.26))):
        coll = bpy.data.collections.new("PreviewFrame" + tag)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        cube = bpy.context.active_object
        cube.matrix_world = Matrix.LocRotScale(Vector(loc), None, Vector(scale))
        cube.hide_render = True
        for c in list(cube.users_collection):
            c.objects.unlink(cube)
        coll.objects.link(cube)
        framers[tag] = coll

    def recolour(names, hex_colour, glow=False):
        for m in bpy.data.materials:
            if m.name.split(".")[0] not in names or not m.use_nodes:
                continue
            bsdf = m.node_tree.nodes.get("Principled BSDF")
            if bsdf is None:
                continue
            bsdf.inputs["Base Color"].default_value = pk.linear(hex_colour)
            if glow:
                bsdf.inputs["Emission Color"].default_value = pk.linear(hex_colour)

    team_cols = ["#E8434B", "#3A7BEA"]
    for idx, (outfit_id, spec) in enumerate(OUTFITS.items()):
        for other_id, (_h, other_meshes) in built.items():
            for m in other_meshes:
                m.hide_render = other_id != outfit_id
        for o in runner_head:
            o.hide_render = spec["hide_head"]
        recolour({"PK_Canvas"}, spec["suit"])
        recolour({"PK_Body"}, spec["helmet"])
        col = team_cols[idx % 2]
        recolour({"PK_Team"}, col)
        recolour({"PK_TeamGlow"}, col, glow=True)
        for tag, coll in (("", None), ("_upper", framers["_upper"]), ("_head", framers["_head"])):
            saved = pk._collection
            if coll is not None:
                pk._collection = coll
            pk.preview(os.path.join(folder, "%s%s.png" % (outfit_id.lower(), tag)), size=440)
            pk._collection = saved
            for o in list(scene.objects):
                if o.name.startswith(("PreviewSun", "PreviewCam")):
                    bpy.data.objects.remove(o, do_unlink=True)


if "--outfit-previews" in _ARGV:
    outfit_previews(_ARGV[_ARGV.index("--outfit-previews") + 1])
