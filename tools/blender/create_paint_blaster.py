"""
Paint Blaster - the first-person weapon (also carried by TDM runners).

Plan: docs/VISUAL_OVERHAUL_PLAN.md section 4.1.

An oversized artist's brush bolted onto a pressure sprayer: a ceramic pressure
chamber, a glass paint tank on top, a hose looping down the left side, a
crimped metal ferrule and a flared bristle tuft at the front. Nothing about it
reads as a real firearm.

Axes: the gun points down BLENDER +Y (which the exporter turns into Godot -Z,
the camera's forward). X is right, Z is up. The object origin is the old
view-model centre, so it drops into player.gd's `_view_model` unchanged.

Nodes Godot relies on (names must not change):
    Muzzle     bristle tuft; its ORIGIN is the glob spawn point (0, 0.36, 0)
               in Blender = (0, 0, -0.36) in Godot, exactly where the old
               white cube sat. Material PK_Accent (pair colour).
    Fill       paint inside the tank; origin at the tank's back end so Godot
               can scale it along the tank as paint drains. Material PK_Fill.
    SkinBand   the menu's gun-skin colour band. Material PK_Skin.
    Needle     pressure-gauge needle; origin at the dial centre.
    Regulator  knob that can spin while the tank refills.

Run:  blender -b --factory-startup --python tools/blender/create_paint_blaster.py
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("PaintBlaster", seed=11)

body = pk.mat("PK_Body")
trim = pk.mat("PK_Trim")
metal = pk.mat("PK_Metal")
brass = pk.mat("PK_Brass")
rubber = pk.mat("PK_Rubber")
glass = pk.mat("PK_Glass")
accent = pk.mat("PK_Accent")
fill = pk.mat("PK_Fill")
wet = pk.mat("PK_Wet")
skin = pk.mat("PK_Team", name="PK_Skin", color="#63D9C7")
dark = pk.mat("PK_Dark")

root = pk.empty("PaintBlaster")

# A lathe spins around local Z; rot (-90, 0, 0) turns local Z to face +Y, so
# every lathed part below runs along the gun's length.
ALONG_Y = (-90, 0, 0)

# --- Pressure chamber: a rounded ceramic capsule -----------------------------
chamber = pk.lathe("Chamber", [
    (0.000, -0.165), (0.026, -0.163), (0.040, -0.155), (0.048, -0.140),
    (0.050, -0.120), (0.050, 0.120), (0.047, 0.140), (0.040, 0.152),
    (0.030, 0.160), (0.000, 0.162)], loc=(0, 0.0, 0), rot=ALONG_Y,
    material=body, segments=18, parent_obj=root)

for i, y in enumerate((-0.10, 0.10)):
    pk.torus("Hoop%d" % i, 0.0505, 0.0055, loc=(0, y, 0), rot=(90, 0, 0),
             material=trim, segments=18, ring_segments=4, parent_obj=root)

pk.cyl("SkinBand", 0.0512, 0.075, loc=(0, 0.0, 0), rot=(90, 0, 0), material=skin,
       verts=22, parent_obj=root)

# Rear cap and the regulator knob at the back of the chamber.
pk.cyl("RearCap", 0.03, 0.014, loc=(0, -0.168, 0), rot=(90, 0, 0), material=trim,
       verts=14, bevel=0.003, segments=1, parent_obj=root)
regulator = pk.cyl("Regulator", 0.016, 0.02, loc=(0, -0.182, 0), rot=(90, 0, 0),
                   material=brass, verts=10, bevel=0.003, segments=1, parent_obj=root)

# --- Paint tank on top --------------------------------------------------------
TANK_Z = 0.088
pk.lathe("Tank", [
    (0.000, -0.090), (0.022, -0.087), (0.032, -0.078), (0.035, -0.064),
    (0.035, 0.064), (0.032, 0.078), (0.022, 0.087), (0.000, 0.090)],
    loc=(0, 0.0, TANK_Z), rot=ALONG_Y, material=glass, segments=18, parent_obj=root)
fill_obj = pk.cyl("Fill", 0.028, 0.15, loc=(0, 0.0, TANK_Z), rot=(90, 0, 0),
                  material=fill, verts=14, parent_obj=root)
pk.apply(fill_obj, location=False, rotation=True, scale=True)
pk.set_origin(fill_obj, (0, -0.075, TANK_Z))
for i, y in enumerate((-0.094, 0.094)):
    pk.cyl("TankCap%d" % i, 0.03, 0.016, loc=(0, y, TANK_Z), rot=(90, 0, 0),
           material=brass, verts=12, bevel=0.003, segments=1, parent_obj=root)
pk.cyl("Valve", 0.008, 0.026, loc=(0, 0.094, TANK_Z + 0.03), material=brass, verts=8,
       parent_obj=root)
pk.sphere("ValveCap", 0.011, loc=(0, 0.094, TANK_Z + 0.046), material=trim, segments=10,
          rings=5, parent_obj=root)
for i, y in enumerate((-0.05, 0.05)):
    pk.box("TankMount%d" % i, (0.022, 0.024, 0.04), loc=(0, y, 0.052), material=trim,
           bevel=0.004, segments=1, parent_obj=root)

# --- Pressure gauge on the LEFT (-X) face, the side the player sees ------------
GAUGE = (-0.058, -0.07, 0.012)
pk.cyl("GaugeBody", 0.022, 0.014, loc=GAUGE, rot=(0, 90, 0), material=pk.mat("PK_Body", name="PK_Dial", color="#FBF8F0"),
       verts=18, parent_obj=root)
pk.torus("GaugeRim", 0.022, 0.004, loc=GAUGE, rot=(0, 90, 0), material=brass,
         segments=14, ring_segments=4, parent_obj=root)
needle = pk.box("Needle", (0.004, 0.003, 0.017), loc=(GAUGE[0] - 0.008, GAUGE[1], GAUGE[2] + 0.007),
                material=dark, parent_obj=root)
pk.set_origin(needle, (GAUGE[0] - 0.008, GAUGE[1], GAUGE[2]))

# --- Ferrule and bristle tuft -------------------------------------------------
pk.lathe("Ferrule", [
    (0.030, 0.150), (0.036, 0.160), (0.038, 0.200), (0.041, 0.240),
    (0.045, 0.285), (0.046, 0.300), (0.030, 0.302)],
    loc=(0, 0, 0), rot=ALONG_Y, material=metal, segments=20, parent_obj=root)
for i, y in enumerate((0.215, 0.265)):
    pk.torus("Crimp%d" % i, 0.041 + 0.003 * i, 0.004, loc=(0, y, 0), rot=(90, 0, 0),
             material=metal, segments=16, ring_segments=4, parent_obj=root)

# The tuft: a flared core plus a ring of splayed clumps, all in the pair
# colour, joined into one mesh named Muzzle.
core = pk.lathe("TuftCore", [
    (0.000, 0.296), (0.044, 0.298), (0.054, 0.340), (0.056, 0.380),
    (0.048, 0.418), (0.030, 0.438), (0.000, 0.444)],
    loc=(0, 0, 0), rot=ALONG_Y, material=accent, segments=14)
clumps = [core]
for i in range(8):
    angle = math.tau * i / 8 + random.uniform(-0.12, 0.12)
    r = 0.045
    x, z = math.cos(angle) * r, math.sin(angle) * r
    tilt_out = random.uniform(6, 13)
    clump = pk.cyl("Clump%d" % i, 0.013, 0.12, loc=(x * 1.05, 0.372, z * 1.05),
                   rot=(-90, 0, 0), radius_top=0.004, material=accent, verts=7)
    # Splay each clump outward from the centre line, like a well-used brush.
    clump.rotation_euler.rotate_axis("X", math.radians(-math.sin(angle) * tilt_out))
    clump.rotation_euler.rotate_axis("Z", math.radians(math.cos(angle) * tilt_out))
    clumps.append(clump)
muzzle = pk.join("Muzzle", clumps)
pk.set_origin(muzzle, (0, 0.36, 0))
pk.parent(muzzle, root)

# Paint drips off the ferrule and a few wet smears, in the pair colour.
drips = []
for i, (y, x, length) in enumerate(((0.23, -0.012, 0.03), (0.262, 0.018, 0.022), (0.286, -0.028, 0.017))):
    drips.append(pk.sphere("Drip%d" % i, 0.0075, loc=(x, y, -0.043 - length * 0.5),
                           scale=(1, 1, length / 0.015 * 0.5 + 0.6), material=wet,
                           segments=6, rings=4))
    drips.append(pk.sphere("DripBead%d" % i, 0.0085, loc=(x, y, -0.043 - length),
                           material=wet, segments=6, rings=4))
for i, (y, a) in enumerate(((0.19, 200), (0.245, 330), (0.29, 30))):
    ang = math.radians(a)
    drips.append(pk.sphere("Smear%d" % i, 0.014, loc=(math.cos(ang) * 0.04, y, math.sin(ang) * 0.04),
                           scale=(1.0, 1.4, 0.35), material=wet, segments=6, rings=3))
pk.parent(pk.join("PaintDrips", drips), root)

# --- Grip, trigger and guard --------------------------------------------------
# Outline drawn in (forward, up) coordinates; rotation (90, 0, 90) stands the
# flat outline up in the Y-Z plane with its thickness along X.
grip = pk.prism("Grip", [(0.005, -0.032), (-0.07, -0.032), (-0.118, -0.19),
                         (-0.095, -0.205), (-0.048, -0.2), (-0.025, -0.1)],
                0.036, rot=(90, 0, 90), material=rubber, bevel=0.01, segments=3,
                parent_obj=root)
pk.box("GripCap", (0.04, 0.055, 0.014), loc=(0, -0.075, -0.205), rot=(-18, 0, 0),
       material=trim, bevel=0.004, segments=1, parent_obj=root)
pk.prism("Trigger", [(0.028, -0.045), (0.012, -0.045), (0.008, -0.075),
                     (0.02, -0.092), (0.03, -0.09), (0.022, -0.075)],
         0.012, rot=(90, 0, 90), material=trim, bevel=0.002, segments=1, parent_obj=root)
pk.tube("TriggerGuard", [(0, -0.01, -0.046), (0, 0.05, -0.05), (0, 0.068, -0.085),
                         (0, 0.045, -0.118), (0, -0.03, -0.118)],
        0.0055, material=trim, resolution=1, path_resolution=3, parent_obj=root)

# --- Hose: tank back cap, down the left flank, into the ferrule ----------------
pk.tube("Hose", [(0, -0.104, TANK_Z), (-0.03, -0.15, 0.05), (-0.06, -0.12, 0.0),
                 (-0.064, -0.02, -0.012), (-0.062, 0.1, -0.012), (-0.046, 0.18, 0.0),
                 (-0.03, 0.2, 0.004)],
        0.0085, material=rubber, resolution=1, path_resolution=3, parent_obj=root)

pk.smooth_all(35.0)
pk.export("paint_blaster.glb", budget=3500)

# --- A one-piece copy for the TDM runners ------------------------------------
# A bot's gun is small on screen and never animates, so it does not need 27
# separate parts and 12 materials. Everything is joined into one mesh and the
# materials folded into four: body, dark trim, pair/team paint (PK_Accent) and
# the skin band. Same shape, a fraction of the cost with 19 bots on the field.
blaster_prop = pk.merge_all("BlasterMesh")
body_mat = pk.mat("PK_Body")
trim_mat = pk.mat("PK_Trim")
accent_mat = pk.mat("PK_Accent")
pk.remap_materials(blaster_prop, {
    "PK_Dial": body_mat, "PK_Glass": body_mat, "PK_Metal": trim_mat,
    "PK_Brass": trim_mat, "PK_Rubber": trim_mat, "PK_Dark": trim_mat,
    "PK_Fill": accent_mat, "PK_Wet": accent_mat,
})
pk.export("paint_blaster_prop.glb", budget=3500)
