"""Export a full multi-team league to JSON, pool-normalised.

Unlike export_roster.py (one team, absolute ratings), this fetches every player
across every team, normalises them *together* so attributes are league-relative
(a 40% three-point shooter rates against the whole league's distribution), then
writes one League JSON the Godot client loads.

League config is JSON:

    {
      "season": "2025-26",
      "teams": [
        {"name": "Crimson Wolves", "abbr": "CRW", "players": ["...", "..."]},
        {"name": "Storm",          "abbr": "STM", "players": ["...", "..."]}
      ]
    }

Examples
--------
    # Offline demo with the bundled sample config:
    python export_league.py --mock --config sample_league.json \\
        --out ../../data/rosters/league.json

    # Live via nba_api:
    python export_league.py --source nba_api --config my_league.json \\
        --out ../../data/rosters/league.json
"""

from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from schema import Player, Team, League  # noqa: E402
from normalize import normalize_pool  # noqa: E402


def _make_source(kind: str):
    if kind == "mock":
        from sources.mock_source import MockSource

        return MockSource()
    if kind == "nba_api":
        from sources.nba_api_source import NbaApiSource

        return NbaApiSource()
    raise ValueError(f"Unknown source '{kind}'. Use 'mock' or 'nba_api'.")


def build_league(source, config: dict) -> League:
    season = config.get("season", "2025-26")

    # 1) Fetch every player across the whole league into one flat list, keeping
    #    track of which team each belongs to.
    flat_lines = []
    owner = []  # parallel list of (team_index, jersey)
    teams_meta = config["teams"]
    for ti, tcfg in enumerate(teams_meta):
        for pi, name in enumerate(tcfg["players"]):
            flat_lines.append(source.fetch_player(name, season))
            owner.append((ti, (pi * 7 + 3) % 99))

    # 2) Normalise the whole pool together -> league-relative attributes.
    blocks = normalize_pool(flat_lines, position_relative=True)

    # 3) Reassemble into teams.
    teams = [
        Team(team_id=t["abbr"].lower(), name=t["name"], abbreviation=t["abbr"])
        for t in teams_meta
    ]
    for idx, (line, blk) in enumerate(zip(flat_lines, blocks)):
        ti, jersey = owner[idx]
        t = teams[ti]
        t.players.append(
            Player(
                player_id=f"{t.abbreviation.lower()}-{len(t.players):02d}",
                name=line.name,
                position=line.position,
                jersey=jersey,
                attributes=blk,
            )
        )
    return League(season=season, teams=teams)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Export a pool-normalised league.")
    p.add_argument("--source", default=None, help="mock | nba_api")
    p.add_argument("--mock", action="store_true", help="shorthand for --source mock")
    p.add_argument("--config", required=True, help="league config JSON path")
    p.add_argument("--out", required=True)
    args = p.parse_args(argv)

    kind = "mock" if args.mock else (args.source or "nba_api")
    source = _make_source(kind)

    with open(args.config, encoding="utf-8") as fh:
        config = json.load(fh)

    league = build_league(source, config)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(league.to_dict(), fh, indent=2)

    total = sum(len(t.players) for t in league.teams)
    print(f"Wrote league: {len(league.teams)} teams, {total} players -> {args.out} "
          f"(source={kind}, pool-normalised).")
    for t in league.teams:
        top = max(t.players, key=lambda pl: pl.attributes.overall())
        print(f"  {t.abbreviation:<4} {t.name:<18} "
              f"top: {top.name} (OVR {top.attributes.overall()})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
