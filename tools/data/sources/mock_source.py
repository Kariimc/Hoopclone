"""Offline mock stat source.

Lets the export pipeline and demos run without network access or nba_api. It
fabricates plausible RawStatLines deterministically from the player's name so
output is stable across runs.
"""

from __future__ import annotations

import hashlib

from .base import RawStatLine, StatSource

_POOL = ["PG", "SG", "SF", "PF", "C"]


def _seed(name: str) -> int:
    return int(hashlib.sha256(name.encode()).hexdigest(), 16)


class MockSource(StatSource):
    """Deterministic fake stats — useful for tests, CI, and offline demos."""

    def fetch_player(self, name: str, season: str = "2025-26") -> RawStatLine:
        s = _seed(name)
        pos = _POOL[s % 5]

        def f(lo: float, hi: float, salt: int) -> float:
            frac = ((s >> salt) % 1000) / 1000.0
            return round(lo + frac * (hi - lo), 3)

        return RawStatLine(
            name=name,
            position=pos,
            games=int(f(55, 82, 3)),
            minutes=f(20, 36, 5),
            pts=f(8, 28, 7),
            fg_pct=f(0.40, 0.55, 9),
            fg3_pct=f(0.30, 0.43, 11),
            fg3a=f(1.0, 9.0, 13),
            ft_pct=f(0.68, 0.92, 15),
            ast=f(1.5, 9.0, 17),
            stl=f(0.4, 2.2, 19),
            blk=f(0.2, 2.4, 21),
            reb=f(2.5, 12.5, 23),
            ast_to=f(1.0, 3.2, 25),
        )
