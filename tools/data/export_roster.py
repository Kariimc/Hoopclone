"""Export roster JSON for the Godot client.

Fetch a list of players from a chosen stat source, normalise each into the 13
HoopClone attributes, assemble a Team/League, and write JSON that Godot loads
from ``data/rosters/``.

Examples
--------
    # Offline, no dependencies — proves the pipeline end to end:
    python export_roster.py --mock --team "Crimson Wolves" --abbr CRW \\
        --players "Alpha Guard" "Bravo Wing" "Charlie Big" --out ../../data/rosters/crimson.json

    # Live via nba_api (needs `pip install nba_api`, run from a residential IP):
    python export_roster.py --source nba_api --team "Crimson Wolves" --abbr CRW \\
        --players "Stephen Curry" "LeBron James" --out ../../data/rosters/crimson.json
"""

from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from schema import Player, Team, League, AttributeBlock  # noqa: E402
from normalize import normalize  # noqa: E402


def _make_source(kind: str):
    if kind == "mock":
        from sources.mock_source import MockSource

        return MockSource()
    if kind == "nba_api":
        from sources.nba_api_source import NbaApiSource

        return NbaApiSource()
    raise ValueError(f"Unknown source '{kind}'. Use 'mock' or 'nba_api'.")


def build_team(
    source, team_name: str, abbr: str, player_names: list[str], season: str
) -> Team:
    team = Team(team_id=abbr.lower(), name=team_name, abbreviation=abbr)
    for i, name in enumerate(player_names):
        raw = source.fetch_player(name, season)
        attrs: AttributeBlock = normalize(raw)
        team.players.append(
            Player(
                player_id=f"{abbr.lower()}-{i:02d}",
                name=raw.name,
                position=raw.position,
                jersey=(i * 7 + 3) % 99,
                attributes=attrs,
            )
        )
    return team


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Export HoopClone roster JSON.")
    p.add_argument("--source", default=None, help="mock | nba_api")
    p.add_argument("--mock", action="store_true", help="shorthand for --source mock")
    p.add_argument("--team", required=True)
    p.add_argument("--abbr", required=True)
    p.add_argument("--players", nargs="+", required=True)
    p.add_argument("--season", default="2025-26")
    p.add_argument("--out", required=True)
    args = p.parse_args(argv)

    kind = "mock" if args.mock else (args.source or "nba_api")
    source = _make_source(kind)

    team = build_team(source, args.team, args.abbr, args.players, args.season)
    league = League(season=args.season, teams=[team])

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(league.to_dict(), fh, indent=2)

    print(f"Wrote {len(team.players)} players to {args.out} (source={kind}).")
    for pl in team.players:
        print(f"  #{pl.jersey:>2} {pl.name:<16} {pl.position}  OVR {pl.attributes.overall()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
