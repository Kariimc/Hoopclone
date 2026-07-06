# Hoopclone — Sprints 6–7 Architecture (Franchise + CEO)

> Authored by Claude Fable 5 · 2026-07-06. Extracted as Part A of FABLE-FINAL-ARTIFACTS.md
> (Part B — the gold-standard eval pack — lives in the my-skills repo's datasets/).

# PART A — Hoopclone Sprints 6–7 Architecture (Franchise + CEO)

## A0. The one invariant (inherited from the Sprint 5 plan, restated because everything hangs on it)
The possession engine is the **single source of truth for outcomes** and stays **headless-runnable** (no scene-tree dependency). Franchise and CEO are pure-data layers that *schedule* and *consume* possession-engine runs. Any Sprint 6/7 PR that makes an outcome decision outside the engine is architecturally wrong — reject it in review regardless of how convenient it is.

## A1. The key decision: two-fidelity simulation, one truth
A season is ~1,230 games. Full possession-sim for every game is correct but slow; hand-tuned "quick sim" formulas are fast but drift from the real engine — the classic franchise-mode rot. The fix:

- **Fidelity 1 — full sim:** the possession loop, used for the user's own games (play/spectate) and any game the user watches.
- **Fidelity 2 — aggregate sim:** team-strength → score-distribution model used for background league games. **Never hand-tuned.** It is *calibrated from the possession engine*: a Python tool runs N thousand headless possession sims across attribute spreads and fits coefficients (pace, efficiency vs. attribute deltas, variance). Output: `calibration.json`, committed like roster JSON.
- Both Godot and the Python tool read the same `calibration.json`. GDScript never contains fitted constants in code → **no new parity burden**. Recalibration is a build step that reruns whenever shot/contest math changes (add it to CI as a drift check: if fresh calibration diverges >2% from committed, fail).

This is the load-bearing idea of Sprint 6. Everything else is plumbing.

## A2. Sprint 6 — Franchise layer components (build order)
1. **`League` data model** (GDScript `Resource` or plain Dictionary — keep plain Dict + JSON, house style): `{teams[], schedule[], results[], day_index, rng_seed}`. **Deterministic seeded RNG per game** (`hash(season_seed, game_id)`) so any past game is exactly replayable — this is what makes bug reports and tests tractable, and it's nearly free if done first, painful retrofitted.
2. **Schedule generator** — round-robin with home/away balance. Pure function: `(teams, season_seed) -> schedule`. Test: every team plays the same count, no team plays twice on one day.
3. **Season loop** — `advance_day()`: for each game today, route to Fidelity 2 (or 1 if user-involved); append results; bump `day_index`. The economy (Sprint 7) will tick on this same clock — design `advance_day()` to emit a `day_advanced(day, results)` signal now.
4. **Standings/leaders** — pure derivations of `results[]`. Never stored, always computed (no cache-invalidation class of bugs).
5. **Player progression** — age curves over the existing 13 attributes: `attr(age+1) = attr(age) + curve(archetype, age) + noise(seeded)`. Ships v1 with 3 archetype curves (guard/wing/big). Injuries v1 = availability roll only (out N games); no body-part modeling — upgrade path noted, not built.
6. **Roster moves** — v1 is user-initiated trades/signings with a validity check (roster size, and salary once Sprint 7 lands). **No AI GM negotiation in v1** — flag it; AI GMs are a full sprint of their own and block nothing.
7. **Persistence** — one JSON save per franchise, schema-versioned (`"schema": 1`), snapshot-on-day-advance. JSON matches the whole repo's data philosophy; no SQLite until saves exceed ~10MB (upgrade path, one line, done).

## A3. Sprint 7 — CEO layer components
1. **The ledger is the architecture.** All money is an **append-only transaction log** `{day, amount, category, ref}`; balances/budgets are derivations, never stored fields. This single decision makes the entire economy testable ("sum of ledger == displayed balance" is one assert) and makes every future UI free.
2. **Income:** ticket sales = f(arena capacity, ticket price, team performance, win-streak buzz) — the elasticity curve is the one tunable that matters; expose it in `calibration.json` too. Sponsorships = per-season contracts (flat v1). 
3. **Costs:** salaries (per player per day), facilities (flat tiers v1: arena/training/medical — training tier feeds a small multiplier into progression, which is the CEO→Franchise coupling that makes the layer feel real).
4. **Decisions surface:** ticket price, facility tier, hire/fire (v1: coach slot only, affects a single team-wide modifier). Everything else is derived display.
5. **Coupling rule:** CEO reads franchise state, writes ONLY through (a) the ledger and (b) declared modifiers (`training_bonus`, `coach_bonus`). No CEO code reaches into the possession engine. Enforce by module boundary: `game/franchise/` may not import from `game/ceo/`; `ceo` imports `franchise` read-only.

## A4. What Sprint 6/7 explicitly does NOT contain (scope fence, pre-drawn)
Playoffs seeding drama v1 = top-8 straight bracket. No draft (needs prospect generation — own sprint). No AI GM trading. No fan-sentiment sim. No multi-season contracts v1 (all 1-season). Each is a one-line upgrade path, none blocks shipping a playable season.

## A5. Test spine (write these WITH each component, not after)
Schedule fairness · replay determinism (same seed → identical season) · aggregate-vs-full-sim drift <2% on 1k-game sample (CI) · progression curves monotone where designed · **ledger conservation** (every screen's money == ledger sum) · save/load round-trip byte-equality. All pure-function tests, all runnable headless — the invariant pays off here.

---

