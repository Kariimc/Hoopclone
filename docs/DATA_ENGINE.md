# Data Engine

## Two normalisation paths
- **Absolute (`normalize`)** — single-player imports. Linear scales + position
  baselines + overrides. Used by `export_roster.py`.
- **Pool (`normalize_pool`)** — whole-league imports. Each observable attribute is
  the player's **percentile within the league** (position-relative for
  rebounding / interior D / hops / finishing), blended 70/30 with the absolute
  value so a weak league can't inflate everyone. Used by `export_league.py`.

Unobservable attributes (speed, dunking) stay baseline-led; manual `overrides`
always win last.

## League import
`export_league.py --config league.json` fetches every player across every team,
pools them, normalises together, and writes one League JSON. See
`tools/data/sample_league.json` for the config shape. Run offline with `--mock`.

## Live service
`live_service.py` serves `/scores`, `/news`, `/boxscore`, `/health` on localhost.
A TTL cache means Godot can poll freely without re-hitting nba_api. Scores carry
period / clock / bonus / possession; headlines are synthesised from live game
state (leader, margin, late-game) and mixed with a rotating pool.

## Tests
`tools/data`: 13 pytest (absolute + pool: range, monotonicity, position-relative
rebounding, overrides). `tools/sim`: 22 pytest (9 shot curve + 11 contest model +
2 cross-language constant parity).

CI also runs a **Godot engine self-test** (`tests/godot/run_tests.gd`) — the real
GDScript `ShotModel` + `ContestModel` headless under Godot, asserting behaviour
(e.g. a contested shot's make% is lower than an open one) and failing the build
on any bad assertion. So the engine side is verified automatically, not just the
Python mirror. Two CI jobs: `python-tests`, `godot-tests`.
