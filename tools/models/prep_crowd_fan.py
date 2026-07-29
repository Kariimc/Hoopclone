"""Prepare a generated spectator for the instanced crowd.

A generated model arrives with real geometry and a real texture but no idea which
part of it is a leg or an arm. The crowd's vertex shader needs that, so this tags
every vertex in a SECOND UV channel: X says which body part (0 legs, 1 torso,
2 arms, 3 head), Y says how far up that part the vertex sits, so bends pivot from
the right place. The tagging is purely geometric - height bands plus how far a
vertex sits from the body's centre line - which is all a seated figure needs.

It also decimates to a crowd budget and shrinks the textures. Seven hundred of
these are drawn at 20-40 metres; the source detail is invisible there and only
costs frames.
"""
import bpy, bmesh, sys, os
from mathutils import Vector

def cli(n, d=None):
    a = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    return a[a.index(n)+1] if n in a else d

SRC = cli("--src"); OUT = cli("--out")
TRIS = int(cli("--tris", "1400"))
TEX = int(cli("--tex", "512"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.context.view_layer.objects.active = meshes[0]
for o in meshes:
    o.select_set(True)
if len(meshes) > 1:
    bpy.ops.object.join()
obj = bpy.context.active_object
obj.name = "CrowdFan"

before = sum((len(p.vertices)-2) for p in obj.data.polygons)
if before > TRIS:
    dec = obj.modifiers.new("Decimate", 'DECIMATE')
    dec.decimate_type = 'COLLAPSE'
    dec.ratio = float(TRIS) / float(before)
    bpy.ops.object.modifier_apply(modifier=dec.name)
after = sum((len(p.vertices)-2) for p in obj.data.polygons)
print("FAN: %d -> %d tris" % (before, after))

# Stand the figure on the origin with its feet at zero, facing -Y, at a real
# seated height, so the crowd placement code can treat it like the old one.
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
lo = Vector((min(v.co.x for v in obj.data.vertices),
             min(v.co.y for v in obj.data.vertices),
             min(v.co.z for v in obj.data.vertices)))
hi = Vector((max(v.co.x for v in obj.data.vertices),
             max(v.co.y for v in obj.data.vertices),
             max(v.co.z for v in obj.data.vertices)))
size = hi - lo
mid_x = (lo.x + hi.x) * 0.5
mid_y = (lo.y + hi.y) * 0.5
print("FAN: raw bounds %.3f x %.3f x %.3f" % (size.x, size.y, size.z))

for v in obj.data.vertices:
    v.co.x -= mid_x
    v.co.y -= mid_y
    v.co.z -= lo.z

# Face the model FORWARD (-Y in Blender, which becomes -Z in Godot) before doing
# anything else. A generated model arrives pointing wherever the generator felt
# like, and the crowd placement code cannot know that - the first build seated
# 688 people sideways to the court.
#
# Found geometrically rather than guessed: a seated person's shins and feet stick
# out in front of the body, so the direction from the body's centre to the
# centroid of its LOWEST slice is forward.
import math
zs = [v.co.z for v in obj.data.vertices]
floor_cut = min(zs) + (max(zs) - min(zs)) * 0.18
low = [v.co for v in obj.data.vertices if v.co.z <= floor_cut]
if low:
    fx = sum(c.x for c in low) / len(low)
    fy = sum(c.y for c in low) / len(low)
    forward = Vector((fx, fy, 0.0))
    if forward.length > 1e-4:
        forward.normalize()
        # Rotate about Z so `forward` lands on -Y.
        yaw = math.atan2(forward.x, -forward.y)
        c, s = math.cos(-yaw), math.sin(-yaw)
        for v in obj.data.vertices:
            x, y = v.co.x, v.co.y
            v.co.x = x * c - y * s
            v.co.y = x * s + y * c
        print("FAN: forward was (%.3f, %.3f); rotated %.1f degrees to face -Y"
              % (forward.x, forward.y, math.degrees(-yaw)))
    else:
        print("FAN: could not read a forward direction; left unrotated")

# Bounds changed after rotating, so re-measure everything the tagging depends on.
lo = Vector((min(v.co.x for v in obj.data.vertices),
             min(v.co.y for v in obj.data.vertices),
             min(v.co.z for v in obj.data.vertices)))
hi = Vector((max(v.co.x for v in obj.data.vertices),
             max(v.co.y for v in obj.data.vertices),
             max(v.co.z for v in obj.data.vertices)))
size = hi - lo
height = size.z
half_w = max(1e-6, size.x * 0.5)

LEG_TOP = 0.42
HEAD_BOTTOM = 0.82
ARM_OUT = 0.55

bm = bmesh.new()
bm.from_mesh(obj.data)
uv2 = bm.loops.layers.uv.get("UV2") or bm.loops.layers.uv.new("UV2")

def put(item, value):
    if hasattr(item, "uv"):
        item.uv = value
    else:
        item[:] = value

counts = {0: 0, 1: 0, 2: 0, 3: 0}
for f in bm.faces:
    for l in f.loops:
        co = l.vert.co
        hz = co.z / height
        lateral = abs(co.x) / half_w
        if hz < LEG_TOP:
            part, up = 0.0, 0.0
        elif hz > HEAD_BOTTOM:
            part, up = 3.0, 1.0
        elif lateral > ARM_OUT:
            part, up = 2.0, (hz - LEG_TOP) / (HEAD_BOTTOM - LEG_TOP)
        else:
            part, up = 1.0, (hz - LEG_TOP) / (HEAD_BOTTOM - LEG_TOP)
        counts[int(part)] += 1
        put(l[uv2], (part, up))
bm.to_mesh(obj.data)
bm.free()
print("FAN: tagged loops legs=%d torso=%d arms=%d head=%d" % (counts[0], counts[1], counts[2], counts[3]))
print("FAN: uv layers %s" % [l.name for l in obj.data.uv_layers])

for img in bpy.data.images:
    if img.size[0] > TEX:
        w = img.size[0]
        img.scale(TEX, TEX)
        print("FAN: texture %s %d -> %d" % (img.name, w, TEX))

albedo_out = os.path.splitext(OUT)[0] + "_albedo.png"
saved = False
for mat in obj.data.materials:
    if mat and mat.node_tree:
        for n in mat.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image and "Color" in n.image.name:
                n.image.filepath_raw = albedo_out
                n.image.file_format = 'PNG'
                n.image.save()
                saved = True
                print("FAN: albedo written to %s" % albedo_out)
                break
if not saved:
    print("FAN: WARN no colour texture found to write out")

bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True,
                          export_apply=True, export_image_format='AUTO')
print("FAN: exported %s (%.2f MB)" % (OUT, os.path.getsize(OUT)/1048576.0))