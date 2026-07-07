---
name: ship
description: HoopClone's full pre-merge gauntlet — run every verification (pytest, Godot self-test, fresh-boot check, doc sync), then commit, push, and open a PR the house way. Use before pushing any change, or when asked to "ship it", "make a PR", or "finish up".
---

# Ship a HoopClone change

The repo's guarantee is that `main` always boots from a fresh clone and every
sim curve is spec-locked. This skill is the gauntlet a change runs before it
leaves the machine. Run it top to bottom; don't skip steps because the change
"is small" — the historical breakages here were all small changes.

## Step 1 — Python spec locks (always, ~0.1 s)

```bash
python -m pytest tools -q
```

Must be green. If a spec-lock test fails, the fix is in your code or (rarely)
a deliberate spec change — never in weakening the test. A deliberate spec
change also updates the matching `docs/*.md` and, if it's a design shift,
`docs/DECISIONS.md`.

## Step 2 — Godot engine self-test (whenever any `.gd`, `.tscn`, `.import`, `project.godot`, or asset changed)

Ensure the pinned binary exists (same convention as PLAY.bat / CI):

```bash
[ -x .godot-bin/Godot_v4.3-stable_linux.x86_64 ] || {
  mkdir -p .godot-bin && curl -fsSL -o .godot-bin/godot.zip \
    https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip \
  && unzip -o -q .godot-bin/godot.zip -d .godot-bin \
  && chmod +x .godot-bin/Godot_v4.3-stable_linux.x86_64; }
./.godot-bin/Godot_v4.3-stable_linux.x86_64 --headless --path . --import
./.godot-bin/Godot_v4.3-stable_linux.x86_64 --headless --path . --script res://tests/godot/run_tests.gd
```

Judge by **exit code and the `ALL GODOT TESTS PASSED` line** — ignore
`ObjectDB instances leaked` / `resources still in use` stderr noise.

## Step 3 — Fresh-boot check (whenever a scene, asset path, or loader changed)

The asset-optional-boot invariant: `main.tscn` must run with zero optional
binaries. If you touched `main.gd`'s hydration code, candidates lists, or
anything under `assets/`, boot the real scene via the `run-hoopclone` skill
(xvfb + compatibility renderer) and screenshot it. If the change is visual
(textures, crowd, UI), actually look at the PNG before calling it done.

## Step 4 — Doc sync (every PR)

Check each and update in THIS commit, not a follow-up:

- [ ] The system's spec doc (`docs/SHOT_MODEL.md`, `CONTEST_MODEL.md`,
      `DATA_ENGINE.md`, `ASSET_INDEX.md`, …) still describes the code.
- [ ] `docs/DECISIONS.md` gains an entry if you locked a new design choice.
- [ ] `README.md` sprint table and file-role tables still true (the audit
      flagged a stale sprint table once already — §4.3).
- [ ] Test counts quoted in docs still match reality if you added tests.

## Step 5 — Commit

Conventional commit with scope, imperative, intent-first. Scopes in use:
`sim`, `scene`, `scripts`, `ci`, `assets`, `docs`, `tooling`, `data`, and
combos like `sim+scene`. Examples from history:

```
feat(sim+scene): Sprint 5 defender contest model + live shot wiring
fix(scripts): pull before push so SAVE-WORK can't be rejected for being behind
chore: track binary assets with Git LFS (additive)
```

One logical change per PR. Never commit `.godot/`, `.godot-bin/`, or any
per-machine state. New binaries must match a `.gitattributes` LFS pattern
(verify with `git check-attr filter <path>` → `lfs`).

## Step 6 — Push + PR

```bash
git push -u origin <branch>    # retry 2s/4s/8s/16s only on network errors
```

Then open a PR (ready, not draft) unless one is already open for the branch.
PR body uses the house four-liner, honestly filled:

```
**Changed:** what and where, one or two lines.
**Testing:** exactly what ran and passed (pytest count, Godot self-test,
  screenshot verified) — and what was NOT verified (e.g. live nba_api needs a
  residential IP) stated plainly.
**Risk:** what could break and why it probably won't.
**Rollback:** how to undo (usually "revert the merge; no data migration").
```

Subscribe to PR activity after creating it, and watch CI: the Python matrix
(3.10/3.11/3.12) AND the Godot self-test job must both go green. A CI failure
is yours to fix on the same branch — re-run the gauntlet after each fix.

## Step 7 — Report

Tell the owner: what shipped, PR link, what was verified, anything left that
needs the laptop (residential-IP data pulls, in-editor visual checks). The
owner's next action should always be obvious and never require typing
commands — if it does, you've left the job unfinished.
