# CLAUDE.md — HoopClone Operating Manual

Read this whole file before touching code. It is written so a model can work
here at full quality without rediscovering the project's rules the hard way.

## Start here: `PROGRESS.md`

**Before doing anything else, read `PROGRESS.md`.** It is the live checklist
against `docs/HOOPCLONE-AUDIT.md` and `docs/SPRINT_6_7_ARCHITECTURE.md` — the
first unchecked item in it IS the task. Take it, do it, check it off in the
same PR, report, stop. **Do not re-audit the codebase, do not re-derive the
Sprint 5 build order, do not propose an alternative plan** — that work is
already done and re-doing it is the single biggest way a session wastes its
budget here. If you finish an item and want to pick up the next one, keep
going down the list in order. If `PROGRESS.md` is empty or every item is
checked, only then fall back to `docs/HOOPCLONE-AUDIT.md` for the next tier
of ranked work.

## What this project is

Data-driven basketball sim (Hoop Land–inspired) with a CEO/ownership layer on
top. **Godot 4.3** (Forward+) is the game; **Python** (stdlib-only core) owns
data ingestion and the canonical sim math. The owner (Kariim) works from a
laptop (double-clicks `.bat` scripts, does not type commands) and from Claude
Code cloud sessions. **You are the engineer; the docs are the spec.**

Sprint status lives in `README.md`. Currently: Sprints 0–4 shipped; Sprint 5
(box-score simulator) is in progress — see `PROGRESS.md` for exactly what's
done and what's next, with its build plan in `docs/HOOPCLONE-AUDIT.md` §5 and
Sprints 6–7 designed in `docs/SPRINT_6_7_ARCHITECTURE.md`. **Execute against
those documents — do not re-plan work that is already planned.**

## The architecture in one paragraph

Python fetches NBA stats (nba_api) offline and emits committed JSON
(`data/rosters/*.json`); Godot only ever reads JSON or polls a localhost
`live_service`. The sim math (shot curve, contest curve — later possessions)
exists **twice on purpose**: a canonical Python module in `tools/sim/` and a
GDScript mirror in `game/core/`, kept identical, with pytest locking the
curve shape and `test_gdscript_parity.py` failing CI if constants drift.
Ball flight is **outcome-first**: roll the make probability, then animate the
ball to match — never rigid-body physics deciding makes.

## Map

| Path | What it is |
|---|---|
| `tools/sim/` | **Canonical** sim math (shot_model.py, contest_model.py) + spec-lock pytest |
| `game/core/` | GDScript mirrors of tools/sim + attributes + game_state |
| `tools/data/` | nba_api ingestion → roster/league JSON; `live_service.py` |
| `tools/godot/` | Headless drivers (screenshot.gd — see `run-hoopclone` skill) |
| `tests/godot/run_tests.gd` | Headless engine self-test (runs the REAL .gd in CI) |
| `game/main.tscn` + `main.gd` | Boot scene (flagged for split — audit §4.1) |
| `docs/DECISIONS.md` | Locked decisions — **never relitigate these** |
| `docs/HOOPCLONE-AUDIT.md` | Known bugs, ranked debt, Sprint 5 plan |
| `docs/` (SHOT_MODEL, CONTEST_MODEL, DATA_ENGINE, ASSET_INDEX) | Per-system specs |
| `PLAY.bat` / `SAVE-WORK.bat` / `GET-LATEST.bat` | Owner's no-typing workflow — keep them working |

## Conventions (the ones followed, plus the ones you must add to)

1. **Docs are load-bearing.** Every system has a doc in `docs/`; DECISIONS.md
   records why. When you change behavior, update the matching doc **in the same
   PR** — a PR that changes the shot curve but not `docs/SHOT_MODEL.md` is
   incomplete.
2. **Twin-module pattern.** Any gameplay math shared between sim and engine is
   written Python-first in `tools/sim/`, mirrored in `game/core/`, constants
   added to `test_gdscript_parity.py`, behavior added to
   `tests/godot/run_tests.gd`. Follow `.claude/skills/twin-module/`.
3. **Commit style:** conventional commits with a scope, imperative, explaining
   intent: `feat(sim+scene): Sprint 5 defender contest model`, `fix(scripts): pull
   before push so SAVE-WORK can't be rejected`. One logical change per PR;
   everything merges via PR to `main`.
4. **Stdlib-only Python core.** `nba_api` is import-guarded and only touched by
   live fetches; tests must run with nothing but pytest installed.
5. **Asset-optional boot.** `main.tscn` must open and run with zero binary
   assets present (fallback capsule/colors). Never add a hard dependency on a
   texture or mesh. Assets load via `_first_existing(candidates)` lists.
6. **Binaries go through Git LFS** (see `.gitattributes`) with their `.import`
   sidecars committed. Follow `.claude/skills/asset-intake/`.
7. **Plain Dicts + JSON over classes/Resources/SQLite.** House style for all
   data (rosters, saves, calibration). Schema-version any persisted JSON.
8. **Determinism where the sim rolls dice.** New randomness in sim code takes a
   seeded RNG parameter (Sprint 6 requires replayable games — build it in now).
9. **Pure functions for derivations.** Standings, balances, box-score totals
   are computed from source data every time, never cached fields.
10. **CI is the contract:** `python -m pytest tools` (3.10/3.11/3.12) plus the
    headless Godot 4.3 self-test. Both must be green before any push.

## Mistakes a weaker model will make here — named, with the preventing rule

- **The one-sided edit.** Tweaking a constant or formula in `shot_model.py` OR
  `shot_model.gd` but not both. *Rule:* never open one twin without opening the
  other; run `python -m pytest tools/sim` before committing — the parity test
  exists to catch you.
- **The physics "improvement."** "Fixing" ball flight to use real rigid-body
  physics for makes. *Rule:* outcome-first ball is a locked decision
  (DECISIONS.md / audit §2). Roll the outcome, animate to match. Reject the
  urge.
- **Godot-first math.** Prototyping new sim logic in GDScript because that's
  where the game is. *Rule:* Python first (pytest iteration is 10× faster),
  mirror second. The mirror must stay headless-runnable — no scene-tree
  (`get_node`, signals to UI) dependencies inside `game/core/` sim modules.
- **The hard asset dependency.** Preloading a texture/mesh that isn't in the
  repo, breaking boot and CI on fresh clones. *Rule:* every asset load goes
  through an existence check with a coded fallback; verify by booting headless
  (skill `run-hoopclone`) after touching asset paths.
- **Feeding the god-object.** Adding new systems into `game/main.gd` because
  everything else is there. *Rule:* audit §4.1 — new systems get their own file
  under `game/<area>/`; if `main.gd` is still unsplit, do the split first (it's
  Sprint 5 task #1).
- **Relitigating locked decisions.** Suggesting balldontlie, Ursina, per-defender
  contest lists, hand-tuned quick-sim formulas, vertical camera, generated
  animation. *Rule:* check DECISIONS.md before proposing architecture. If you
  disagree, say so in the PR description — don't silently build the other thing.
- **Breaking the owner's workflow.** Renaming/moving `PLAY.bat`,
  `SAVE-WORK.bat`, `GET-LATEST.bat`, `ADD-ASSETS.bat`, or making them require
  typing. *Rule:* the owner double-clicks; any change to these must remain
  zero-setup and must keep the pull-before-push behavior.
- **Scraping Basketball-Reference.** Forbidden by ToS. *Rule:* new data comes
  through a `StatSource` adapter (`tools/data/sources/`) only.
- **"Fixing" the leaked-objects warning.** Headless Godot prints
  `ObjectDB instances leaked at exit` — it's benign, exit code is what matters.
  *Rule:* judge Godot runs by exit code and test output, not stderr noise.
- **Editing generated/cached state.** `.godot/`, `.godot-bin/` are per-machine
  and gitignored. *Rule:* never commit them; never rely on their contents.
- **Changing signal semantics that others consume.** (Audit §3.2: `missed`
  fires when the bounce starts.) *Rule:* before a system consumes a signal,
  settle its meaning in the doc; after two consumers exist, changing semantics
  is a breaking change requiring an explicit decision entry.

## Quality bar per deliverable — checkable, not adjectives

**Any PR:**
- [ ] `python -m pytest tools` green locally (35+ tests, grows monotonically)
- [ ] Godot self-test green: `godot --headless --path . --script res://tests/godot/run_tests.gd` (exit 0)
- [ ] Matching `docs/*.md` updated in the same PR; README sprint table still true
- [ ] Conventional-commit message with scope; PR body states Changed / Testing / Risk / Rollback
- [ ] No new hard asset dependency (fresh-clone boot still works)

**New/changed sim math:**
- [ ] Python module in `tools/sim/` with docstring stating design intent
- [ ] Factors are bounded and individually monotonic (house curve style)
- [ ] pytest locks: range/clamps, monotonicity per factor, boundary values
- [ ] GDScript mirror in `game/core/` with identical constants
- [ ] Constants added to `test_gdscript_parity.py`; behavior added to `run_tests.gd`
- [ ] Doc created/updated in `docs/`

**Scene/engine change:**
- [ ] Boots headless with zero optional assets present
- [ ] Verified visually via the `run-hoopclone` skill (screenshot) when it affects rendering/gameplay feel
- [ ] Nothing new in `main.gd` that belongs in its own module
- [ ] Registration/wiring failures `push_warning`, never silently no-op

**New data pipeline code:**
- [ ] Runs offline with `--mock`; nba_api touch is import-guarded
- [ ] Output is committed JSON with a stable, documented schema
- [ ] No network calls in any test

**Assets:**
- [ ] Follow `.claude/skills/asset-intake/` — LFS-tracked, sidecar committed,
      wired via candidates list, boot verified with and without the file

## When uncertain — exact escalation rules

**Proceed without asking** when the answer is already written down: DECISIONS.md,
the audit, the architecture doc, or an existing pattern in the code. Reversible,
in-scope work (refactors from the audit list, bug fixes with tests, doc syncs)
needs no permission.

**Ask (AskUserQuestion) before acting** when:
1. A change would contradict DECISIONS.md or the audit's "do not touch" table.
2. Two reasonable interpretations of the request lead to different code — ask
   with the concrete options, not "what do you mean?".
3. You'd change the meaning of an existing signal, JSON schema, or public
   constant that another system already consumes.
4. Anything destructive: deleting assets, rewriting git history, force-push.
5. Scope grows: the task reveals a second problem worth >30 min — finish the
   asked task, report the finding, ask before fixing it.

**Never ask, just do:** run tests, run the game headless, read any file, update
docs to match code you changed, add tests.

**When blocked** (e.g., nba_api blocks the datacenter IP): fall back to `--mock`
/ offline paths, state clearly in the PR what was verified and what needs a
residential-IP run by the owner. Never fake a live verification.

**When tests fail after your change:** fix or revert before pushing. Never
skip, weaken, or delete a spec-lock test to get green — those tests ARE the
spec. If a test seems wrong, that's an "ask" (rule 3).

## Verification commands (memorize)

```bash
python -m pytest tools -q                      # all Python spec locks (~0.1 s)
# Godot self-test (binary lives in .godot-bin/, see run-hoopclone skill to fetch):
./.godot-bin/Godot_v4.3-stable_linux.x86_64 --headless --path . --import   # once per fresh clone
./.godot-bin/Godot_v4.3-stable_linux.x86_64 --headless --path . --script res://tests/godot/run_tests.gd
```

For playing/screenshotting the actual scene, use the `run-hoopclone` skill.
