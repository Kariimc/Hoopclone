# HANDOFF - Kariimc/Hoopclone

> Continuity doc. Any agent must resume cold from this file with zero briefing.
> Update it in the same commit as any code change.

**Seeded:** 2026-07-15 from verified repo state. Sections marked UNVERIFIED were not
provable from the repo alone - fill them in, do not guess.

## Verified facts

| | |
|---|---|
| Repo | `Kariimc/Hoopclone` |
| Namespace | user `Kariimc` |
| Default branch | `main` |
| Visibility | public |
| Language | GDScript |
| Files | 113 |
| Last commit | 2026-07-08 - fix(scene+sim): Sprint 5 refactor-first pass + live progress tracker ( |
| Branches | 14 |
| Open PRs | 1 |

**Top-level dirs:** `.claude`, `.github`, `assets`, `data`, `docs`, `game`, `tests`, `tools`

**Root files:** `.gitattributes`, `.gitignore`, `ADD-ASSETS.bat`, `CLAUDE.md`, `GET-LATEST.bat`, `PLAY.bat`, `PROGRESS.md`, `README.md`, `SAVE-WORK.bat`, `icon.svg`, `icon.svg.import`, `manifest.json`

**Existing docs:** `CLAUDE.md`, `PROGRESS.md`, `README.md`, `docs/SPRINT_6_7_ARCHITECTURE.md`

## Open PRs

- #16 refactor: sprint-5 prep — bug fixes + main.gd split + smoke test  `refactor/sprint5-prep`

## Current state

**Session 2026-07-29 (laptop, Claude Code).** Verified by running the commands,
not inferred:

- The project now opens on **Godot 4.7** (it was authored against 4.3). Opening
  it rewrote every `.import` sidecar and generated the `.uid` files Godot 4.4+
  expects. That churn is committed on its own as a `chore:` commit so it never
  gets confused with behavior changes.
- **Godot MCP Pro v1.15.1** (paid) is installed into this project and registered
  globally for every Claude Code session on this laptop, so any session gets the
  editor bridge without a per-folder setup step. The addon itself and `.mcp.json`
  are **gitignored** - this repo is public and the addon is paid software.
  Reinstall it from the purchased zip on any other machine.
- **PROGRESS.md Sprint 5 step 1f is done** (`GameState` is now an autoload the
  scorebug and ticker actually read). Proven green: engine self-test 12/12,
  revert-to-red on the new same-phase guard, and an error-free headless boot of
  `main.tscn` that reports phase `LIVE`.

Everything else in PROGRESS.md is unchanged - that file, not this one, is the
authoritative checklist.

### Session 2026-07-29, part 2 - the court had no floor

A council (three challenger voices + a synthesizing judge) was run on "what
next". Verdict, which overruled the initial instinct to do a visual/asset pass
first: fix the physics, then build the possession loop, and ship something
VISIBLE in the same block so progress is legible to a non-programmer owner.

Fixed and committed:

- The court had **no collision shape**. Nothing in the game was standing on
  anything. Added one to the `Floor` body.
- Neither `player.gd` nor `defender.gd` applied gravity. Both do now.
- The player's capsule was the engine default (radius .5, height 2) centred ON
  the origin, so resting on the floor left the model a metre up. Now matches the
  defender: radius .35, height 1.9, offset to stand on its feet.
- **Root cause of the floating:** the defender slid into the attacker, the
  attacker climbed the capsule and was carried at head height (measured Y 1.897)
  while the pair drifted down the floor together. Player and defender now sit on
  **separate collision layers masking only the floor**, so bodies pass through
  each other. The contest model reads positions, never contacts, so nothing is
  lost. Real jostling/screens are a later feature needing a shared layer AND an
  anti-climb rule - do not simply re-merge the layers.
- Defender slide gained arrival braking so it settles on its guard spot.
- `run_tests.gd` now boots the real `main.tscn` and asserts the wiring chain plus
  both standing heights. This closes the audit's §6 test-strategy gap and is the
  guard for the whole bug class above. 21/21 green.

**Gotcha that cost time:** with the Godot editor open, a **newly created** script
under `res://` will not run via `--script` - the run hangs until the editor
imports it. Existing scripts are fine. Put throwaway diagnostics inside an
already-imported file (e.g. `run_tests.gd`) rather than creating a probe file.

**Next:** the possession loop (`tools/sim/possession.py`), headless and seeded,
then its GDScript mirror, then place the already-written scorebug and ticker in
the scene so the owner can see a clock and a score move.

### Session 2026-07-29, part 3 - the look pass

Owner overruled the council and asked for looks before game logic. Delivered:

- **HoopBuilder** (`game/arena/hoop_builder.gd`) turns each bare hoop anchor into
  a real basket: rim torus, line-mesh net, glass backboard with a white padded
  border and painted shooter square, gooseneck, stanchion, padded base. It never
  moves the anchor - the anchor origin IS rim centre and the ball, shot and
  contest models all read it.
- **CrowdFans** (`game/arena/crowd_fans.gd`) draws 688 seated spectators through
  ONE MultiMesh with every bit of motion in a vertex shader. That is the standard
  stadium-crowd technique: the CPU never touches a fan. Per-instance custom data
  carries a seed (rhythm, build, shirt colour, eagerness) so no two move together.
  CrowdBowl owns the instance and forwards `set_intensity`, so the existing
  made-basket hook already puts them on their feet.
- **Kit swap fixed.** Measured: `player_base.glb` is a SINGLE mesh with ONE
  surface and one baked full-body texture; the `*_jersey_albedo.png` files are
  flat 2D garment layouts (front panel, back panel, shorts on a white sheet), NOT
  unwrapped to this model's UVs. Assigning one as albedo painted garment artwork
  across the whole character, face included - which is exactly what the owner saw.
  Teams now TINT the baked texture. A real swap is gated behind a new
  `"jersey_uv_matched": true` flag per team in the manifest, only correct once
  someone authors a kit unwrapped to this model.

**Two Godot gotchas that cost real time, both about the editor holding imports:**
1. A **newly created** script under `res://` will not run via `--script` while the
   editor is open - the run HANGS. Put throwaway diagnostics inside an
   already-imported file instead.
2. A new `class_name` is not visible to other scripts until Godot re-scans. Run
   `godot --headless --editor --quit --path .` once after adding one, or every
   caller fails with `Identifier "X" not declared in the current scope`.

**Live-play loop:** a watcher script in the session scratchpad keeps one playable
window open and restarts it whenever a game file changes (about 4 seconds), so the
owner plays continuously while edits land. It only ever kills the PID it started.

**Still visibly wrong:** fans are blocky and read as furniture; a wide empty dark
band surrounds the court; the defender is still a blue capsule; still 1-on-1 not
5-on-5; no arena above the crowd; no score or clock on screen.

**Next:** better fan geometry (owner has Meshy, authorised free CC0 model
downloads, and named the `3d-master-modeler` skill - which routes engine assets
through headless Blender; `bpy` is NOT installed on this laptop). Then 5-on-5,
then the possession loop.

### Session 2026-07-29, part 4 - modelled crowd

Ran the `3d-master-modeler` skill properly (run card at
`tools/models/RUNCARD-crowd-fan.md`, all eight rows filled).

- **Blender 5.2 is ALREADY INSTALLED** at `C:\Program Files\Blender Foundation\
  Blender 5.2` and runs headless (`blender.exe --background --factory-startup
  --python <script>`, Python 3.13.13). Do not try `pip install bpy` on this
  laptop - no wheel exists for its Python 3.12, and the attempt wastes minutes.
- The laptop's network is **fully open**: blender.org, download.blender.org and
  the Poly Haven API all answered 200. Real CC0 photographed PBR sets and HDRIs
  are available for the court, courtside and props whenever wanted.
- `tools/models/build_fan.py` builds the seated spectator and is the only way the
  asset should ever change - regenerate, never hand-edit the GLB. 456 triangles,
  zero non-manifold edges, 24 KB.
- The mesh's **second UV channel carries the animation tags** (0 legs, 1 torso,
  2 arms, 3 head; V = height up that part). The Godot vertex shader reads them to
  sit, sway and stand the fans. Any replacement mesh MUST carry the same tags or
  the crowd stops animating.
- Godot colours each fan itself: shirt from instance colour, trousers a darkened
  take on it, skin from a per-instance tone. No textures on the crowd at all.

**Blender gotcha (cost one pass):** a UV loop element is a `BMLoopUV` on some
builds and a plain `Vector` on others - `l[uv][:] = ...` throws
`'BMLoopUV' object does not support item assignment`. The build script handles
both. **Modelling gotcha (cost one pass):** build figures facing **-Y**; +Y means
every render and the engine sees the back of the model.

**Next:** the defender is still a blue capsule, the court is ringed by a wide
empty dark band, and there is still no score or clock. 5-on-5 and the possession
loop remain the two big pieces.

### Session 2026-07-29, part 5 - five a side, and the concrete

- The blue capsule is gone. The defender wears the real player model in the away
  kit, via a shared `_dress()` helper in the spawner.
- `main.gd` now loads `data/rosters/league.json` and splits it BY TEAM
  (`_load_teams`). The old `_load_roster` flattened every team into one list,
  which is the reason only the first player of the first team was ever used.
- Ten bodies on the floor: 5 CRW vs 5 STM. The four extra defenders are real
  Defender nodes that are deliberately never `assign()`ed a man, so they hold
  their spots instead of all chasing the ball. They ARE registered on the shot,
  so the contest model sees all five and a shot into a crowd is punished.
- `game/arena/seating_deck.gd` fills the dark ring: a stepped bowl of treads and
  risers derived FROM the CrowdFans constants (change the crowd layout and the
  concrete follows), a dark apron, 52 courtside chairs on both sidelines, and a
  scorer's table on the far side.

### ANIMATION - measured facts, read before promising anything

`assets/models/player_base.glb` contains **one animation clip, 0.30 seconds long,
5 tracks**. That is a stub, not an animation. It is the entire reason the player
stands holding the ball: there is nothing to play. `anim_state_machine.gd`
enumerates a full moveset but no clip behind any state exists.

The skeleton is **24 bones with Mixamo naming** (Hips, LeftUpLeg, LeftLeg,
LeftFoot, LeftToeBase, Spine/Spine01/Spine02, LeftShoulder, LeftArm, LeftForeArm,
LeftHand, neck, Head, ...). That is the good news - this rig accepts
Mixamo-format clips almost directly.

Sources checked (2026-07-29):
- **Mixamo** - has basketball clips (dribble, shoot, layup), free for commercial
  use, but downloads need an Adobe login. Only Kariim can do that step.
- **Quaternius Universal Animation Library** - CC0, 120+ clips, explicitly
  Mixamo-rig compatible, FBX/GLB/Godot builds, free tier. **No sports clips** -
  locomotion, combat, emotes only. Useful for run/idle/strafe, useless for
  dribble/jumpshot. itch.io needs an account to download.
- Hand-authoring clips in Blender against these known bone names is viable
  (3d-master-modeler Template I) and needs no login. Lower ceiling than mocap.

### Session 2026-07-29, part 6 - motion capture WITHOUT a graphics card

Measured: this laptop has **Intel Iris Xe integrated graphics, no CUDA**. That
rules out the whole GVHMR / WHAM / 4D-Humans class of video-to-motion tools -
they are CUDA-only. Do not sink time into them here.

**The workaround that does work: MediaPipe Pose, which runs entirely on the CPU.**
Installed (`mediapipe 1.0.0`, pulls opencv + matplotlib, userspace). No account,
no GPU, no cloud. Two tools now live in `tools/mocap/`:

- `video_to_joints.py` - any video file -> JSON of smoothed 3D joint tracks.
- `retarget_to_rig.py` - that JSON -> bone rotations on the SHIPPED 24-bone rig
  -> a glTF whose animations Godot imports by name. It solves each bone from the
  DIRECTION between two tracked joints, expressed in parent space and walked
  parents-first down the chain. Bone lengths are never touched, so the character
  keeps its own proportions regardless of who was filmed.

**Rights note, stated once:** pulling motion out of broadcast footage and shipping
it is a rights problem, not a technical one. Film it, or use footage we own.

### The lesson that changes how clips get authored

A first pass hand-authored six clips (idle, dribble, run, jumpshot, def_slide,
rebound) by picking **euler angles per bone by eye**. Rendering the jumpshot
proved it wrong: the arms tear into spikes, because the assumed local bone axes
are not the rig's actual axes. **Do not author clips by hand-picked euler angles
on this rig.**

The correct route is the one the retargeter already implements: author a move as
**joint TARGET POSITIONS** and let the same direction-solver turn those into bone
rotations. No axis guessing, and it shares a single code path with video capture.
That is the next piece of work.

Also worth knowing: the base player model renders **well** - a proper basketball
player in a numbered kit. The art is not the weak link; the animation is.

**PowerShell gotcha:** piping a long-running command into `Select-Object -First N`
KILLS it when N results arrive. A 38-frame render silently stopped at 5 frames.
Redirect to a file and filter afterwards.

### Session 2026-07-29, part 7 - real basketball motion capture, retargeted

**The find:** Carnegie Mellon's Graphics Lab motion capture database is free, has
no licence fee, and **subject 06 is basketball** - forward/backward/sideways
dribble, dribbling with turns, freestyle dribble, and crossover-and-shoot. All 15
trials are downloaded to `assets/mocap/06_01.bvh` .. `06_15.bvh` from the GitHub
mirror `una-dinosauria/cmu-mocap` (path shape `data/006/06_NN.bvh` - note the
THREE-digit folder). No GPU, no account, no video needed.

Trial map: 06_02..05 forward dribble, 06_06..07 backward, 06_08..09 sideways,
06_10..12 dribble with turns, 06_13 freestyle, **06_14..15 crossover + shoot**.

`tools/mocap/retarget_bvh.py` drives the shipped player rig from a BVH. The CMU
skeleton names its limb bones IDENTICALLY to ours (LeftUpLeg, LeftForeArm, ...);
only spine/neck differ and are mapped explicitly.

**Three method failures, recorded so nobody repeats them:**
1. Hand-picking euler angles per bone - tore the arms into spikes. The rig's
   local bone axes are not what they look like. Never author this rig that way.
2. Composing the correction quaternion by hand in parent space - contorted the
   whole body. **The method that works: write `pose_bone.matrix` directly**
   (armature space) and call `view_layer.update()` before solving the children,
   so Blender derives the local rotation including each bone's rest orientation.
3. Deriving travel scale from leg lengths and THEN multiplying by 100 - threw the
   player a hundred metres off camera. The leg-length ratio already converts into
   the rig's bone units; do not scale again.

**Also load-bearing:** the collarbones are deliberately NOT retargeted. The two
skeletons hang their clavicles at very different rest angles, and aiming them by
direction dragged the whole arm chain into the chest. Left at rest they act as a
stable socket while the upper arm carries the motion - standard practice.

**State:** legs, hips, spine and head retarget cleanly and read as a real person
moving. The arms are stable but under-driven - they track low and do not yet read
clearly as a dribble. Next step is the arm chain, then batch all 15 trials into a
clip library and wire it to `anim_state_machine.gd`.

**PowerShell gotcha, again:** piping a long render into `Select-Object -First N`
kills it early. Redirect to a log file and filter afterwards.

### Session 2026-07-29, part 8 - motion capture is IN THE GAME, and a live loop

Every body on the floor now loads `assets/models/player_animated.glb` - the same
model with a retargeted CMU capture baked on - and plays it looped, each starting
at a random point in the cycle so ten players do not dribble in unison. The bare
model stays as an automatic fallback, so the scene still runs if no clip has been
generated yet. Clips are retargeted **in place** (`--in-place 1`, the default):
the GAME moves the character, and a clip that also travels makes him skate.

**Two live channels now exist, both automatic:**
- `game/ui/build_feed.gd` draws a panel over the game showing whatever is in
  `.build_status.txt`. Write to that file and the player sees it within a second.
- `game/dev/session_recorder.gd` writes `dev_session/session.log` (position,
  speed, feet-down, defenders contesting, fps, twice a second) and a screenshot
  every three seconds. That is how a session gets debugged without the player
  having to describe anything. Both are gitignored and editor/debug only.
- A watcher script in the session scratchpad restarts the game window whenever a
  file under `game/`, `assets/`, `data/` or `project.godot` changes. It does NOT
  watch `tests/`. **A stale window is the first thing to suspect** when the live
  game disagrees with a headless run - it cost a debugging detour here.

### The next real blocker: the ball is part of the player's body

`player_base.glb` has a basketball MODELLED AND TEXTURED INTO the mesh, in his
right hand. That is why he reads as holding a ball rather than dribbling: the
ball is welded to the hand and moves with it. A separate Ball node is spawned too,
so there are effectively two balls.

Removing it is not a quick win: the mesh is **28,463 verts in 2,555 disconnected
loose parts** (typical of a generated mesh), so "separate by loose parts" does not
isolate the ball. Next approach: classify faces by sampling the albedo texture at
their UVs (basketball orange is well separated from the blue kit, less so from
skin) AND gate on proximity to the RightHand bone, then delete that set and export
a ball-free player. The ball then becomes the existing standalone Ball node,
parented to the hand only while dribbling.

### Session 2026-07-29, part 9 - the welded ball is out

tools/models/strip_ball.py removes the basketball that was modelled and textured
INTO the player mesh. It produces assets/models/player_noball.glb, which is now
the source the motion-capture retarget runs on.

How it finds the ball, because no single signal works:
1. Which hand - count ball-coloured faces near each hand bone and take the
   winner. The first attempt assumed RightHand and bit a hole in the EMPTY hand.
   The ball is in LeftHand.
2. Colour - sample the albedo texture at each face UV; basketball leather is a
   saturated orange. Skin shares the hue but not the saturation, so saturation is
   what actually separates them.
3. Settle the centre - colour alone also catches orange kit trim, so iterate a
   median inside one ball radius until the centre converges on the ball.
4. Geometric sweep - take the whole sphere around that centre, because the dark
   seam lines and shaded underside fail the colour test and otherwise survive as
   an orange fringe. Spare faces close to the hand bone so the fingers stay,
   EXCEPT ones colour already flagged as leather, or a fleck survives between
   the fingers.

Result: 3,180 faces removed, mesh 30,933 -> 27,753 polys, hand intact.

PREMIUM ASSET GENERATION IS AVAILABLE. Higgsfield exposes Tripo text-to-3D and
image-to-3D with texture_quality/geometry_quality set to "detailed" plus PBR, and
Meshy for rigging existing GLBs. The account is on the ultra plan with ~2,585
credits; a detailed textured asset costs about 12.5. Meshy via the Unity bridge
is NOT usable here - it needs the Unity editor running and imports into a Unity
project, not Godot.

Live-reload gotcha: the watcher only matched *.gd,*.tscn,*.tres,*.json, so
regenerating a .glb did NOT restart the game and the window silently showed stale
art. It now also watches glb/png/jpeg/bvh/import.
### Session 2026-07-29, part 10 - premium generated assets, cut to budget

The asset route is: generate at the HIGHEST quality setting, then cut it down.
Generated assets arrive unusable for real time - the basketball came back at
1,907,500 triangles and 55 MB - and the detail that actually reads at broadcast
distance lives in the normal and colour maps, not in raw geometry.

- assets/models/basketball.glb - 2,999 tris, 0.7 MB, 2K colour/normal/ORM.
  Replaces the flat orange sphere. The old textured sphere stays as a fallback so
  the scene never depends on the asset existing.
- assets/models/crowd_fan.glb - a real seated person with a photographed texture,
  1,400 tris, 0.13 MB. Replaces the hand-built blocky body.

Reusable tools, both in tools/models/:
- optimise_asset.py - decimate to a triangle target and downscale textures. Run
  this on EVERY generated asset before it enters the project.
- prep_crowd_fan.py - tags every vertex in a SECOND UV channel with which body
  part it belongs to (0 legs, 1 torso, 2 arms, 3 head, plus height up that part).
  A generated model has no idea what a limb is, and the crowd's vertex shader
  needs those tags to sit, sway and stand the fans. ANY replacement crowd mesh
  must go through this or the crowd stops animating.

The crowd shader now samples the model's own texture and only TINTS the shirt per
instance, so skin, hair and jeans keep what the photograph gave them. Tinting
everything turned the stands into painted statues.

Generation settings that matter: model tripo_3d (or tripo_h3_1_image_to_3d),
texture_quality "detailed", geometry_quality "detailed", pbr true, auto_size true,
and face_limit to cap the mesh at source. About 12.5 credits per asset.
### Session 2026-07-29, part 11 - the full moveset, and a shared asset library

tools/mocap/build_moveset.py builds EVERY clip into one glTF in a single pass.
Five clips, each a slice of a Carnegie Mellon basketball capture retargeted onto
the player rig: idle, dribble, run, crossover, jumpshot. Edit the CLIPS table at
the top to add or re-time one; nothing else needs touching.

game/player/clip_driver.gd picks the clip from how the body is actually moving -
run above 1.2 m/s, dribble while walking, idle when still - and a shot clip wins
for 0.85 s when the player releases the shoot button. It resolves clip names
tolerantly because glTF prefixes them with the armature, and a missing clip is
skipped rather than fatal so a body without animation still spawns.

### Shared asset library: C:\Users\Kariim\Dev\asset-library (its own git repo)

Not tied to this project. Holds three A-pose base bodies (athletic male, athletic
female, heavyset male) as untouched raw generations PLUS the pipeline tools:
optimise_asset.py, retarget_bvh.py, strip_prop_from_mesh.py. Its README carries
the rule everything follows - generate at maximum quality, then cut to budget -
with the measured numbers behind it.

Meshy rigging (3d_rigging via Higgsfield) FAILED server-side on a 20k-face,
4K-texture body. Not retried. If it is wanted later, try a decimated body first.
### Session 2026-07-29, part 12 - two bugs that hid every generated asset

The owner reported the crowd looked like untextured mannequins sitting the wrong
way, and that nothing from the asset generation was visible. Both were real.

1. **Facing.** A generated model arrives pointing wherever the generator felt
   like - this one was 93.5 degrees off - and the placement code cannot know
   that, so 688 people sat sideways to the court. `prep_crowd_fan.py` now finds
   forward GEOMETRICALLY (a seated person's shins and feet stick out in front, so
   the direction from the body centre to the centroid of its lowest slice is
   forward) and rotates the mesh to face -Y before anything else. Bounds are
   re-measured after the rotation because the part tagging depends on them.
2. **Texture.** Reading the albedo back off the imported glTF material in Godot
   returned nothing, so `has_tex` stayed 0 and the whole crowd rendered flat.
   The prep script now writes the colour map out as its own PNG beside the model
   and CrowdFans loads it BY PATH.

Lesson for every future generated asset: never trust its orientation, and never
rely on pulling a texture back out of an imported glTF material - export the map
alongside and load it explicitly.

### Council verdict on what "AAA" actually means here (2026-07-29)

Three challenger voices plus a synthesiser, all independent. Unanimous: the gap
is NOT fidelity. The arena is already past the bar. Ranked, with status:

1. Broadcast HUD - score, game clock, shot clock. MISSING.
2. Sound - dribble, sneakers, rim, net, crowd bed. MISSING ENTIRELY.
3. Ball lives in the hand. BROKEN - it is a separate object that does not follow.
4. Consequence - possession change, out of bounds, rebounds, fouls. MISSING.
5. Motion continuity - blended locomotion. BROKEN, clips snap.
6. Presentation reactions - crowd swell, replay. MISSING.
7. Environment fidelity. ALREADY STRONG - stop polishing it.
8. Unique faces per player. Do NOT fund - invisible at broadcast distance.

The dissent worth keeping: the owner's eye is a biased instrument. The floating
ball and the clip snapping only show in MOTION, so work must be shown to him
running and with sound, not as a still.
### Session 2026-07-29, part 13 - the "unnatural mesh", and how badly I chased it

The owner reported the players looked "crazy and unnatural": a long blue blade
sweeping across the body whenever they moved. Finding it took SIX wrong theories
and they are all written down here so nobody repeats them.

Wrong theories, in order:
1. Broken faces in the rest mesh - measured, zero found. The faces are all normal
   sized at rest; only posing breaks them.
2. Bad skin weights, checking each vertex's DOMINANT bone - reported a clean
   mesh. The dominant binding IS correct; the fault is a minor influence.
3. Culling faces that get long when posed, by absolute length - loose thresholds
   left the blade, tight ones ate the shorts hem and punched holes in him.
4. Culling by stretch RATIO (posed length / rest length) - better, still left it.
5. A stray 2-metre Icosphere with no material found riding inside the model.
   Real, removed (`tools/models/strip_stray_objects.py`), but NOT the blade.
6. Retargeting flinging the left foot 57 units sideways. Also real, also fixed
   (feet and toes are now left at rest like the collarbones) - but not the blade.

**The actual cause, and the reason my own test kept lying:** ~350 shorts vertices
at hip height carry a full-weight binding to the **RightHand** bone. When the
hand moves they are hauled to shoulder height, and the stretched shorts are the
blade.

My weight check missed it five times because it measured distance to the bone's
LENGTH (head->tail segment). **This rig's tail data is garbage** - bones report
lengths of 2,000-3,000 units on a 170-unit body - so every bone reads as an
enormous rod passing near everything, and every vertex measures "close".
`fix_weights.py` now measures to the JOINT position only, which is trustworthy.

**Settings that work** (anything more aggressive breaks the arms - verified):

    fix_weights.py --max-frac 0.16 --bones "LeftHand,RightHand,LeftForeArm,RightForeArm,LeftFoot,RightFoot,LeftToeBase,RightToeBase"

**Order matters:** the fix must be applied to `player_noball.glb`, the SOURCE the
moveset is built from. Applying it to `player_animated.glb` is thrown away the
next time the moveset is rebuilt - that cost a full debugging cycle.

**Pipeline, in order:** strip_ball -> fix_weights -> build_moveset ->
strip_stray_objects -> player_animated.glb.

### The ball now lives in the hand

A BoneAttachment3D follows the LeftHand bone; the ball rides it and pumps to the
floor and back on a procedural beat that quickens with the handler's speed. It
settles into the hand when he stops, releases automatically on a shot, and comes
back to him when the shot resolves.
### Session 2026-07-29, part 14 - the broadcast scorebug

game/ui/scorebug_3d.gd - team marks, score, quarter, game clock and a 24-second
shot clock along the bottom. Ranked FIRST by the review council: a player clocks a
missing scoreboard in about a second, long before they judge any model.

It OWNS the clocks. Anything needing to know whether play is live asks it, rather
than every system running its own timer and slowly disagreeing. It emits
period_ended and shot_clock_expired for the possession rules to consume.

Details that matter: the shot clock turns red under five seconds, and the game
clock switches to tenths inside the last minute, which is what makes a final
possession feel like one.

A made basket scores through it FIRST, then the crowd reacts - so the roar reads
as a reaction to the number changing. Worth comes from shot.was_three(), added to
the shot controller, because the shot model already decided whether the attempt
was behind the line.

Gotcha: anchoring the container itself to the bottom of the screen collapsed it to
zero size and the whole bug rendered off-screen. A full-rect Control with a
bottom-aligned VBox inside it is what works.
### Session 2026-07-29, part 15 - the arena has sound

Ranked second by the council, and for a blunt reason: silence is not read as a
small budget, it is read as a broken game. Real basketball is sonically dense and
its absence is instantly wrong even to someone who could not say why.

**The sounds are SYNTHESISED, not downloaded.** Every free basketball SFX pack
found needed an account (itch.io, Gumroad, ZapSplat) and nothing usable was
reachable as a direct download. These sounds are physically simple enough to build
honestly, and building them means no licence, no account and exact control:

`tools/audio/make_sfx.py --out assets/audio` writes 13 files - three dribble
variants at different hardness, three sneaker squeaks, rim, backboard, swish,
whistle, buzzer, an 11-second seamless crowd bed and a 3-second crowd roar.
Fixed RNG seed, so the set is reproducible. The crowd bed cross-fades its own tail
into its head so the loop has no seam.

`game/audio/audio_director.gd` owns playback. Eight voices pooled, because a
dribble fires every third of a second and would cut itself off with one player.
Variants never repeat back to back and pitch is jittered per hit so nothing sounds
mechanical. A missing file is skipped rather than fatal.

Wiring worth knowing:
- The ball emits `bounced(speed)` at the exact moment of floor contact - the
  audio listens for that instead of guessing a rhythm, so the sound lands ON the
  bounce whether he is dribbling or the ball is loose.
- Made basket: net first, then the crowd surging under it. Miss: iron, with glass
  first about a third of the time.
- The crowd you SEE and the crowd you HEAR ride one dial (`main._set_crowd`), so
  they cannot drift apart.
- Sneaker squeaks trigger on the ANGLE between the old and new heading above a
  real speed, not simply on movement - which is when a shoe actually squeaks.
- Buzzer on period end, whistle on shot-clock expiry, both from the scorebug's
  own signals.
### Session 2026-07-29, part 16 - motion continuity

Three changes to `clip_driver.gd`, all aimed at the same thing: motion that reads
as a person moving rather than animation playing on top of movement.

1. **Hysteresis.** A single speed threshold makes the clip flicker whenever the
   player hovers on it, which reads far worse than either clip alone. He has to be
   clearly running (1.6 m/s) before the run starts and clearly slower (1.1 m/s)
   before it stops.
2. **Smoothed speed.** The decision reads a smoothed speed, so one jittery frame
   can never change which clip is playing.
3. **Speed-matched playback.** Each locomotion clip records how fast the captured
   performer was travelling; playback is scaled by actual speed over that. This is
   the single biggest thing that stops retargeted motion looking like skating.

Cross-fade was already in place (0.22 s), so the council's "clips snap" note was
half right - the snap was the threshold flicker, not a missing blend.

## Where this stands against the council's ranked list

1. Broadcast HUD - **DONE** (score, quarter, game clock, shot clock)
2. Sound - **DONE** (13 synthesised sounds, all wired to real events)
3. Ball lives in the hand - **DONE** (bone attachment, procedural dribble)
4. Consequence - possession change, out of bounds, rebounds, fouls - **NOT DONE**
5. Motion continuity - **DONE** (blend, hysteresis, speed matching)
6. Presentation reactions - crowd swell **DONE**; replay, announcer NOT DONE
7. Environment fidelity - already strong, deliberately left alone
8. Unique faces - deliberately NOT funded, invisible at broadcast distance

**The one big remaining piece is number 4: consequence.** There is still no
possession change, no out of bounds, no rebound contest and no fouls - which means
the ball cannot actually be lost. That is the next real feature-shaped work, and
it is game logic, not art.
### Session 2026-07-29, part 17 - the lighting pass, and why the assets looked cheap

The owner reported the assets looked cheap and not hyper-realistic. Judged against
a full-resolution frame (the 640x360 session grabs hide all of this), the models
were never the problem. Four things were:

1. **Nothing cast a shadow.** Every player floated. This is the single biggest
   tell in the whole frame.
2. **The court was matte.** A match-day floor is sealed and buffed to nearly a
   mirror; a matte plane reads as the wrong material before anyone questions
   geometry.
3. **The stands were brighter than the floor** - backwards for a broadcast. A
   broadcast arena lights the court and lets the stands fall into the dark. That
   CONTRAST is the look; evenly lit reads as a gym.
4. **No tone mapping, bloom or occlusion at all**, so the image sat flat.

`game/arena/arena_lighting.gd` fixes all four, engine-side, with no new art:
shadowed key light, cool fill so the shadow side is not solid black, **eight**
catwalk spot rigs (more lights at LOWER energy each is what removes the hard cone
edges a few bright spots leave), ACES tone mapping, restrained bloom, SSAO + SSIL
for contact darkening, screen-space reflections for the polished floor, a light
grade, and depth fog so the far stands recede.

It must run LAST in `_ready()` - it reaches into the crowd and floor materials,
which have to exist by then.

**Tuning notes, both learned the hard way.** The first pass overexposed badly: the
floor went solid orange and the crowd washed out pale. Broadcast arenas are
CONTRASTY, not bright. And the source hardwood photo is heavily orange-red, so the
floor material now multiplies it toward neutral maple - without that it reads as a
lurid plastic sheet no matter how well it is lit.

### Players now turn to face where they are going

Reported: "the players only face one way even though it is a 3D character." Correct
and important - none of the three body scripts ever rotated. A body sliding in any
direction while permanently facing the camera reads as a cardboard cutout being
dragged around, and it undoes the motion capture entirely. `_face_travel()` in
player, defender and teammate yaws smoothly toward the direction of travel. Yaw
only; a basketball player never pitches or rolls.
## Exact next steps

1. **PROGRESS.md step 1e** - roster to 5-on-5 mapping. Still only `roster[0]`
   hydrates the boot player. PROGRESS.md notes this can wait until step 4 if the
   possession loop stays pure-data, which the audit recommends.
2. **PROGRESS.md step 2** - the possession loop (`tools/sim/possession.py`),
   headless-runnable, seeded RNG. This is the next real feature-shaped work.

## Open decisions

- **Gotcha, already cost one debug cycle:** calling `GameState.set_phase()` by
  the bare autoload name is a *parse* error ("Cannot call non-static function
  ... directly") - the parser resolves the bare name to the script, not to the
  instance. Reach the singleton with `get_node("/root/GameState")` and preload
  the script only so the `Phase` enum resolves. All three callers use that shape.
- The `missed` signal semantics decision in PROGRESS.md step 1c stays locked -
  do not re-litigate it once a rebound system consumes the signal.

## Rules

- Repos span TWO namespaces: user `Kariimc` AND org `shift9-studio`. Enumerate with
  `gh api '/user/repos?affiliation=owner,collaborator,organization_member'`, never
  `gh repo list Kariimc` alone. See `Kariimc/my-skills` `rules/10-repo-topology.md`.
- Never assert an absence, status, or completion without proving your scope was exhaustive.
- Update this file in the same commit as any code change. A global pre-commit hook enforces it.
