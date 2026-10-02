"""
Fine Liner - the sniper weapon.

A giant technical ink fine-liner pen turned into a long rifle: a slender
ceramic pen barrel, a long pocket clip running along the top, a glass ink
cartridge mounted on the clip as the scope, the pen's fat cap "posted" on the
back end as the stock, and a fine conical nib at the very front where the
shots leave. Nothing about it reads as a real firearm.

Axes: the gun points down BLENDER +Y (which the exporter turns into Godot -Z,
the camera's forward). X is right, Z is up. The object origin is the
view-model centre, the same spot as on the Paint Blaster: the body sits there
and the grip hangs below it. It is the longest weapon: about y -0.33 (back of
the stock) to y +0.70 (tip of the nib).

Nodes Godot relies on (names must not change):
    Muzzle     the nib; its ORIGIN is the very point of the nib, (0, 0.70, 0)
               in Blender = (0, 0, -0.70) in Godot. Shots leave from here.
               Material PK_Accent (pair colour).
    Fill       ink inside the scope cartridge; origin at the cartridge's back
               end so Godot can shorten it along the scope as ink drains.
               Material PK_Fill.
    SkinBand   the menu's gun-skin colour band around the barrel. Material
               PK_Skin.
    PaintDrips an ink drip under the nib, in the pair colour (PK_Wet).

Run:  blender -b --factory-startup --python tools/blender/create_weapon_fine_liner.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402

pk.begin("FineLiner", seed=21)

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

root = pk.empty("FineLiner")

# A lathe spins around local Z; rot (-90, 0, 0) turns local Z to face +Y, so
# every lathed part below runs along the gun's length.
ALONG_Y = (-90, 0, 0)

# --- Pen barrel: one long, slightly tapering ceramic tube --------------------
# The back end hides inside the posted cap, the front end inside the tip cone.
pk.lathe("Barrel", [
    (0.000, -0.150), (0.030, -0.150), (0.030, 0.320), (0.0275, 0.360),
    (0.0275, 0.500), (0.000, 0.500)], rot=ALONG_Y, material=body, segments=18,
    parent_obj=root)

# Thin dark rings, the "printed" lines a real pen has along its body.
for i, (y, r) in enumerate(((-0.112, 0.030), (0.210, 0.030), (0.330, 0.0295))):
    pk.torus("TrimRing%d" % i, r, 0.003, loc=(0, y, 0), rot=(90, 0, 0), material=trim,
             segments=14, ring_segments=3, parent_obj=root)

pk.cyl("SkinBand", 0.0312, 0.05, loc=(0, 0.13, 0), rot=(90, 0, 0), material=skin,
       verts=18, parent_obj=root)

# The ribbed rubber finger grip every fine-liner has just behind its tip.
ribs = [(0.0275, 0.372)]
for i in range(4):
    y = 0.380 + i * 0.028
    ribs += [(0.0310, y + 0.004), (0.0310, y + 0.016), (0.0282, y + 0.026)]
ribs += [(0.0275, 0.494)]
pk.lathe("FingerGrip", ribs, rot=ALONG_Y, material=rubber, segments=12, parent_obj=root)

# --- Tip: dark tapering cone, thin metal sleeve, and the nib -----------------
pk.lathe("TipCone", [
    (0.000, 0.490), (0.0285, 0.490), (0.0285, 0.502), (0.024, 0.540),
    (0.016, 0.585), (0.0100, 0.616), (0.0085, 0.624), (0.000, 0.624)],
    rot=ALONG_Y, material=trim, segments=14, parent_obj=root)
pk.cyl("Sleeve", 0.0080, 0.045, loc=(0, 0.6375, 0), rot=(90, 0, 0), material=metal,
       verts=10, parent_obj=root)

# The nib: a short fibre point in the pair colour. Its origin is moved to the
# very tip, which is where the game spawns each shot.
muzzle = pk.lathe("Muzzle", [
    (0.000, 0.655), (0.0090, 0.655), (0.0088, 0.668), (0.0069, 0.682),
    (0.0041, 0.694), (0.0015, 0.6995), (0.000, 0.700)],
    rot=ALONG_Y, material=accent, segments=12)
# Bake the lathe's turn into the mesh so the node itself is unrotated: then its
# local axes match the gun's, and a squash along its local Z (Godot) is a
# squash along the barrel.
pk.apply(muzzle, location=False, rotation=True, scale=True)
pk.set_origin(muzzle, (0, 0.70, 0))
pk.parent(muzzle, root)

# One drop of ink hanging off the tip cone, in the pair colour.
drips = [
    pk.sphere("Drip", 0.0042, loc=(0.002, 0.598, -0.0135), scale=(1, 1, 1.9),
              material=wet, segments=6, rings=4),
    pk.sphere("DripBead", 0.0052, loc=(0.002, 0.598, -0.0225), material=wet,
              segments=6, rings=4),
    pk.sphere("Smear", 0.009, loc=(0.0, 0.60, -0.0085), scale=(1.1, 1.6, 0.35),
              material=wet, segments=6, rings=3),
]
pk.parent(pk.join("PaintDrips", drips), root)

# --- Pocket clip along the top: also the rail the scope sits on --------------
# A metal collar near the back holds the clip; the flat strip runs forward and
# ends in the little ball every pen clip has.
pk.cyl("ClipCollar", 0.0318, 0.028, loc=(0, -0.071, 0), rot=(90, 0, 0), material=metal,
       verts=18, parent_obj=root)
clip_parts = [
    pk.box("ClipStrip", (0.016, 0.46, 0.0065), loc=(0, 0.160, 0.0358), material=metal,
           bevel=0.002, segments=1),
    pk.box("ClipRoot", (0.019, 0.026, 0.013), loc=(0, -0.071, 0.034), material=metal,
           bevel=0.003, segments=1),
    pk.sphere("ClipBall", 0.0088, loc=(0, 0.392, 0.0345), scale=(1.1, 1.5, 0.85),
              material=metal, segments=8, rings=4),
]
pk.parent(pk.join("PocketClip", clip_parts), root)

# --- Scope: a glass ink cartridge full of paint ------------------------------
SCOPE_Z = 0.081
pk.lathe("ScopeTube", [
    (0.000, -0.110), (0.019, -0.110), (0.023, -0.104), (0.024, -0.094),
    (0.024, 0.092), (0.0225, 0.104), (0.0155, 0.114), (0.000, 0.117)],
    loc=(0, 0, SCOPE_Z), rot=ALONG_Y, material=glass, segments=18, parent_obj=root)
fill_obj = pk.cyl("Fill", 0.0187, 0.186, loc=(0, -0.004, SCOPE_Z), rot=(90, 0, 0),
                  material=fill, verts=14, parent_obj=root)
pk.apply(fill_obj, location=False, rotation=True, scale=True)
pk.set_origin(fill_obj, (0, -0.097, SCOPE_Z))

# Brass eyepiece at the back with a rubber eye cup, brass objective bell at the
# front with a dark lens, and two brass scope rings over the mounts.
pk.cyl("Eyepiece", 0.0262, 0.034, loc=(0, -0.122, SCOPE_Z), rot=(90, 0, 0), material=brass,
       verts=16, bevel=0.003, segments=1, parent_obj=root)
pk.torus("EyeCup", 0.0215, 0.0058, loc=(0, -0.141, SCOPE_Z), rot=(90, 0, 0), material=rubber,
         segments=14, ring_segments=4, parent_obj=root)
pk.lathe("ObjectiveBell", [
    (0.0230, 0.096), (0.0262, 0.096), (0.0330, 0.138), (0.0330, 0.148),
    (0.0282, 0.148), (0.0230, 0.112), (0.0230, 0.096)],
    loc=(0, 0, SCOPE_Z), rot=ALONG_Y, material=brass, segments=16, parent_obj=root)
pk.cyl("Lens", 0.0290, 0.004, loc=(0, 0.140, SCOPE_Z), rot=(90, 0, 0), material=dark,
       verts=16, parent_obj=root)
for i, y in enumerate((-0.058, 0.058)):
    pk.torus("ScopeRing%d" % i, 0.0243, 0.0038, loc=(0, y, SCOPE_Z), rot=(90, 0, 0),
             material=brass, segments=14, ring_segments=3, parent_obj=root)
    pk.box("ScopeMount%d" % i, (0.013, 0.018, 0.022), loc=(0, y, 0.0485), material=trim,
           bevel=0.003, segments=1, parent_obj=root)

# --- Stock: the pen's fat cap, posted on the back end -------------------------
# The open end of the cap slides over the back of the barrel, exactly like
# posting a cap while you draw. A rubber butt pad closes the back.
pk.lathe("CapStock", [
    (0.031, -0.112), (0.040, -0.112), (0.0435, -0.120), (0.0445, -0.136),
    (0.0445, -0.284), (0.0425, -0.298), (0.0370, -0.306), (0.000, -0.307)],
    rot=ALONG_Y, material=body, segments=18, parent_obj=root)
pk.torus("CapLip", 0.0415, 0.0045, loc=(0, -0.118, 0), rot=(90, 0, 0), material=trim,
         segments=18, ring_segments=3, parent_obj=root)
pk.lathe("ButtPad", [
    (0.000, -0.300), (0.0395, -0.300), (0.0410, -0.312), (0.0390, -0.324),
    (0.0320, -0.330), (0.000, -0.331)], rot=ALONG_Y, material=rubber, segments=18,
    parent_obj=root)
# The cap's own little clip, root at the closed end, ball toward the open end.
cap_clip = [
    pk.box("CapClipStrip", (0.012, 0.118, 0.005), loc=(0, -0.232, 0.0485), material=metal,
           bevel=0.0018, segments=1),
    pk.box("CapClipRoot", (0.016, 0.020, 0.010), loc=(0, -0.288, 0.0455), material=metal,
           bevel=0.003, segments=1),
    pk.sphere("CapClipBall", 0.0068, loc=(0, -0.172, 0.047), scale=(1.1, 1.5, 0.85),
              material=metal, segments=8, rings=4),
]
pk.parent(pk.join("CapClip", cap_clip), root)

# --- Receiver block under the barrel, holding the grip ------------------------
# Outline drawn in (forward, up) coordinates; rotation (90, 0, 90) stands the
# flat outline up in the Y-Z plane with its thickness along X.
pk.prism("Receiver", [(0.075, -0.020), (0.075, -0.034), (0.052, -0.058),
                      (-0.105, -0.058), (-0.105, -0.020)],
         0.038, rot=(90, 0, 90), material=trim, bevel=0.007, segments=2, parent_obj=root)
for i, y in enumerate((-0.098, 0.058)):
    pk.cyl("Clamp%d" % i, 0.0322, 0.018, loc=(0, y, 0), rot=(90, 0, 0), material=trim,
           verts=18, parent_obj=root)

# --- Grip, trigger and guard --------------------------------------------------
pk.prism("Grip", [(0.005, -0.050), (-0.070, -0.050), (-0.118, -0.192),
                  (-0.095, -0.207), (-0.048, -0.202), (-0.025, -0.104)],
         0.034, rot=(90, 0, 90), material=rubber, bevel=0.01, segments=3, parent_obj=root)
pk.box("GripCap", (0.038, 0.055, 0.014), loc=(0, -0.075, -0.207), rot=(-18, 0, 0),
       material=trim, bevel=0.004, segments=1, parent_obj=root)
pk.prism("Trigger", [(0.028, -0.054), (0.012, -0.054), (0.008, -0.082),
                     (0.020, -0.098), (0.030, -0.096), (0.022, -0.082)],
         0.012, rot=(90, 0, 90), material=trim, bevel=0.002, segments=1, parent_obj=root)
pk.tube("TriggerGuard", [(0, -0.01, -0.056), (0, 0.05, -0.058), (0, 0.068, -0.090),
                         (0, 0.045, -0.122), (0, -0.03, -0.122)],
        0.0055, material=trim, resolution=1, path_resolution=3, parent_obj=root)

pk.smooth_all(35.0)
pk.export("weapon_fine_liner.glb", budget=4000)

# --- A one-piece copy for bots and other players -----------------------------
# Small on screen and never animated, so everything is joined into one mesh
# and the materials folded into four: body, dark trim, pair/team paint
# (PK_Accent) and the skin band.
liner_prop = pk.merge_all("FineLinerMesh")
body_mat = pk.mat("PK_Body")
trim_mat = pk.mat("PK_Trim")
accent_mat = pk.mat("PK_Accent")
pk.remap_materials(liner_prop, {
    "PK_Dial": body_mat, "PK_Glass": body_mat, "PK_Metal": trim_mat,
    "PK_Brass": trim_mat, "PK_Rubber": trim_mat, "PK_Dark": trim_mat,
    "PK_Fill": accent_mat, "PK_Wet": accent_mat, "PK_AccentGlow": accent_mat,
})
pk.export("weapon_fine_liner_prop.glb", budget=4000)
