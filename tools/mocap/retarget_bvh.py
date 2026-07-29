"""Carnegie Mellon motion capture -> the player rig, inside Blender.

    blender --background --factory-startup --python retarget_bvh.py -- \
        --bvh 06_14.bvh --clip crossover_shoot --glb out.glb [--start 0 --end 240]

The CMU basketball captures (subject 06) use a skeleton whose limb bones are
named IDENTICALLY to the shipped player rig - LeftUpLeg, LeftForeArm and so on.
Only the spine and neck differ, and those are mapped explicitly below.

Retarget method: for every frame, take the DIRECTION each source bone points in
world space and rotate the matching target bone to point the same way, walking
parents-first so a parent's rotation is already applied when its child is solved.
Nothing copies raw rotation values, because the two skeletons do not share local
bone axes - that assumption is exactly what tore the arms apart on the earlier
hand-authored attempt. Bone LENGTHS are never touched, so the character keeps its
own proportions no matter the build of the performer.

Root travel is copied from the hips and rescaled by the leg-length ratio between
the two skeletons, so a taller character covers proportionally more ground
instead of moon-walking.
"""
import bpy, math, os, sys
from mathutils import Vector, Quaternion, Matrix

def cli(n, d=None, required=False):
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if n in a:
        return a[a.index(n) + 1]
    if required:
        raise SystemExit("missing " + n)
    return d

SRC_GLB = cli("--src", r"C:\Users\Kariim\Dev\hoopclone\assets\models\player_base.glb")
BVH     = cli("--bvh", required=True)
CLIP    = cli("--clip", "captured")
GLB     = cli("--glb", required=True)
START   = int(cli("--start", "0"))
END     = int(cli("--end", "0"))
STEP    = int(cli("--step", "4"))      # CMU is 120fps; every 4th frame gives 30fps
LOOP    = cli("--loop", "0") == "1"
# In-place clips carry no travel. The GAME moves the character; if the clip
# also slides him, the two fight and he skates across the floor.
IN_PLACE = cli("--in-place", "1") == "1"

# CMU bone -> player-rig bone. Limbs match by name; spine and neck do not.
MAP = {
    "LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg",
    "RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg",
    "LowerBack": "Spine02", "Spine": "Spine01", "Spine1": "Spine",
    "Neck1": "neck", "Head": "Head",
    "LeftArm": "LeftArm", "LeftForeArm": "LeftForeArm", "LeftHand": "LeftHand",
    "RightArm": "RightArm", "RightForeArm": "RightForeArm", "RightHand": "RightHand",
}
# The collarbones are deliberately NOT retargeted. The two skeletons hang their
# clavicles at very different rest angles, so aiming them by direction dragged
# the whole arm chain into the chest. Left at rest they act as a stable socket
# and the upper arm carries the motion, which is standard retargeting practice.
# Parents before children, so each solve sees its parent already posed.
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

bpy.ops.import_scene.gltf(filepath=SRC_GLB)
tgt = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
tgt.name = "PlayerRig"
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)

bpy.ops.import_anim.bvh(filepath=BVH, global_scale=1.0, use_fps_scale=False,
                        update_scene_fps=False, update_scene_duration=True)
src = next(o for o in bpy.data.objects if o.type == 'ARMATURE' and o is not tgt)
src.name = "MocapRig"

total = scene.frame_end
end = END if END > 0 else total
end = min(end, total)
print("AUDIT: bvh frames=%d using %d..%d step %d" % (total, START, end, STEP))

def world_dir(ob, pb):
    v = ob.matrix_world.to_3x3() @ (pb.matrix.to_3x3() @ Vector((0, 1, 0)))
    return v.normalized() if v.length > 1e-8 else Vector((0, 1, 0))

def bone_len(ob, name):
    b = ob.data.bones.get(name)
    return 0.0 if b is None else (ob.matrix_world.to_3x3() @ (b.tail_local - b.head_local)).length

# Leg length decides how far the character travels per step of the performer.
src_leg = bone_len(src, "LeftUpLeg") + bone_len(src, "LeftLeg")
tgt_leg = bone_len(tgt, "LeftUpLeg") + bone_len(tgt, "LeftLeg")
scale = (tgt_leg / src_leg) if src_leg > 1e-6 else 1.0
print("AUDIT: leg lengths src=%.3f tgt=%.3f -> travel scale %.4f" % (src_leg, tgt_leg, scale))

bpy.context.view_layer.objects.active = tgt
bpy.ops.object.mode_set(mode='POSE')
for pb in tgt.pose.bones:
    pb.rotation_mode = 'QUATERNION'

act = bpy.data.actions.new(CLIP)
tgt.animation_data_create()
tgt.animation_data.action = act

src_hips = src.pose.bones.get("Hips")
origin = None
out_frame = 0
solves = 0

for f in range(START if START > 0 else 1, end + 1, STEP):
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

        # Where the captured bone points, brought into the target rig's own space.
        world_target = world_dir(src, spb)
        target = (tgt.matrix_world.inverted().to_3x3() @ world_target).normalized()

        # Aim the bone by writing its MATRIX rather than composing rotations by
        # hand. Blender derives the local rotation from this, including whatever
        # rest orientation the bone has - the two skeletons do not share local
        # axes, and hand-composed quaternions got that wrong twice.
        m = dpb.matrix.copy()
        cur = (m.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
        q = cur.rotation_difference(target)
        rotated = (q.to_matrix() @ m.to_3x3()).to_4x4()
        rotated.translation = m.to_translation()
        dpb.matrix = rotated
        # Children read their parent's matrix, so it has to be live before they solve.
        bpy.context.view_layer.update()
        solves += 1

    hips = tgt.pose.bones.get("Hips")
    if hips is not None and src_hips is not None and not IN_PLACE:
        world_hips = (src.matrix_world @ src_hips.matrix).to_translation()
        if origin is None:
            origin = world_hips.copy()
        # `scale` already converts capture units into the rig's own bone units
        # (both leg lengths were measured through matrix_world), so the offset is
        # applied straight. Multiplying by 100 here on top of that threw the
        # player a hundred metres off camera on the first run.
        off = (world_hips - origin) * scale
        hips.location = (off.x, off.y, off.z)
        hips.keyframe_insert("location", frame=out_frame)

    for pb in tgt.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=out_frame)

act.use_fake_user = True
bpy.ops.object.mode_set(mode='OBJECT')
print("AUDIT: clip '%s' out_frames=%d bone_solves=%d loop=%s" % (CLIP, out_frame, solves, LOOP))

bpy.data.objects.remove(src, do_unlink=True)
bpy.ops.object.select_all(action='SELECT')
scene.render.fps = 30
bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', export_apply=False,
                          export_animations=True, export_animation_mode='ACTIONS',
                          export_image_format='AUTO')
print("AUDIT: exported %s (%d bytes)" % (GLB, os.path.getsize(GLB)))