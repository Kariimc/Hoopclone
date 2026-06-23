# HoopClone

Data-driven basketball simulation, Hoop Land–inspired, with a CEO/ownership
layer on top. **Engine: Godot 4. Data: nba_api (via a Python toolchain).**

This repo is the `feature/engine-spine` deliverable — Sprint 1. It stands up the
skeleton every later sprint hangs off: the broadcast camera, the player +
animation/hair spine, the 13-attribute model shared end to end, and the Python
data pipeline that feeds Godot.

---

## How the two halves talk

Godot can't speak nba_api directly (it needs browser-like headers, retries, and
caching that are painful in GDScript). So Python owns ingestion and Godot
consumes plain JSON / localhost HTTP:

```
                 tools/data (Python)                         game (Godot 4)
  nba_api ─► StatSource ─► normalize ─► export_roster ─► data/rosters/*.json ─► roster loader
  nba_api live ─► live_service (localhost:8777) ◄── HTTPRequest ── scorebug + ticker
```

The 13 attributes are defined once in `tools/data/schema.py` and mirrored
verbatim in `game/core/attributes.gd`. Keep them in lockstep.

---

## Python toolchain (`tools/data/`)

Stdlib-only for the core; `nba_api` only needed for live fetches.

| File | Role |
|------|------|
| `schema.py` | `AttributeBlock`, `Player`, `Team`, `League` dataclasses + `to_dict` |
| `sources/base.py` | `StatSource` protocol + provider-neutral `RawStatLine` |
| `sources/nba_api_source.py` | nba_api adapter (import-guarded) |
| `sources/mock_source.py` | deterministic offline source for tests/demos |
| `normalize.py` | raw stats → 13 attributes (0-99); percentile + linear-scale paths, position baselines, manual overrides |
| `export_roster.py` | CLI: fetch → normalize → write roster JSON for Godot |
| `live_service.py` | localhost service feeding the scorebug + ticker |
| `tests/test_normalize.py` | pytest: range + monotonicity + baselines + overrides |

### Setup & run

```bash
cd tools/data
python -m pip install -r requirements.txt        # nba_api + pytest

python -m pytest -q                               # validate the rating math

# Offline pipeline check (no network):
python export_roster.py --mock --team "Crimson Wolves" --abbr CRW \
  --players "Alpha Guard" "Bravo Wing" "Charlie Big" \
  --out ../../data/rosters/crimson.json

# Live import (residential IP recommended — see caveats):
python export_roster.py --source nba_api --team "Crimson Wolves" --abbr CRW \
  --players "Stephen Curry" "LeBron James" \
  --out ../../data/rosters/crimson.json

# Live scores/ticker service (Godot polls this):
python live_service.py --port 8777          # add --mock to force offline data
```

### nba_api caveats (baked into the code)

- Endpoints hit stats.nba.com, are **rate-limited**, and sometimes **block
  datacenter/cloud IPs**. Run exports from a residential machine; the adapter
  already spaces requests (`request_delay`).
- Treat this as a build-time/offline import that produces JSON you commit —
  not a per-frame runtime dependency. `live_service` is the only runtime touch,
  and it falls back to mock data on any error.

---

## Godot client (`game/`)

| File | Role |
|------|------|
| `core/attributes.gd` | 13-attribute mirror of `schema.py`; `mod()` → 0-1 physics scalars |
| `core/game_state.gd` | runtime phase tracker (BOOT…FINAL) |
| `camera/broadcast_camera.gd` | locked rig: ~7m high, ~14m back, −22° tilt, ~30° FOV, eased ball-follow |
| `player/player.gd` | `CharacterBody3D`; speed scaled by the Speed attribute |
| `player/anim_state_machine.gd` | full offense/defense moveset enumerated; one-shot vs locomotion handling |
| `player/verlet_hair.gd` | self-contained Verlet bone-chain solver (decoupled from anim) |
| `court/court.gd` | horizontal court dims + left/right basket anchors |
| `ui/scorebug.gd` | NBC-style scorebug, polls `live_service` `/scores` |
| `ui/ticker.gd` | top-left ticker: pop-in + scroll + dismiss, polls `/news` |
| `main.tscn` / `main.gd` | Sprint 1 smoke scene wiring camera + roster load + UI |

Open `project.godot` in Godot 4.x (Forward+). `main.tscn` is the boot scene.
The mesh/material imports (locked Higgsfield arena, floor, basket, rigged
player) land in the asset-pipeline sprint; Sprint 1 ships logic + anchors.

---

## Sprint status

- [x] **Sprint 0** — playable design sandbox (`hoopclone_mvp.html`)
- [x] **Sprint 1** — engine spine: camera, player/anim/hair, attribute model, Python data pipeline (this repo)
- [x] **Sprint 2** — shot + ball physics (green-zone meter, rim/backboard, shot model)
- [ ] **Sprint 3** — data engine hardening (percentile pools, full league import, live feed polish)
- [ ] **Sprint 4** — asset pipeline + AnimationTree blend trees + rigged hair write-back
- [ ] **Sprint 5** — box-score simulator (sim/spectate/play)
- [ ] **Sprint 6** — Season / Franchise
- [ ] **Sprint 7** — Commissioner + CEO/ownership layer

---

## feature/engine-spine — PR summary

- **Changed:** new repo scaffold — Godot 4 project + Python data toolchain.
- **Files:** see tree above (13 GDScript/scene/asset files, 8 Python modules + tests).
- **Testing:** `pytest` 9/9 green (range, monotonicity, position baselines, overrides, percentile); `export_roster.py --mock` and `live_service.py --mock` both verified end-to-end.
- **Risk:** nba_api IP-blocking/rate limits (mitigated: offline-first, mock fallback, request spacing). GDScript is unit-tested only via the data layer — engine scripts validated in-editor next sprint.
- **Rollback:** scaffold-only; delete the branch. No existing code touched.
