"""
Paint Glob - the one shared paint projectile (player, enemies, TDM bots).

Plan: docs/VISUAL_OVERHAUL_PLAN.md section 4.11.

A glossy teardrop of thrown paint: a round head at the front that tapers
into a pointed tail, with two small droplets trailing behind it. Dozens are
alive at once, so it is kept tiny (120 triangles) but smooth-shaded.

Axes: the round head points down BLENDER +Y, which the exporter turns into
Godot -Z ("forward"). projectile.gd can simply look_at() its direction.

Nodes Godot relies on (names must not change):
    PaintGlob  root (plain Node3D).
    Glob       the whole glob, tail droplets included, as ONE mesh. Its
               ORIGIN is the centre of the round head (radius 0.14, the same
               size as the old SphereMesh). Material PK_Wet (glob colour,
               replaced at runtime).

Run:  blender -b --factory-startup --python tools/blender/create_paint_glob.py
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paintkit as pk  # noqa: E402


def smooth_fully(obj):
    """Smooth-shade every face and clear any sharp-edge marks. (pk.smooth()
    keeps sharp edges an earlier call marked, so it can't undo the 35-degree
    pass.)"""
    pk.select_only(obj)
    bpy.ops.object.shade_smooth(keep_sharp_edges=False)


pk.begin("PaintGlob", seed=4)

wet = pk.mat("PK_Wet")

root = pk.empty("PaintGlob")

HEAD_R = 0.14

# The teardrop is lathed around local Z, then rot (-90, 0, 0) lays local Z
# along +Y, so the profile's "up" becomes the glob's "forward".
# Profile points are (radius, distance along the flight line). 6 points x 10
# segments = 80 triangles, the same as a UV sphere 8 x 6, but rounder when
# seen from behind (which is how the shooter sees it).
body = pk.lathe("GlobBody", [
    (0.000, HEAD_R),            # nose (front pole of the head)
    (0.108, 0.089),             # head, about 40 degrees up
    (HEAD_R, 0.000),            # widest point, right on the origin
    (0.106, -0.098),            # shoulder, tapering back
    (0.040, -0.170),
    (0.000, -0.200),            # tail tip: total length 0.34 m
], rot=(-90, 0, 0), material=wet, segments=10)

# Two trailing droplets (icosahedra, 20 triangles each), slightly off the
# centre line so the trail looks thrown rather than machined.
drop_a = pk.ico("DropA", 0.030, loc=(0.008, -0.252, -0.006), scale=(1.0, 1.3, 1.0),
                material=wet, subdiv=1)
drop_b = pk.ico("DropB", 0.021, loc=(-0.006, -0.305, 0.004), scale=(1.0, 1.25, 1.0),
                material=wet, subdiv=1)

glob = pk.join("Glob", [body, drop_a, drop_b])
pk.apply(glob, location=False, rotation=True, scale=True)
pk.set_origin(glob, (0.0, 0.0, 0.0))
pk.parent(glob, root)

# 8 segments means 45 degrees between neighbouring faces, which the usual
# 35-degree rule would leave faceted. The glob is meant to look liquid, so it
# is smoothed completely instead of calling pk.smooth_all(35).
smooth_fully(glob)

pk.export("paint_glob.glb", budget=120)
