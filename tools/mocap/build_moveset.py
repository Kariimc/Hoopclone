"""Build the player's whole moveset into ONE glTF, in one pass.

    blender --background --factory-startup --python build_moveset.py -- --glb out.glb

Each entry in CLIPS is a slice of a Carnegie Mellon basketball capture retargeted
onto the player rig as its own named clip. Godot imports the result as an
AnimationPlayer holding every clip by name.

HOW THE RETARGET WORKS, and why it is not the obvious thing.

Attempt one AIMED each target bone along the direction its source counterpart
points. Aiming constrains only where a bone POINTS; the twist around its own
axis is left to whatever the minimal rotation happens to produce, and down a
chain that twist accumulates. It surfaced as feet pointing sideways mid-stride.

Attempt two carried the source bone's whole orientation across, rest-relative:

    target_world = source_world * inverse(source_rest) * target_rest

That fixed the legs and broke the torso: the character ran correctly while
facing backwards. The reason is that the delta source_world * inverse(source_rest)
is expressed in the SOURCE skeleton's world frame. Handing it to a skeleton
whose bind pose sits in a different frame reinterprets every axis - "lean
forward" arrives as "lean backward".

What ships is that same transfer with the two missing pieces:

1. PELVIS-RELATIVE. Everything is measured against the performer's own hips
   rather than the capture stage, so a clip carries only what the body did and
   never which way the stage had them pointing. The game turns the character
   itself, so absolute facing inside a clip is noise at best.

2. BIND-POSE ALIGNMENT. One rotation A is fitted once, before any frame is
   solved, mapping the source's bind pose onto the target's. It comes from a
   least-squares fit (Kabsch) over the joint POSITIONS the two skeletons share
   - hips, spine, shoulders, knees, feet - which are trustworthy on both rigs.
   Every delta is then conjugated through it, A * delta * inverse(A), so a
   rotation means the same thing on the receiving skeleton as it did on the
   performer.

With both in place a single solver drives every bone, legs and torso alike -
no per-bone special cases, no undriven chains propping up a wrong frame.

Bone LENGTHS are never touched, so the character keeps its own proportions
whatever the build of the performer.

The collarbones stay out of the map: the two skeletons hang them at very
different rest angles and driving them drags the arm chain into the chest. Left
alone they act as a stable socket while the upper arm carries the motion, which is
standard practice.
"""
import bpy, os, sys
import numpy as np
from mathutils import Vector, Quaternion, Euler

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "dev"))
from hold import reload_hold      # pauses the live window while the .glb is written

def cli(n, d=None):
    a = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    return a[a.index(n)+1] if n in a else d

ROOT = r"C:\Users\Kariim\Dev\hoopclone"
SRC  = cli("--src", os.path.join(ROOT, "assets", "models", "player_noball.glb"))
GLB  = cli("--glb", os.path.join(ROOT, "assets", "models", "player_animated.glb"))
MOCAP = os.path.join(ROOT, "assets", "mocap")
# Stand the body at this height (Blender units, rest pose, mesh bounds) so a
# swapped-in body arrives the same size as the one it replaces. 0 = leave alone.
HEIGHT = float(cli("--height", "0") or 0)

# A .glb of clips authored for the SAME rig as the body (Quaternius ships its
# characters and its animation library separately). Empty = the body's own clips
# only.
CLIPS_GLB = cli("--clips", "")

# Clips taken as-is under the game's name, never solved from capture: a clip made
# FOR a rig always beats one transferred onto it. Each game name lists the action
# names worth accepting, best first, looked for in the body and then in the clip
# library.
FROM_SOURCE = {
    "idle": ["idle", "Idle_Loop"],
    "run":  ["run", "Jog_Fwd_Loop", "Sprint_Loop"],
    "walk": ["walk", "Walk_Loop"],
}

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
    # Hips are NOT driven. Every other bone is now measured relative to the
    # performer's hips, so the pelvis carries no motion of its own to pass on -
    # and leaving it at rest keeps the character upright and lets the game
    # decide which way it faces.
    "LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg", "LeftFoot": "LeftFoot",
    "LeftToeBase": "LeftToeBase",
    "RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg", "RightFoot": "RightFoot",
    "RightToeBase": "RightToeBase",
    "LowerBack": "Spine02", "Spine": "Spine01", "Spine1": "Spine",
    "Neck1": "neck", "Head": "Head",
    "LeftShoulder": "LeftShoulder", "RightShoulder": "RightShoulder",
    "LeftArm": "LeftArm", "LeftForeArm": "LeftForeArm", "LeftHand": "LeftHand",
    "RightArm": "RightArm", "RightForeArm": "RightForeArm", "RightHand": "RightHand",
}
# The same map for a Mixamo-named skeleton - the naming every free rigged body
# and every free animation library uses. Picked automatically below, so
# swapping in another Mixamo body needs no edit here. The CMU performer's own
# names are already Mixamo's minus the prefix, which is why the limbs are a
# straight pass-through and only the spine chain shifts by one link.
MAP_MIXAMO = dict(
    {n: "mixamorig:" + n for n in [
        "Hips",
        "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
        "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
        "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
        "RightShoulder", "RightArm", "RightForeArm", "RightHand",
        "Head",
    ]},
    LowerBack="mixamorig:Spine", Spine="mixamorig:Spine1",
    Spine1="mixamorig:Spine2", Neck1="mixamorig:Neck",
)

# And for the Universal rig (Unreal's bone names), which is what the public-domain
# character libraries use. Same reasoning again: only the naming differs.
MAP_UNIVERSAL = {
    "Hips": "pelvis",
    "LowerBack": "spine_01", "Spine": "spine_02", "Spine1": "spine_03",
    "Neck1": "neck_01", "Head": "Head",
    "LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l",
    "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
    "RightShoulder": "clavicle_r", "RightArm": "upperarm_r",
    "RightForeArm": "lowerarm_r", "RightHand": "hand_r",
    "LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l",
    "LeftToeBase": "ball_l",
    "RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r",
    "RightToeBase": "ball_r",
}

# Parents before children, so each solve sees its parent already posed.
ORDER = ["LowerBack", "Spine", "Spine1", "Neck1", "Head",
         "LeftShoulder", "RightShoulder",
         "LeftArm", "LeftForeArm", "LeftHand",
         "RightArm", "RightForeArm", "RightHand",
         "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
         "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]

# Joints used to fit the bind-pose alignment. Deliberately NOT every mapped
# bone: elbows and hands sit in wildly different places between an A-pose and a
# T-pose and would drag the fit. Hips, spine, shoulder sockets, knees and feet
# land in the same anatomical spots on any humanoid bind pose, so they measure
# the frame difference and nothing else.
# Which joint each bone points AT in its bind pose. Used to refine the global
# alignment limb by limb: the two skeletons stand in different bind poses (one
# T-pose, one A-pose, shoulders 76 degrees apart), so a single rotation cannot
# make every limb agree. Leaves have no child and inherit their parent's.
CHILD = {
    "LowerBack": "Spine", "Spine": "Spine1", "Spine1": "Neck1", "Neck1": "Head",
    "LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand",
    "RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand",
    "LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase",
    "RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase",
}
INHERIT = {"Head": "Neck1", "LeftHand": "LeftForeArm", "RightHand": "RightForeArm",
           "LeftToeBase": "LeftFoot", "RightToeBase": "RightFoot"}

# Whatever is nearest the boards decides where the floor is.
GROUND = ["LeftFoot", "LeftToeBase", "RightFoot", "RightToeBase"]

ALIGN_JOINTS = ["Hips", "LowerBack", "Spine", "Spine1",
                "LeftArm", "RightArm",
                "LeftUpLeg", "LeftLeg", "LeftFoot",
                "RightUpLeg", "RightLeg", "RightFoot"]

# Five clips take about a minute to solve and the .glb lands at the end. Without
# the hold, the live window reloads onto a half-written model or simply vanishes
# from under whoever is playing.
_HOLD = reload_hold("rebuilding the player's moveset")
_HOLD.__enter__()

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=SRC)
tgt = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
tgt.name = "PlayerRig"

# Which naming scheme this body uses. Read off the skeleton rather than passed in,
# so a new body drops in without a flag to remember.
if any(b.name.startswith("mixamorig:") for b in tgt.data.bones):
    MAP = MAP_MIXAMO
    print("MOVESET: target rig is Mixamo-named (%d bones)" % len(tgt.data.bones))
elif "pelvis" in tgt.data.bones and "spine_01" in tgt.data.bones:
    MAP = MAP_UNIVERSAL
    print("MOVESET: target rig is the Universal rig (%d bones)" % len(tgt.data.bones))
else:
    print("MOVESET: target rig uses the original naming (%d bones)" % len(tgt.data.bones))
TGT_HIPS = MAP.get("Hips", "Hips")
missing = [n for n in MAP.values() if n not in tgt.data.bones]
if missing:
    raise RuntimeError("target rig is missing mapped bones: %s" % missing)

# Anything not bound to the skeleton is not part of the body. Downloaded models
# often carry a leftover object from the scene they were exported from; unskinned,
# it cannot follow the character and just hangs in the air.
for ob in [o for o in bpy.data.objects if o.type == 'MESH']:
    if not any(m.type == 'ARMATURE' for m in ob.modifiers):
        print("MOVESET: dropped unskinned object '%s' (%d faces)"
              % (ob.name, len(ob.data.polygons)))
        bpy.data.objects.remove(ob, do_unlink=True)

def copy_clip(src_arm, act, dst_arm, name):
    """Copy a clip bone-for-bone from one skeleton onto the same rig.

    Not a retarget and deliberately not one. Both skeletons carry the same bone
    names in the same hierarchy, so a bone's POSE - its offset from its own rest -
    already means the same thing on both, whatever the two builds' proportions.
    Copying that offset frame by frame is exact, and it avoids reinterpreting the
    clip's curves, which is where every transfer loses fidelity.
    """
    src_arm.animation_data_create()
    src_arm.animation_data.action = act
    try:
        if act.slots:
            src_arm.animation_data.action_slot = act.slots[0]
    except AttributeError:
        pass                       # Blender before slotted actions

    shared = [b.name for b in dst_arm.pose.bones if b.name in src_arm.pose.bones]
    for pb in list(src_arm.pose.bones) + list(dst_arm.pose.bones):
        pb.rotation_mode = 'QUATERNION'

    out = bpy.data.actions.new(name)
    out.use_fake_user = True
    dst_arm.animation_data_create()
    dst_arm.animation_data.action = out

    first, last = (int(round(v)) for v in act.frame_range)
    written = 0
    for f in range(first, last + 1):
        scene.frame_set(f)
        written += 1
        for n in shared:
            dst_arm.pose.bones[n].matrix_basis = src_arm.pose.bones[n].matrix_basis.copy()
        for n in shared:
            pb = dst_arm.pose.bones[n]
            pb.keyframe_insert("rotation_quaternion", frame=written)
            pb.keyframe_insert("location", frame=written)
    print("MOVESET: %-10s <- '%s' from the clip library, %d frames, %d bones"
          % (name, act.name, written, len(shared)))
    return out


# Clips taken as-is, kept under the game's names. Renamed before the sweep below
# so the sweep cannot delete them.
kept = {}
by_name = {a.name: a for a in bpy.data.actions}
for game_name, candidates in FROM_SOURCE.items():
    for candidate in candidates:
        act = by_name.get(candidate)
        if act is None:
            continue
        act.name = game_name
        act.use_fake_user = True
        kept[game_name] = act
        break
if kept:
    print("MOVESET: kept the body's own clips: %s" % ", ".join(sorted(kept)))
for a in list(bpy.data.actions):
    if a.name not in kept:
        bpy.data.actions.remove(a)

# A separate library of clips for the same rig, if one was given.
if CLIPS_GLB:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=CLIPS_GLB)
    lib_objects = [o for o in bpy.data.objects if o not in before]
    lib = next(o for o in lib_objects if o.type == 'ARMATURE')
    lib_bones = {b.name for b in lib.data.bones}
    overlap = len(lib_bones & {b.name for b in tgt.data.bones})
    if overlap < len(MAP):
        raise RuntimeError("the clip library shares only %d bone names with the body - "
                           "it was authored for a different rig" % overlap)
    library = {a.name: a for a in bpy.data.actions if a.name not in kept}
    print("MOVESET: clip library has %d clips on a matching rig (%d shared bones)"
          % (len(library), overlap))
    for game_name, candidates in FROM_SOURCE.items():
        if game_name in kept:
            continue
        act = next((library[c] for c in candidates if c in library), None)
        if act is None:
            print("MOVESET: WARN no clip in the library for '%s' (looked for %s)"
                  % (game_name, ", ".join(candidates)))
            continue
        kept[game_name] = copy_clip(lib, act, tgt, game_name)
    for ob in lib_objects:
        bpy.data.objects.remove(ob, do_unlink=True)
    # The library's armature was very likely the active object; the solve loop
    # below switches mode, which needs one.
    bpy.context.view_layer.objects.active = tgt
    tgt.select_set(True)
    for a in list(bpy.data.actions):
        if a.name not in kept:
            bpy.data.actions.remove(a)

# Stand it at the height of the body it replaces. Uniform scale on the roots
# only: bone rotations are scale-free, so nothing about the transfer changes,
# and the clips' own keys are left untouched.
if HEIGHT > 0:
    zs = [(o.matrix_world @ v.co).z
          for o in bpy.data.objects if o.type == 'MESH' for v in o.data.vertices]
    now = (max(zs) - min(zs)) if zs else 0.0
    if now > 1e-6:
        k = HEIGHT / now
        for o in bpy.data.objects:
            if o.parent is None:
                o.scale = (o.scale.x * k, o.scale.y * k, o.scale.z * k)
        bpy.context.view_layer.update()
        print("MOVESET: height %.3f -> %.3f (x%.4f)" % (now, HEIGHT, k))


def rest_world_rotations(ob):
    """Each bone's rest orientation in world space - the reference the transfer is
    measured against."""
    out = {}
    for b in ob.data.bones:
        out[b.name] = (ob.matrix_world.to_3x3() @ b.matrix_local.to_3x3()).to_quaternion()
    return out


def rest_world_heads(ob):
    """Each bone's rest JOINT position in world space.

    Positions, not directions: this rig's bone tail data is unreliable (bones
    report lengths in the thousands on a 170-unit body), so anything derived
    from head->tail is untrustworthy. A joint's location is not.
    """
    return {b.name: ob.matrix_world @ b.head_local.copy() for b in ob.data.bones}


def fit_alignment(src_heads, src_hips_rot, tgt_heads, tgt_hips_rot):
    """The one rotation that maps the source bind pose onto the target's.

    Both skeletons are first expressed in their own pelvis frame, which strips
    out where each happened to be standing and how big each is. What is left is
    purely how the two bind poses are oriented relative to one another,
    recovered by Kabsch: the rotation minimising the squared distance between
    the two sets of corresponding joints.
    """
    pairs = [(s, MAP.get(s, s)) for s in ALIGN_JOINTS]
    pairs = [(s, t) for s, t in pairs if s in src_heads and t in tgt_heads]
    if len(pairs) < 3:
        raise RuntimeError("bind alignment needs 3+ shared joints, got %d" % len(pairs))

    s_inv = src_hips_rot.inverted()
    t_inv = tgt_hips_rot.inverted()
    s_org = src_heads["Hips"]
    t_org = tgt_heads[TGT_HIPS]
    P = np.array([list(s_inv @ (src_heads[s] - s_org)) for s, _ in pairs], dtype=float)
    Q = np.array([list(t_inv @ (tgt_heads[t] - t_org)) for _, t in pairs], dtype=float)
    # Uniform scale cancels out of the rotation, but only once each cloud is
    # normalised - otherwise the taller skeleton dominates the fit.
    P /= (np.linalg.norm(P) or 1.0)
    Q /= (np.linalg.norm(Q) or 1.0)

    U, _, Vt = np.linalg.svd(P.T @ Q)
    d = np.sign(np.linalg.det(Vt.T @ U.T)) or 1.0
    R = Vt.T @ np.diag([1.0, 1.0, d]) @ U.T
    m = Quaternion((1.0, 0.0, 0.0, 0.0)).to_matrix()
    for i in range(3):
        for j in range(3):
            m[i][j] = float(R[i][j])
    residual = float(np.sqrt(((P @ R.T - Q) ** 2).sum() / len(P)))
    return m.to_quaternion(), residual


def limb_alignments(align, src_heads, src_hips_rot, tgt_heads, tgt_hips_rot):
    """One alignment rotation per bone, not one for the whole body.

    The global fit gets the two skeletons standing the same way up and facing the
    same way. It cannot make every limb agree, because the bind poses genuinely
    differ: measured on these two, the performer's elbows are dead straight where
    the character's rest at 30-37 degrees, and the shoulders sit 76 degrees apart
    - a T-pose against an A-pose. Rotating an arm that starts out sideways by the
    same amount as one that starts hanging down does not put it in the same place,
    which is why the legs tracked well while the elbows were 30-60 degrees out.

    So each bone gets the global rotation plus whatever extra turn brings its own
    rest DIRECTION onto its counterpart's. Directions come from joint positions -
    this rig's bone tail data is unusable."""
    s_inv = src_hips_rot.inverted()
    t_inv = tgt_hips_rot.inverted()
    out = {}
    for s_name, s_child in CHILD.items():
        t_name, t_child = MAP.get(s_name), MAP.get(s_child)
        if not t_name or not t_child:
            continue
        if any(n not in src_heads for n in (s_name, s_child)):
            continue
        if any(n not in tgt_heads for n in (t_name, t_child)):
            continue
        ds = s_inv @ (src_heads[s_child] - src_heads[s_name])
        dt = t_inv @ (tgt_heads[t_child] - tgt_heads[t_name])
        if ds.length < 1e-6 or dt.length < 1e-6:
            continue
        extra = (align @ ds.normalized()).rotation_difference(dt.normalized())
        out[s_name] = extra @ align
    for leaf, parent in INHERIT.items():
        if parent in out:
            out[leaf] = out[parent]
    return out


TGT_REST = rest_world_rotations(tgt)
TGT_HEADS = rest_world_heads(tgt)
# Which way each target bone points when nothing has moved it, taken from joint
# positions. Needed to steer the bone at the performer's limb rather than trust
# the rotation alone - see the aim step in the solve loop.
TGT_DIR = {}
for _s, _c in CHILD.items():
    _t, _tc = MAP.get(_s), MAP.get(_c)
    if _t in TGT_HEADS and _tc in TGT_HEADS:
        _v = TGT_HEADS[_tc] - TGT_HEADS[_t]
        if _v.length > 1e-6:
            TGT_DIR[_s] = _v.normalized()
SRC_REST = {}
ALIGN = None
LIMB_ALIGN = {}
made = []

for clip, bvh, start, end, step in CLIPS:
    if clip in kept:
        print("MOVESET: %-10s <- the body's own clip (not solved from capture)" % clip)
        continue
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
        src_heads = rest_world_heads(src)
        ALIGN, residual = fit_alignment(src_heads, SRC_REST["Hips"],
                                        TGT_HEADS, TGT_REST[TGT_HIPS])
        ax, ang = ALIGN.axis, ALIGN.angle
        print("MOVESET: bind alignment %.1f deg about (%.2f, %.2f, %.2f), residual %.4f"
              % (ang * 57.2957795, ax.x, ax.y, ax.z, residual))
        LIMB_ALIGN = limb_alignments(ALIGN, src_heads, SRC_REST["Hips"],
                                     TGT_HEADS, TGT_REST[TGT_HIPS])
        for n in ORDER:
            q = LIMB_ALIGN.get(n)
            if q is not None:
                print("MOVESET:   %-14s limb correction %5.1f deg"
                      % (n, (q @ ALIGN.inverted()).angle * 57.2957795))

    src_hips_rest_inv = SRC_REST["Hips"].inverted()
    tgt_hips_rest = TGT_REST[TGT_HIPS]
    tgt_hips_rest_inv = tgt_hips_rest.inverted()
    arm_inv = tgt.matrix_world.inverted().to_3x3().to_quaternion()

    last = min(end, scene.frame_end)

    # How high the performer's lowest foot is on every frame we are about to
    # use, and the lowest it ever gets - the floor of this capture. Read before
    # anything is solved, because it costs nothing here and the solve needs it.
    src_lift = {}
    for f in range(max(1, start), last + 1, step):
        scene.frame_set(f)
        heights = [(src.matrix_world @ src.pose.bones[n].head).z
                   for n in GROUND if n in src.pose.bones]
        if heights:
            src_lift[f] = min(heights)
    _low = sorted(src_lift.values())
    src_floor = _low[max(0, int(len(_low) * 0.10) - 1)] if _low else 0.0
    # One body's leg against the other's, so a tall character is not asked to
    # crouch by a short performer's centimetres.
    def _leg(ob, hip, foot):
        a = ob.data.bones.get(hip)
        b = ob.data.bones.get(foot)
        if a is None or b is None:
            return 0.0
        return ((ob.matrix_world @ b.head_local) - (ob.matrix_world @ a.head_local)).length

    src_leg = _leg(src, "Hips", "LeftFoot")
    tgt_leg = _leg(tgt, TGT_HIPS, MAP.get("LeftFoot", ""))
    if src_leg < 1e-6 or tgt_leg < 1e-6:
        raise RuntimeError("cannot measure a leg on one of the skeletons "
                           "(source %.4f, target %.4f) - foot planting would be "
                           "applied in the wrong units" % (src_leg, tgt_leg))
    leg_ratio = tgt_leg / src_leg
    print("MOVESET: leg %.3f (character) / %.3f (performer) = x%.4f for foot planting"
          % (tgt_leg, src_leg, leg_ratio))
    tgt_floor = min((tgt.matrix_world @ tgt.data.bones[MAP[n]].head_local).z
                    for n in GROUND if n in MAP and MAP[n] in tgt.data.bones)

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

        # The performer's pelvis this frame. Every bone below is measured
        # against it, so the capture stage's own orientation drops out.
        src_hips_now_inv = (src.matrix_world.to_3x3()
                            @ src.pose.bones["Hips"].matrix.to_3x3()
                            ).to_quaternion().inverted()

        for src_name in ORDER:
            dst_name = MAP.get(src_name)
            spb = src.pose.bones.get(src_name)
            dpb = tgt.pose.bones.get(dst_name) if dst_name else None
            if spb is None or dpb is None:
                continue
            s_rest = SRC_REST.get(src_name)
            d_rest = TGT_REST.get(dst_name)
            if s_rest is None or d_rest is None:
                continue

            s_world = (src.matrix_world.to_3x3() @ spb.matrix.to_3x3()).to_quaternion()
            # What the bone did, in the performer's pelvis frame.
            delta = (src_hips_now_inv @ s_world) @ (src_hips_rest_inv @ s_rest).inverted()
            # Say the same thing in the target's frame, then put it back onto
            # the target's own pelvis and rest pose.
            A = LIMB_ALIGN.get(src_name, ALIGN)
            delta = (A @ delta) @ A.inverted()
            want = tgt_hips_rest @ delta @ tgt_hips_rest_inv @ d_rest

            # AIM, then keep the twist.
            #
            # Carrying the rotation across is right only where the two bind
            # poses agree. They do not: the performer stands in a T-pose, the
            # character in an A-pose, and the shoulders sit 76 degrees apart.
            # Turning an arm that starts out sideways by the same amount as one
            # hanging down does not put it in the same place - measured, the
            # hands missed the performer's by more than the whole distance the
            # performer's hands travelled, while the legs (whose bind poses are
            # close) tracked fine.
            #
            # So the bone is first swung to POINT where the performer's bone
            # points, which fixes where the hand and foot end up, and the
            # rotation transfer above is kept for everything the aim leaves
            # free - the twist about the bone's own length, which is what makes
            # a foot land flat and a palm face the right way. Bones with no
            # child to point at keep the transfer alone.
            child = CHILD.get(src_name)
            t_dir = TGT_DIR.get(src_name)
            spb_child = src.pose.bones.get(child) if child else None
            if t_dir is not None and spb_child is not None:
                s_dir = (src.matrix_world @ spb_child.head) - (src.matrix_world @ spb.head)
                if s_dir.length > 1e-6:
                    # ALIGN, not the per-limb rotation. The per-limb one was
                    # BUILT from the bind difference, so aiming through it just
                    # reproduces the character's A-pose offset - measured, it
                    # made the aim step a no-op to the tenth of a degree. The
                    # whole-body alignment carries only which way the two
                    # skeletons face, which is what an aim should honour.
                    aim = (tgt_hips_rest @ ALIGN @ src_hips_now_inv
                           @ s_dir.normalized())
                    # t_dir is where the bone points at REST, so it has to be
                    # taken back into the bone's own frame before the wanted
                    # rotation is applied to it.
                    now = want @ (d_rest.inverted() @ t_dir)
                    if aim.length > 1e-6 and now.length > 1e-6:
                        _corr = now.normalized().rotation_difference(aim.normalized())
                        if os.environ.get("MOVESET_DEBUG_AIM") and out_frame == 5:
                            print("AIMDBG %-14s correction %6.1f deg"
                                  % (src_name, _corr.angle * 57.2957795))
                        want = _corr @ want

            m = dpb.matrix.copy()
            posed = (arm_inv @ want).to_matrix().to_4x4()
            posed.translation = m.to_translation()
            dpb.matrix = posed
            # Children read their parent's matrix, so it must be live first.
            bpy.context.view_layer.update()
            solves += 1

        if os.environ.get("MOVESET_DEBUG_POSE") and out_frame in (5, 20):
            for _n in ORDER:
                _c = CHILD.get(_n)
                _t, _tc = MAP.get(_n), MAP.get(_c) if _c else None
                _sp, _spc = src.pose.bones.get(_n), src.pose.bones.get(_c) if _c else None
                _dp = tgt.pose.bones.get(_t) if _t else None
                _dpc = tgt.pose.bones.get(_tc) if _tc else None
                if not (_sp and _spc and _dp and _dpc):
                    continue
                _sv = (src.matrix_world @ _spc.head) - (src.matrix_world @ _sp.head)
                _tv = (tgt.matrix_world @ _dpc.head) - (tgt.matrix_world @ _dp.head)
                if _sv.length < 1e-6 or _tv.length < 1e-6:
                    continue
                _goal = ALIGN @ (src_hips_now_inv @ _sv.normalized())
                _have = tgt_hips_rest_inv @ _tv.normalized()
                print("POSEDBG f%-3d %-14s %6.1f deg from goal"
                      % (out_frame, _n, _goal.angle(_have) * 57.2957795))

        # Everything the solve can leave on a bone, not just the rotation.
        # `dpb.matrix = ...` sets the bone's whole transform; a translation or a
        # scale left behind by that is part of the pose, and a channel that is
        # never keyed does not exist in the exported clip at all.
        # PLANT. Everything above is angles; this is the one length that matters.
        hips_pb = tgt.pose.bones.get(TGT_HIPS)
        if hips_pb is not None and f in src_lift:
            standing = [(tgt.matrix_world @ tgt.pose.bones[MAP[n]].head).z
                        for n in GROUND if n in MAP and MAP[n] in tgt.pose.bones]
            if standing:
                want_low = tgt_floor + max(0.0, src_lift[f] - src_floor) * leg_ratio
                dz = want_low - min(standing)
                world = tgt.matrix_world @ hips_pb.matrix
                world.translation.z += dz
                hips_pb.matrix = tgt.matrix_world.inverted() @ world
                bpy.context.view_layer.update()

        for pb in tgt.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=out_frame)
            pb.keyframe_insert("location", frame=out_frame)
            pb.keyframe_insert("scale", frame=out_frame)

    act.use_fake_user = True
    made.append((clip, out_frame))
    print("MOVESET: %-10s <- %s frames %d..%d -> %d keyed (%d bone solves)"
          % (clip, bvh, start, last, out_frame, solves))

    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.data.objects.remove(src, do_unlink=True)

# The BVH importer leaves its own action behind for every trial read. They are
# not the character's and exporting them ships four extra skeletons' worth of
# curves in the game's asset.
for name, act in kept.items():
    made.append((name, int(act.frame_range[1] - act.frame_range[0]) + 1))
keep = {c for c, _ in made}
for a in list(bpy.data.actions):
    if a.name not in keep:
        bpy.data.actions.remove(a)

scene.render.fps = 30
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', export_apply=False,
                          export_animations=True, export_animation_mode='ACTIONS',
                          export_image_format='AUTO')
print("MOVESET: exported %s (%.1f MB) with %d clips: %s"
      % (GLB, os.path.getsize(GLB)/1048576.0, len(made), ", ".join(c for c, _ in made)))
_HOLD.__exit__(None, None, None)
