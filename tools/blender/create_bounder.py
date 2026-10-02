"""
Bounder - the mint melee rusher (Light Step / Brittle Canvas).

Plan: docs/VISUAL_OVERHAUL_PLAN.md section 4.5.

A house-painter's roller turned brawler: low, wide and bottom-heavy. Two big
coil-spring legs in short piston sleeves, a compact forward-hunched shell with
a small head bump and twin glowing eyes, and two oversized paint-roller fists
dripping mint paint. No gun - it reads as "it will jump at you".

Axes: the enemy FACES BLENDER -Y (the exporter turns that into Godot +Z, the
direction enemy.gd turns toward the player). X is the enemy's left, Z is up.
The origin is on the floor, centred under the body (the capsule's base).
Size: 1.40 m tall, 1.0 m wide at the rollers - the r 0.45 / h 1.40 capsule.

Nodes Godot relies on (names must not change):
    Bounder    root empty at the origin.
    Spring_L   left leg (+X): coil spring, piston sleeves and foot as one mesh.
    Spring_R   right leg (-X). ORIGIN AT THE TOP where each meets the hips and
               no rotation, so scaling local Y in Godot (Blender Z) squashes
               the leg up toward the body.
    Arm_L      left arm (+X), ORIGIN AT THE SHOULDER, no rotation, so a
    Arm_R      rotation around local X swings the roller fist forward.
    Roller_L   the roller drum, a CHILD of its arm. ORIGIN ON THE ROLLER AXIS
    Roller_R   centre, no rotation: spinning around local X rolls it.

Material roles Godot recolours: PK_Accent (shell panels, roller covers),
PK_AccentGlow (eyes), PK_Wet (drips).

Run:  blender -b --factory-startup --python tools/blender/create_bounder.py
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

COLLECTION = pk.begin("Bounder", seed=55)

MINT = "#98FF98"
shell = pk.mat("PK_Shell", name="PK_ShellSage", color="#DCE6DE", roughness=0.7)
trim = pk.mat("PK_Trim")
metal = pk.mat("PK_Metal")
rubber = pk.mat("PK_Rubber")
dark = pk.mat("PK_Dark")
accent = pk.mat("PK_Accent", color=MINT)
glow = pk.mat("PK_AccentGlow", color=MINT)
wet = pk.mat("PK_Wet", color=MINT)

root = pk.empty("Bounder")


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


def paint(obj, material, test):
    """Give the faces whose centre (object space) passes test() a second
    material, so a panel costs no extra triangles."""
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


def transform(obj, matrix):
    """Move/turn/squash an object by a world matrix and bake it into the mesh
    (leaves the object with no rotation and no scale)."""
    bpy.context.view_layer.update()
    obj.matrix_world = matrix @ obj.matrix_world
    pk.apply(obj, location=False, rotation=True, scale=True)
    return obj


# ---------------------------------------------------------------------------
# Springs: coil + piston sleeves + foot. Origin at the top, under the hips.
# ---------------------------------------------------------------------------

LEG_X = 0.20              # spring tops, under the hips
SPLAY_DEG = 7.0           # springs lean out into a wide, planted A-stance
LEG_Y = 0.05
HIP_Z = 0.72             # top of each spring, where it meets the hip block
COIL_R = 0.104           # centre line of the coil wire
WIRE_R = 0.026
COIL_Z0, COIL_Z1 = 0.09, 0.66
# A NURBS path through 6 points per turn cuts inside them; 1.2 x brings the
# finished coil back out to COIL_R.
NURBS_OUT = 1.2

for side, suffix in ((1, "L"), (-1, "R")):
    x = LEG_X * side
    coil = pk.tube("Coil", [(px + x, py + LEG_Y, pz) for px, py, pz in
                            pk.helix(COIL_R * NURBS_OUT, COIL_Z1 - COIL_Z0, 5,
                                     points_per_turn=6, z0=COIL_Z0)],
                   WIRE_R, material=metal, resolution=0, path_resolution=1)
    soft(coil, 100)
    # Upper piston sleeve, hanging from the hips.
    sleeve = pk.lathe("Sleeve", [
        (0.112, HIP_Z - 0.16), (0.152, HIP_Z - 0.148), (0.160, HIP_Z - 0.122),
        (0.160, HIP_Z)],
        loc=(x, LEG_Y, 0), material=trim, segments=10)
    soft(sleeve, 40)
    # Lean the spring outward around its top, then put the foot flat on the
    # floor under the coil's new bottom end.
    pivot = Vector((x, LEG_Y, HIP_Z))
    lean = (Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(-SPLAY_DEG * side), 4, "Y")
            @ Matrix.Translation(-pivot))
    for part in (coil, sleeve):
        transform(part, lean)
    foot_x = (lean @ Vector((x, LEG_Y, COIL_Z0))).x
    # Foot: a flat rubber pad (longer front-to-back) with a short lower
    # sleeve that holds the bottom of the coil.
    foot = pk.lathe("Foot", [
        (0.158, 0.000), (0.176, 0.038), (0.140, 0.082), (0.128, 0.150), (0.106, 0.158)],
        loc=(0, 0, 0), material=rubber, segments=10)
    soft(foot, 45)
    paint(foot, trim, lambda c: c.z > 0.08)
    transform(foot, Matrix.Translation((foot_x, LEG_Y - 0.035, 0)) @ Matrix.Diagonal((1.0, 1.3, 1.0, 1.0)))
    spring = build("Spring_" + suffix, [sleeve, coil, foot])
    pk.apply(spring, location=False, rotation=True, scale=True)
    pk.set_origin(spring, pivot)
    pk.parent(spring, root)

# ---------------------------------------------------------------------------
# Body: hip block, hunched torso shell, head bump with twin eyes
# ---------------------------------------------------------------------------

body_parts = []
body_parts.append(pk.box("Hips", (0.62, 0.30, 0.14), loc=(0, LEG_Y, HIP_Z + 0.035),
                         material=trim, bevel=0.045, segments=1))

# The torso is a lathed egg, squashed front-to-back, then tipped forward
# around its base so the back hunches over the hips.
TORSO_BASE = Vector((0.0, 0.08, 0.72))
HUNCH_DEG = 28.0
TORSO_SHAPE = (Matrix.Translation(TORSO_BASE) @ Matrix.Rotation(math.radians(HUNCH_DEG), 4, "X")
               @ Matrix.Diagonal((1.0, 0.84, 1.0, 1.0)))
torso = pk.lathe("Torso", [
    (0.000, 0.000), (0.200, 0.022), (0.300, 0.118), (0.332, 0.250), (0.326, 0.380),
    (0.290, 0.500), (0.220, 0.606), (0.118, 0.680), (0.000, 0.704)],
    loc=(0, 0, 0), material=shell, segments=16)


def _angle(c):
    return math.degrees(math.atan2(c.y, c.x))   # -90 = front, +90 = back


# Mint panels: a big plate over the hunched back and a chest plate under the
# head. Painted onto the shell's own faces, so they cost no triangles.
paint(torso, accent, lambda c: (abs(_angle(c) - 90) < 55 and 0.09 < c.z < 0.64)
      or (abs(_angle(c) + 90) < 40 and 0.11 < c.z < 0.42))
transform(torso, TORSO_SHAPE)
body_parts.append(torso)

# Head bump: a small dome pushed out of the front-top of the shell.
HEAD = TORSO_SHAPE @ Vector((0.0, -0.13, 0.636))
head = pk.lathe("Head", [
    (0.122, -0.040), (0.152, 0.025), (0.140, 0.105), (0.080, 0.155), (0.000, 0.168)],
    loc=HEAD, material=shell, segments=12)
soft(head, 50)
# A dark visor band round the front of the head, for the eyes to sit in.
paint(head, dark, lambda c: abs(_angle(c) + 90) < 70 and 0.03 < c.z < 0.1)
transform(head, Matrix.Translation(HEAD) @ Matrix.Rotation(math.radians(HUNCH_DEG * 0.5), 4, "X")
          @ Matrix.Translation(-HEAD))
body_parts.append(head)

# Twin eye lights in the visor band.
for side in (1, -1):
    eye = pk.sphere("Eye", 0.034, loc=(0.058 * side, -0.138, 0.066), scale=(1.0, 0.55, 1.0),
                    material=glow, segments=6, rings=3)
    soft(eye, 60)
    transform(eye, Matrix.Translation(HEAD) @ Matrix.Rotation(math.radians(HUNCH_DEG * 0.5), 4, "X"))
    body_parts.append(eye)

body = build("Body", body_parts)
pk.apply(body, location=False, rotation=True, scale=True)
pk.parent(body, root)

# ---------------------------------------------------------------------------
# Arms: shoulder pad, upper arm, elbow, forearm, wrist, yoke; roller drum
# The rollers are held forward at hip height, so the springs still show
# under them from the front.
# ---------------------------------------------------------------------------

SHOULDER = Vector((0.35, 0.0, 1.10))
ELBOW = Vector((0.43, 0.03, 0.82))
WRIST = Vector((0.315, -0.22, 0.68))
ROLLER = Vector((0.315, -0.27, 0.44))     # drum axis centre
DRUM_R = 0.12
DRUM_HALF = 0.15
YOKE_Z = ROLLER.z + DRUM_R + 0.05
YOKE_X = DRUM_HALF + 0.012

for side, suffix in ((1, "L"), (-1, "R")):
    def m(v):
        return Vector((v.x * side, v.y, v.z))
    s, e, w, c = m(SHOULDER), m(ELBOW), m(WRIST), m(ROLLER)
    parts = [
        soft(pk.sphere("Pad", 0.112, loc=s + Vector((0.01 * side, 0, 0.022)), scale=(1.0, 1.1, 0.8),
                       material=accent, segments=10, rings=5), 50),
        limb("UpperArm", s, e, 0.066, 0.056, verts=8, material=trim),
        soft(pk.sphere("Elbow", 0.066, loc=e, material=metal, segments=8, rings=4), 60),
        limb("Forearm", e, w, 0.058, 0.05, verts=8, material=trim),
        soft(pk.sphere("Wrist", 0.062, loc=w, scale=(1.0, 1.0, 0.85), material=shell, segments=8,
                       rings=4), 60),
        # Handle from the wrist down to the yoke's cross bar.
        limb("Handle", w, (c.x, c.y, YOKE_Z), 0.03, 0.03, verts=6, material=metal),
        # U-shaped yoke holding both ends of the drum.
        soft(pk.tube("Yoke", [(c.x - YOKE_X, c.y, c.z), (c.x - YOKE_X, c.y, YOKE_Z),
                              (c.x + YOKE_X, c.y, YOKE_Z), (c.x + YOKE_X, c.y, c.z)],
                     0.021, material=metal, resolution=1, smooth_path=False), 65),
    ]
    # Wet mint paint hanging under the drum (on the arm, so it never spins).
    for i, (dx, length) in enumerate(((-0.075, 0.11), (0.055, 0.08))):
        parts.append(drip("Drip%d" % i, (c.x + dx * side, c.y + 0.01, c.z - DRUM_R + 0.014),
                          length, 0.042, wet))
    arm = build("Arm_" + suffix, parts)
    pk.apply(arm, location=False, rotation=True, scale=True)
    pk.set_origin(arm, s)
    pk.parent(arm, root)

    # The drum: a lathe along X (rot (0, 90, 0) turns local Z to +X), mint
    # cover with metal end caps.
    drum = pk.lathe("Roller_" + suffix, [
        (0.000, -DRUM_HALF), (0.085, -DRUM_HALF), (DRUM_R, -DRUM_HALF + 0.03),
        (DRUM_R, DRUM_HALF - 0.03), (0.085, DRUM_HALF), (0.000, DRUM_HALF)],
        loc=c, rot=(0, 90, 0), material=accent, segments=12)
    paint(drum, metal, lambda v: abs(v.z) > DRUM_HALF - 0.005)
    pk.apply(drum, location=False, rotation=True, scale=True)
    pk.set_origin(drum, c)
    pk.parent(drum, arm)

shade_rest()

# Report the finished size and the animated nodes.
bpy.context.view_layer.update()
lo = Vector((1e9, 1e9, 1e9))
hi = Vector((-1e9, -1e9, -1e9))
for obj in pk.objects():
    if obj.type == "MESH":
        for v in obj.data.vertices:
            wv = obj.matrix_world @ v.co
            lo = Vector(map(min, lo, wv))
            hi = Vector(map(max, hi, wv))
print("[bounder] bounds x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % (lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
for obj in pk.objects():
    if obj.name in ("Bounder", "Spring_L", "Spring_R", "Arm_L", "Arm_R", "Roller_L", "Roller_R"):
        print("[bounder] node %-9s parent=%-8s world=(%.3f, %.3f, %.3f) local=(%.3f, %.3f, %.3f) rot=(%.1f, %.1f, %.1f) scale=(%.2f, %.2f, %.2f)" % (
            obj.name, obj.parent.name if obj.parent else "-", *obj.matrix_world.translation,
            *obj.matrix_local.translation, *(math.degrees(a) for a in obj.rotation_euler), *obj.scale))

pk.export("enemy_bounder.glb", budget=2000)
