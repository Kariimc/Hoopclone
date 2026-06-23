# Sprint 4 — In-Editor Checklist

This sprint's logic ships as scripts (`verlet_hair.gd`, `player_animator.gd`,
`asset_loader.gd`, `build_animation_tree.gd`). The wiring happens in the Godot
editor. Work top to bottom; each step is independently testable.

## 0. Open the project
Open `project.godot` in Godot 4.3+ (Forward+). Confirm `main.tscn` runs (you
should see the camera + lighting from Sprint 1).

## 1. Import the rigged player mesh
1. Export the rigged, textured GLB from Higgsfield (3D job `65167a5f`) and drop
   it at `res://assets/models/player_base.glb`.
2. Select it in the FileSystem dock → **Import** tab:
   - Import As: **Scene**
   - Skins / Skeleton: keep; enable **Import Animations** if the GLB carries any.
   - Materials: leave PBR maps as-is (you'll override the jersey at runtime).
3. Double-click to open; confirm there's a **Skeleton3D** with a bone for the
   hair/dread strand. Note the bone names — you'll need their indices in step 4.

## 2. Get animation clips into an AnimationLibrary
Mocap is engine-owned (not generated). Either:
- **A — clips embedded in the GLB:** they land in the mesh's AnimationPlayer.
- **B — separate clips (Mixamo etc.):** import each as Scene, set
  **Animation > Retarget** to your skeleton, then drag the clips into one
  `AnimationLibrary`. Name them to match `ACTION_CLIPS` in
  `build_animation_tree.gd` (Idle, Walk, Run, Sprint, JumpShot, Layup, Dunk, …).

## 3. Build the AnimationTree
Fastest path:
1. Open `tools/godot/build_animation_tree.gd`, then **File ▸ Run**
   (Ctrl/Cmd+Shift+X). It writes `res://game/player/player_tree.tres`.
2. On your player scene add an **AnimationPlayer** (with the library from step 2)
   and an **AnimationTree** node.
3. AnimationTree: set **Anim Player** to that AnimationPlayer, set **Tree Root**
   to `player_tree.tres`, toggle **Active** on.
4. If any state errors "missing animation", rename the clip or the state's
   `animation` field so they match.

Manual alternative (if the EditorScript API differs in your build): AnimationTree
root = **AnimationNodeStateMachine**; add a **BlendSpace1D** named `Locomotion`
with blend points Idle@0, Walk@0.33, Run@0.66, Sprint@1.0; add one state per
action playing its clip; Start→Locomotion, Locomotion↔each action (action→
Locomotion set to **At End**).

## 4. Wire the animator + hair on the player
1. Make a `Player` scene: `CharacterBody3D` root with `player.gd`, the imported
   mesh as a child, plus the AnimationPlayer + AnimationTree from step 3.
2. Add a **Node** child with `player_animator.gd`; set **Animation Tree Path** to
   your AnimationTree. From `player.gd`'s `_ready`, call
   `animator.setup(anim)` and each physics frame
   `animator.update_locomotion_blend(velocity_planar_length)`.
3. Add `verlet_hair.gd` (a **SkeletonModifier3D**) as a **child of the
   Skeleton3D**. Set `bone_chain` to the hair bone indices (root→tip; use
   `Skeleton3D.find_bone("name")` in a quick script to get indices). If the hair
   kinks, flip `bone_forward_axis` (try `Vector3.DOWN` or `Vector3.FORWARD`).

## 5. Apparel hot-swap
1. Export each team's jersey **albedo + normal** PNGs into
   `res://assets/textures/` matching the paths in `assets/team_manifest.json`.
2. Add an `AssetLoader` node; call `spawn_player("CRW")` (or `apply_team(mesh,
   "CRW")`) to dress the mesh. If your jersey surface isn't named "Jersey", pass
   the real surface name as the second arg.

## 6. Test
Run the scene. You should get: locomotion blending with movement, an action clip
firing on shoot, the hair swinging under motion, and the correct team kit. Tune
`segment_length`, `damping`, `iterations` on the hair to taste.

---

### What's still stubbed (next sprints)
- Contest/defense feeds into the shot model — Sprint 5.
- Real clip set (full moveset mocap) is incremental; the tree tolerates missing
  states during bring-up.
- Cohesion pass on the pixel-player ↔ photoreal-arena hybrid — asset polish.
