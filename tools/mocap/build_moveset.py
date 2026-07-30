"""Build the player's whole moveset into ONE glTF, in one pass.

    blender --background --factory-startup --python build_moveset.py -- --glb out.glb

Each entry in CLIPS is a slice of a Carnegie Mellon basketball capture retargeted
onto the player rig as its own named clip. Godot imports the result as an
AnimationPlayer holding every clip by name.

HOW THE RETARGET WORKS, and why it is not the obvious thing.

The obvious approach is to AIM each target bone along the direction its source
counterpart points. That was the first implementation and it is subtly wrong:
aiming constrains only where a bone POINTS, leaving the twist around its own axis
to whatever the minimal rotation happens to produce. Down a leg chain the twist
accumulates, and it surfaces as feet pointing sideways while the player runs.

What works is carrying the source bone's whole ORIENTATION across, corrected for
the two skeletons' different rest poses:

    target_world = source_world * inverse(source_rest) * target_rest

A source bone still in its own rest pose therefore leaves the target bone in ITS
rest pose, and any rotation the performer actually made is reproduced - including
the twist that keeps a foot pointing the way the leg is travelling.

Bone LENGTHS are never touched, so the character keeps its own proportions
whatever the build of the performer.

The collarbones stay out of the map: the two skeletons hang them at very
different rest angles and driving them drags the arm chain into the chest. Left
alone they act as a stable socket while the upper arm carries the motion, which is
standard practice.
"""
import bpy, os, sys
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
    ("idle",      "06_01.bvh", 100, 340, 4),
    ("dribble",   "06_02.bvh", 200, 440, 4),
    ("run",       "06_10.bvh", 120, 360, 4),
    ("crossover", "06_13.bvh", 400, 640, 4),
    ("jumpshot",  "06_14.bvh", 240, 480, 4),
]

MAP = {
    "LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg", "LeftFoot": "LeftFoot",
    "LeftToeBase": "LeftToeBase",
    "RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg", "RightFoot": "RightFoot",
    "RightToeBase": "RightToeBase",
    "LowerBack": "Spine02", "Spine": "Spine01", "Spine1": "Spine",
    # Neck and head are deliberately NOT driven. Aimed, they tip the head back to
    # stare at the ceiling, because the two skeletons hold the head at very
    # different rest angles. A level head reads correctly in every clip and a
    # player looking up reads as broken in all of them.
    "LeftArm": "LeftArm", "LeftForeArm": "LeftForeArm", "LeftHand": "LeftHand",
    "RightArm": "RightArm", "RightForeArm": "RightForeArm", "RightHand": "RightHand",
}
# Parents before children, so each solve sees its parent already posed.
ORDER = ["LowerBack", "Spine", "Spine1",
         "LeftArm", "LeftForeArm", "LeftHand",
         "RightArm", "RightForeArm", "RightHand",
         "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
         "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]

# TWO solvers, each used where it demonstrably wins. Both were checked by
# rendering the run clip and looking at it.
#
# FULL ROTATION (rest-relative) carries the source bone's whole orientation,
# twist included. On the LEGS this is transformative: it produces a real stride
# with the feet pointing where the player is travelling. Aiming left the twist
# unconstrained and the feet ended up sideways.
#
# On the SPINE and ARMS the same method twists the torso and folds the arms
# across the chest, because those bones' rest orientations differ far more between
# the two skeletons than the legs' do. There, plain direction AIMING is correct
# and looks right.
FULL_ROTATION = {
    "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
    "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
}

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=SRC)
tgt = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
tgt.name = "PlayerRig"
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)


def rest_world_rotations(ob):
    """Each bone's rest orientation in world space - the reference the transfer is
    measured against."""
    out = {}
    for b in ob.data.bones:
        out[b.name] = (ob.matrix_world.to_3x3() @ b.matrix_local.to_3x3()).to_quaternion()
    return out


TGT_REST = rest_world_rotations(tgt)
SRC_REST = {}
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
    if not SRC_REST:
        SRC_REST = rest_world_rotations(src)

    last = min(end, scene.frame_end)
    bpy.context.view_layer.objects.active = tgt
    bpy.ops.object.mode_set(mode='POSE')
    for pb in tgt.pose.bones:
        pb.rotation_mode = 'QUATERNION'

    act = bpy.data.actions.new(clip)
    tgt.animation_data_create()
    tgt.animation_data.action = act

    out_frame = 0
    solves = 0
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

            m = dpb.matrix.copy()
            if src_name in FULL_ROTATION:
                s_rest = SRC_REST.get(src_name)
                d_rest = TGT_REST.get(dst_name)
                if s_rest is None or d_rest is None:
                    continue
                s_world = (src.matrix_world.to_3x3() @ spb.matrix.to_3x3()).to_quaternion()
                want = (s_world @ s_rest.inverted()) @ d_rest
                arm_rot = tgt.matrix_world.inverted().to_3x3().to_quaternion() @ want
                posed = arm_rot.to_matrix().to_4x4()
            else:
                world_dir = (src.matrix_world.to_3x3()
                             @ (spb.matrix.to_3x3() @ Vector((0.0, 1.0, 0.0)))).normalized()
                target = (tgt.matrix_world.inverted().to_3x3() @ world_dir).normalized()
                cur = (m.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
                posed = (cur.rotation_difference(target).to_matrix() @ m.to_3x3()).to_4x4()

            posed.translation = m.to_translation()
            dpb.matrix = posed
            # Children read their parent's matrix, so it must be live first.
            bpy.context.view_layer.update()
            solves += 1

        for pb in tgt.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=out_frame)

    act.use_fake_user = True
    made.append((clip, out_frame))
    print("MOVESET: %-10s <- %s frames %d..%d -> %d keyed (%d bone solves)"
          % (clip, bvh, start, last, out_frame, solves))

    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.data.objects.remove(src, do_unlink=True)

scene.render.fps = 30
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', export_apply=False,
                          export_animations=True, export_animation_mode='ACTIONS',
                          export_image_format='AUTO')
print("MOVESET: exported %s (%.1f MB) with %d clips: %s"
      % (GLB, os.path.getsize(GLB)/1048576.0, len(made), ", ".join(c for c, _ in made)))