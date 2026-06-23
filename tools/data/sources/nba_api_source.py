"""nba_api stat source adapter.

Wraps the ``nba_api`` package (https://github.com/swar/nba_api) behind the
:class:`StatSource` contract. The import is guarded so this module loads even
when ``nba_api`` isn't installed (e.g. in CI that only runs the normaliser
tests); the dependency is only required when you actually fetch.

Caveats baked in below:
  * nba_api hits stats.nba.com endpoints, which are rate-limited and sometimes
    block cloud / datacenter IPs. Run exports from a residential machine, add a
    small delay between players, and cache results.
  * Endpoints occasionally need a browser-like header set and a longer timeout.
"""

from __future__ import annotations

import time
from typing import Optional

from .base import RawStatLine, StatSource

try:  # pragma: no cover - exercised only when the dependency is present
    from nba_api.stats.static import players as _players
    from nba_api.stats.endpoints import (
        playercareerstats as _career,
        commonplayerinfo as _info,
    )
    _NBA_API_AVAILABLE = True
except Exception:  # ImportError or downstream import errors
    _NBA_API_AVAILABLE = False


_POS_MAP = {
    "Guard": "PG",
    "Guard-Forward": "SG",
    "Forward-Guard": "SF",
    "Forward": "SF",
    "Forward-Center": "PF",
    "Center-Forward": "C",
    "Center": "C",
}


class NbaApiSource(StatSource):
    """Fetch season-average stats for a player by name via nba_api."""

    def __init__(self, request_delay: float = 0.6, timeout: int = 30) -> None:
        if not _NBA_API_AVAILABLE:
            raise RuntimeError(
                "nba_api is not installed. Run `pip install nba_api` "
                "(see tools/data/requirements.txt) before using NbaApiSource."
            )
        self.request_delay = request_delay
        self.timeout = timeout

    def _resolve_id(self, name: str) -> tuple[str, str]:
        matches = _players.find_players_by_full_name(name)
        if not matches:
            raise LookupError(f"No NBA player found matching '{name}'.")
        m = matches[0]
        return str(m["id"]), m["full_name"]

    def fetch_player(self, name: str, season: str = "2025-26") -> RawStatLine:
        player_id, full_name = self._resolve_id(name)
        time.sleep(self.request_delay)

        info = _info.CommonPlayerInfo(
            player_id=player_id, timeout=self.timeout
        ).get_normalized_dict()["CommonPlayerInfo"][0]
        position = _POS_MAP.get(info.get("POSITION", "Forward"), "SF")

        time.sleep(self.request_delay)
        rows = _career.PlayerCareerStats(
            player_id=player_id, timeout=self.timeout
        ).get_normalized_dict()["SeasonTotalsRegularSeason"]

        season_row = next(
            (r for r in rows if r.get("SEASON_ID", "").endswith(season[-2:])),
            rows[-1] if rows else None,
        )
        if season_row is None:
            raise LookupError(f"No season stats for {full_name}.")

        gp = max(1, int(season_row.get("GP", 1)))

        def per_game(key: str) -> float:
            return round(float(season_row.get(key, 0) or 0) / gp, 2)

        fga = float(season_row.get("FGA", 0) or 0)
        fta = float(season_row.get("FTA", 0) or 0)

        return RawStatLine(
            name=full_name,
            position=position,
            games=gp,
            minutes=per_game("MIN"),
            pts=per_game("PTS"),
            fg_pct=_safe_pct(season_row.get("FG_PCT")),
            fg3_pct=_safe_pct(season_row.get("FG3_PCT")),
            fg3a=per_game("FG3A"),
            ft_pct=_safe_pct(season_row.get("FT_PCT")),
            ft_rate=round(fta / fga, 3) if fga else None,
            ast=per_game("AST"),
            stl=per_game("STL"),
            blk=per_game("BLK"),
            reb=per_game("REB"),
            ast_to=(
                round(
                    float(season_row.get("AST", 0) or 0)
                    / float(season_row.get("TOV", 1) or 1),
                    2,
                )
                if season_row.get("TOV")
                else None
            ),
        )


def _safe_pct(value) -> Optional[float]:
    try:
        v = float(value)
    except (TypeError, ValueError):
        return None
    return v if 0.0 <= v <= 1.0 else None
