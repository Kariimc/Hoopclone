# HANDOFF - Kariimc/Hoopclone

> Continuity doc. Any agent must resume cold from this file with zero briefing.
> Update it in the same commit as any code change.

**Seeded:** 2026-07-15 from verified repo state. Sections marked UNVERIFIED were not
provable from the repo alone - fill them in, do not guess.

## Verified facts

| | |
|---|---|
| Repo | `Kariimc/Hoopclone` |
| Namespace | user `Kariimc` |
| Default branch | `main` |
| Visibility | public |
| Language | GDScript |
| Files | 113 |
| Last commit | 2026-07-08 - fix(scene+sim): Sprint 5 refactor-first pass + live progress tracker ( |
| Branches | 14 |
| Open PRs | 1 |

**Top-level dirs:** `.claude`, `.github`, `assets`, `data`, `docs`, `game`, `tests`, `tools`

**Root files:** `.gitattributes`, `.gitignore`, `ADD-ASSETS.bat`, `CLAUDE.md`, `GET-LATEST.bat`, `PLAY.bat`, `PROGRESS.md`, `README.md`, `SAVE-WORK.bat`, `icon.svg`, `icon.svg.import`, `manifest.json`

**Existing docs:** `CLAUDE.md`, `PROGRESS.md`, `README.md`, `docs/SPRINT_6_7_ARCHITECTURE.md`

## Open PRs

- #16 refactor: sprint-5 prep — bug fixes + main.gd split + smoke test  `refactor/sprint5-prep`

## Current state

**UNVERIFIED.** Percent-complete and working/broken status cannot be derived from
the repo alone. Do not write a number here you have not proven. Read the code, run
the build, then record what you observed and how you observed it.

## Exact next steps

**UNVERIFIED.** Fill in on first real session in this repo.

## Open decisions

**UNVERIFIED.**

## Rules

- Repos span TWO namespaces: user `Kariimc` AND org `shift9-studio`. Enumerate with
  `gh api '/user/repos?affiliation=owner,collaborator,organization_member'`, never
  `gh repo list Kariimc` alone. See `Kariimc/my-skills` `rules/10-repo-topology.md`.
- Never assert an absence, status, or completion without proving your scope was exhaustive.
- Update this file in the same commit as any code change. A global pre-commit hook enforces it.
