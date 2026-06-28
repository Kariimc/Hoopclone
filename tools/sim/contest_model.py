"""Contest model — how hard a defender pressures a shot.

This is the canonical contest curve for Sprint 5 (defenders). The Godot runtime
mirrors it verbatim in ``game/core/contest_model.gd``; ``shot_model.py`` consumes
the 0-1 scalar it produces as the ``contest`` argument to ``make_probability``.
Keep the two in lockstep (same constants), exactly like the attributes and
shot-model mirrors. The pytest in ``tests/test_contest_model.py`` is the spec
lock.

Design intent
-------------
``contest`` is a product of three independent, bounded factors so each one is
individually monotonic and easy to reason about, mirroring the shot model:

    contest = proximity(d) * lane(geometry) * defender_skill(rating)

* proximity   — closer defender = more pressure; zero past CONTEST_RADIUS.
* lane        — a defender between the shooter and the basket (in the shot
                lane) contests more than one beside or trailing the shooter.
* defender_skill — a better defender gets a better hand up; never zero, because
                a body in your face contests regardless of rating.

Everything works in the horizontal (XZ) plane: positions are ``(x, z)`` tuples.
The Godot side passes ``Vector2(pos.x, pos.z)``. The ball arcs up to the basket,
but "is the defender between me and the rim" is a floor-plane question, so the
basket's height is intentionally ignored.
"""

from __future__ import annotations

import math
from typing import Iterable, Sequence, Tuple

# --- Tunable constants (mirror these exactly in contest_model.gd) ---
CONTEST_RADIUS = 3.5        # metres; past this a defender applies no pressure
LANE_FLOOR = 0.40           # contest kept for a defender beside/behind the shooter
DEF_SKILL_FLOOR = 0.60      # contest multiplier from a rating-0 defender in your face
DEF_SKILL_RANGE = 0.40      # added at rating 99 -> 1.0 multiplier for an elite defender
EPS = 1e-4                  # degenerate-geometry guard (defender on top of shooter)

Point = Tuple[float, float]


def _clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def proximity_factor(distance_m: float) -> float:
    """1 when the defender is on the shooter, fading linearly to 0 at CONTEST_RADIUS."""
    return _clamp(1.0 - distance_m / CONTEST_RADIUS, 0.0, 1.0)


def defender_skill(rating: float) -> float:
    """0-99 defensive rating -> contest multiplier in [FLOOR, FLOOR+RANGE]."""
    r = _clamp(rating, 0.0, 99.0)
    return DEF_SKILL_FLOOR + DEF_SKILL_RANGE * (r / 99.0)


def lane_factor(shooter: Point, defender: Point, basket: Point) -> float:
    """How much the defender sits in the shooter->basket lane.

    1.0 when the defender is directly between shooter and basket; fades to
    LANE_FLOOR as the defender moves beside or behind the shooter.
    """
    to_basket = (basket[0] - shooter[0], basket[1] - shooter[1])
    to_def = (defender[0] - shooter[0], defender[1] - shooter[1])
    db = math.hypot(to_basket[0], to_basket[1])
    dd = math.hypot(to_def[0], to_def[1])
    if dd < EPS or db < EPS:
        # Defender on top of the shooter (or shooter at the rim): full lane contest.
        return 1.0
    cos = (to_basket[0] * to_def[0] + to_basket[1] * to_def[1]) / (db * dd)
    cos = max(0.0, cos)
    return LANE_FLOOR + (1.0 - LANE_FLOOR) * cos


def contest(shooter: Point, defender: Point, basket: Point, defender_rating: float) -> float:
    """Pressure in [0, 1] a single defender applies to a shot.

    shooter / defender / basket are horizontal (x, z) positions in metres.
    defender_rating is 0-99 (PerimD for jumpers, InsideD for close shots — the
    caller picks, mirroring how the shot model picks Shooting vs ThreePT).
    """
    dist = math.hypot(defender[0] - shooter[0], defender[1] - shooter[1])
    c = (
        proximity_factor(dist)
        * lane_factor(shooter, defender, basket)
        * defender_skill(defender_rating)
    )
    return _clamp(c, 0.0, 1.0)


def contest_from_defenders(
    shooter: Point,
    basket: Point,
    defenders: Iterable[Tuple[Sequence[float], float]],
) -> float:
    """Strongest contest among several defenders.

    defenders is an iterable of ``(position, rating)`` where position is an
    ``(x, z)`` pair. Returns the single largest contest (the defender who
    pressures the shot most). Empty -> 0.0 (a wide-open shot).
    """
    best = 0.0
    for pos, rating in defenders:
        best = max(best, contest(shooter, (pos[0], pos[1]), basket, rating))
    return best
