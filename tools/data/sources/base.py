"""Provider-neutral stat source contract.

Every external data provider (nba_api today; balldontlie, a CSV importer, or a
custom-league editor tomorrow) implements :class:`StatSource` and emits
:class:`RawStatLine` records. The normaliser only ever sees ``RawStatLine``,
so swapping providers never touches the rating math.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol, Optional


@dataclass
class RawStatLine:
    """One player's raw per-game / rate stats from some provider.

    Fields are intentionally provider-neutral. Anything a provider can't supply
    is left as ``None`` and the normaliser falls back to a position baseline.
    """

    name: str
    position: str = "SF"
    games: int = 0
    minutes: float = 0.0

    # Scoring / efficiency
    pts: float = 0.0
    fg_pct: Optional[float] = None        # 0-1
    fg3_pct: Optional[float] = None       # 0-1
    fg3a: Optional[float] = None          # attempts per game
    ft_pct: Optional[float] = None        # 0-1
    ft_rate: Optional[float] = None       # FTA / FGA
    rim_fg_pct: Optional[float] = None    # at-rim FG% (advanced; may be None)

    # Playmaking
    ast: float = 0.0
    ast_to: Optional[float] = None        # assist/turnover ratio

    # Defense / activity
    stl: float = 0.0
    blk: float = 0.0
    reb: float = 0.0
    oreb_pct: Optional[float] = None
    dreb_pct: Optional[float] = None
    dbpm: Optional[float] = None          # defensive box plus/minus

    # Manual overrides keyed by attribute name (e.g. {"dunking": 92}). These win
    # over computed values — for the attributes box scores can't infer (hops,
    # dunking, handles) a scout/editor supplies them here.
    overrides: dict = field(default_factory=dict)


class StatSource(Protocol):
    """Anything that can produce RawStatLines for players."""

    def fetch_player(self, name: str, season: str) -> RawStatLine:
        ...
