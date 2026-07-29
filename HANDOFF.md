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
