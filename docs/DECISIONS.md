# HoopClone — Decisions Log

Locked decisions, newest context first. This is the single source of truth for
"why is it built this way" so no decision gets relitigated from memory.

## Sprint 4.5 — box-score prep refactor

Bridge work between the Sprint 4 asset pipeline and the Sprint 5 box-score
simulator. Three bug fixes + a `main.gd` split, no gameplay features added.

- **Ball rebound signal is separate from the miss outcome.** `ball.gd` now has
  **two** signals: `missed` (the OUTCOME — emitted the instant a shot is decided
  a miss, while the bounce is just starting) and a new `rebound_live` (emitted
  later, when the ball has finished bouncing and is actually grabbable). We chose
  to ADD `rebound_live` rather than move `missed` to the settle point, because
  the box score needs both moments — "shot missed" (for the stat line) and "ball
  is now live" (for rebound logic) — and moving `missed` would have broken any
  existing listener that treats it as the outcome. Additive, non-breaking.
- **A "miss" can no longer swish.** `shot.gd` picked the miss target with a square
  ±0.35 m x/z offset; with a 0.23 m rim radius some of those offsets landed inside
  the rim and fell clean through. Replaced with a polar offset on a ring strictly
  OUTSIDE the rim (`rad ∈ [rim+0.05, 0.40]`), keeping the small vertical jitter.
- **Silent defender no-op is now loud.** If the shot never got a `ShotController`
  (e.g. `RightHoop` missing so equip early-returned, or `_ready` ordering broke),
  defender registration used to no-op silently — every shot uncontested, no error.
  It now emits a `push_warning` on that path. A headless scene-smoke test
  (`tests/godot/run_tests.gd`) boots `main.tscn` and asserts the player ends
  `_ready` with a shot, ball, rim, and ≥1 registered defender, so the whole
  boot-order bug class fails CI instead of shipping quiet.
- **`main.gd` split into helpers.** The 388-line boot script is now ~65 lines of
  `_ready()` orchestration. Behaviour-preserving extractions to static helper
  classes (each a `class_name`, called on the same host node so node wiring and
  order are identical): `CrowdBowl` (`game/arena/crowd_bowl.gd`), `ArenaBuilder`
  (`game/arena/arena_builder.gd`), `Spawner` (`game/boot/spawner.gd`). Chose
  static host-param helpers over child-node scripts so the scene tree and
  `_ready` ordering are untouched.

## Stack

- **Engine: Godot 4** (Forward+). Chosen over Ursina for native AnimationTree,
  PBR, shaders, and `Skeleton3D` — all required by the fluid-animation + hair
  goals.
- **Data: nba_api** (`swar/nba_api`). Free, no key. Wrapped behind a
  `StatSource` protocol so swapping to balldontlie or a CSV/custom-league
  importer never touches rating math.
- **Python owns ingestion, Godot consumes JSON / localhost.** nba_api's headers
  and rate limits are unmanageable in GDScript; ingestion is an offline build
  step that emits committed JSON, plus a localhost live service for scores/news.

## Camera

Horizontal broadcast. Court runs left↔right, baskets at the left/right
baselines facing inward. Elevated near-sideline rig: ~7 m high, ~14 m back,
pitch −22°, narrow FOV ~30°, tracks ball X with easing lag.

## Art direction

- **Players:** stylized pixel-art, ~7.5-head realistic proportions, moderately
  dense / "slightly chunky" pixels.
- **World:** photorealistic arena + court. Hybrid accepted; a cohesion pass is
  flagged for the asset sprint.
- **Ball:** locked to the uploaded leather photo (albedo + derived normal map).
- **Apparel swaps = texture swap** (albedo+normal) on a fixed mesh, never
  regeneration. `manifest.json` drives URL-based asset swaps.
- **Animation = engine-owned** (mocap retarget + AnimationTree state machine +
  blend trees), NOT generated. Higgsfield supplies base meshes, PBR textures,
  and concept/UI refs only.
- **Hair:** Verlet bone-chain (3–6 bones) + capsule collision, decoupled from
  the animation state machine, per-archetype tunables.

## Attributes (13, shared sandbox ↔ Python ↔ Godot)

Shooting, ThreePT, Finishing, Dunking, Passing, Handles, Steals, Hustle, Hops,
Rebounding, PerimD, InsideD, Speed — each 0–99.

- **Normalization:** percentile-rank within a position pool → weighted blend →
  clamp; linear-scale fallback when no pool. Hops / Dunking / Handles aren't in
  box scores → position proxies + manual override.

## Broadcast UI

- **Scorebug:** NBC/Peacock style, bottom-right. Team-colored end-caps, scores
  bracketing a center clock module, fouls/bonus row.
- **News ticker:** horizontal bar, top-left, **non-persistent** — pops in,
  headline **scrolls** across (~9 s), slides out, re-fires (~12 s).
- Both are live-data driven (Python `live_service`); Higgsfield images are
  design references only.

## Defenders & contest (Sprint 5)

- **Contest = a 0-1 scalar**, not a per-defender hit list. It's the product of
  three bounded factors — defender **proximity** (gate; zero past 3.5 m), **shot-
  lane angle** (between shooter and basket contests most), and **defensive
  rating** (PerimD on jumpers/threes, InsideD inside) — mirrored Python↔GDScript.
  pytest locks the curve's shape and parity-checks the GDScript constants against
  the Python module (`test_gdscript_parity.py`); the formula stays in lockstep by
  hand. See `docs/CONTEST_MODEL.md`.
- **Strongest defender wins**, no double-team stacking yet — keeps the curve
  honest and the math trivial to verify before we add help defense.
- **On-ball D is deliberately beatable:** the defender's slide speed sits a touch
  under a typical attacker, so a quick first step creates separation. Defense
  lowers your percentage; it doesn't make scoring impossible.
- **Floor-plane geometry:** contest is computed in XZ. The shot arcs up, but
  "is the defender between me and the rim" is a 2D question.

## Scope marker

CEO / ownership-economic layer (arena, tickets, sponsorships, staff) is the one
net-new system beyond Hoop Land parity. It lands last (Sprint 7), on top of a
complete Commissioner layer.

## Data-source ground rules

- balldontlie: keyed API + official Python SDK (alternative, not chosen).
- nba_api: free, can be rate-limited / IP-blocked from datacenters — offline
  import + residential IP recommended.
- Basketball-Reference scraping is **forbidden** by ToS — never scrape; use an
  adapter only.
