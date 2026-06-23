"""Tests for Sprint 3 percentile-pool normalisation."""

import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from schema import ATTRIBUTES  # noqa: E402
from sources.base import RawStatLine  # noqa: E402
import normalize as nz  # noqa: E402


def _shooter(name, pos, fg3p, fg3a, reb=4.0, stl=1.0, blk=0.4):
    return RawStatLine(
        name=name, position=pos, games=70, minutes=30,
        fg_pct=0.46, fg3_pct=fg3p, fg3a=fg3a, ft_pct=0.80,
        ast=3.0, stl=stl, blk=blk, reb=reb, ast_to=2.0,
    )


def test_pool_three_pt_leader_rises():
    lines = [
        _shooter("Sniper", "SG", 0.45, 8.0),
        _shooter("Average A", "SG", 0.34, 4.0),
        _shooter("Average B", "SF", 0.33, 3.0),
        _shooter("NonShooter", "C", 0.20, 0.5),
    ]
    blocks = nz.normalize_pool(lines)
    by_name = {l.name: b for l, b in zip(lines, blocks)}
    assert by_name["Sniper"].three_pt > by_name["Average A"].three_pt
    assert by_name["Sniper"].three_pt > by_name["NonShooter"].three_pt


def test_pool_keeps_range():
    lines = [_shooter(f"P{i}", "SF", 0.30 + i * 0.01, i % 9) for i in range(12)]
    for blk in nz.normalize_pool(lines):
        for a in ATTRIBUTES:
            assert 0 <= getattr(blk, a) <= 99


def test_position_relative_rebounding():
    # 6 guards rebound poorly, 6 centres rebound well. Two test players both
    # grab 8.0 reb: elite for a guard, below-average for a centre.
    lines = []
    for i in range(6):
        lines.append(_shooter(f"G{i}", "PG", 0.34, 4.0, reb=2.5 + i * 0.1))
    for i in range(6):
        lines.append(_shooter(f"C{i}", "C", 0.25, 0.5, reb=10.0 + i * 0.1))
    pg = _shooter("BigGuard", "PG", 0.34, 4.0, reb=8.0)
    cen = _shooter("SmallBig", "C", 0.25, 0.5, reb=8.0)
    lines += [pg, cen]
    blocks = nz.normalize_pool(lines, position_relative=True)
    by_name = {l.name: b for l, b in zip(lines, blocks)}
    # Same raw boards, but elite-for-a-guard should out-rate below-avg-for-a-centre.
    assert by_name["BigGuard"].rebounding > by_name["SmallBig"].rebounding


def test_pool_overrides_win():
    lines = [
        _shooter("A", "SF", 0.36, 5.0),
        _shooter("B", "SF", 0.33, 3.0),
    ]
    lines[0].overrides = {"dunking": 97, "hops": 93}
    blocks = nz.normalize_pool(lines)
    assert blocks[0].dunking == 97
    assert blocks[0].hops == 93
