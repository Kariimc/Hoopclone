# Contest Model

Sprint 5 — defenders. How hard an on-ball defender pressures a shot, expressed
as a single `contest` scalar in **[0, 1]** — the `contest` argument to
`ShotModel.make_probability(...)` (the `contest_factor` term in the shot curve,
`docs/SHOT_MODEL.md`).

One curve, two consumers: the Godot runtime (`game/core/contest_model.gd`) and
the Python simulator (`tools/sim/contest_model.py`). The pytest in
`tools/sim/tests/` is the spec lock: `test_contest_model.py` locks the curve's
shape, and `test_gdscript_parity.py` mechanically checks the GDScript constants
against this module so a constant can't drift between the two. The formula
bodies are kept in lockstep by hand — change one, change both.

## The curve

```
contest = proximity(d) * lane(geometry) * defender_skill(rating)
```

Three independent, bounded, individually-monotonic factors (same design as the
shot model), so the whole thing is easy to reason about:

- **proximity(d):** `1 - d / 3.5`, clamped to [0, 1]. On the shooter → 1; at or
  beyond `CONTEST_RADIUS` (3.5 m) → 0. This is the gate: a far defender applies
  no pressure no matter how good or how well-positioned.
- **lane(geometry):** how much the defender sits in the shooter→basket line.
  `cos θ` between *(basket − shooter)* and *(defender − shooter)*, floored so a
  defender beside or trailing the shooter still counts: `0.40 + 0.60·max(0, cosθ)`.
  Directly between shooter and rim → 1.0; off to the side or behind → 0.40.
- **defender_skill(rating):** `0.60 + 0.40·(rating/99)`. A body in your face
  contests even at rating 0 (0.60); an elite defender (99) maxes it (1.0). The
  caller passes **PerimD** for jumpers / threes, **InsideD** for close attempts
  — mirroring how the shot model picks Shooting vs ThreePT.

Everything is computed in the **horizontal (XZ) plane**. The ball arcs up to the
rim, but "is the defender between me and the basket" is a floor-plane question,
so the basket's height is intentionally ignored. The Godot side passes
`Vector2(pos.x, pos.z)`.

## Multiple defenders

`contest_from_defenders(shooter, basket, defenders)` returns the **single
strongest** contest among the candidates — the one defender pressuring the shot
most. No double-teams stacking yet; an empty list is a wide-open shot (0.0).

## Where it plugs in

`game/player/shot.gd` collects the live, registered `Defender` nodes at release,
asks each for the rating that matters for the shot type, and runs
`ContestModel.contest_from_defenders(...)`. The result replaces the old
hard-coded `0.0` in `ShotModel.make_probability(...)`. With `CONTEST_WEIGHT =
0.55`, a smothered, in-lane, elite-defended shot keeps ~45% of its open make %.

## Defender AI

`game/player/defender.gd` is a `CharacterBody3D` that marks a player and protects
a basket, sliding to the spot `guard_gap` (1.4 m) off the mark on the basket
side. Slide speed scales with Speed off a base a touch under a typical attacker,
so it is deliberately beatable — a quick first step creates separation, like real
on-ball defense. `game/main.gd` spawns one in the boot scene.
