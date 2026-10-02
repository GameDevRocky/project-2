"""
Splat Bucket - the shotgun weapon.

A paint can turned on its side and fitted with a wide flared bell mouth: the
can is the body (rolled metal rims, a label band, the lid at the back), its
wire bail handle arches over the top as a carry handle, a glass sight window
on the left side shows how much paint is left, a pump grip slides on a rail
under the front, and the bell mouth is brimming with paint. Short and wide,
nothing like a real firearm.

Axes: the gun points down BLENDER +Y (which the exporter turns into Godot -Z,
the camera's forward). X is right, Z is up. The object origin is the
view-model centre, the same spot as on the Paint Blaster: the can sits there
and the grip hangs below it.

Nodes Godot relies on (names must not change):
    Muzzle     the paint filling the bell mouth; its ORIGIN is the centre of
               the mouth, (0, 0.333, 0) in Blender = (0, 0, -0.333) in Godot.
               Shots leave from here. Material PK_Accent (pair colour).
    Fill       paint seen through the sight window on the left side; origin at
               the window's back end so Godot can shorten it as paint drains.
               Material PK_Fill.
    SkinBand   the can's label band, the menu's gun-skin colour. Material
               PK_Skin.
    PaintDrips paint running over the rims, in the pair colour (PK_Wet).

Run:  blender -b --factory-startup --python tools/blender/create_weapon_splat_bucket.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("SplatBucket", seed=41)

body = pk.mat("PK_Body")
trim = pk.mat("PK_Trim")
metal = pk.mat("PK_Metal")
rubber = pk.mat("PK_Rubber")
glass = pk.mat("PK_Glass")
accent = pk.mat("PK_Accent")
fill = pk.mat("PK_Fill")
wet = pk.mat("PK_Wet")
skin = pk.mat("PK_Team", name="PK_Skin", color="#63D9C7")

root = pk.empty("SplatBucket")

# A lathe spins around local Z; rot (-90, 0, 0) turns local Z to face +Y, so
# every lathed part below runs along the gun's length.
ALONG_Y = (-90, 0, 0)

CAN_R = 0.075          # radius of the paint can
CAN_BACK = -0.166      # the lid end
CAN_FRONT = 0.098      # the bottom of the can, where the bell mouth fixes on

# --- The paint can, lying along the gun --------------------------------------
# One spun profile: the wall with a raised bead near each end, like a real
# can, closed at the front. The back is closed by the lid.
pk.lathe("Can", [
    (0.066, CAN_BACK), (0.073, CAN_BACK + 0.004), (0.075, -0.155), (0.0775, -0.150),
    (0.075, -0.145), (0.075, 0.070), (0.0775, 0.075), (0.075, 0.080),
    (0.075, 0.090), (0.072, 0.096), (0.000, 0.100)],
    rot=ALONG_Y, material=body, segments=22, parent_obj=root)
# Rolled metal rims at both ends.
pk.torus("BackRim", 0.072, 0.0065, loc=(0, CAN_BACK, 0), rot=(90, 0, 0), material=metal,
         segments=22, ring_segments=4, parent_obj=root)
pk.torus("FrontRim", 0.071, 0.006, loc=(0, CAN_FRONT - 0.003, 0), rot=(90, 0, 0),
         material=metal, segments=22, ring_segments=4, parent_obj=root)
# The lid at the back, with the groove you lever it open by.
pk.cyl("Lid", 0.068, 0.006, loc=(0, CAN_BACK - 0.002, 0), rot=(90, 0, 0), material=metal,
       verts=22, parent_obj=root)
pk.torus("LidGroove", 0.056, 0.0042, loc=(0, CAN_BACK - 0.0055, 0), rot=(90, 0, 0),
         material=trim, segments=16, ring_segments=3, parent_obj=root)

# The can's label: the gun-skin colour band.
pk.cyl("SkinBand", 0.0762, 0.09, loc=(0, -0.030, 0), rot=(90, 0, 0), material=skin,
       verts=22, parent_obj=root)

# --- Wire bail handle, arching over the top ----------------------------------
# A paint can's handle: a wire hooked into an "ear" on each side. It leans
# back a little and is taller than it is wide, so it clears the can's curve
# all the way over. A rubber sleeve in the middle is where you would carry it.
EAR_Y = 0.055
bail = []
for i in range(17):
    a = math.pi * i / 16
    bail.append((0.080 * math.cos(a), EAR_Y - 0.040 * math.sin(a), 0.115 * math.sin(a)))
pk.tube("Bail", bail, 0.0036, material=metal, resolution=1, smooth_path=False,
        parent_obj=root)
pk.cyl("BailGrip", 0.0105, 0.050, loc=(0, EAR_Y - 0.040, 0.115), rot=(0, 90, 0),
       material=rubber, verts=12, bevel=0.003, segments=1, parent_obj=root)
for i, x in enumerate((-0.077, 0.077)):
    pk.cyl("Ear%d" % i, 0.012, 0.006, loc=(x, EAR_Y, 0), rot=(0, 90, 0), material=metal,
           verts=12, parent_obj=root)

# --- Sight window on the LEFT (-X) side, the side the player sees ------------
# A dark frame on the can, a glass strip over it, and the paint behind the
# glass. Little tick marks along the top read as a level gauge.
WIN_Y, WIN_LEN = -0.050, 0.176
pk.box("WindowFrame", (0.012, WIN_LEN, 0.044), loc=(-0.0735, WIN_Y, 0), material=trim,
       bevel=0.003, segments=1, parent_obj=root)
pk.box("WindowGlass", (0.005, WIN_LEN - 0.016, 0.030), loc=(-0.0812, WIN_Y, 0),
       material=glass, parent_obj=root)
FILL_LEN = WIN_LEN - 0.024
fill_obj = pk.box("Fill", (0.003, FILL_LEN, 0.024), loc=(-0.0807, WIN_Y, 0), material=fill,
                  parent_obj=root)
pk.set_origin(fill_obj, (-0.0807, WIN_Y - FILL_LEN * 0.5, 0))
ticks = [pk.box("Tick%d" % i, (0.002, 0.003, 0.009), loc=(-0.0840, WIN_Y + dy, 0.0105),
                material=trim) for i, dy in enumerate((-0.054, -0.018, 0.018, 0.054))]
pk.parent(pk.join("WindowTicks", ticks), root)

# --- Bell mouth at the front -------------------------------------------------
# A dark collar on the can's bottom, then the flared metal bell: narrow at
# first, then opening quickly like a trumpet. The profile runs up the outside,
# over the lip and back down the inside, so the mouth is hollow; the paint
# below fills it.
pk.cyl("NeckCollar", 0.048, 0.044, loc=(0, 0.118, 0), rot=(90, 0, 0), material=trim,
       verts=20, parent_obj=root)
pk.lathe("Bell", [
    (0.042, 0.120), (0.045, 0.170), (0.050, 0.215), (0.058, 0.250),
    (0.070, 0.278), (0.084, 0.302), (0.093, 0.320), (0.096, 0.330),
    (0.093, 0.336), (0.088, 0.336), (0.081, 0.326), (0.068, 0.305),
    (0.000, 0.290)], rot=ALONG_Y, material=metal, segments=20, parent_obj=root)
pk.torus("BellRim", 0.0925, 0.0062, loc=(0, 0.333, 0), rot=(90, 0, 0), material=trim,
         segments=22, ring_segments=4, parent_obj=root)

# The paint brimming in the mouth: a domed disc with a few lumps, all in the
# pair colour, joined into one mesh named Muzzle. The turn is baked into the
# mesh so the node is unrotated, then its origin goes to the mouth's centre.
# Its rim is tucked inside the bell's wall so no paint pokes through outside.
MOUTH_Y = 0.333
paint = [pk.lathe("PaintDome", [
    (0.000, 0.300), (0.066, 0.300), (0.078, 0.314), (0.076, 0.326),
    (0.055, 0.334), (0.025, 0.339), (0.000, 0.340)], rot=ALONG_Y, material=accent,
    segments=20)]
for i, (a, r, size) in enumerate(((40, 0.034, 0.016), (165, 0.040, 0.013), (285, 0.026, 0.012))):
    ang = math.radians(a)
    paint.append(pk.sphere("Lump%d" % i, size, loc=(math.cos(ang) * r, 0.334, math.sin(ang) * r),
                           scale=(1.0, 0.45, 1.0), material=accent, segments=8, rings=4))
muzzle = pk.join("Muzzle", paint)
pk.apply(muzzle, location=False, rotation=True, scale=True)
pk.set_origin(muzzle, (0, MOUTH_Y, 0))
pk.parent(muzzle, root)

# --- Paint running over the rims, in the pair colour --------------------------
drips = []
# Drops hanging under the front rim and under the bell's lip.
for i, (x, y, top, length) in enumerate(((-0.032, 0.097, -0.072, 0.024), (0.036, 0.097, -0.071, 0.015),
                                         (-0.024, 0.331, -0.095, 0.020))):
    drips.append(pk.sphere("Drip%d" % i, 0.0072, loc=(x, y, top - length * 0.5),
                           scale=(1, 1, length / 0.014 * 0.5 + 0.6), material=wet,
                           segments=6, rings=4))
    drips.append(pk.sphere("DripBead%d" % i, 0.0082, loc=(x, y, top - length),
                           material=wet, segments=6, rings=4))
# Runs down the can's sides from the back rim, lying flat on the wall.
for i, (side, length) in enumerate(((-1, 0.036), (1, 0.026))):
    drips.append(pk.sphere("Run%d" % i, 0.008, loc=(side * 0.0755, -0.152, -0.004 - length * 0.5),
                           scale=(0.45, 1.0, length / 0.016), material=wet, segments=6, rings=4))
# A run down the lid at the back, the face the player looks at most.
drips.append(pk.sphere("LidRun", 0.0085, loc=(0.014, CAN_BACK - 0.0055, 0.046),
                       scale=(1.0, 0.35, 2.6), material=wet, segments=6, rings=4))
drips.append(pk.sphere("LidRunBead", 0.0095, loc=(0.014, CAN_BACK - 0.0055, 0.024),
                       scale=(1.0, 0.5, 1.0), material=wet, segments=6, rings=4))
# Smears over the top of the front rim.
for i, a in enumerate((78, 128)):
    ang = math.radians(a)
    drips.append(pk.sphere("Smear%d" % i, 0.013, loc=(math.cos(ang) * 0.074, 0.093, math.sin(ang) * 0.074),
                           scale=(1.0, 1.3, 0.4), rot=(0, 90 - a, 0), material=wet,
                           segments=6, rings=3))
pk.parent(pk.join("PaintDrips", drips), root)

# --- Pump grip on a slide rail under the front --------------------------------
RAIL_Z = -0.097
pk.cyl("Rail", 0.0075, 0.19, loc=(0, 0.158, RAIL_Z), rot=(90, 0, 0), material=metal,
       verts=10, parent_obj=root)
pk.box("RailBracketBack", (0.016, 0.016, 0.032), loc=(0, 0.072, -0.082), material=trim,
       bevel=0.003, segments=1, parent_obj=root)
pk.box("RailBracketFront", (0.014, 0.014, 0.036), loc=(0, 0.246, -0.078), material=trim,
       bevel=0.003, segments=1, parent_obj=root)
# The pump: a ribbed rubber sleeve you pull back to rack the next splat.
ribs = [(0.000, 0.106), (0.018, 0.106), (0.024, 0.112)]
for i in range(4):
    y = 0.112 + i * 0.022
    ribs += [(0.024, y + 0.016), (0.021, y + 0.022)]
ribs += [(0.024, 0.206), (0.018, 0.212), (0.000, 0.212)]
pk.lathe("Pump", ribs, loc=(0, 0, RAIL_Z), rot=ALONG_Y, material=rubber, segments=12,
         parent_obj=root)

# --- Grip, trigger and guard --------------------------------------------------
# Outline drawn in (forward, up) coordinates; rotation (90, 0, 90) stands the
# flat outline up in the Y-Z plane with its thickness along X.
pk.prism("Grip", [(0.005, -0.066), (-0.070, -0.066), (-0.114, -0.196),
                  (-0.092, -0.211), (-0.046, -0.206), (-0.024, -0.114)],
         0.036, rot=(90, 0, 90), material=rubber, bevel=0.01, segments=3, parent_obj=root)
pk.box("GripCap", (0.04, 0.055, 0.014), loc=(0, -0.073, -0.211), rot=(-18, 0, 0),
       material=trim, bevel=0.004, segments=1, parent_obj=root)
pk.prism("Trigger", [(0.028, -0.070), (0.012, -0.070), (0.008, -0.098),
                     (0.020, -0.114), (0.030, -0.112), (0.022, -0.098)],
         0.012, rot=(90, 0, 90), material=trim, bevel=0.002, segments=1, parent_obj=root)
pk.tube("TriggerGuard", [(0, -0.01, -0.072), (0, 0.05, -0.074), (0, 0.068, -0.104),
                         (0, 0.045, -0.134), (0, -0.03, -0.134)],
        0.0055, material=trim, resolution=1, path_resolution=3, parent_obj=root)

pk.smooth_all(35.0)
pk.export("weapon_splat_bucket.glb", budget=4000)

# --- A one-piece copy for bots and other players -----------------------------
# Small on screen and never animated, so everything is joined into one mesh
# and the materials folded into four: body, dark trim, pair/team paint
# (PK_Accent) and the skin band.
bucket_prop = pk.merge_all("SplatBucketMesh")
body_mat = pk.mat("PK_Body")
trim_mat = pk.mat("PK_Trim")
accent_mat = pk.mat("PK_Accent")
pk.remap_materials(bucket_prop, {
    "PK_Dial": body_mat, "PK_Glass": body_mat, "PK_Metal": trim_mat,
    "PK_Brass": trim_mat, "PK_Rubber": trim_mat, "PK_Dark": trim_mat,
    "PK_Fill": accent_mat, "PK_Wet": accent_mat, "PK_AccentGlow": accent_mat,
})
pk.export("weapon_splat_bucket_prop.glb", budget=4000)
