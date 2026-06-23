"""Shot model — make probability and the green-zone timing meter.

This is the canonical shot curve. The Godot runtime mirrors it verbatim in
``game/core/shot_model.gd``; the Sprint 5 box-score simulator imports this
module directly. Keep the two in lockstep (same constants), exactly like the
attributes mirror.

Design intent
-------------
make_probability is a product of independent, bounded factors so each one is
individually monotonic and easy to reason about:

    p = skill(rating) * distance_factor(d) * contest_factor * timing_factor

The green-zone meter rewards better shooters with a wider perfect-release
window, and converts a release offset into a 0-1 ``timing_error`` that feeds
back into make_probability.
"""

from __future__ import annotations

# --- Tunable constants (mirror these exactly in shot_model.gd) ---
SKILL_FLOOR = 0.30          # point-blank make% at rating 0
SKILL_RANGE = 0.45          # added at rating 99  -> ~0.75 point-blank
DIST_FALLOFF = 0.06         # make% lost per metre beyond 1 m
DIST_FACTOR_FLOOR = 0.12    # deep heaves never go fully to zero
CONTEST_WEIGHT = 0.55       # full contest removes 55% of the make
TIMING_WEIGHT = 0.60        # worst timing removes 60% of the make
P_MIN, P_MAX = 0.02, 0.98

GREEN_FLOOR = 0.06          # green half-width (meter units) at rating 0
GREEN_RANGE = 0.12          # added at rating 99 -> ~0.18 half-width


def _clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def skill(rating: float) -> float:
    r = _clamp(rating, 0.0, 99.0)
    return SKILL_FLOOR + SKILL_RANGE * (r / 99.0)


def distance_factor(distance_m: float) -> float:
    beyond = max(0.0, distance_m - 1.0)
    return _clamp(1.0 - DIST_FALLOFF * beyond, DIST_FACTOR_FLOOR, 1.0)


def make_probability(
    distance_m: float,
    rating: float,
    contest: float = 0.0,
    timing_error: float = 0.0,
) -> float:
    """Probability in [P_MIN, P_MAX] that a shot goes in.

    rating       0-99 (Shooting for twos, ThreePT for threes — caller picks)
    contest      0-1 defender pressure
    timing_error 0-1 from the release meter (0 = perfect)
    """
    p = (
        skill(rating)
        * distance_factor(distance_m)
        * (1.0 - CONTEST_WEIGHT * _clamp(contest, 0.0, 1.0))
        * (1.0 - TIMING_WEIGHT * _clamp(timing_error, 0.0, 1.0))
    )
    return _clamp(p, P_MIN, P_MAX)


def green_half_width(rating: float) -> float:
    """Half-width of the perfect-release window (meter units, 0-1)."""
    r = _clamp(rating, 0.0, 99.0)
    return GREEN_FLOOR + GREEN_RANGE * (r / 99.0)


def timing_error(release_offset: float, rating: float) -> float:
    """Convert |release - perfect| (0-1) into a 0-1 timing error.

    Inside the green window -> 0. Outside -> scales to 1 at the meter edge.
    """
    offset = abs(release_offset)
    half = green_half_width(rating)
    if offset <= half:
        return 0.0
    return _clamp((offset - half) / (1.0 - half), 0.0, 1.0)
