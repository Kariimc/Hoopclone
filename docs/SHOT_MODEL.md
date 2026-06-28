# Shot Model

One curve, two consumers: the Godot runtime (`game/core/shot_model.gd`) and the
Python simulator (`tools/sim/shot_model.py`). Same constants — change one,
change both. The pytest in `tools/sim/tests/` is the spec lock.

## Make probability

```
p = skill(rating) * distance_factor(d) * contest_factor * timing_factor
```

- **skill(rating):** 0-99 maps to ~0.30 (floor) → ~0.75 point-blank make%.
  Caller passes Shooting for twos, ThreePT for threes.
- **distance_factor(d):** full inside 1 m, loses ~6%/m, floored at 0.12 so deep
  heaves aren't impossible.
- **contest_factor:** full pressure removes 55% of the make. The 0-1 `contest`
  scalar comes from the **contest model** (`docs/CONTEST_MODEL.md`) — defender
  proximity × shot-lane angle × defensive rating.
- **timing_factor:** worst release removes 60%.
- Clamped to [0.02, 0.98].

Sample (rating 75, open): 0.64 at the rim, 0.49 at 5 m, 0.41 at 7 m, 0.22 at 12 m.

## Green-zone meter

The meter ping-pongs 0→1→0; perfect release is the top (1.0). The green window
half-width grows with rating (≈0.11 at 40, ≈0.18 at 95), so elite shooters get a
more forgiving release. Release offset outside the window scales to a 0-1
`timing_error` that feeds back into make probability.

## Ball flight (outcome-first)

We roll make/miss from `p`, then fly the ball to match — a make targets the rim
centre and drops; a miss targets a small offset and bounces. This is how real
sims keep makes from depending on flaky rigid-body luck.
