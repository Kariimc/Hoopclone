# HoopClone — Architecture Audit & Forward Roadmap
**Written by Claude Fable 5 · July 6, 2026 · audited from `Kariimc/Hoopclone` @ HEAD**
**Purpose: the durable "bank now, execute later" artifact. Any model (Opus, Sonnet) can work from this document after July 7.**

---

## 1. Verdict up front

The architecture is genuinely good. The three decisions that matter most — Python owns data ingestion, Godot consumes plain JSON; the shot/contest math lives in twin Python↔GDScript modules with a CI parity lock; outcome-first ball flight instead of trusting physics — are the same shape real basketball sims use, and they're documented in a decisions log so they can't get relitigated. CI runs the real GDScript headlessly, not just the Python mirror. For a solo project, this verification story is above average.

The risks are concentrated in exactly one place: **`game/main.gd` is becoming a god-object**, and Sprint 5 (box score, possessions, rebounds) is the sprint that will either fix that or make it permanent. Everything below is ranked so the highest-payoff work is first.

---

## 2. What's solid (do not touch, do not "improve")

| System | Why it's right |
|---|---|
| Python→JSON→Godot data pipeline | nba_api's headers/rate-limits are unmanageable in GDScript. Offline import + committed JSON + localhost live service is the correct split. |
| Twin shot/contest models + parity test | `test_gdscript_parity.py` parses the `.gd` constants and fails CI on drift — the most common silent rot in mirrored code is already locked. |
| Headless Godot self-test in CI | Proves the GDScript *runs* in the pinned engine (4.3), catching what the language boundary could hide. Keep this pattern for every new core module. |
| Outcome-first ball (`ball.gd`) | Roll the make, then fly the ball to match. Rigid-body makes are a tar pit; you correctly avoided it. |
| Asset-optional boot | Scene runs with zero binaries present (capsule + fallback colors), hydrates real assets when dropped in. This keeps the repo clonable and CI green forever. |
| Contest as one 0–1 scalar | Proximity × lane × rating, strongest defender wins. Simple, testable, verifiable. Resist adding double-team stacking until box-score sim proves the need. |

---

## 3. Bugs & correctness risks found (fix in Sprint 5, cheap now, expensive later)

**3.1 — Misses can visually swish. (real bug, cosmetic-to-trust-breaking)**
`shot.gd release()`: a miss targets `rim_pos + offset` where the offset is `randf_range(-0.35, 0.35)` per axis. The rim radius is `0.23`. Any miss whose offset lands inside ~0.23 m of rim center flies a clean arc *through the hoop* and then bounces sideways off nothing — the player sees a swish scored as a miss. Fix: generate the miss offset in polar form with a minimum radius just outside the rim, e.g. `radius = randf_range(rim_radius + 0.05, 0.40)`, random angle. One function, both the GDScript and any future Python sim visual.

**3.2 — `missed` fires before the miss resolves.**
`ball.gd _resolve()` emits `missed` at the instant the bounce *starts*, while `made` fires when flight ends. When Sprint 5 adds rebounds and the box score, "missed" must mean "ball is now live for a rebound," not "bounce animation began." Move `missed.emit()` to where the bounce settles (`_step_bounce`, the `< 0.6` branch), or add a third signal `rebound_live`. Decide before the box score consumes these signals, because changing signal semantics after two systems listen to them is a breaking change.

**3.3 — Defender registration silently no-ops if equip order ever changes.**
`main.gd _spawn_defender()` registers the defender only if `player.shot != null` *and* `_equip_player_shot()` succeeded earlier (it early-returns if `RightHoop` is missing). Today the call order in `_ready()` makes this work; one reorder and every shot is uncontested with no error. Add one guard: if the defender can't register, `push_warning`. Cheap insurance on the system your whole contest model hangs off.

**3.4 — Only the first roster player is used.**
`_apply_roster_to_player` hydrates the boot player from `roster[0]`. Fine for Sprint 4, but Sprint 5's box score needs the full 5-on-5 mapping. Flagging so it's a planned task, not a surprise.

**3.5 — `GameState` is instanced but unused.**
`main.gd` creates a `GameState`, sets phase LIVE, and nothing reads it. Either make it an autoload singleton (Godot's intended pattern for this) and have the scorebug/ticker/sim read phase from it, or delete it until Sprint 5 needs it. Dead-but-present state machines get half-wired by accident.

---

## 4. Tech debt, ranked by payoff

**4.1 — Split `main.gd` before Sprint 5. (the one structural fix that matters)**
It's ~430 lines doing five jobs: scene bootstrap, crowd shader source, procedural arc mesh, entity spawning, and asset hydration. Sprint 5 wants to add possessions, rebounds, box score, and crowd reactions — into this same file by gravity. Split along the seams that already exist:
- `game/arena/crowd_bowl.gd` — shader constant + `_make_crowd_arc` + `set_crowd_intensity` (the shader string alone is a third of the file)
- `game/arena/arena_builder.gd` — underfloor, courtside, floor texture hydration
- `game/boot/spawner.gd` — player body, ball, defender spawning
- `main.gd` keeps only `_ready()` orchestration (~60 lines)
This is a pure cut-and-paste refactor with zero behavior change — a perfect cheap-model task once this plan exists. **Do it as Sprint 5 task #1, before new systems land.**

**4.2 — Repo bloat: ~40 MB of binaries in git history, one duplicated.**
`crowd_panorama_dense.png` (2.7 MB) is committed twice (`assets/` and `game/`), and `arena_backdrop.png.jpeg` is 9.3 MB with a confusing double extension. Every clone and CI checkout pays this forever, and it only grows through the asset sprints. Plan (execute any time, 30 min): dedupe the crowd texture to one path, rename `*.png.jpeg` → `.jpeg`, then move `assets/**` to Git LFS. Not urgent; gets worse the longer you wait.

**4.3 — README sprint table is stale.**
Sprint 5 is unchecked in the README, but defender/contest code marked "Sprint 5" already ships in `main.gd`, and DECISIONS.md documents the contest model as landed. The README is your cross-session source of truth (your PROGRESS.md system depends on docs matching reality). Reconcile: either the contest work was "Sprint 5 phase 1" (say so) or the table needs a Sprint 4.5 row.

**4.4 — The formula bodies are still hand-synced.**
The parity test locks *constants* but the Python↔GDScript formula bodies are kept in lockstep by hand (documented honestly in the test docstring). Current risk is low because the functions are tiny. The cheap upgrade when the models grow in Sprint 5: golden-value tests — one shared JSON of (inputs → expected output to 6 decimals) that both pytest and the Godot self-test assert against. That locks the curves, not just the coefficients, with no cross-language tooling.

**4.5 — Ticker/scorebug polling has no shared backoff.**
`live_service` has a TTL cache server-side (good), but two UI nodes polling independently means duplicated request logic and no coordinated failure handling. Fine now; when Sprint 5 adds a third consumer (box score), introduce one `LiveFeed` autoload that polls once and emits signals. Noted so it becomes a deliberate refactor, not accretion.

---

## 5. Sprint 5 build plan (box-score simulator) — the artifact to execute against

Order matters; each step is verifiable before the next.

1. **Refactor first** — split `main.gd` (4.1), fix miss-offset (3.1), settle signal semantics (3.2). Half a day of cheap-model work with this doc as the spec.
2. **Possession loop (pure sim, no rendering)** — a `tools/sim/possession.py` that runs shooter selection → shot/contest models → outcome → rebound roll, emitting box-score lines. Python first because pytest iteration is 10× faster than in-engine, and the twin-module pattern is already your house style. Rebounding uses the existing `rebounding` + `hops` attributes; keep it one weighted roll, no positioning sim yet.
3. **GDScript mirror + parity** — `game/core/possession.gd`, constants added to the parity test, behavior added to `run_tests.gd`, golden values (4.4) introduced here.
4. **Box score UI** — reads sim output; the existing `boxscore` endpoint in `live_service` already sketches the schema.
5. **Crowd hook** — `set_crowd_intensity` is already the gameplay API; wire sim events (lead change, big run, buzzer) to it. Zero new rendering work needed.
6. **Sim/spectate/play toggle** — the sim loop is authoritative; "play" mode substitutes human input for the shooter-decision step only. This keeps one source of truth for outcomes, which is what makes the Franchise layer (Sprint 6) cheap later.

**Sprint 6–7 note (don't build yet, just protect):** the Franchise and CEO layers are pure-data systems over the sim loop. Every Sprint 5 decision that keeps the sim headless-runnable (no scene-tree dependency in `possession.gd`'s mirror) directly cheapens Sprints 6–7. That's the one architectural invariant to defend in review.

---

## 6. Test strategy (current state + the gap that matters)

Covered today: rating math (range/monotonicity/baselines/overrides), shot+contest curve shape, constant parity, headless engine behavior. Multi-version Python matrix in CI. Good.

The gap: **nothing tests the scene wiring** — the `_ready()` chain in `main.gd` (equip → spawn → register) is exactly where bugs 3.3/3.4 live, and it's untested. After the 4.1 refactor, add one headless scene-smoke test: instance `main.tscn` headlessly, assert player has a shot, ball, rim, and ≥1 registered defender. ~30 lines in `run_tests.gd`'s style; catches the whole class of "boot order silently broke."

---

## 7. One-line risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Sprint 5 lands inside `main.gd` | High if 4.1 skipped | Refactor is task #1 |
| Signal semantics locked in wrong (3.2) | Medium | Decide before box score consumes them |
| nba_api IP blocks | Known | Already mitigated (offline-first, mock fallback) |
| Repo weight snowballs | Certain, slow | LFS migration (4.2) any quiet afternoon |
| Python↔GDScript curve drift | Low now, grows with model count | Golden values at Sprint 5 (4.4) |
