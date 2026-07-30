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

ALIGN_JOINTS = ["Hips", "LowerBack", "Spine", "Spine1",
                "LeftArm", "RightArm",
                "LeftUpLeg", "LeftLeg", "LeftFoot",
                "RightUpLeg", "RightLeg", "RightFoot"]

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
    t_org = tgt_heads["Hips"]
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
                                        TGT_HEADS, TGT_REST["Hips"])
        ax, ang = ALIGN.axis, ALIGN.angle
        print("MOVESET: bind alignment %.1f deg about (%.2f, %.2f, %.2f), residual %.4f"
              % (ang * 57.2957795, ax.x, ax.y, ax.z, residual))
        LIMB_ALIGN = limb_alignments(ALIGN, src_heads, SRC_REST["Hips"],
                                     TGT_HEADS, TGT_REST["Hips"])
        for n in ORDER:
            q = LIMB_ALIGN.get(n)
            if q is not None:
                print("MOVESET:   %-14s limb correction %5.1f deg"
                      % (n, (q @ ALIGN.inverted()).angle * 57.2957795))

    src_hips_rest_inv = SRC_REST["Hips"].inverted()
    tgt_hips_rest = TGT_REST["Hips"]
    tgt_hips_rest_inv = tgt_hips_rest.inverted()
    arm_inv = tgt.matrix_world.inverted().to_3x3().to_quaternion()

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

        for pb in tgt.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=out_frame)

    act.use_fake_user = True
    made.append((clip, out_frame))
    print("MOVESET: %-10s <- %s frames %d..%d -> %d keyed (%d bone solves)"
          % (clip, bvh, start, last, out_frame, solves))

    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.data.objects.remove(src, do_unlink=True)

# The BVH importer leaves its own action behind for every trial read. They are
# not the character's and exporting them ships four extra skeletons' worth of
# curves in the game's asset.
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
