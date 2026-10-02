"""
Blob Lobber - the grenade / blob launcher.

A fat, short drum launcher: a revolving drum with a paint blob showing in each
chamber, a dark receiver with narrow straps over and under the drum, a short
wide barrel that ends in a ladle-like bowl with a big blob of paint sitting in
it, a glass jar hopper on top (lid facing the player) full of paint, a chunky
grip and a rubber front handle. Toy-like, nothing like a real firearm.

Axes: the gun points down BLENDER +Y (which the exporter turns into Godot -Z,
the camera's forward). X is right, Z is up. The object origin is the
view-model centre, the same spot as on the Paint Blaster: the receiver and
drum sit there and the grip hangs below the receiver.

Nodes Godot relies on (names must not change):
    Muzzle     the big paint blob in the bowl; its ORIGIN is the blob's centre,
               (0, 0.335, 0) in Blender = (0, 0, -0.335) in Godot. Shots leave
               from here. Material PK_Accent (pair colour).
    Fill       paint inside the glass jar hopper; origin at the jar's back end
               so Godot can shorten it as the paint drains. Material PK_Fill.
    SkinBand   the menu's gun-skin colour band round the barrel. Material
               PK_Skin.
    Drum       the revolving drum; its origin is on the drum's axis, so it can
               be spun about its own length. The chamber blobs and rims are
               its children and turn with it.
    PaintDrips paint dripping off the bowl, in the pair colour (PK_Wet).

Run:  blender -b --factory-startup --python tools/blender/create_weapon_blob_lobber.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("BlobLobber", seed=51)

body = pk.mat("PK_Body")
trim = pk.mat("PK_Trim")
metal = pk.mat("PK_Metal")
rubber = pk.mat("PK_Rubber")
glass = pk.mat("PK_Glass")
accent = pk.mat("PK_Accent")
fill = pk.mat("PK_Fill")
wet = pk.mat("PK_Wet")
skin = pk.mat("PK_Team", name="PK_Skin", color="#63D9C7")

root = pk.empty("BlobLobber")

# A lathe spins around local Z; rot (-90, 0, 0) turns local Z to face +Y, so
# every lathed part below runs along the gun's length.
ALONG_Y = (-90, 0, 0)

# --- Receiver: a chunky ceramic slab at the back -------------------------------
# Outline drawn in (forward, up) coordinates; rotation (90, 0, 90) stands the
# flat outline up in the Y-Z plane with its thickness along X. Its front end
# reaches into the drum, where the drum hides it.
pk.prism("Receiver", [(-0.195, -0.055), (-0.050, -0.058), (-0.035, -0.062),
                      (0.000, -0.062), (0.000, 0.060), (-0.035, 0.060),
                      (-0.052, 0.066), (-0.185, 0.058), (-0.208, 0.036),
                      (-0.212, -0.030)],
         0.074, rot=(90, 0, 90), material=body, bevel=0.012, segments=2, parent_obj=root)
# Narrow dark straps over and under the drum, joining the receiver to the barrel,
# like the frame of a revolver. Narrow so they never cover a chamber.
for i, z in enumerate((0.074, -0.074)):
    pk.box("Strap%d" % i, (0.026, 0.150, 0.024), loc=(0, 0.030, z), material=trim,
           bevel=0.004, segments=1, parent_obj=root)

# --- The revolving drum -------------------------------------------------------
DRUM_R, DRUM_BACK, DRUM_FRONT = 0.072, -0.040, 0.090
DRUM_MID = (DRUM_BACK + DRUM_FRONT) * 0.5
drum = pk.lathe("Drum", [
    (0.000, DRUM_BACK), (0.060, DRUM_BACK), (0.068, DRUM_BACK + 0.003),
    (DRUM_R, DRUM_BACK + 0.010), (DRUM_R, DRUM_FRONT - 0.010),
    (0.068, DRUM_FRONT - 0.003), (0.060, DRUM_FRONT), (0.000, DRUM_FRONT)],
    rot=ALONG_Y, material=body, segments=20)
# Bake the lathe's turn so the node is unrotated, and put its origin on the
# axis: spinning it about its own length then turns it in place.
pk.apply(drum, location=False, rotation=True, scale=True)
pk.set_origin(drum, (0, DRUM_MID, 0))
pk.parent(drum, root)
for i, y in enumerate((DRUM_BACK + 0.012, DRUM_FRONT - 0.012)):
    pk.cyl("DrumBand%d" % i, DRUM_R + 0.0012, 0.010, loc=(0, y, 0), rot=(90, 0, 0),
           material=trim, verts=20, parent_obj=drum)
# Six chambers. Each shows a blob of paint bulging out through a dark round
# port in the drum's side. The angles skip straight up and straight down,
# where the straps run.
blobs, rims = [], []
for i in range(6):
    a = math.radians(60 * i)
    ca, sa = math.cos(a), math.sin(a)
    blobs.append(pk.sphere("ChamberBlob%d" % i, 0.022, loc=(ca * 0.062, DRUM_MID, sa * 0.062),
                           material=wet, segments=8, rings=4))
    # rot Y by (90 - angle) turns the ring's axis to point straight out of
    # the drum at that angle.
    rims.append(pk.torus("ChamberRim%d" % i, 0.0205, 0.0038,
                         loc=(ca * 0.0722, DRUM_MID, sa * 0.0722), rot=(0, 90 - 60 * i, 0),
                         material=trim, segments=10, ring_segments=3))
pk.parent(pk.join("ChamberBlobs", blobs), drum)
pk.parent(pk.join("ChamberRims", rims), drum)

# --- Barrel -------------------------------------------------------------------
pk.cyl("BreechRing", 0.068, 0.020, loc=(0, 0.101, 0), rot=(90, 0, 0), material=trim,
       verts=20, parent_obj=root)
pk.lathe("Barrel", [
    (0.000, 0.100), (0.060, 0.100), (0.062, 0.110), (0.062, 0.268), (0.000, 0.270)],
    rot=ALONG_Y, material=body, segments=20, parent_obj=root)
pk.cyl("SkinBand", 0.0632, 0.040, loc=(0, 0.145, 0), rot=(90, 0, 0), material=skin,
       verts=20, parent_obj=root)

# --- The ladle bowl at the front, with the blob sitting in it -----------------
# The profile runs round the outside of the bowl, over the lip and back down
# the inside, so the bowl is hollow.
pk.lathe("Bowl", [
    (0.056, 0.258), (0.070, 0.280), (0.080, 0.310), (0.083, 0.340),
    (0.080, 0.351), (0.075, 0.343), (0.071, 0.316), (0.060, 0.293),
    (0.000, 0.280)], rot=ALONG_Y, material=metal, segments=20, parent_obj=root)
pk.torus("BowlLip", 0.0795, 0.0055, loc=(0, 0.349, 0), rot=(90, 0, 0), material=trim,
         segments=20, ring_segments=3, parent_obj=root)

# The blob: a slightly squashed ball with a couple of lumps, all in the pair
# colour, joined into one mesh named Muzzle. Its origin is the blob's centre,
# where the game spawns each shot.
BLOB_Y = 0.335
blob_parts = [pk.sphere("Blob", 0.063, loc=(0, BLOB_Y, 0), scale=(1.0, 0.85, 1.0),
                        material=accent, segments=12, rings=8)]
pk.displace_random(blob_parts[0], 0.0022, seed=5)
for i, (x, z, r) in enumerate(((0.030, 0.040, 0.020), (-0.036, 0.022, 0.016))):
    blob_parts.append(pk.sphere("BlobLump%d" % i, r, loc=(x, BLOB_Y + 0.022, z),
                                material=accent, segments=6, rings=4))
muzzle = pk.join("Muzzle", blob_parts)
pk.set_origin(muzzle, (0, BLOB_Y, 0))
pk.parent(muzzle, root)

# Paint dripping off the bowl's lip, in the pair colour.
drips = []
for i, (x, length) in enumerate(((-0.022, 0.024), (0.026, 0.016))):
    drips.append(pk.sphere("Drip%d" % i, 0.0072, loc=(x, 0.346, -0.080 - length * 0.5),
                           scale=(1, 1, length / 0.014 * 0.5 + 0.6), material=wet,
                           segments=6, rings=4))
    drips.append(pk.sphere("DripBead%d" % i, 0.0082, loc=(x, 0.346, -0.080 - length),
                           material=wet, segments=6, rings=4))
for i, a in enumerate((72, 118)):
    ang = math.radians(a)
    drips.append(pk.sphere("Smear%d" % i, 0.013, loc=(math.cos(ang) * 0.080, 0.347, math.sin(ang) * 0.080),
                           scale=(1.0, 1.3, 0.4), rot=(0, 90 - a, 0), material=wet,
                           segments=6, rings=3))
pk.parent(pk.join("PaintDrips", drips), root)

# --- Glass jar hopper on top --------------------------------------------------
# A fat jar lying along the gun, its screw lid at the back facing the player,
# sitting in a funnel-shaped feed neck and held by a clamp band. The paint
# inside is the Fill.
HOP_Z = 0.140
pk.cyl("FeedNeck", 0.016, 0.044, loc=(0, -0.072, 0.078), radius_top=0.030, material=trim,
       verts=12, parent_obj=root)
pk.cyl("JarClamp", 0.0505, 0.014, loc=(0, -0.072, HOP_Z), rot=(90, 0, 0), material=trim,
       verts=18, parent_obj=root)
pk.lathe("Hopper", [
    (0.000, -0.136), (0.036, -0.136), (0.036, -0.124), (0.046, -0.112),
    (0.049, -0.098), (0.049, -0.020), (0.046, -0.004), (0.036, 0.008),
    (0.000, 0.013)], loc=(0, 0, HOP_Z), rot=ALONG_Y, material=glass, segments=18,
    parent_obj=root)
fill_obj = pk.cyl("Fill", 0.041, 0.112, loc=(0, -0.068, HOP_Z), rot=(90, 0, 0),
                  material=fill, verts=16, parent_obj=root)
pk.apply(fill_obj, location=False, rotation=True, scale=True)
pk.set_origin(fill_obj, (0, -0.124, HOP_Z))
pk.cyl("HopperLid", 0.041, 0.024, loc=(0, -0.146, HOP_Z), rot=(90, 0, 0), material=metal,
       verts=16, bevel=0.004, segments=1, parent_obj=root)

# --- Grip, trigger and guard --------------------------------------------------
pk.prism("Grip", [(-0.030, -0.050), (-0.110, -0.050), (-0.150, -0.195),
                  (-0.128, -0.212), (-0.080, -0.207), (-0.058, -0.110)],
         0.042, rot=(90, 0, 90), material=rubber, bevel=0.011, segments=3, parent_obj=root)
pk.box("GripCap", (0.046, 0.058, 0.014), loc=(0, -0.106, -0.212), rot=(-14, 0, 0),
       material=trim, bevel=0.004, segments=1, parent_obj=root)
pk.prism("Trigger", [(-0.004, -0.080), (-0.020, -0.080), (-0.024, -0.108),
                     (-0.012, -0.124), (-0.002, -0.122), (-0.010, -0.108)],
         0.012, rot=(90, 0, 90), material=trim, bevel=0.002, segments=1, parent_obj=root)
pk.tube("TriggerGuard", [(0, -0.046, -0.082), (0, 0.016, -0.088), (0, 0.036, -0.118),
                         (0, 0.012, -0.150), (0, -0.063, -0.150)],
        0.0055, material=trim, resolution=1, path_resolution=3, parent_obj=root)

# --- Front handle under the barrel --------------------------------------------
# A ribbed rubber handle spun around its own upright axis, raked a little
# forward, held by a clamp ring round the barrel.
pk.cyl("HandleClamp", 0.0645, 0.026, loc=(0, 0.212, 0), rot=(90, 0, 0), material=trim,
       verts=20, parent_obj=root)
pk.box("HandleMount", (0.024, 0.030, 0.018), loc=(0, 0.214, -0.064), material=trim,
       bevel=0.003, segments=1, parent_obj=root)
pk.lathe("FrontHandle", [
    (0.000, -0.180), (0.017, -0.180), (0.022, -0.172), (0.023, -0.156),
    (0.020, -0.146), (0.023, -0.136), (0.020, -0.126), (0.023, -0.116),
    (0.020, -0.106), (0.021, -0.088), (0.017, -0.062), (0.000, -0.062)],
    loc=(0, 0.204, 0), rot=(10, 0, 0), material=rubber, segments=10, parent_obj=root)

pk.smooth_all(35.0)
pk.export("weapon_blob_lobber.glb", budget=4000)

# --- A one-piece copy for bots and other players -----------------------------
# Small on screen and never animated, so everything is joined into one mesh
# and the materials folded into four: body, dark trim, pair/team paint
# (PK_Accent) and the skin band.
lobber_prop = pk.merge_all("BlobLobberMesh")
body_mat = pk.mat("PK_Body")
trim_mat = pk.mat("PK_Trim")
accent_mat = pk.mat("PK_Accent")
pk.remap_materials(lobber_prop, {
    "PK_Dial": body_mat, "PK_Glass": body_mat, "PK_Metal": trim_mat,
    "PK_Brass": trim_mat, "PK_Rubber": trim_mat, "PK_Dark": trim_mat,
    "PK_Fill": accent_mat, "PK_Wet": accent_mat, "PK_AccentGlow": accent_mat,
})
pk.export("weapon_blob_lobber_prop.glb", budget=4000)
