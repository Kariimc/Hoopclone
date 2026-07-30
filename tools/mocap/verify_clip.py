"""Measure a retargeted clip against the human it came from.

Eyeballing a render tells you something is wrong; it does not tell you WHICH bone
or by how much. This compares the finished character, frame by frame, against the
motion-capture performer that drove it, and reports the angle between each pair of
corresponding bones.

That performer is a real person wearing markers, so agreement with them IS the
definition of natural motion here - there is no better reference available, and it
is objective rather than a matter of taste.

    blender --background --factory-startup --python verify_clip.py -- \
        --glb player_animated.glb --clip run --bvh 06_10.bvh --start 120 --end 360

Reads FAIL if any driven bone averages more than --tolerance degrees off.
"""
import bpy, math, os, sys
from mathutils import Vector

def cli(n, d=None):
    a = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    return a[a.index(n)+1] if n in a else d

ROOT = r"C:\Users\Kariim\Dev\hoopclone"
GLB = cli("--glb", os.path.join(ROOT, "assets", "models", "player_animated.glb"))
CLIP = cli("--clip", "run")
BVH = cli("--bvh", os.path.join(ROOT, "assets", "mocap", "06_10.bvh"))
START = int(cli("--start", "120"))
END = int(cli("--end", "360"))
STEP = int(cli("--step", "4"))
TOL = float(cli("--tolerance", "25"))

# Only bones the retarget actually drives. Neck, head and collarbones are
# deliberately left at rest, so measuring them would report a failure for a
# decision that was made on purpose.
PAIRS = [
    ("LowerBack", "Spine02"), ("Spine", "Spine01"), ("Spine1", "Spine"),
    ("LeftArm", "LeftArm"), ("LeftForeArm", "LeftForeArm"),
    ("RightArm", "RightArm"), ("RightForeArm", "RightForeArm"),
    ("LeftUpLeg", "LeftUpLeg"), ("LeftLeg", "LeftLeg"), ("LeftFoot", "LeftFoot"),
    ("RightUpLeg", "RightUpLeg"), ("RightLeg", "RightLeg"), ("RightFoot", "RightFoot"),
]

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=GLB)
tgt = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
act = None
for a in bpy.data.actions:
    if a.name == CLIP or a.name.endswith(CLIP):
        act = a
        break
if act is None:
    raise SystemExit("VERIFY: no clip '%s' in %s (have %s)"
                     % (CLIP, os.path.basename(GLB), [a.name for a in bpy.data.actions]))
tgt.animation_data_create()
tgt.animation_data.action = act

bpy.ops.import_anim.bvh(filepath=BVH, global_scale=1.0, use_fps_scale=False,
                        update_scene_fps=False, update_scene_duration=True)
src = next(o for o in bpy.data.objects if o.type == 'ARMATURE' and o is not tgt)

def world_dir(ob, pb):
    v = ob.matrix_world.to_3x3() @ (pb.matrix.to_3x3() @ Vector((0, 1, 0)))
    return v.normalized() if v.length > 1e-8 else Vector((0, 1, 0))


def rest_rotations(ob):
    """Each bone's resting ORIENTATION in world space, taken from matrix_local.

    Not from tail minus head: this rig's tail data is garbage - bones report
    lengths of thousands of units on a body 170 units tall - and a metric built on
    it already sent one investigation down the wrong road for hours. matrix_local
    is the bind orientation and is reliable."""
    out = {}
    for b in ob.data.bones:
        out[b.name] = (ob.matrix_world.to_3x3() @ b.matrix_local.to_3x3()).to_quaternion()
    return out


def world_rot(ob, pb):
    return (ob.matrix_world.to_3x3() @ pb.matrix.to_3x3()).to_quaternion()

SRC_REST = rest_rotations(src)
TGT_REST = rest_rotations(tgt)

# The character's own frames run 1..N while the source runs START..END; walk both.
last = min(END, scene.frame_end)
source_frames = list(range(max(1, START), last + 1, STEP))
totals = {}
worst = {}

for i, sf in enumerate(source_frames):
    out_frame = i + 1
    if out_frame > int(act.frame_range[1]):
        break
    scene.frame_set(sf)
    src_swing = {}
    for s_name, _ in PAIRS:
        pb = src.pose.bones.get(s_name)
        if pb is not None and s_name in SRC_REST:
            # How far this joint has rotated from its own bind pose.
            src_swing[s_name] = world_rot(src, pb) @ SRC_REST[s_name].inverted()

    scene.frame_set(out_frame)
    for s_name, t_name in PAIRS:
        s_swing = src_swing.get(s_name)
        tpb = tgt.pose.bones.get(t_name)
        if s_swing is None or tpb is None or t_name not in TGT_REST:
            continue
        t_swing = world_rot(tgt, tpb) @ TGT_REST[t_name].inverted()
        # Angle between the two swings: how differently the character moved that
        # joint compared with the performer.
        deg = math.degrees((s_swing.inverted() @ t_swing).angle)
        if deg > 180.0:
            deg = 360.0 - deg
        totals.setdefault(t_name, []).append(deg)
        if deg > worst.get(t_name, 0.0):
            worst[t_name] = deg

print("VERIFY: clip '%s' against %s, %d frames compared"
      % (CLIP, os.path.basename(BVH), len(source_frames)))
fails = []
for _, t_name in PAIRS:
    vals = totals.get(t_name)
    if not vals:
        continue
    mean = sum(vals) / len(vals)
    flag = "  <-- OFF" if mean > TOL else ""
    if mean > TOL:
        fails.append((t_name, mean))
    print("VERIFY:   %-14s mean %5.1f deg   worst %5.1f deg%s"
          % (t_name, mean, worst.get(t_name, 0.0), flag))

if fails:
    print("VERIFY: FAIL - %d bone(s) average more than %.0f degrees from the performer: %s"
          % (len(fails), TOL, ", ".join("%s %.0f" % f for f in fails)))
else:
    print("VERIFY: PASS - every driven bone tracks the performer within %.0f degrees" % TOL)