"""Make the generated basketball game-ready without losing its look.

Tripo returns a beautiful 1.9M-triangle, 55MB asset with 4K colour, ORM and
normal maps. None of that survives contact with a real-time frame budget, and at
the size a ball occupies on a broadcast camera none of it is visible either. The
detail is preserved where it actually reads - in the NORMAL and colour maps - and
thrown away where it does not, in raw geometry.
"""
import bpy, sys, os
def cli(n, d=None):
    a = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    return a[a.index(n)+1] if n in a else d

SRC = cli("--src"); OUT = cli("--out")
TARGET_TRIS = int(cli("--tris", "3000"))
TEX = int(cli("--tex", "2048"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
obj = next(o for o in bpy.data.objects if o.type == 'MESH')
before = sum((len(p.vertices)-2) for p in obj.data.polygons)

bpy.context.view_layer.objects.active = obj
obj.select_set(True)
dec = obj.modifiers.new("Decimate", 'DECIMATE')
dec.decimate_type = 'COLLAPSE'
dec.ratio = min(1.0, float(TARGET_TRIS) / float(before))
bpy.ops.object.modifier_apply(modifier=dec.name)
after = sum((len(p.vertices)-2) for p in obj.data.polygons)
bpy.ops.object.shade_smooth()
print("BALLOPT: %d -> %d tris (ratio %.5f)" % (before, after, dec.ratio))

for img in bpy.data.images:
    if img.size[0] > TEX:
        w, h = img.size
        img.scale(TEX, TEX)
        print("BALLOPT: texture %s %dx%d -> %dx%d" % (img.name, w, h, TEX, TEX))

obj.name = "Basketball"
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=True,
                          export_image_format='AUTO')
print("BALLOPT: exported %s (%.1f MB)" % (OUT, os.path.getsize(OUT)/1048576.0))