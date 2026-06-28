"""Contest-model spec tests: lock the contest curve's shape so neither the Python
sim nor the GDScript mirror (game/core/contest_model.gd) can drift without a
failing test.

Geometry is in the horizontal (x, z) plane, metres. Convention used throughout:
the shooter is at the origin, the basket is down +x, so a defender at positive x
is "in the lane" between shooter and basket.

Run from tools/sim:  python -m pytest -q
"""

import math
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import contest_model as cm  # noqa: E402

SHOOTER = (0.0, 0.0)
BASKET = (8.0, 0.0)


def test_contest_bounds():
    # Across distances, ratings, and angles the result stays in [0, 1].
    for dx in (0.0, 0.5, 1.0, 2.0, 3.5, 5.0):
        for dz in (-2.0, 0.0, 2.0):
            for r in (0, 50, 99):
                c = cm.contest((0.0, 0.0), (dx, dz), BASKET, r)
                assert 0.0 <= c <= 1.0


def test_closer_defender_contests_more():
    near = cm.contest(SHOOTER, (1.0, 0.0), BASKET, 70)
    far = cm.contest(SHOOTER, (3.0, 0.0), BASKET, 70)
    assert near > far


def test_no_contest_beyond_radius():
    # A defender at exactly / beyond CONTEST_RADIUS applies no pressure.
    assert cm.contest(SHOOTER, (cm.CONTEST_RADIUS, 0.0), BASKET, 99) == 0.0
    assert cm.contest(SHOOTER, (cm.CONTEST_RADIUS + 2.0, 0.0), BASKET, 99) == 0.0


def test_better_defender_contests_more():
    weak = cm.contest(SHOOTER, (1.0, 0.0), BASKET, 30)
    elite = cm.contest(SHOOTER, (1.0, 0.0), BASKET, 90)
    assert elite > weak


def test_in_lane_beats_trailing():
    # Same distance: a defender between shooter and basket (+x) contests more
    # than one trailing on the far side (-x).
    in_lane = cm.contest(SHOOTER, (1.5, 0.0), BASKET, 70)
    trailing = cm.contest(SHOOTER, (-1.5, 0.0), BASKET, 70)
    assert in_lane > trailing


def test_in_lane_beats_beside():
    in_lane = cm.contest(SHOOTER, (1.5, 0.0), BASKET, 70)
    beside = cm.contest(SHOOTER, (0.0, 1.5), BASKET, 70)
    assert in_lane > beside


def test_contest_monotonic_in_distance():
    prev = None
    for dx in (0.2, 0.6, 1.0, 1.6, 2.2, 3.0):
        c = cm.contest(SHOOTER, (dx, 0.0), BASKET, 70)
        if prev is not None:
            assert c < prev
        prev = c


def test_defender_on_shooter_is_well_defined():
    # Degenerate geometry (defender exactly on the shooter) must not blow up and
    # should be maximal pressure: proximity 1, lane 1, so contest == skill.
    c = cm.contest(SHOOTER, (0.0, 0.0), BASKET, 80)
    assert math.isfinite(c)
    assert c == cm.defender_skill(80)


def test_from_defenders_takes_strongest():
    near = ((1.0, 0.0), 70)
    far = ((3.2, 0.0), 70)
    best = cm.contest_from_defenders(SHOOTER, BASKET, [near, far])
    assert best == cm.contest(SHOOTER, (1.0, 0.0), BASKET, 70)
    # Strongest of the set is >= any individual member.
    assert best >= cm.contest(SHOOTER, (3.2, 0.0), BASKET, 70)


def test_from_defenders_empty_is_open():
    assert cm.contest_from_defenders(SHOOTER, BASKET, []) == 0.0


def test_factors_have_expected_bounds():
    assert cm.proximity_factor(0.0) == 1.0
    assert cm.proximity_factor(cm.CONTEST_RADIUS) == 0.0
    assert cm.defender_skill(0) == cm.DEF_SKILL_FLOOR
    assert cm.defender_skill(99) == cm.DEF_SKILL_FLOOR + cm.DEF_SKILL_RANGE
