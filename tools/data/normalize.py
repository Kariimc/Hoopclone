"""Normalisation: RawStatLine -> AttributeBlock (each attribute 0-99).

Strategy
--------
Two complementary tools live here:

1. ``percentile_rank(value, pool)`` — when you hand the normaliser a *pool* of
   the same raw metric across the league, an attribute can be rated by where the
   player falls in that distribution. This is the preferred path once a full
   league is loaded.

2. ``scale(value, lo, hi)`` — a deterministic piecewise-linear fallback used
   when no pool is available (single-player imports, tests, early sprints). Each
   attribute maps from one or more raw fields through tuned (lo -> 0, hi -> 99)
   anchors, then a position baseline nudges attributes that box scores can't see
   directly (interior defence, speed), and explicit overrides win last.

The fallback path is fully deterministic and dependency-free, which is what the
unit tests exercise. Swapping in percentile ranking later doesn't change the
public surface (`normalize`).
"""

from __future__ import annotations

from typing import Iterable, Optional

from schema import AttributeBlock, ATTRIBUTES
from sources.base import RawStatLine


def clamp(v: float, lo: float = 0.0, hi: float = 99.0) -> int:
    return int(max(lo, min(hi, round(v))))


def scale(value: Optional[float], lo: float, hi: float) -> float:
    """Linear map value in [lo, hi] -> [0, 99], clamped. None -> 0 contribution."""
    if value is None:
        return 0.0
    if hi == lo:
        return 0.0
    return max(0.0, min(99.0, (value - lo) / (hi - lo) * 99.0))


def percentile_rank(value: float, pool: Iterable[float]) -> float:
    """Percentile (0-99) of ``value`` within ``pool``. Empty pool -> 50."""
    data = sorted(v for v in pool if v is not None)
    if not data:
        return 50.0
    below = sum(1 for v in data if v < value)
    equal = sum(1 for v in data if v == value)
    return ((below + 0.5 * equal) / len(data)) * 99.0


# Per-position baselines for attributes that aren't directly visible in a box
# score (interior defence, speed, hops). These are gentle priors, not the final
# value — computed signal and overrides move them.
_POS_BASELINE = {
    "PG": {"speed": 82, "perim_d": 60, "inside_d": 40, "hops": 60, "dunking": 55},
    "SG": {"speed": 78, "perim_d": 62, "inside_d": 45, "hops": 64, "dunking": 60},
    "SF": {"speed": 74, "perim_d": 64, "inside_d": 55, "hops": 66, "dunking": 64},
    "PF": {"speed": 66, "perim_d": 55, "inside_d": 70, "hops": 64, "dunking": 70},
    "C":  {"speed": 58, "perim_d": 48, "inside_d": 80, "hops": 60, "dunking": 74},
}


def _baseline(position: str, attr: str, default: int = 50) -> int:
    return _POS_BASELINE.get(position, {}).get(attr, default)


def normalize(raw: RawStatLine) -> AttributeBlock:
    """Convert one RawStatLine into a rated AttributeBlock."""
    pos = raw.position if raw.position in _POS_BASELINE else "SF"
    blk = AttributeBlock()

    # --- Directly computable from common box-score / rate stats ---
    blk.shooting = clamp(
        0.65 * scale(raw.fg_pct, 0.40, 0.55)
        + 0.35 * scale(raw.ft_pct, 0.70, 0.92)
    )
    blk.three_pt = clamp(
        0.75 * scale(raw.fg3_pct, 0.30, 0.43)
        + 0.25 * scale(raw.fg3a, 1.0, 9.0)  # volume reward
    )
    blk.finishing = clamp(
        scale(raw.rim_fg_pct, 0.52, 0.74)
        if raw.rim_fg_pct is not None
        else 0.6 * scale(raw.fg_pct, 0.42, 0.60)
        + 0.4 * scale(raw.ft_rate, 0.15, 0.55)
    )
    blk.passing = clamp(
        0.7 * scale(raw.ast, 1.5, 10.0) + 0.3 * scale(raw.ast_to, 1.0, 3.5)
    )
    blk.handles = clamp(
        0.6 * scale(raw.ast, 1.5, 9.0)
        + 0.4 * scale(raw.ast_to, 1.0, 3.0)
    )
    blk.steals = clamp(scale(raw.stl, 0.4, 2.2))
    blk.rebounding = clamp(scale(raw.reb, 2.5, 13.0))
    blk.hustle = clamp(
        0.5 * scale(raw.oreb_pct, 0.02, 0.12)
        + 0.5 * scale(raw.stl, 0.4, 2.0)
        if raw.oreb_pct is not None
        else scale(raw.stl, 0.4, 2.0)
    )

    # --- Baseline-led (box scores barely see these); blend computed signal in ---
    blk.inside_d = clamp(
        0.6 * _baseline(pos, "inside_d") + 0.4 * scale(raw.blk, 0.2, 2.5) * 99 / 99
    )
    blk.perim_d = clamp(
        0.7 * _baseline(pos, "perim_d") + 0.3 * scale(raw.stl, 0.4, 2.2)
    )
    blk.speed = _baseline(pos, "speed")
    blk.hops = clamp(
        0.7 * _baseline(pos, "hops") + 0.3 * scale(raw.blk, 0.2, 2.0)
    )
    blk.dunking = _baseline(pos, "dunking")

    # --- Manual overrides win last (hops/dunking/handles scouting, etc.) ---
    for attr, value in raw.overrides.items():
        if attr in ATTRIBUTES:
            setattr(blk, attr, clamp(float(value)))

    return blk


# ---------------------------------------------------------------------------
# Sprint 3: percentile-pool normalisation
# ---------------------------------------------------------------------------
# Rate observable attributes by where a player falls within the *league*
# distribution instead of fixed absolute anchors. Position-relative cohorts are
# used for size-dependent skills (rebounding, interior D, hops, finishing) so a
# 7-footer isn't graded on the rebounding curve of guards. Percentile is blended
# with the absolute scale so a weak league can't inflate everyone to elite.

def _g(v: Optional[float]) -> float:
    return v if v is not None else 0.0


# One ordering metric per pool-rated attribute (percentile only needs ordering).
_METRIC = {
    "shooting": lambda r: 0.65 * _g(r.fg_pct) + 0.35 * _g(r.ft_pct),
    "three_pt": lambda r: _g(r.fg3_pct) * (0.4 + 0.6 * min(1.0, _g(r.fg3a) / 8.0)),
    "finishing": lambda r: (
        r.rim_fg_pct if r.rim_fg_pct is not None
        else 0.6 * _g(r.fg_pct) + 0.4 * _g(r.ft_rate)
    ),
    "passing": lambda r: _g(r.ast),
    "handles": lambda r: 0.6 * _g(r.ast) + 0.4 * _g(r.ast_to),
    "steals": lambda r: _g(r.stl),
    "hustle": lambda r: _g(r.stl) + 10.0 * _g(r.oreb_pct),
    "rebounding": lambda r: _g(r.reb),
    "perim_d": lambda r: _g(r.stl),
    "inside_d": lambda r: _g(r.blk),
    "hops": lambda r: _g(r.blk),
}

# Attributes graded against position-cohort pools rather than the whole league.
POOL_RELATIVE = {"rebounding", "inside_d", "hops", "finishing"}

# Weight on the percentile signal vs the absolute-scale value from normalize().
PCT_BLEND = 0.7
MIN_COHORT = 5


def build_metric_pools(lines: list) -> dict:
    """{attr: {"ALL": [...], "PG": [...], ...}} of ordering metrics."""
    pools: dict = {a: {"ALL": []} for a in _METRIC}
    for ln in lines:
        for a in _METRIC:
            val = _METRIC[a](ln)
            pools[a]["ALL"].append(val)
            pools[a].setdefault(ln.position, []).append(val)
    return pools


def _cohort(pools: dict, attr: str, position: str, position_relative: bool) -> list:
    if position_relative and attr in POOL_RELATIVE:
        pos_pool = pools[attr].get(position, [])
        if len(pos_pool) >= MIN_COHORT:
            return pos_pool
    return pools[attr]["ALL"]


def normalize_pool(lines: list, position_relative: bool = True) -> list:
    """Normalise a whole pool together so attributes are league-relative.

    Returns AttributeBlocks aligned with ``lines``. Baseline-led attributes
    (speed, dunking) come from the absolute path; observable attributes are the
    percentile/absolute blend; manual overrides win last.
    """
    pools = build_metric_pools(lines)
    out: list = []
    for ln in lines:
        absolute = normalize(ln)
        blk = AttributeBlock()
        for a in ATTRIBUTES:
            setattr(blk, a, getattr(absolute, a))
        for a in _METRIC:
            cohort = _cohort(pools, a, ln.position, position_relative)
            pct = percentile_rank(_METRIC[a](ln), cohort)
            blended = PCT_BLEND * pct + (1.0 - PCT_BLEND) * getattr(absolute, a)
            setattr(blk, a, clamp(blended))
        for attr, value in ln.overrides.items():  # overrides win last
            if attr in ATTRIBUTES:
                setattr(blk, attr, clamp(float(value)))
        out.append(blk)
    return out
