"""Live data service for the broadcast UI (scorebug + news ticker).

A localhost HTTP service the Godot client polls via HTTPRequest:

    GET /scores    -> rich game state (period, clock, bonus, possession)
    GET /news      -> headline strings, synthesised from live game state
    GET /boxscore  -> per-team summary lines for the first game
    GET /health    -> {"ok": true, "live": bool}

Sprint 3 hardening:
  * TTL cache — nba_api is fetched at most once per `cache_ttl` seconds no matter
    how fast Godot polls, so the scorebug can poll every frame-ish safely.
  * Richer schema — period/clock/bonus/possession feed a real scorebug.
  * Synthesised headlines — the ticker reflects what's actually happening
    (leader, margin, late-game) instead of a static loop.
  * Graceful degradation — any nba_api error falls back to mock data.

Run:  python live_service.py --port 8777     (add --mock to force offline data)
"""

from __future__ import annotations

import argparse
import json
import random
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:  # pragma: no cover
    from nba_api.live.nba.endpoints import scoreboard as _scoreboard
    _LIVE_AVAILABLE = True
except Exception:
    _LIVE_AVAILABLE = False


# --- tiny TTL cache so we never refetch faster than cache_ttl ---------------
class _TTLCache:
    def __init__(self, ttl: float = 6.0) -> None:
        self.ttl = ttl
        self._store: dict = {}

    def get_or(self, key: str, producer):
        now = time.monotonic()
        hit = self._store.get(key)
        if hit and (now - hit[0]) < self.ttl:
            return hit[1]
        value = producer()
        self._store[key] = (now, value)
        return value


_CACHE = _TTLCache()
_EXTRA_HEADLINES = [
    "Trade buzz: front office eyeing a stretch big at the deadline",
    "Rookie guard drops career-high 34 off the bench",
    "Player of the Week: 28.4 PPG on 49/41/90 splits",
    "Injury update: starting centre listed day-to-day (ankle)",
]


def _live_scores() -> list[dict]:
    if not _LIVE_AVAILABLE:
        return _mock_scores()
    try:
        board = _scoreboard.ScoreBoard().get_dict()
        out = []
        for g in board["scoreboard"]["games"][:8]:
            ht, at = g["homeTeam"], g["awayTeam"]
            out.append({
                "home": ht["teamTricode"], "away": at["teamTricode"],
                "home_score": ht["score"], "away_score": at["score"],
                "period": g.get("period", 0),
                "clock": _fmt_clock(g.get("gameClock", "")),
                "status": g.get("gameStatusText", "").strip(),
                "home_bonus": ht.get("inBonus", "0") == "1",
                "away_bonus": at.get("inBonus", "0") == "1",
                "possession": _poss(g),
            })
        return out or _mock_scores()
    except Exception:
        return _mock_scores()


def _fmt_clock(iso: str) -> str:
    # nba_api gives ISO 8601 duration like "PT04M12.00S"; show MM:SS.
    if not iso.startswith("PT"):
        return iso
    body = iso[2:]
    mins = secs = 0
    if "M" in body:
        m, body = body.split("M", 1)
        mins = int(float(m))
    if "S" in body:
        secs = int(float(body.split("S")[0]))
    return f"{mins}:{secs:02d}"


def _poss(g: dict) -> str:
    pid = str(g.get("possession", "") or "")
    if pid and pid == str(g["homeTeam"].get("teamId", "")):
        return "home"
    if pid and pid == str(g["awayTeam"].get("teamId", "")):
        return "away"
    return ""


def _mock_scores() -> list[dict]:
    return [
        {"home": "CRW", "away": "STM", "home_score": 88, "away_score": 81,
         "period": 3, "clock": "4:12", "status": "Q3", "home_bonus": True,
         "away_bonus": False, "possession": "home"},
        {"home": "BAY", "away": "NIT", "home_score": 64, "away_score": 70,
         "period": 2, "clock": "1:33", "status": "Q2", "home_bonus": False,
         "away_bonus": False, "possession": "away"},
    ]


def _synthesise_headlines(games: list[dict]) -> list[str]:
    lines: list[str] = []
    for g in games:
        hs, as_ = g["home_score"], g["away_score"]
        lead, trail = (g["home"], g["away"]) if hs >= as_ else (g["away"], g["home"])
        margin = abs(hs - as_)
        late = g["period"] >= 4 or (g["period"] == 3 and ":" in str(g["clock"]))
        if margin == 0:
            lines.append(f"All square: {g['away']} {as_} - {hs} {g['home']} "
                         f"in Q{g['period']}")
        elif margin <= 4 and late:
            lines.append(f"Down to the wire: {lead} clings to a {margin}-point lead "
                         f"({g['away']} {as_} - {hs} {g['home']})")
        else:
            lines.append(f"{lead} leads {trail} by {margin} "
                         f"({g['away']} {as_} - {hs} {g['home']}, Q{g['period']})")
    pool = lines + _EXTRA_HEADLINES
    random.shuffle(pool)
    return pool


def _boxscore(games: list[dict]) -> dict:
    if not games:
        return {}
    g = games[0]
    return {
        "home": {"team": g["home"], "pts": g["home_score"], "bonus": g["home_bonus"]},
        "away": {"team": g["away"], "pts": g["away_score"], "bonus": g["away_bonus"]},
        "period": g["period"], "clock": g["clock"],
    }


class Handler(BaseHTTPRequestHandler):
    def _send(self, payload) -> None:
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        games = _CACHE.get_or("scores", _live_scores)
        if self.path.startswith("/scores"):
            self._send({"games": games})
        elif self.path.startswith("/news"):
            self._send({"headlines": _synthesise_headlines(games)})
        elif self.path.startswith("/boxscore"):
            self._send(_boxscore(games))
        elif self.path.startswith("/health"):
            self._send({"ok": True, "live": _LIVE_AVAILABLE})
        else:
            self.send_error(404)

    def log_message(self, *_a):
        return


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="HoopClone live data service.")
    p.add_argument("--port", type=int, default=8777)
    p.add_argument("--mock", action="store_true", help="force offline mock data")
    p.add_argument("--ttl", type=float, default=6.0, help="cache TTL seconds")
    args = p.parse_args(argv)

    global _LIVE_AVAILABLE
    if args.mock:
        _LIVE_AVAILABLE = False
    _CACHE.ttl = args.ttl

    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    mode = "live (nba_api)" if _LIVE_AVAILABLE else "mock"
    print(f"HoopClone live service on http://127.0.0.1:{args.port}  "
          f"[{mode}, ttl={args.ttl}s]")
    print("  GET /scores  /news  /boxscore  /health   (Ctrl+C to stop)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
