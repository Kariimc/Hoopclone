"""Find faces that only break when the rig MOVES, and cut them.

Some broken geometry is invisible at rest: every edge is a normal length in the
bind pose, and only when a clip plays does one corner follow a distant bone and
the face stretch into a shard across the character. Measuring the rest mesh finds
nothing, and the skin weights measure clean, because the fault is a face whose
corners simply belong to different parts of the body.

So this poses the character through the real clips, evaluates the DEFORMED mesh
each sampled frame, and records any face that ever stretches past a sane limit.
Those face indices are then removed from the rest mesh and the model re-exported.

    blender --background --factory-startup --python cull_posed_strays.py -- \
        --src animated.glb --out clean.glb [--frames 12] [--max-frac 0.16] [--dry 1]
"""
import bpy, sys, os

def cli(n, d=None):
    a = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    return a[a.index(n)+1] if n in a else d

SRC = cli("--src"); OUT = cli("--out")
SAMPLES = int(cli("--frames", "12"))
MAX_RATIO = float(cli("--max-ratio", "6.0"))
DRY = cli("--dry", "0") == "1"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
scene = bpy.context.scene
obj = next(o for o in bpy.data.objects if o.type == 'MESH')
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')

# Judge a face by how much it STRETCHES, not by how long it gets.
#
# An absolute length limit cannot work: set it loose and the shard survives, set
# it tight and it eats the shorts hem and the hair, which are legitimately long
# faces. A broken face is one that is TINY at rest and enormous when posed - so
# measure each face against its own resting size and cull only the ones whose
# ratio is absurd.
rest_longest = {}
for poly in obj.data.polygons:
    vs = [obj.data.vertices[i].co for i in poly.vertices]
    rest_longest[poly.index] = max(
        (vs[i] - vs[(i + 1) % len(vs)]).length for i in range(len(vs)))
print("CULL: a face may stretch %.1fx its resting size before it counts as broken"
      % MAX_RATIO)

deps = bpy.context.evaluated_depsgraph_get()
bad = set()
actions = [a for a in bpy.data.actions]
print("CULL: sampling %d clips" % len(actions))

for act in actions:
    arm.animation_data_create()
    arm.animation_data.action = act
    lo, hi = act.frame_range
    for s in range(SAMPLES):
        f = lo + (hi - lo) * (float(s) / max(1, SAMPLES - 1))
        scene.frame_set(int(round(f)))
        deps = bpy.context.evaluated_depsgraph_get()
        ev = obj.evaluated_get(deps)
        me = ev.to_mesh()
        for poly in me.polygons:
            if poly.index in bad:
                continue
            vs = [me.vertices[i].co for i in poly.vertices]
            longest = 0.0
            for i in range(len(vs)):
                longest = max(longest, (vs[i] - vs[(i + 1) % len(vs)]).length)
            rest = rest_longest.get(poly.index, 0.0)
            if rest > 1e-6 and longest / rest > MAX_RATIO:
                bad.add(poly.index)
        ev.to_mesh_clear()
    print("CULL:   after %-24s %d broken faces found" % (act.name, len(bad)))

print("CULL: %d faces stretch when posed (%.2f%% of the mesh)"
      % (len(bad), 100.0 * len(bad) / max(1, len(obj.data.polygons))))

if DRY:
    print("CULL: dry run - nothing deleted")
else:
    import bmesh
    arm.animation_data.action = None
    scene.frame_set(int(scene.frame_start))
    bm = bmesh.new(); bm.from_mesh(obj.data); bm.faces.ensure_lookup_table()
    doomed = [bm.faces[i] for i in sorted(bad) if i < len(bm.faces)]
    bmesh.ops.delete(bm, geom=doomed, context='FACES')
    bm.to_mesh(obj.data); bm.free()
    print("CULL: mesh now %d polys" % len(obj.data.polygons))
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=False,
                              export_animations=True, export_animation_mode='ACTIONS',
                              export_image_format='AUTO')
    print("CULL: exported %s (%.1f MB)" % (OUT, os.path.getsize(OUT)/1048576.0))