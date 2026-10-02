"""
PaintKit - shared helpers for the Blender asset scripts in tools/blender/.

Every create_*.py script in this folder builds ONE game asset out of code,
then exports it as a .glb file (a 3D model format Godot loads directly) into
models/generated/. Nothing is modelled by hand, so re-running a script always
produces the same model, and changing a model means changing numbers in a
script rather than pushing vertices around.

HOW TO RUN ONE SCRIPT (from the project folder):

    blender -b --factory-startup --python tools/blender/create_paint_blaster.py

    -b                 run Blender without opening its window ("background")
    --factory-startup  ignore any personal Blender settings, so every machine
                       builds the same thing
    --python FILE      run this script, then quit

Optional arguments go after a bare "--":

    ... -- --out some/other/place.glb     export somewhere else
    ... -- --preview sheet.png            also render a 4-view contact sheet

To rebuild everything: tools/blender/build_all.sh

CONVENTIONS (shared with docs/VISUAL_OVERHAUL_PLAN.md section 3):
  * Units are metres.
  * Blender is Z-up. The glTF exporter turns Blender -Y into Godot +Z. Enemies
    and runners face Godot +Z, so they are built FACING BLENDER -Y. The
    first-person weapon points down Godot -Z, so it is built pointing
    BLENDER +Y.
  * Materials are named by ROLE (PK_Accent, PK_Team, PK_Fill...), not by
    colour. Godot swaps the gameplay-coloured roles for its own materials at
    runtime, so pair and team colours stay defined in the game code.
  * Moving parts are separate objects whose origin sits on their pivot.
"""

import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(REPO, "models", "generated")

_collection = None


# ---------------------------------------------------------------------------
# Arguments and scene
# ---------------------------------------------------------------------------

def args():
    """Options passed after '--': --out PATH, --preview PATH."""
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"out": None, "preview": None}
    i = 0
    while i < len(argv):
        key = argv[i].lstrip("-")
        if key in opts and i + 1 < len(argv):
            opts[key] = argv[i + 1]
            i += 2
        else:
            i += 1
    return opts


def begin(asset_name, seed=1):
    """Start from an empty scene with one working collection for this asset.

    read_factory_settings(use_empty=True) throws away the default cube, camera
    and light, so nothing from a previous run or a user's startup file can end
    up in the export. The fixed random seed makes 'random' details (bristle
    tilt, paint splotches) identical on every run.
    """
    global _collection
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(seed)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    _collection = bpy.data.collections.new(asset_name)
    scene.collection.children.link(_collection)
    layer = bpy.context.view_layer.layer_collection.children[asset_name]
    bpy.context.view_layer.active_layer_collection = layer
    return _collection


def objects():
    return list(_collection.all_objects)


# ---------------------------------------------------------------------------
# Colour and materials
# ---------------------------------------------------------------------------

def linear(hex_colour, alpha=1.0):
    """'#RRGGBB' (what art tools show, sRGB) -> the linear RGBA Blender's
    shader inputs expect. Without this, every colour exports too bright."""
    h = hex_colour.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], alpha)


## Default look for each material role. Godot overrides the gameplay-coloured
## ones (Accent, Team, Fill, Wet, AccentGlow, TeamGlow) at runtime; the rest are
## used as exported. Values follow the material table in the plan (section 2.3).
PRESETS = {
    "PK_Body":       dict(color="#F2EEE6", roughness=0.45),
    "PK_Shell":      dict(color="#DCE3E6", roughness=0.6),
    "PK_Trim":       dict(color="#3A3D52", roughness=0.4, metallic=0.35),
    "PK_Metal":      dict(color="#B7B2C6", roughness=0.32, metallic=0.65),
    "PK_Brass":      dict(color="#C9A45C", roughness=0.3, metallic=0.75),
    "PK_Rubber":     dict(color="#2A2C3A", roughness=0.9),
    "PK_Canvas":     dict(color="#E9E1D2", roughness=0.95),
    "PK_Dark":       dict(color="#1B1D2B", roughness=0.6),
    "PK_Wood":       dict(color="#A87552", roughness=0.8),
    "PK_Glass":      dict(color="#E6F4FF", roughness=0.06, alpha=0.32),
    "PK_Accent":     dict(color="#FFB7C5", roughness=0.35),
    "PK_AccentGlow": dict(color="#FFB7C5", roughness=0.3, emission=1.4),
    "PK_Fill":       dict(color="#FFB7C5", roughness=0.15, emission=0.6),
    "PK_Wet":        dict(color="#FFB7C5", roughness=0.1),
    "PK_Team":       dict(color="#58D7F2", roughness=0.4),
    "PK_TeamGlow":   dict(color="#58D7F2", roughness=0.3, emission=1.2),
    "PK_Dry1":       dict(color="#C9A45C", roughness=0.85),   # ochre
    "PK_Dry2":       dict(color="#9C8FC4", roughness=0.85),   # lilac
    "PK_Dry3":       dict(color="#B7806E", roughness=0.85),   # clay
    "PK_Dry4":       dict(color="#7FA9A3", roughness=0.85),   # sea-glass
}


def mat(role, name=None, **overrides):
    """Get (or create once) the material for a role.

    `name` lets a script make a second material in the same role family with
    its own look, e.g. mat("PK_Body", name="PK_Plaster", color="#E3DCD0").
    Other overrides: roughness, metallic, emission, alpha, double_sided.
    """
    mat_name = name or role
    existing = bpy.data.materials.get(mat_name)
    if existing is not None:
        return existing
    spec = dict(PRESETS.get(role, PRESETS["PK_Body"]))
    spec.update(overrides)
    material = bpy.data.materials.new(mat_name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    colour = linear(spec["color"])
    bsdf.inputs["Base Color"].default_value = colour
    bsdf.inputs["Roughness"].default_value = spec.get("roughness", 0.5)
    bsdf.inputs["Metallic"].default_value = spec.get("metallic", 0.0)
    if spec.get("emission", 0.0) > 0.0:
        bsdf.inputs["Emission Color"].default_value = colour
        bsdf.inputs["Emission Strength"].default_value = spec["emission"]
    alpha = spec.get("alpha", 1.0)
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        # BLENDED tells the glTF exporter to mark this material alphaMode=BLEND.
        material.surface_render_method = "BLENDED"
    material.diffuse_color = colour  # the viewport/solid colour, for previews
    # Back-face culling ON unless asked otherwise. Without it the glTF exporter
    # marks every material doubleSided, and Godot then draws the inside faces
    # of every closed part too - wasted work, twenty characters at a time.
    # Pass double_sided=True only for a genuinely one-sided sheet that can be
    # seen from both sides.
    material.use_backface_culling = not spec.get("double_sided", False)
    return material


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------

def _rad(rotation_degrees):
    return tuple(math.radians(a) for a in rotation_degrees)


def _adopt(name, material, parent_obj):
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    if material is not None:
        obj.data.materials.clear()
        obj.data.materials.append(material)
    if parent_obj is not None:
        parent(obj, parent_obj)
    return obj


def _bevel(obj, width, segments):
    if width <= 0.0:
        return
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    # Only bevel genuinely sharp edges, so curved surfaces are left alone.
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(40)
    mod.harden_normals = False


def box(name, size, loc=(0, 0, 0), rot=(0, 0, 0), material=None, bevel=0.0,
        segments=2, parent_obj=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=_rad(rot))
    obj = _adopt(name, material, parent_obj)
    obj.scale = size
    apply(obj, location=False, rotation=False, scale=True)
    _bevel(obj, bevel, segments)
    return obj


def cyl(name, radius, depth, loc=(0, 0, 0), rot=(0, 0, 0), material=None,
        verts=16, radius_top=None, bevel=0.0, segments=2, parent_obj=None):
    """A cylinder along its local Z. Give radius_top for a cone/taper."""
    if radius_top is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth,
                                            location=loc, rotation=_rad(rot))
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=radius_top,
                                        depth=depth, location=loc, rotation=_rad(rot))
    obj = _adopt(name, material, parent_obj)
    _bevel(obj, bevel, segments)
    return obj


def sphere(name, radius, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), material=None,
           segments=16, rings=8, parent_obj=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius,
                                         location=loc, rotation=_rad(rot))
    obj = _adopt(name, material, parent_obj)
    obj.scale = scale
    apply(obj, location=False, rotation=False, scale=True)
    return obj


def ico(name, radius, loc=(0, 0, 0), scale=(1, 1, 1), material=None, subdiv=2,
        parent_obj=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=loc)
    obj = _adopt(name, material, parent_obj)
    obj.scale = scale
    apply(obj, location=False, rotation=False, scale=True)
    return obj


def torus(name, major, minor, loc=(0, 0, 0), rot=(0, 0, 0), material=None,
          segments=24, ring_segments=8, parent_obj=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=segments, minor_segments=ring_segments,
                                     location=loc, rotation=_rad(rot))
    return _adopt(name, material, parent_obj)


def lathe(name, profile, loc=(0, 0, 0), rot=(0, 0, 0), material=None, segments=24,
          parent_obj=None):
    """Spin a profile of (radius, height) points around the local Z axis, like
    a pot on a potter's wheel. Start and/or end the profile at radius 0 to
    close the top/bottom."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    verts = [bm.verts.new((r, 0.0, z)) for r, z in profile]
    edges = [bm.edges.new((verts[i], verts[i + 1])) for i in range(len(verts) - 1)]
    bmesh.ops.spin(bm, geom=verts + edges, cent=(0, 0, 0), axis=(0, 0, 1),
                   angle=math.tau, steps=segments, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    _collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = _rad(rot)
    if material is not None:
        mesh.materials.append(material)
    if parent_obj is not None:
        parent(obj, parent_obj)
    return obj


def prism(name, points, depth, loc=(0, 0, 0), rot=(0, 0, 0), material=None, bevel=0.0,
          segments=2, parent_obj=None):
    """Extrude a flat outline (x, y points, counter-clockwise) upward by
    `depth` along local Z, centred on Z. Good for grips, palettes, fins."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bottom = [bm.verts.new((x, y, -depth * 0.5)) for x, y in points]
    face = bm.faces.new(bottom)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    top = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=top, vec=(0, 0, depth))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    _collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = _rad(rot)
    if material is not None:
        mesh.materials.append(material)
    _bevel(obj, bevel, segments)
    if parent_obj is not None:
        parent(obj, parent_obj)
    return obj


def tube(name, points, radius, material=None, resolution=3, smooth_path=True,
         path_resolution=6, parent_obj=None):
    """A round tube following a path of (x, y, z) points - hoses, pipes,
    springs. Built as a curve, then converted to a mesh so it exports."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = resolution
    curve.use_fill_caps = True
    spline = curve.splines.new("NURBS" if smooth_path else "POLY")
    spline.points.add(len(points) - 1)
    for p, co in zip(spline.points, points):
        p.co = (co[0], co[1], co[2], 1.0)
    if smooth_path:
        spline.use_endpoint_u = True
        spline.order_u = min(4, len(points))
    spline.resolution_u = path_resolution
    obj = bpy.data.objects.new(name, curve)
    _collection.objects.link(obj)
    select_only(obj)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    if material is not None:
        obj.data.materials.clear()
        obj.data.materials.append(material)
    if parent_obj is not None:
        parent(obj, parent_obj)
    return obj


def helix(radius, height, turns, points_per_turn=10, z0=0.0):
    """Points along a coil spring, for tube()."""
    total = int(turns * points_per_turn) + 1
    return [(radius * math.cos(math.tau * turns * i / (total - 1)),
             radius * math.sin(math.tau * turns * i / (total - 1)),
             z0 + height * i / (total - 1)) for i in range(total)]


def empty(name, loc=(0, 0, 0), rot=(0, 0, 0), parent_obj=None):
    """An invisible marker node: a pivot, socket or root. Exported to Godot
    as a plain Node3D with the same name."""
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = 0.1
    _collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = _rad(rot)
    if parent_obj is not None:
        parent(obj, parent_obj)
    return obj


# ---------------------------------------------------------------------------
# Object housekeeping
# ---------------------------------------------------------------------------

def select_only(*objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def apply(obj, location=False, rotation=True, scale=True):
    """Bake the object's transform into its mesh, so the node exports with a
    clean transform. Scale is always baked: Godot must never see a squashed
    node (and Jolt physics refuses non-uniform scale on bodies)."""
    select_only(obj)
    bpy.ops.object.transform_apply(location=location, rotation=rotation, scale=scale)


def parent(child, parent_obj):
    """Attach child to parent without moving it."""
    # matrix_world is only recalculated when the scene updates. Objects whose
    # location/rotation were just set in Python still report the OLD matrix
    # until then, so refresh first or the child silently loses its rotation.
    bpy.context.view_layer.update()
    world = child.matrix_world.copy()
    child.parent = parent_obj
    child.matrix_parent_inverse = parent_obj.matrix_world.inverted()
    child.matrix_world = world


def set_origin(obj, point):
    """Move an object's origin (its pivot) to a world-space point without
    moving the mesh. Used for legs (pivot at the hip), strips (top edge)..."""
    bpy.context.view_layer.update()
    point = Vector(point)
    delta = obj.matrix_world.inverted() @ point
    obj.data.transform(Matrix.Translation(-delta))
    obj.matrix_world = obj.matrix_world @ Matrix.Translation(delta)


def join(name, parts):
    """Merge several meshes into one object (fewer nodes, fewer draw calls).
    Modifiers are applied first so each part keeps its bevel.

    The joined object keeps the FIRST part's transform. If that part is
    rotated, bake it first (apply(part, location=True)) before editing the
    joined mesh's vertices, or the edits happen in a tilted frame."""
    for p in parts:
        select_only(p)
        for mod in list(p.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    select_only(*parts)
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    return obj


def merge_all(name="Static"):
    """Join EVERY mesh in the asset into one object named `name`, parented to
    the asset's root empty. For things that never animate (props, the bot's
    copy of the blaster): one node instead of dozens means Godot has far fewer
    nodes to move each frame and far fewer draw calls. Parts that share a
    material become one surface. Call after smoothing, before export."""
    meshes = [o for o in objects() if o.type == "MESH"]
    roots = [o for o in objects() if o.parent is None and o.type == "EMPTY"]
    if not meshes:
        return None
    # Detach first so joining cannot orphan or move anything.
    for o in meshes:
        world = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = world
    for o in meshes:
        apply(o, location=True, rotation=True, scale=True)
    merged = join(name, meshes) if len(meshes) > 1 else meshes[0]
    merged.name = name
    merged.data.name = name
    # Drop any empties left over from the parts (they no longer hold anything),
    # except the root.
    for o in objects():
        if o.type == "EMPTY" and o not in roots and not o.children:
            bpy.data.objects.remove(o)
    if roots:
        parent(merged, roots[0])
    return merged


def remap_materials(obj, mapping):
    """Swap an object's materials by name ({"PK_Brass": material, ...}) and
    merge slots that end up with the same material, so each material is one
    surface (one draw call) in Godot."""
    targets = []
    index_map = []
    for slot in obj.material_slots:
        target = mapping.get(slot.material.name, slot.material) if slot.material else None
        if target not in targets:
            targets.append(target)
        index_map.append(targets.index(target))
    # Read every face's new slot BEFORE touching the list: clearing a mesh's
    # materials also resets every face to slot 0.
    new_indices = [index_map[poly.material_index] for poly in obj.data.polygons]
    obj.data.materials.clear()
    for target in targets:
        obj.data.materials.append(target)
    for poly, index in zip(obj.data.polygons, new_indices):
        poly.material_index = index


def smooth(obj, angle=35.0):
    """Smooth shading, but keep edges sharper than `angle` crisp.

    Note: Blender 5 keeps edges that are ALREADY marked sharp, so calling this
    again with a bigger angle does not soften them. To fully smooth a part
    after smooth_all(), use bpy.ops.object.shade_smooth(keep_sharp_edges=False)."""
    if obj.type != "MESH":
        return
    select_only(obj)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))


def smooth_all(angle=35.0):
    for obj in objects():
        smooth(obj, angle)


def displace_random(obj, amount, seed=0):
    """Nudge every vertex a little, for hand-made looking lumps and folds."""
    rng = random.Random(seed)
    for v in obj.data.vertices:
        v.co += Vector((rng.uniform(-amount, amount), rng.uniform(-amount, amount),
                        rng.uniform(-amount, amount)))


# ---------------------------------------------------------------------------
# Checking and exporting
# ---------------------------------------------------------------------------

def triangle_count(objs=None):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    total = 0
    per = {}
    for obj in objs or objects():
        if obj.type != "MESH":
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        per[obj.name] = len(mesh.loop_triangles)
        total += per[obj.name]
        evaluated.to_mesh_clear()
    return total, per


def export(asset_file, budget):
    """Check the triangle budget, then export the working collection as GLB.

    Fails loudly (non-zero exit) if the model is over budget, so an overweight
    model can never slip into the game unnoticed."""
    opts = args()
    out = opts["out"] or os.path.join(OUT_DIR, asset_file)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    total, per = triangle_count()
    print("[paintkit] %s: %d triangles (budget %d)" % (asset_file, total, budget))
    for name, count in sorted(per.items(), key=lambda kv: -kv[1]):
        print("[paintkit]    %-24s %d" % (name, count))
    if total > budget:
        print("[paintkit] ERROR: over budget")
        sys.exit(1)
    select_only(*objects())
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        use_selection=True,
        export_apply=True,      # bake modifiers (bevels) into the exported mesh
        export_yup=True,        # Godot is Y-up
        export_cameras=False,
        export_lights=False,
        export_materials="EXPORT",
        export_extras=False,
    )
    print("[paintkit] wrote %s" % os.path.relpath(out, REPO))
    if opts["preview"]:
        preview(opts["preview"])
    return out


def preview(png_path, size=360):
    """Render a 2x2 contact sheet (front, right side, back, 3/4) with Cycles
    on the CPU, so a model can be checked without opening Blender or Godot.
    'Front' is Blender -Y, the side enemies face."""
    import numpy as np
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = linear("#8C889E")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world

    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for obj in objects():
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            mins = Vector(map(min, mins, w))
            maxs = Vector(map(max, maxs, w))
    centre = (mins + maxs) * 0.5
    extent = max((maxs - mins).length, 0.1)

    sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = _rad((50, 10, -35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = extent * 1.08
    scene.collection.objects.link(cam)
    scene.camera = cam

    views = [(-90, 0), (0, 0), (90, 0), (-45, 25)]   # (azimuth, elevation) degrees
    tiles = []
    # Unique per process: several scripts may preview into one folder at once.
    tmp = os.path.join(os.path.dirname(os.path.abspath(png_path)),
                       "_pk_tile_%d.png" % os.getpid())
    for azimuth, elevation in views:
        az, el = math.radians(azimuth), math.radians(elevation)
        direction = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
        cam.location = centre + direction * extent * 2.0
        cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(size, size, 4)
        tiles.append(px)
        bpy.data.images.remove(img)
    top = np.concatenate([tiles[0], tiles[1]], axis=1)
    bottom = np.concatenate([tiles[2], tiles[3]], axis=1)
    sheet = np.concatenate([bottom, top], axis=0)   # Blender pixels run bottom-up
    out = bpy.data.images.new("sheet", size * 2, size * 2, alpha=True)
    out.pixels = sheet.flatten().tolist()
    out.filepath_raw = png_path
    out.file_format = "PNG"
    out.save()
    os.remove(tmp)
    print("[paintkit] preview %s" % png_path)
