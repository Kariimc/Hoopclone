"""Build the player's whole moveset into ONE glTF, in one pass.

    blender --background --factory-startup --python build_moveset.py -- --glb out.glb

Each entry below is a slice of a Carnegie Mellon basketball capture retargeted
onto the player rig as its own named clip. Godot imports the result as an
AnimationPlayer holding every clip by name, which is what the state machine
drives.

The retarget maths is identical to retarget_bvh.py and deliberately duplicated
nowhere: this file imports it. Read that file for why bones are aimed by writing
their matrix rather than by composing rotations.
"""
import bpy, os, sys, importlib.util
from mathutils import Vector, Quaternion

def cli(n, d=None):
    a = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    return a[a.index(n)+1] if n in a else d

ROOT = r"C:\Users\Kariim\Dev\hoopclone"
SRC  = cli("--src", os.path.join(ROOT, "assets", "models", "player_noball.glb"))
GLB  = cli("--glb", os.path.join(ROOT, "assets", "models", "player_animated.glb"))
MOCAP = os.path.join(ROOT, "assets", "mocap")

# clip name -> (bvh trial, first frame, last frame, keep every Nth frame)
# Trials: 06_02..05 forward dribble, 06_06..07 backward, 06_08..09 sideways,
# 06_10..12 dribble with turns, 06_13 freestyle, 06_14..15 crossover + shoot.
CLIPS = [
    ("idle",     "06_01.bvh", 100, 340, 4),
    ("dribble",  "06_02.bvh", 200, 440, 4),
    ("run",      "06_10.bvh", 120, 360, 4),
    ("crossover","06_13.bvh", 400, 640, 4),
    ("jumpshot", "06_14.bvh", 240, 480, 4),
]

MAP = {
    "LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg",
    "RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg",
    "LowerBack": "Spine02", "Spine": "Spine01", "Spine1": "Spine",
    "Neck1": "neck", "Head": "Head",
    "LeftArm": "LeftArm", "LeftForeArm": "LeftForeArm", "LeftHand": "LeftHand",
    "RightArm": "RightArm", "RightForeArm": "RightForeArm", "RightHand": "RightHand",
}
ORDER = ["LowerBack", "Spine", "Spine1", "Neck1", "Head",
         "LeftArm", "LeftForeArm", "LeftHand",
         "RightArm", "RightForeArm", "RightHand",
         "LeftUpLeg", "LeftLeg",
         "RightUpLeg", "RightLeg"]
# Feet and toes are deliberately NOT retargeted, for the same reason as the
# collarbones: the two skeletons hold them at completely different rest angles,
# and aiming them by direction threw the foot 57 units out from the body - the
# stretched shoe read as a long blade sweeping across the player and survived
# five separate attempts to fix it as a mesh or skinning fault. Left at rest the
# ankle stays neutral while the shin carries the motion, which reads correctly at
# any distance the camera actually uses.

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=SRC)
tgt = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
tgt.name = "PlayerRig"
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)

def world_dir(ob, pb):
    v = ob.matrix_world.to_3x3() @ (pb.matrix.to_3x3() @ Vector((0, 1, 0)))
    return v.normalized() if v.length > 1e-8 else Vector((0, 1, 0))

made = []
for clip, bvh, start, end, step in CLIPS:
    path = os.path.join(MOCAP, bvh)
    if not os.path.exists(path):
        print("MOVESET: WARN missing %s, skipping %s" % (bvh, clip))
        continue

    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.import_anim.bvh(filepath=path, global_scale=1.0, use_fps_scale=False,
                            update_scene_fps=False, update_scene_duration=True)
    src = next(o for o in bpy.data.objects if o.type == 'ARMATURE' and o is not tgt)

    last = min(end, scene.frame_end)
    bpy.context.view_layer.objects.active = tgt
    bpy.ops.object.mode_set(mode='POSE')
    for pb in tgt.pose.bones:
        pb.rotation_mode = 'QUATERNION'

    act = bpy.data.actions.new(clip)
    tgt.animation_data_create()
    tgt.animation_data.action = act

    out_frame = 0
    for f in range(max(1, start), last + 1, step):
        scene.frame_set(f)
        out_frame += 1
        for pb in tgt.pose.bones:
            pb.rotation_quaternion = Quaternion()
            pb.location = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()

        for src_name in ORDER:
            dst_name = MAP.get(src_name)
            spb = src.pose.bones.get(src_name)
            dpb = tgt.pose.bones.get(dst_name) if dst_name else None
            if spb is None or dpb is None:
                continue
            target = (tgt.matrix_world.inverted().to_3x3() @ world_dir(src, spb)).normalized()
            m = dpb.matrix.copy()
            cur = (m.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
            rotated = (cur.rotation_difference(target).to_matrix() @ m.to_3x3()).to_4x4()
            rotated.translation = m.to_translation()
            dpb.matrix = rotated
            bpy.context.view_layer.update()

        for pb in tgt.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=out_frame)

    act.use_fake_user = True
    made.append((clip, out_frame))
    print("MOVESET: %-10s <- %s frames %d..%d -> %d keyed" % (clip, bvh, start, last, out_frame))

    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.data.objects.remove(src, do_unlink=True)

scene.render.fps = 30
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', export_apply=False,
                          export_animations=True, export_animation_mode='ACTIONS',
                          export_image_format='AUTO')
print("MOVESET: exported %s (%.1f MB) with %d clips: %s"
      % (GLB, os.path.getsize(GLB)/1048576.0, len(made), ", ".join(c for c, _ in made)))