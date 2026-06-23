"""Shot-model spec tests: lock the curve's shape so neither the Python sim nor
the GDScript mirror can drift without a failing test.

Run from tools/sim:  python -m pytest -q
"""

import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import shot_model as sm  # noqa: E402


def test_probability_bounds():
    for d in (0, 1, 5, 8, 25):
        for r in (0, 50, 99):
            p = sm.make_probability(d, r)
            assert sm.P_MIN <= p <= sm.P_MAX


def test_closer_is_better():
    near = sm.make_probability(1.0, 70)
    far = sm.make_probability(8.0, 70)
    assert near > far


def test_higher_rating_is_better():
    lo = sm.make_probability(5.0, 40)
    hi = sm.make_probability(5.0, 90)
    assert hi > lo


def test_contest_lowers_probability():
    open_ = sm.make_probability(5.0, 70, contest=0.0)
    pressed = sm.make_probability(5.0, 70, contest=1.0)
    assert pressed < open_


def test_timing_error_lowers_probability():
    perfect = sm.make_probability(5.0, 70, timing_error=0.0)
    bricked = sm.make_probability(5.0, 70, timing_error=1.0)
    assert bricked < perfect


def test_green_window_widens_with_rating():
    assert sm.green_half_width(90) > sm.green_half_width(40)


def test_timing_error_zero_inside_window():
    half = sm.green_half_width(80)
    assert sm.timing_error(half * 0.5, 80) == 0.0


def test_timing_error_grows_outside_window():
    r = 50
    half = sm.green_half_width(r)
    small = sm.timing_error(half + 0.1, r)
    big = sm.timing_error(half + 0.3, r)
    assert 0.0 < small < big <= 1.0


def test_distance_factor_has_floor():
    assert sm.distance_factor(100.0) == sm.DIST_FACTOR_FLOOR
