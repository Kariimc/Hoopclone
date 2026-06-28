# HoopClone — Asset Index

Every locked asset, what it is, and where it goes in the Godot project.

> **How art gets into the game (read this).** The build reads art only from the
> **git repo**. A cloud session clones a fresh copy and cannot see images posted
> in chat, earlier sessions, your local downloads, or Higgsfield's servers (the
> CDN is blocked by network policy). So art must be **committed to the repo** to
> appear in the build — posting it in chat does nothing for the game.
>
> **The easy way:** double-click **`ADD-ASSETS.bat`** in the project root, pick
> each image when prompted, and it copies them to the right place and uploads
> them. No paths or renaming. The game then uses them automatically.

## Engine assets — import these into the project

| Asset | Job ID | File type | Target path | Notes |
|-------|--------|-----------|-------------|-------|
| **Rigged player model** | `65167a5f` | `.glb` | `res://assets/models/player_base.glb` | The GLB you're importing now. Rigged + textured, from player `256aea43`. |
| **Court floor** | `239e37bc` | image | `res://assets/textures/court_floor.png` | Hardwood floor albedo for the court plane. |
| **Team logo (crimson wolf)** | `e3bd0346` | `.svg` | `res://assets/textures/crw_logo.svg` | Vector — imports crisp at any size. Jersey crest + app icon. |
| **Arena (broadcast angle)** | `df5a3d96` | image | `res://assets/env/arena_backdrop.png` | Backdrop / environment reference behind the court. |

## Model references — use as modelling/texture reference, not direct import

| Asset | Job ID | What it's for |
|-------|--------|----------------|
| **Basket / hoop** | `c42a4d13` | Reference for the hoop prop model (backboard, breakaway rim, gooseneck, padded base). |
| **Main player (pixel art)** | `256aea43` | Source art the 3D was built from. Keep as the canonical character ref. |
| **Point guard #3** | `3f25a458` | Roster character ref. |
| **Wing #7** | `13b41417` | Roster character ref. |
| **Center #21** | `9ae54116` | Roster character ref. |
| **Women's #24** | `db2ed9c3` | Roster character ref. |
| **Referee** | `d515e415` | Official model ref (future). |

## UI design references — guides for the coded UI, not imported

| Asset | Job ID | What it guides |
|-------|--------|----------------|
| **News ticker (scrolling)** | `7bacfa17` | The look the coded `ticker.gd` reproduces. |
| **Ticker bar (base)** | `cce6e513` | Earlier ticker design. |
| **Scorebug (NBC-style)** | `85b6d07f` *(prefix)* | The look the coded `scorebug.gd` reproduces. |

## ⚠️ Not generated yet — the one real gap

`assets/team_manifest.json` references jersey textures that **don't exist yet**:

- `crw_jersey_albedo.png` / `crw_jersey_normal.png`
- `stm_jersey_albedo.png` / `stm_jersey_normal.png`
- `bay_jersey_albedo.png` / `bay_jersey_normal.png`

These need to be created (generate jersey-wrap textures, or author them) before
the apparel hot-swap (Sprint 4, step 5) does anything visible. Until then the
player wears whatever the base GLB shipped with. Say the word and I'll generate a
first pass of jersey albedo/normal maps.

## Folder layout you're building toward
```
res://assets/
  models/    player_base.glb
  textures/  court_floor.png   crw_logo.svg   crw_jersey_albedo.png  (…)
  env/       arena_backdrop.png
```
The job-id → origin mapping also lives in `assets/team_manifest.json` (machine
side) and `assets/manifest.json` (full catalogue) in the repo.
