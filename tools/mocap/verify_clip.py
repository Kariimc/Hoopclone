"""Measure a retargeted clip against the human it came from.

Eyeballing a render tells you something is wrong; it does not tell you WHICH joint
or by how much. This compares the finished character, frame by frame, against the
motion-capture performer that drove it.

That performer is a real person wearing markers, so agreement with them IS the
definition of natural motion here - there is no better reference available, and it
is objective rather than a matter of taste.

    blender --background --factory-startup --python verify_clip.py -- \
        --glb player_animated.glb --clip run --bvh 06_10.bvh --start 120 --end 360

WHAT IT MEASURES, and the two wrong metrics it had to get past first.

WRONG ONCE: compare each bone's rotation away from its own bind pose. That is
only meaningful if the two skeletons agree on which way is forward, which they do
not - and worse, it is precisely the quantity the retarget copies, so it graded
the transfer against its own formula and passed any bug the formula shared. It
scored an upside-down character as near-perfect.

WRONG TWICE: compare raw joint bends and joint positions. Honest, but it charges
the animation for the character's ANATOMY. Measured on the bind poses alone, with
nobody moving: the performer's elbows are dead straight where the character's rest
at 30-37 degrees, and their shoulders sit 76-81 degrees apart because one skeleton
stands in a T-pose and the other in an A-pose. Every one of those degrees showed
up as animation error.

WHAT IT DOES: compare MOVEMENT - how far each joint travelled from its own bind
pose - on both skeletons, two ways.

1. BEND. How far the knee, elbow, hip, ankle, shoulder and spine are folded.
   Purely geometric: no skeleton size, no facing, no rig convention. Read as an
   absolute, because the retarget now steers each limb at the performer's rather
   than preserving the character's rest offset - so the angles should agree
   outright, not merely change together.

2. POINTING, in the body's own frame. Which way each limb segment actually
   points, measured against the character's own hip line and spine. This is the
   one that catches a limb on the wrong side of the body: bends are unsigned and
   happily agree while an arm swings across the chest instead of out to the side.
   Measured on the shipped build it caught exactly that - the dribbling hand was
   sitting on the character's LEFT while the performer's was on their right.

Both are reported per joint, and both must pass.
"""
import bpy, math, os, sys
from mathutils import Vector

def cli(n, d=None):
    a = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    return a[a.index(n)+1] if n in a else d

GLB = cli("--glb", os.path.join(ROOT, "assets", "models", "player_animated.glb"))
CLIP = cli("--clip", "run")
BVH = cli("--bvh", os.path.join(ROOT, "assets", "mocap", "06_10.bvh"))
START = int(cli("--start", "120"))
END = int(cli("--end", "360"))
STEP = int(cli("--step", "4"))
# A bend is set by the two limb segments either side of it, so its error is
# roughly the sum of theirs - it cannot be held to a tighter bar than they are.
ANGLE_TOL = float(cli("--angle-tolerance", "25"))
# 20 degrees of pointing error is about a hand's width at the end of an arm.
DIR_TOL = float(cli("--direction-tolerance", "20"))

# source bone -> target bone, for every joint this check reads.
JOINTS = {
    "Hips": "Hips",
    "LowerBack": "Spine02", "Spine": "Spine01", "Spine1": "Spine",
    "Neck1": "neck", "Head": "Head",
    "LeftArm": "LeftArm", "LeftForeArm": "LeftForeArm", "LeftHand": "LeftHand",
    "RightArm": "RightArm", "RightForeArm": "RightForeArm", "RightHand": "RightHand",
    "LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg", "LeftFoot": "LeftFoot",
    "LeftToeBase": "LeftToeBase",
    "RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg", "RightFoot": "RightFoot",
    "RightToeBase": "RightToeBase",
}

# The same table for a Mixamo-named skeleton, picked automatically below. Same
# reasoning as build_moveset.py's MAP_MIXAMO: the performer's own bone names are
# Mixamo's without the prefix, so only the spine chain shifts by one link.
JOINTS_MIXAMO = dict(
    {n: "mixamorig:" + n for n in [
        "Hips", "Head",
        "LeftArm", "LeftForeArm", "LeftHand",
        "RightArm", "RightForeArm", "RightHand",
        "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
        "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
    ]},
    LowerBack="mixamorig:Spine", Spine="mixamorig:Spine1",
    Spine1="mixamorig:Spine2", Neck1="mixamorig:Neck",
)

# And the Universal rig (Unreal's bone names), used by the public-domain
# character libraries.
JOINTS_UNIVERSAL = {
    "Hips": "pelvis",
    "LowerBack": "spine_01", "Spine": "spine_02", "Spine1": "spine_03",
    "Neck1": "neck_01", "Head": "Head",
    "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
    "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r", "RightHand": "hand_r",
    "LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l",
    "LeftToeBase": "ball_l",
    "RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r",
    "RightToeBase": "ball_r",
}

# label -> (joint before, the joint being measured, joint after). The bend is
# measured AT the middle joint.
BENDS = [
    ("left knee",      ("LeftUpLeg", "LeftLeg", "LeftFoot")),
    ("right knee",     ("RightUpLeg", "RightLeg", "RightFoot")),
    ("left hip",       ("Spine1", "LeftUpLeg", "LeftLeg")),
    ("right hip",      ("Spine1", "RightUpLeg", "RightLeg")),
    ("left ankle",     ("LeftLeg", "LeftFoot", "LeftToeBase")),
    ("right ankle",    ("RightLeg", "RightFoot", "RightToeBase")),
    ("left elbow",     ("LeftArm", "LeftForeArm", "LeftHand")),
    ("right elbow",    ("RightArm", "RightForeArm", "RightHand")),
    ("left shoulder",  ("Spine1", "LeftArm", "LeftForeArm")),
    ("right shoulder", ("Spine1", "RightArm", "RightForeArm")),
    ("upper spine",    ("LowerBack", "Spine1", "Neck1")),
]

# Limb segments whose POINTING is checked, as (from joint, to joint).
SEGMENTS = [
    ("left thigh",   ("LeftUpLeg", "LeftLeg")),
    ("left shin",    ("LeftLeg", "LeftFoot")),
    ("left foot",    ("LeftFoot", "LeftToeBase")),
    ("right thigh",  ("RightUpLeg", "RightLeg")),
    ("right shin",   ("RightLeg", "RightFoot")),
    ("right foot",   ("RightFoot", "RightToeBase")),
    ("left upper arm",  ("LeftArm", "LeftForeArm")),
    ("left forearm",    ("LeftForeArm", "LeftHand")),
    ("right upper arm", ("RightArm", "RightForeArm")),
    ("right forearm",   ("RightForeArm", "RightHand")),
    ("lower spine",  ("LowerBack", "Spine1")),
    ("neck",         ("Neck1", "Head")),
]

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=GLB)
tgt = next(o for o in bpy.data.objects if o.type == 'ARMATURE')

# Which naming scheme the graded body uses. Read off the skeleton, never assumed.
if any(b.name.startswith("mixamorig:") for b in tgt.data.bones):
    JOINTS = JOINTS_MIXAMO
elif "pelvis" in tgt.data.bones and "spine_01" in tgt.data.bones:
    JOINTS = JOINTS_UNIVERSAL
# A joint this check cannot find is a joint it silently skips, and a run that
# skips every joint prints PASS having measured nothing. Refuse to start instead.
absent = [n for n in JOINTS.values() if n not in tgt.data.bones]
if absent:
    raise SystemExit("VERIFY: this rig has no bone(s) %s - the check would grade "
                     "nothing and report a pass. Fix the name table first." % absent)

act = None
for a in bpy.data.actions:
    if a.name == CLIP or a.name.endswith(CLIP):
        act = a
        break
if act is None:
    raise SystemExit("VERIFY: no clip '%s' in %s (have %s)"
                     % (CLIP, os.path.basename(GLB), [a.name for a in bpy.data.actions]))

bpy.ops.import_anim.bvh(filepath=BVH, global_scale=1.0, use_fps_scale=False,
                        update_scene_fps=False, update_scene_duration=True)
src = next(o for o in bpy.data.objects if o.type == 'ARMATURE' and o is not tgt)


def rest_heads(ob, names):
    """Where each named joint rests, in world space, before anything moves.

    Joint locations, never bone directions: this rig's tail data is garbage -
    bones report lengths of thousands of units on a body 170 units tall - and a
    metric built on it already sent one investigation down the wrong road for
    hours."""
    out = {}
    for n in names:
        b = ob.data.bones.get(n)
        if b is not None:
            out[n] = ob.matrix_world @ b.head_local.copy()
    return out


def posed_heads(ob, names):
    """Where each named joint is right now."""
    out = {}
    for n in names:
        pb = ob.pose.bones.get(n)
        if pb is not None:
            out[n] = ob.matrix_world @ pb.head.copy()
    return out


def bend(p, a, b, c):
    """Degrees of bend at joint b. A straight limb reads 0."""
    if a not in p or b not in p or c not in p:
        return None
    u = p[a] - p[b]
    v = p[c] - p[b]
    if u.length < 1e-6 or v.length < 1e-6:
        return None
    return 180.0 - math.degrees(u.angle(v))


def body_frame(p, hips, lhip, rhip, chest):
    """An axis system belonging to the body itself, not to the world.

    Across the hips, forward out of the chest, and up the spine. Expressing a
    joint in these axes removes which way the character happens to be facing;
    dividing by its own height removes how big it is. What is left is the pose."""
    if any(n not in p for n in (hips, lhip, rhip, chest)):
        return None
    across = p[rhip] - p[lhip]
    up = p[chest] - p[hips]
    if across.length < 1e-6 or up.length < 1e-6:
        return None
    across.normalize()
    fwd = across.cross(up.normalized())
    if fwd.length < 1e-6:
        return None
    fwd.normalize()
    return p[hips], (across, fwd, fwd.cross(across).normalized())


def pointing(p, frame, a, b):
    """Which way the segment a->b points, in the body's own axes."""
    if frame is None or a not in p or b not in p:
        return None
    d = p[b] - p[a]
    if d.length < 1e-6:
        return None
    d.normalize()
    axes = frame[1]
    return Vector((d.dot(axes[0]), d.dot(axes[1]), d.dot(axes[2])))


def snapshot(p, hips, lhip, rhip, chest, name_of):
    """Every measurement this check needs, taken from one set of joint positions."""
    frame = body_frame(p, hips, lhip, rhip, chest)
    bends = {}
    for label, (a, b, c) in BENDS:
        bends[label] = bend(p, name_of(a), name_of(b), name_of(c))
    dirs = {}
    for label, (a, b) in SEGMENTS:
        dirs[label] = pointing(p, frame, name_of(a), name_of(b))
    return bends, dirs


SRC_NAMES = list(JOINTS.keys())
TGT_NAMES = list(JOINTS.values())
src_id = lambda n: n
tgt_id = lambda n: JOINTS.get(n, n)

# The bind pose of each skeleton - the zero every movement below is measured from.
SRC_BIND = snapshot(rest_heads(src, SRC_NAMES), "Hips", "LeftUpLeg", "RightUpLeg",
                    "Spine1", src_id)
# Through the table, like every other joint: these are SOURCE names being
# translated, not literal bone names on the target.
TGT_BIND = snapshot(rest_heads(tgt, TGT_NAMES), tgt_id("Hips"), tgt_id("LeftUpLeg"),
                    tgt_id("RightUpLeg"), tgt_id("Spine1"), tgt_id)

tgt.animation_data_create()
tgt.animation_data.action = act
try:
    if act.slots:
        tgt.animation_data.action_slot = act.slots[0]
except AttributeError:
    pass

last = min(END, scene.frame_end)
source_frames = list(range(max(1, START), last + 1, STEP))
angle_err = {}
place_err = {}
# How much the performer moved that joint at all. Without it a "40 degrees off"
# is unreadable: 40 out of 45 is a broken joint, 40 out of 300 is a wobble.
angle_ref = {}
place_ref = {}
compared = 0

# Where the clip actually lives once it has been through a file, which is not
# necessarily one frame per capture sample - see the note at the top.
clip_start, clip_end = (float(v) for v in act.frame_range)
span = max(len(source_frames) - 1, 1)

for i, sf in enumerate(source_frames):
    out_frame = clip_start + (clip_end - clip_start) * i / span

    scene.frame_set(sf)
    s_now = snapshot(posed_heads(src, SRC_NAMES), "Hips", "LeftUpLeg", "RightUpLeg",
                     "Spine1", src_id)
    scene.frame_set(int(out_frame), subframe=out_frame - int(out_frame))
    t_now = snapshot(posed_heads(tgt, TGT_NAMES), tgt_id("Hips"), tgt_id("LeftUpLeg"),
                     tgt_id("RightUpLeg"), tgt_id("Spine1"), tgt_id)
    compared += 1

    for label, _ in BENDS:
        sa, sb = s_now[0].get(label), SRC_BIND[0].get(label)
        ta = t_now[0].get(label)
        if None in (sa, ta):
            continue
        angle_err.setdefault(label, []).append(abs(sa - ta))
        if sb is not None:
            # How far the performer folded it away from their own rest, so a
            # reading of "18 degrees off" can be told from a joint that barely
            # moved and one that swung through 90.
            angle_ref.setdefault(label, []).append(abs(sa - sb))

    for label, _ in SEGMENTS:
        sa, ta = s_now[1].get(label), t_now[1].get(label)
        if sa is None or ta is None:
            continue
        # Absolute pointing, both read in their own body's axes. Bind pose does
        # not enter into it, so anatomy is never charged as animation error.
        place_err.setdefault(label, []).append(math.degrees(sa.angle(ta)))
        sb = SRC_BIND[1].get(label)
        if sb is not None:
            place_ref.setdefault(label, []).append(math.degrees(sa.angle(sb)))

print("VERIFY: clip '%s' against %s, %d frames compared "
      "(capture %d..%d against clip frames %.0f..%.0f)"
      % (CLIP, os.path.basename(BVH), compared, source_frames[0], source_frames[-1],
         clip_start, clip_end))
fails = []

print("VERIFY: -- how far each joint is folded vs the performer (degrees) --")
for label, _ in BENDS:
    vals = angle_err.get(label)
    if not vals:
        continue
    mean = sum(vals) / len(vals)
    off = mean > ANGLE_TOL
    if off:
        fails.append("%s bend %.0f deg" % (label, mean))
    ref = angle_ref.get(label) or [0.0]
    print("VERIFY:   %-15s mean %5.1f   worst %5.1f   (performer moved it %5.1f)%s"
          % (label, mean, max(vals), sum(ref) / len(ref), "   <-- OFF" if off else ""))

print("VERIFY: -- which way each limb points vs the performer (degrees) --")
for name, _ in SEGMENTS:
    vals = place_err.get(name)
    if not vals:
        continue
    mean = sum(vals) / len(vals)
    off = mean > DIR_TOL
    if off:
        fails.append("%s points %.0f deg out" % (name, mean))
    ref = place_ref.get(name) or [0.0]
    print("VERIFY:   %-15s mean %5.1f   worst %5.1f   (performer moved it %5.1f)%s"
          % (name, mean, max(vals), sum(ref) / len(ref), "   <-- OFF" if off else ""))

graded = sum(1 for l, _ in BENDS if angle_err.get(l))
graded += sum(1 for n, _ in SEGMENTS if place_err.get(n))
if graded < len(BENDS) + len(SEGMENTS):
    raise SystemExit("VERIFY: FAIL - only %d of %d measurements were taken; the "
                     "rest found no data. A partial grade is not a pass."
                     % (graded, len(BENDS) + len(SEGMENTS)))

if fails:
    print("VERIFY: FAIL - %d measurement(s) outside tolerance: %s"
          % (len(fails), ", ".join(fails)))
else:
    print("VERIFY: PASS - every joint bends and points like the performer, within "
          "%.0f and %.0f degrees" % (ANGLE_TOL, DIR_TOL))
