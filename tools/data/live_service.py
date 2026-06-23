"""Live data service for the broadcast UI (scorebug + news ticker).

A tiny localhost HTTP service the Godot client polls via HTTPRequest:

    GET /scores  -> current/most-recent games (feeds the scorebug)
    GET /news    -> headline strings (feeds the scrolling ticker)
    GET /health  -> {"ok": true}

Why a sidecar instead of Godot calling stats.nba.com directly? nba_api needs a
specific header set and tolerates rate limits with retries/caching that are far
easier to manage in Python than in GDScript. Godot just polls localhost.

Run:  python live_service.py --port 8777   (add --mock to force offline data)
Falls back to mock data automatically if nba_api is unavailable or errors.
"""

from __future__ import annotations

import argparse
import json
import random
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:  # pragma: no cover
    from nba_api.live.nba.endpoints import scoreboard as _scoreboard
    _LIVE_AVAILABLE = True
except Exception:
    _LIVE_AVAILABLE = False


_MOCK_HEADLINES = [
    "Crimson Wolves win 5th straight | CRW 112 - 104 STM",
    "Rookie guard drops career-high 34 off the bench",
    "Trade buzz: front office eyeing a stretch big at the deadline",
    "Injury update: starting center listed day-to-day (ankle)",
    "Player of the Week: 28.4 PPG on 49/41/90 splits",
]


def _live_scores() -> list[dict]:
    if not _LIVE_AVAILABLE:
        return _mock_scores()
    try:
        board = _scoreboard.ScoreBoard().get_dict()
        games = board["scoreboard"]["games"]
        out = []
        for g in games[:8]:
            out.append(
                {
                    "home": g["homeTeam"]["teamTricode"],
                    "away": g["awayTeam"]["teamTricode"],
                    "home_score": g["homeTeam"]["score"],
                    "away_score": g["awayTeam"]["score"],
                    "status": g.get("gameStatusText", "").strip(),
                }
            )
        return out or _mock_scores()
    except Exception:
        return _mock_scores()


def _mock_scores() -> list[dict]:
    return [
        {"home": "CRW", "away": "STM", "home_score": 88, "away_score": 81,
         "status": "Q3 4:12"},
        {"home": "BAY", "away": "NIT", "home_score": 64, "away_score": 70,
         "status": "Q2 1:33"},
    ]


def _news() -> list[str]:
    items = list(_MOCK_HEADLINES)
    random.shuffle(items)
    return items


class Handler(BaseHTTPRequestHandler):
    def _send(self, payload) -> None:
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802 (http.server API)
        if self.path.startswith("/scores"):
            self._send({"games": _live_scores()})
        elif self.path.startswith("/news"):
            self._send({"headlines": _news()})
        elif self.path.startswith("/health"):
            self._send({"ok": True, "live": _LIVE_AVAILABLE})
        else:
            self.send_error(404)

    def log_message(self, *_args):  # silence default logging
        return


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="HoopClone live data service.")
    p.add_argument("--port", type=int, default=8777)
    p.add_argument("--mock", action="store_true", help="force offline mock data")
    args = p.parse_args(argv)

    if args.mock:
        global _LIVE_AVAILABLE
        _LIVE_AVAILABLE = False

    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    mode = "live (nba_api)" if _LIVE_AVAILABLE else "mock"
    print(f"HoopClone live service on http://127.0.0.1:{args.port}  [{mode}]")
    print("  GET /scores  /news  /health   (Ctrl+C to stop)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
