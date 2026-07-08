# HoopClone — Live Progress Tracker

**Read this before `docs/HOOPCLONE-AUDIT.md`.** The audit is the plan; this file
is the checklist against it. Any agent picking up this repo — cold, no prior
context — should: read `CLAUDE.md`, read this file, take the **first
unchecked item** in order, do it, check it off in the same PR, then stop and
report. **Do not re-audit, re-plan, or re-propose architecture.** The audit
and `docs/SPRINT_6_7_ARCHITECTURE.md` already answered "what should we build
and in what order" — this file only answers "what's done and what's next."

If you disagree with an item's approach, say so in the PR description and do
it anyway (or ask per CLAUDE.md's escalation rules if it contradicts
DECISIONS.md) — don't silently re-plan instead of executing.

## Sprint 5 build order (`docs/HOOPCLONE-AUDIT.md` §5) — the spine

- [x] **Step 1a — Split `main.gd`** (audit §4.1). Done: `game/arena/crowd_bowl.gd`,
      `game/arena/arena_builder.gd`, `game/boot/spawner.gd` carved out;
      `main.gd` is now ~55 lines of `_ready()` orchestration only.
- [x] **Step 1b — Fix miss-offset swish bug** (audit §3.1). Done in
      `game/player/shot.gd`: miss target is now a polar offset floored just
      outside the rim radius (`ball.rim_radius + 0.05` .. `0.40`), so a miss
      can no longer visually pass clean through the hoop.
- [x] **Step 1c — Fix `missed` signal timing** (audit §3.2). Done in
      `game/ball/ball.gd`: `missed.emit()` moved from the start of the bounce
      to where the bounce settles (`_step_bounce`'s `< 0.6` branch) — it now
      means "ball is live for a rebound," not "animation started." No
      consumers existed yet, so this was free; **do not** re-litigate this
      semantics decision once a rebound system starts consuming the signal —
      that becomes a breaking change requiring a DECISIONS.md entry.
- [x] **Step 1d — Defender registration guard** (audit §3.3). Done in
      `game/boot/spawner.gd`'s `spawn_defender`: `push_warning` if the shot
      isn't equipped when the defender registers, instead of a silent no-op.
- [ ] **Step 1e — Roster→player 5-on-5 mapping** (audit §3.4). NOT done —
      still only `roster[0]` hydrates the boot player. Flagged as a Sprint 5
      dependency (the box score needs all 10 players), not yet built. Do this
      before or alongside Step 2 if the possession loop needs live entity
      references; if the possession loop is pure-data (recommended — see
      audit §5 step 2), this can wait until Step 4 (box score UI) actually
      needs multiple bodies on screen.
- [ ] **Step 1f — `GameState` wiring** (audit §3.5). NOT done — `GameState` is
      instanced in `main.gd`, set to `LIVE`, and nothing reads it. Either make
      it an autoload singleton (Godot's intended pattern) with the scorebug/
      ticker/sim reading phase from it, or delete it until Step 2 needs it.
      Small, do it early so nothing else gets built assuming it already works.
- [ ] **Step 2 — Possession loop (pure sim, no rendering).** `tools/sim/possession.py`:
      shooter selection → shot/contest models → outcome → rebound roll →
      box-score lines. **This is the next real feature-shaped piece of work.**
      Use the `twin-module` skill. Keep it headless-runnable (no scene-tree
      dependency) — this is the one architectural invariant Sprint 6/7 depend
      on (see `docs/SPRINT_6_7_ARCHITECTURE.md` A0). New randomness takes a
      seeded RNG parameter (replay determinism, required by Sprint 6).
- [ ] **Step 3 — GDScript mirror + parity.** `game/core/possession.gd`,
      constants into `test_gdscript_parity.py`, behavior into `run_tests.gd`.
      Introduce **golden-value tests** here (audit §4.4): a committed JSON of
      `(inputs → expected output to 6 decimals)` asserted by both pytest and
      the Godot self-test — this model is complex enough that hand-synced
      formula bodies alone are no longer enough.
- [ ] **Step 4 — Box-score UI.** Reads sim output; `live_service`'s existing
      `/boxscore` endpoint already sketches the schema.
- [ ] **Step 5 — Crowd hook.** Wire sim events (lead change, big run, buzzer)
      to `CrowdBowl.set_intensity` (already the gameplay API — see
      `game/arena/crowd_bowl.gd`). Zero new rendering work needed.
- [ ] **Step 6 — Sim/spectate/play toggle.** The sim loop stays authoritative;
      "play" mode substitutes human input for the shooter-decision step only.

## Other ranked debt (`docs/HOOPCLONE-AUDIT.md` §4) — pick up opportunistically

- [x] **§4.1** Split `main.gd` — see Step 1a above.
- [ ] **§4.2** Repo bloat: dedupe the doubly-committed `crowd_panorama_dense.png`,
      rename `arena_backdrop.png.jpeg` → `.jpeg`. (LFS migration itself already
      shipped in #18 — this is the remaining cleanup on top of it.) Any quiet
      30 minutes; not urgent, not blocking Sprint 5.
- [x] **§4.3** Stale README sprint table — fixed in this PR (Sprint 5 marked
      `[~]` in-progress with a pointer to this file and the audit).
- [ ] **§4.4** Formula-body hand-sync risk — addressed as part of Step 3 above
      (golden values), not standalone.
- [ ] **§4.5** No shared polling backoff between scorebug/ticker — defer until
      Step 4 adds a third `live_service` consumer (the box score), per the
      audit's own note. Don't build a `LiveFeed` autoload before there's a
      third consumer to justify it.

## Test-strategy gap (`docs/HOOPCLONE-AUDIT.md` §6)

- [ ] Add a headless scene-smoke test to `tests/godot/run_tests.gd`: instance
      `main.tscn`, assert the player has a shot, a ball, a rim, and ≥1
      registered defender. Do this once Step 1e/1f land, so the assertions
      match the final `_ready()` wiring rather than needing a rewrite.

## How to update this file

Whenever you finish a checklist item: flip its `[ ]` to `[x]`, add one line
of "done: what/where" (like the entries above), and commit it in the **same
PR** as the work — this file drifting from reality is exactly the failure
mode `docs/HOOPCLONE-AUDIT.md` §4.3 already caught once. If you complete work
that reveals a new ranked item not listed here, add it at the bottom of the
relevant section rather than in prose elsewhere — this file, not chat
history, is the durable record of "what's left."
