"""Repair skin weights that drag geometry across the body when the rig moves.

Symptom: the model is perfect standing still, but the moment a clip plays a long
shard of jersey stretches off one hand.

Why the obvious checks miss it. The faces are all normal-sized at rest, so
measuring the rest mesh finds nothing. And each vertex's DOMINANT bone is
correct, so a dominant-only weight check reports a clean mesh. The fault is a
minor influence: a shorts vertex carrying a small weight to a HAND bone. It is
too weak to change the vertex's home, and more than strong enough to drag it
halfway across the character when that hand moves.

So this checks EVERY influence on every vertex. Any influence above MIN_WEIGHT
bound to a bone further away than MAX_FRAC of the body's height is wrong: it gets
removed and the rest renormalised. A vertex is never left with no influence at
all - if every one of them looks wrong it is rebound to the nearest bone.

    blender --background --factory-startup --python fix_weights.py -- \
        --src in.glb --out out.glb [--max-frac 0.13] [--min-weight 0.02] [--dry 1]
"""
import bpy, sys, os

def cli(n, d=None):
    a = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    return a[a.index(n)+1] if n in a else d

SRC = cli("--src"); OUT = cli("--out")
MAX_FRAC = float(cli("--max-frac", "0.13"))
MIN_WEIGHT = float(cli("--min-weight", "0.02"))
DRY = cli("--dry", "0") == "1"
# Which bones may have their stray influences cut. Restricting this matters: the
# long hair is legitimately bound to a SHOULDER far from its tips, and cutting
# that would ruin it. Hands and feet are extremities - a vertex on the far side
# of the body has no business following one, so those are always safe to strip.
ONLY = [s for s in (cli("--bones", "LeftHand,RightHand,LeftFoot,RightFoot") or "").split(",") if s]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
obj = next(o for o in bpy.data.objects if o.type == 'MESH')
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')

to_mesh = obj.matrix_world.inverted() @ arm.matrix_world
bones = []
for b in arm.data.bones:
    bones.append((b.name, to_mesh @ b.head_local, to_mesh @ b.tail_local))

def dist_to_bone(co, head, tail):
    """Distance from a vertex to a JOINT, not to a bone's length.

    Measuring to the segment head->tail is the textbook approach and it is wrong
    on this rig: its tail data is garbage (bones report lengths of 2,000-3,000
    units on a 170-unit body), so every bone reads as an enormous rod passing
    near everything and every vertex measures "close". That is why five passes
    of this check reported a clean mesh while the shorts were visibly bound to a
    hand. The joint position is trustworthy; the tail is not."""
    return (co - head).length

group_index = {g.name: g.index for g in obj.vertex_groups}
index_name = {g.index: g.name for g in obj.vertex_groups}
bone_by_group = {}
for g in obj.vertex_groups:
    entry = next((b for b in bones if b[0] == g.name), None)
    if entry is not None:
        bone_by_group[g.index] = entry

# The threshold has to be RELATIVE. This mesh's units are not metres - the body
# is 170 units tall - so any hard-coded distance is meaningless.
zs = [v.co.z for v in obj.data.vertices]
body_h = max(zs) - min(zs)
MAX_DIST = body_h * MAX_FRAC
print("WEIGHTS: body height %.1f units -> an influence beyond %.1f is wrong"
      % (body_h, MAX_DIST))

touched = 0
cut = 0
rebound = 0
worst = 0.0
report = {}

for v in obj.data.vertices:
    if not v.groups:
        continue
    wrong = []
    for g in v.groups:
        if g.weight < MIN_WEIGHT:
            continue
        entry = bone_by_group.get(g.group)
        if entry is None:
            continue
        d = dist_to_bone(v.co, entry[1], entry[2])
        if d > MAX_DIST and (not ONLY or entry[0] in ONLY):
            wrong.append((g.group, entry[0], d))
    if not wrong:
        continue

    touched += 1
    strong = [g for g in v.groups if g.weight >= MIN_WEIGHT]
    if len(wrong) >= len(strong):
        nearest = min(bones, key=lambda b: dist_to_bone(v.co, b[1], b[2]))
        report["-> " + nearest[0]] = report.get("-> " + nearest[0], 0) + 1
        rebound += 1
        if not DRY:
            for g in list(v.groups):
                nm = index_name.get(g.group)
                if nm in group_index:
                    obj.vertex_groups[group_index[nm]].remove([v.index])
            obj.vertex_groups[group_index[nearest[0]]].add([v.index], 1.0, 'REPLACE')
        continue

    for gi, bone_name, d in wrong:
        report[bone_name] = report.get(bone_name, 0) + 1
        worst = max(worst, d)
        cut += 1
        if not DRY:
            nm = index_name.get(gi)
            if nm in group_index:
                obj.vertex_groups[group_index[nm]].remove([v.index])

print("WEIGHTS: %d vertices affected - %d stray influences cut, %d rebound (worst %.1f)"
      % (touched, cut, rebound, worst))
for name, n in sorted(report.items(), key=lambda kv: -kv[1])[:10]:
    print("WEIGHTS:   %-22s %d" % (name, n))

if DRY:
    print("WEIGHTS: dry run - nothing changed")
else:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=False,
                              export_animations=True, export_animation_mode='ACTIONS',
                              export_image_format='AUTO')
    print("WEIGHTS: exported %s (%.1f MB)" % (OUT, os.path.getsize(OUT)/1048576.0))