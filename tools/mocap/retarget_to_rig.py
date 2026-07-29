"""Joint tracks -> bone rotations on the player rig, inside Blender.

    blender --background --factory-startup --python retarget_to_rig.py -- \
        --joints clip_joints.json --clip dribble --glb out.glb

Takes the JSON that video_to_joints.py writes and drives the SHIPPED 24-bone rig
with it, then exports a glTF whose animation Godot imports by name.

How the retarget works: for every bone we know which pair of tracked joints
defines its direction (upper arm = shoulder to elbow, and so on). Each frame we
work out where that bone should point in world space, compare it with where it
points at rest, and store the rotation that closes the gap - expressed in the
bone's PARENT space, walking down the chain so a parent's rotation is already
accounted for by the time a child is solved. That is the whole trick; everything
else is bookkeeping.

Bone lengths are never touched, so the character keeps its own proportions no
matter who was filmed.
"""
import bpy, json, math, sys, os
from mathutils import Vector, Matrix, Quaternion

def cli(name, default=None, required=False):
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if name in a:
        return a[a.index(name) + 1]
    if required:
        raise SystemExit(f"missing required argument {name}")
    return default

SRC     = cli("--src", r"C:\Users\Kariim\Dev\hoopclone\assets\models\player_base.glb")
JOINTS  = cli("--joints", required=True)
CLIP    = cli("--clip", "captured")
GLB     = cli("--glb", required=True)
CONF    = float(cli("--min-visibility", "0.35"))

# bone -> (joint at its head, joint at its tail). Solved parents-first.
CHAIN = [
    ("LeftUpLeg",    "l_hip",      "l_knee"),
    ("LeftLeg",      "l_knee",     "l_ankle"),
    ("LeftFoot",     "l_ankle",    "l_foot"),
    ("RightUpLeg",   "r_hip",      "r_knee"),
    ("RightLeg",     "r_knee",     "r_ankle"),
    ("RightFoot",    "r_ankle",    "r_foot"),
    ("LeftShoulder", "spine_top",  "l_shoulder"),
    ("LeftArm",      "l_shoulder", "l_elbow"),
    ("LeftForeArm",  "l_elbow",    "l_wrist"),
    ("RightShoulder","spine_top",  "r_shoulder"),
    ("RightArm",     "r_shoulder", "r_elbow"),
    ("RightForeArm", "r_elbow",    "r_wrist"),
    ("neck",         "spine_top",  "nose"),
]
# The spine has no tracked joints of its own; it spans hips to shoulders and the
# rotation is shared across the three segments so no single joint over-bends.
SPINE = ["Spine02", "Spine01", "Spine"]

data = json.load(open(JOINTS))
tracks = data["joints"]
vis = data.get("visibility", {})
frame_count = data["frames"]
fps = data.get("fps", 30.0)

def jp(name, f):
    return Vector(tracks[name][f])

def mid(a, b, f):
    return (jp(a, f) + jp(b, f)) * 0.5

def derived(f):
    return {
        "hip_center": mid("l_hip", "r_hip", f),
        "spine_top": mid("l_shoulder", "r_shoulder", f),
    }

def visible(name, f):
    v = vis.get(name)
    return True if not v else v[f] >= CONF

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
scene = bpy.context.scene
scene.render.fps = int(round(fps))

arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
bpy.context.view_layer.objects.active = arm
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)

bpy.ops.object.mode_set(mode='POSE')
for pb in arm.pose.bones:
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = Quaternion()

act = bpy.data.actions.new(CLIP)
arm.animation_data_create()
arm.animation_data.action = act

def rest_dir(pb):
    """Where this bone points when the rig is untouched, in world space."""
    b = pb.bone
    return (arm.matrix_world.to_3x3() @ (b.tail_local - b.head_local)).normalized()

solved = 0
skipped = set()

for f in range(frame_count):
    d = derived(f)

    def point(name):
        return d[name] if name in d else jp(name, f)

    for bone_name, head_j, tail_j in CHAIN:
        pb = arm.pose.bones.get(bone_name)
        if pb is None:
            skipped.add(bone_name)
            continue
        for j in (head_j, tail_j):
            if j not in d and not visible(j, f):
                break
        else:
            target = (point(tail_j) - point(head_j))
            if target.length < 1e-5:
                continue
            target.normalize()
            # Rotation that takes the bone's CURRENT world direction onto the
            # target, then expressed in parent space so the chain composes.
            cur = (arm.matrix_world.to_3x3() @ (pb.matrix.to_3x3() @ Vector((0, 1, 0)))).normalized()
            delta = cur.rotation_difference(target)
            parent_rot = (arm.matrix_world.to_3x3() @ pb.matrix.to_3x3()).to_quaternion()
            pb.rotation_quaternion = (
                pb.rotation_quaternion @ (parent_rot.inverted() @ delta @ parent_rot)
            ).normalized()
            solved += 1

    # spine: hips-to-shoulders direction, shared evenly across the segments
    spine_target = (d["spine_top"] - d["hip_center"])
    if spine_target.length > 1e-5:
        spine_target.normalize()
        for seg in SPINE:
            pb = arm.pose.bones.get(seg)
            if pb is None:
                skipped.add(seg)
                continue
            cur = (arm.matrix_world.to_3x3() @ (pb.matrix.to_3x3() @ Vector((0, 1, 0)))).normalized()
            delta = cur.rotation_difference(spine_target)
            share = Quaternion().slerp(delta, 1.0 / len(SPINE))
            parent_rot = (arm.matrix_world.to_3x3() @ pb.matrix.to_3x3()).to_quaternion()
            pb.rotation_quaternion = (
                pb.rotation_quaternion @ (parent_rot.inverted() @ share @ parent_rot)
            ).normalized()

    # Hips carry the body's travel; bone space is centimetres at 0.01 rig scale.
    hips = arm.pose.bones.get("Hips")
    if hips is not None:
        base = derived(0)["hip_center"]
        off = (d["hip_center"] - base) * 100.0
        hips.location = (off.x, off.y, off.z)
        hips.keyframe_insert("location", frame=f + 1)

    for pb in arm.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=f + 1)

act.use_fake_user = True
bpy.ops.object.mode_set(mode='OBJECT')

print(f"AUDIT: clip '{CLIP}' frames={frame_count} fps={fps:.2f} bone_solves={solved}")
if skipped:
    print(f"AUDIT: WARN bones missing from rig: {sorted(skipped)}")

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', export_apply=False,
                          export_animations=True, export_animation_mode='ACTIONS',
                          export_image_format='AUTO')
print(f"AUDIT: exported {GLB} ({os.path.getsize(GLB)} bytes)")