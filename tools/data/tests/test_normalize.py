"""Unit tests for the normaliser. No network, no nba_api — pure rating math.

Run from tools/data:  python -m pytest -q
"""

import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from schema import ATTRIBUTES, AttributeBlock  # noqa: E402
from sources.base import RawStatLine  # noqa: E402
import normalize as nz  # noqa: E402


def _line(**kw) -> RawStatLine:
    base = dict(
        name="Test Player",
        position="SF",
        games=70,
        minutes=32.0,
        pts=18.0,
        fg_pct=0.47,
        fg3_pct=0.36,
        fg3a=5.0,
        ft_pct=0.80,
        ast=4.0,
        stl=1.1,
        blk=0.6,
        reb=6.0,
        ast_to=2.0,
    )
    base.update(kw)
    return RawStatLine(**base)


def test_all_attributes_in_range():
    blk = nz.normalize(_line())
    for attr in ATTRIBUTES:
        val = getattr(blk, attr)
        assert 0 <= val <= 99, f"{attr}={val} out of range"


def test_three_pt_is_monotonic_in_fg3_pct():
    low = nz.normalize(_line(fg3_pct=0.30)).three_pt
    high = nz.normalize(_line(fg3_pct=0.43)).three_pt
    assert high > low


def test_passing_is_monotonic_in_assists():
    low = nz.normalize(_line(ast=2.0)).passing
    high = nz.normalize(_line(ast=9.0)).passing
    assert high > low


def test_rebounding_is_monotonic_in_reb():
    low = nz.normalize(_line(reb=3.0)).rebounding
    high = nz.normalize(_line(reb=12.0)).rebounding
    assert high > low


def test_center_has_more_inside_d_than_guard():
    c = nz.normalize(_line(position="C")).inside_d
    pg = nz.normalize(_line(position="PG")).inside_d
    assert c > pg


def test_guard_is_faster_than_center():
    pg = nz.normalize(_line(position="PG")).speed
    c = nz.normalize(_line(position="C")).speed
    assert pg > c


def test_manual_override_wins():
    blk = nz.normalize(_line(overrides={"dunking": 95, "hops": 91}))
    assert blk.dunking == 95
    assert blk.hops == 91


def test_overall_is_bounded():
    blk = nz.normalize(_line())
    assert 0 <= blk.overall() <= 99


def test_percentile_rank_basic():
    pool = [0.30, 0.32, 0.35, 0.38, 0.42]
    assert nz.percentile_rank(0.42, pool) > nz.percentile_rank(0.30, pool)
    assert 0 <= nz.percentile_rank(0.35, pool) <= 99
