"""
Prism Beam - the energy weapon.

An old magic-lantern projector turned into a ray gun: a chunky rounded lamp
housing, a stack of round cooling fins at the back, a little lantern chimney
on top, a glass energy cell strapped to the left side, a brass coil wound
round the lens barrel, and at the front a triangular glass-like PRISM, the
kind that splits light into a rainbow. Here it splits paint.

Axes: the gun points down BLENDER +Y (which the exporter turns into Godot -Z,
the camera's forward). X is right, Z is up. The object origin is the
view-model centre, the same spot as on the Paint Blaster: the housing sits
there and the grip hangs below it.

Nodes Godot relies on (names must not change):
    Muzzle     the prism; its ORIGIN is the prism's front point, (0, 0.354, 0)
               in Blender = (0, 0, -0.354) in Godot. Shots leave from here.
               Material PK_Accent (pair colour).
    Fill       charge inside the glass cell on the left side; origin at the
               cell's back end so Godot can shorten it as the charge drains.
               Material PK_Fill.
    SkinBand   the menu's gun-skin colour band around the housing. Material
               PK_Skin.
    PaintDrips paint dripping off the prism, in the pair colour (PK_Wet).

Run:  blender -b --factory-startup --python tools/blender/create_weapon_prism_beam.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("PrismBeam", seed=31)

body = pk.mat("PK_Body")
trim = pk.mat("PK_Trim")
brass = pk.mat("PK_Brass")
rubber = pk.mat("PK_Rubber")
glass = pk.mat("PK_Glass")
accent = pk.mat("PK_Accent")
glow = pk.mat("PK_AccentGlow")
fill = pk.mat("PK_Fill")
wet = pk.mat("PK_Wet")
skin = pk.mat("PK_Team", name="PK_Skin", color="#63D9C7")

root = pk.empty("PrismBeam")

# A lathe spins around local Z; rot (-90, 0, 0) turns local Z to face +Y, so
# every lathed part below runs along the gun's length.
ALONG_Y = (-90, 0, 0)


def rounded_rect(width, height, radius, steps=4):
    """Outline of a rectangle with rounded corners, as (x, y) points going
    counter-clockwise - the shape pk.prism() extrudes. Used for the housing
    and the skin band so the band hugs the housing's corners exactly."""
    hw, hh = width * 0.5 - radius, height * 0.5 - radius
    points = []
    for cx, cy, start in ((hw, -hh, -90), (hw, hh, 0), (-hw, hh, 90), (-hw, -hh, 180)):
        for i in range(steps + 1):
            a = math.radians(start + 90.0 * i / steps)
            points.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    return points


# rot (-90, 0, 0) on a prism stands its outline up in the X-Z plane (facing
# forward) and points its extrusion along +Y, the gun's length.
FACING_Y = (-90, 0, 0)
BODY_Z = 0.0   # the housing, heat sink and lens barrel all share this axis

# --- Lamp housing: a chunky box with soft rounded corners --------------------
pk.prism("Housing", rounded_rect(0.116, 0.116, 0.026), 0.24, loc=(0, 0.02, BODY_Z),
         rot=FACING_Y, material=body, bevel=0.008, segments=2, parent_obj=root)
pk.prism("SkinBand", rounded_rect(0.121, 0.121, 0.0285), 0.034, loc=(0, 0.112, BODY_Z),
         rot=FACING_Y, material=skin, parent_obj=root)

# --- Heat sink at the back: a dark core with a stack of round ceramic fins ----
pk.cyl("HeatCore", 0.036, 0.125, loc=(0, -0.155, BODY_Z), rot=(90, 0, 0), material=trim,
       verts=16, parent_obj=root)
for i in range(5):
    pk.cyl("Fin%d" % i, 0.055, 0.007, loc=(0, -0.112 - 0.022 * i, BODY_Z), rot=(90, 0, 0),
           material=body, verts=20, parent_obj=root)
pk.lathe("BackCap", [
    (0.036, -0.217), (0.033, -0.227), (0.023, -0.235), (0.000, -0.238)],
    loc=(0, 0, BODY_Z), rot=ALONG_Y, material=trim, segments=16, parent_obj=root)
pk.cyl("PowerKnob", 0.013, 0.016, loc=(0, -0.244, BODY_Z), rot=(90, 0, 0), material=brass,
       verts=10, bevel=0.003, segments=1, parent_obj=root)

# --- Lantern chimney on top, where an old projector let its lamp's heat out ---
pk.lathe("Chimney", [
    (0.000, 0.050), (0.021, 0.050), (0.021, 0.092), (0.032, 0.096),
    (0.034, 0.104), (0.020, 0.116), (0.006, 0.120), (0.000, 0.120)],
    loc=(0, -0.025, BODY_Z), material=trim, segments=16, parent_obj=root)
pk.torus("ChimneyRing", 0.0225, 0.004, loc=(0, -0.025, BODY_Z + 0.066), material=brass,
         segments=16, ring_segments=3, parent_obj=root)

# --- Lens barrel, energy coil and bezel at the front -------------------------
pk.lathe("LensBarrel", [
    (0.000, 0.130), (0.041, 0.130), (0.042, 0.148), (0.045, 0.226),
    (0.000, 0.228)], rot=ALONG_Y, material=trim, segments=18, parent_obj=root)
# A brass wire wound round the barrel like a coil. It starts on the left side,
# where the conduit from the energy cell plugs into it.
COIL_R, COIL_Y0, COIL_LEN, TURNS = 0.0495, 0.150, 0.066, 3.5
coil = []
count = int(TURNS * 12) + 1
for i in range(count):
    t = i / (count - 1)
    a = math.tau * TURNS * t
    coil.append((-COIL_R * math.cos(a), COIL_Y0 + COIL_LEN * t, COIL_R * math.sin(a)))
pk.tube("Coil", coil, 0.0042, material=brass, resolution=1, smooth_path=False,
        parent_obj=root)
pk.torus("Bezel", 0.0475, 0.0068, loc=(0, 0.232, BODY_Z), rot=(90, 0, 0), material=brass,
         segments=18, ring_segments=4, parent_obj=root)
# The lamp itself, glowing in the pair colour behind the prism.
pk.cyl("LampGlow", 0.042, 0.004, loc=(0, 0.231, 0), rot=(90, 0, 0), material=glow,
       verts=18, parent_obj=root)

# --- The prism: a triangular crystal, point forward --------------------------
# Outline drawn in (forward, up) coordinates; rotation (90, 0, 90) stands the
# flat outline up in the Y-Z plane with its thickness along X, so seen from
# the side it is the classic rainbow-prism triangle. No bevel: crisp facets
# read as crystal. The turn is baked into the mesh so the node is unrotated,
# then its origin goes to the front point, where the game spawns each shot.
# The prism is deliberately bigger than the bezel: from the player's eye, just
# behind the gun, anything inside the bezel's outline would be hidden by it.
PRISM_BACK, PRISM_TIP, PRISM_HALF = 0.236, 0.354, 0.068
muzzle = pk.prism("Muzzle", [(PRISM_BACK, -PRISM_HALF), (PRISM_TIP, 0.0),
                             (PRISM_BACK, PRISM_HALF)],
                  0.090, rot=(90, 0, 90), material=accent)
pk.apply(muzzle, location=False, rotation=True, scale=True)
pk.set_origin(muzzle, (0, PRISM_TIP, 0))
pk.parent(muzzle, root)
# Two brass claws gripping the prism's back corners.
for i, z in enumerate((PRISM_HALF + 0.002, -PRISM_HALF - 0.002)):
    pk.box("PrismClaw%d" % i, (0.03, 0.026, 0.008), loc=(0, 0.243, z), material=brass,
           bevel=0.0025, segments=1, parent_obj=root)

# Paint dripping off the prism's sloping underside, in the pair colour. The
# underside rises from the prism's back edge to its point, so each drip starts
# at the height of that slope where it hangs.
drips = []
for i, (x, y, length) in enumerate(((-0.02, 0.250, 0.026), (0.022, 0.266, 0.018))):
    top = -PRISM_HALF + (y - PRISM_BACK) * PRISM_HALF / (PRISM_TIP - PRISM_BACK) + 0.003
    drips.append(pk.sphere("Drip%d" % i, 0.0065, loc=(x, y, top - length * 0.5),
                           scale=(1, 1, length / 0.013 * 0.5 + 0.6), material=wet,
                           segments=6, rings=4))
    drips.append(pk.sphere("DripBead%d" % i, 0.0075, loc=(x, y, top - length),
                           material=wet, segments=6, rings=4))
pk.parent(pk.join("PaintDrips", drips), root)

# --- Energy cell on the LEFT (-X) side, the side the player sees -------------
CELL_X, CELL_Y, CELL_Z = -0.087, 0.005, BODY_Z
pk.lathe("Cell", [
    (0.000, -0.080), (0.016, -0.080), (0.022, -0.075), (0.025, -0.065),
    (0.025, 0.065), (0.022, 0.075), (0.016, 0.080), (0.000, 0.080)],
    loc=(CELL_X, CELL_Y, CELL_Z), rot=ALONG_Y, material=glass, segments=18, parent_obj=root)
fill_obj = pk.cyl("Fill", 0.020, 0.13, loc=(CELL_X, CELL_Y, CELL_Z), rot=(90, 0, 0),
                  material=fill, verts=14, parent_obj=root)
pk.apply(fill_obj, location=False, rotation=True, scale=True)
pk.set_origin(fill_obj, (CELL_X, CELL_Y - 0.065, CELL_Z))
for i, dy in enumerate((-0.082, 0.082)):
    pk.cyl("CellCap%d" % i, 0.0265, 0.016, loc=(CELL_X, CELL_Y + dy, CELL_Z), rot=(90, 0, 0),
           material=brass, verts=14, bevel=0.003, segments=1, parent_obj=root)
for i, dy in enumerate((-0.042, 0.048)):
    pk.box("CellMount%d" % i, (0.016, 0.018, 0.022), loc=(-0.062, CELL_Y + dy, CELL_Z),
           material=trim, bevel=0.003, segments=1, parent_obj=root)
# Conduit from the cell's front cap into the start of the coil.
pk.tube("Conduit", [(CELL_X, 0.095, CELL_Z), (-0.086, 0.118, 0.003), (-0.068, 0.140, 0.001),
                    (-COIL_R, COIL_Y0, 0.0)],
        0.0058, material=brass, resolution=1, path_resolution=4, parent_obj=root)

# --- Grip, trigger and guard --------------------------------------------------
pk.prism("Grip", [(0.005, -0.052), (-0.070, -0.052), (-0.118, -0.194),
                  (-0.095, -0.209), (-0.048, -0.204), (-0.025, -0.106)],
         0.036, rot=(90, 0, 90), material=rubber, bevel=0.01, segments=3, parent_obj=root)
pk.box("GripCap", (0.04, 0.055, 0.014), loc=(0, -0.075, -0.209), rot=(-18, 0, 0),
       material=trim, bevel=0.004, segments=1, parent_obj=root)
pk.prism("Trigger", [(0.028, -0.056), (0.012, -0.056), (0.008, -0.084),
                     (0.020, -0.100), (0.030, -0.098), (0.022, -0.084)],
         0.012, rot=(90, 0, 90), material=trim, bevel=0.002, segments=1, parent_obj=root)
pk.tube("TriggerGuard", [(0, -0.01, -0.058), (0, 0.05, -0.060), (0, 0.068, -0.092),
                         (0, 0.045, -0.124), (0, -0.03, -0.124)],
        0.0055, material=trim, resolution=1, path_resolution=3, parent_obj=root)

pk.smooth_all(35.0)
pk.export("weapon_prism_beam.glb", budget=4000)

# --- A one-piece copy for bots and other players -----------------------------
# Small on screen and never animated, so everything is joined into one mesh
# and the materials folded into four: body, dark trim, pair/team paint
# (PK_Accent) and the skin band.
beam_prop = pk.merge_all("PrismBeamMesh")
body_mat = pk.mat("PK_Body")
trim_mat = pk.mat("PK_Trim")
accent_mat = pk.mat("PK_Accent")
pk.remap_materials(beam_prop, {
    "PK_Dial": body_mat, "PK_Glass": body_mat, "PK_Metal": trim_mat,
    "PK_Brass": trim_mat, "PK_Rubber": trim_mat, "PK_Dark": trim_mat,
    "PK_Fill": accent_mat, "PK_Wet": accent_mat, "PK_AccentGlow": accent_mat,
})
pk.export("weapon_prism_beam_prop.glb", budget=4000)
