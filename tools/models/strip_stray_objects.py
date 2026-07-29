"""Strip anything from a model file that is not the character.

A stray 2-metre Icosphere with no material and no parent was riding inside the
player. Standing still it was hidden inside him; the moment he moved it showed as
a huge blade sweeping across the body - the "unnatural mesh" that survived five
separate attempts to fix it as a skinning problem, because it was never part of
the skin at all.

Keeps the armature and only the meshes actually bound to it. Everything else
goes.
"""
import bpy, sys, os
def cli(n, d=None):
    a = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    return a[a.index(n)+1] if n in a else d

SRC = cli("--src"); OUT = cli("--out")
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

arm = next((o for o in bpy.data.objects if o.type == 'ARMATURE'), None)
keep = set()
if arm:
    keep.add(arm.name)
for o in bpy.data.objects:
    if o.type != 'MESH':
        continue
    bound = any(m.type == 'ARMATURE' and m.object == arm for m in o.modifiers)
    if bound or (arm is not None and o.parent == arm and o.vertex_groups):
        keep.add(o.name)

removed = []
for o in list(bpy.data.objects):
    if o.name not in keep and o.type in ('MESH', 'EMPTY', 'CURVE', 'LIGHT', 'CAMERA'):
        removed.append("%s (%s%s)" % (o.name, o.type,
            ", %d polys" % len(o.data.polygons) if o.type == 'MESH' else ""))
        bpy.data.objects.remove(o, do_unlink=True)

print("STRIP: kept %s" % sorted(keep))
print("STRIP: removed %d stray objects: %s" % (len(removed), "; ".join(removed) or "none"))

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=False,
                          export_animations=True, export_animation_mode='ACTIONS',
                          export_image_format='AUTO')
print("STRIP: exported %s (%.1f MB)" % (OUT, os.path.getsize(OUT)/1048576.0))