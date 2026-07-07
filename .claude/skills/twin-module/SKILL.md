---
name: twin-module
description: Add or change HoopClone sim math the house way — canonical Python module in tools/sim, GDScript mirror in game/core, parity + spec-lock tests, doc. Use whenever creating or editing shot/contest/possession/any gameplay-math module, or when a parity test fails.
---

# Twin-module workflow (Python canonical ↔ GDScript mirror)

All gameplay math in HoopClone exists twice on purpose: a canonical Python
module (`tools/sim/<name>.py`) where iteration is fast and pytest is the spec,
and a GDScript mirror (`game/core/<name>.gd`) the game actually runs.
`tools/sim/tests/test_gdscript_parity.py` fails CI if constants drift;
`tests/godot/run_tests.gd` proves the GDScript runs and behaves in the pinned
engine (4.3). This skill is the checklist that keeps the twins identical.

**Never edit one twin without the other open.** That is the whole failure mode
this pattern exists to prevent.

## Step 1 — Design the curve the house way

Study `tools/sim/contest_model.py` first; it is the template. House curve
style:

- The output is **one bounded scalar** (usually 0–1), a **product of
  independent, individually-monotonic, bounded factors**.
- Every tunable is a module-level `UPPER_SNAKE` constant with a `# comment`
  saying what it means in game terms. No magic numbers inside functions.
- Floors instead of zeros where a factor should never fully cancel
  (e.g. `DEF_SKILL_FLOOR = 0.60` — a body in your face contests at rating 0).
- Geometry is XZ floor-plane `(x, z)` tuples; Godot passes `Vector2(pos.x, pos.z)`.
- Attributes are 0–99; clamp inputs, clamp outputs.
- Module docstring states: what it models, who consumes it, the "Design
  intent" of each factor, and that the mirror must stay in lockstep.
- **New randomness takes a seeded RNG parameter** (replay determinism is a
  Sprint 6 requirement).
- Stdlib only. No scene/engine concepts leak into the Python module.

## Step 2 — Write the Python module + spec-lock tests FIRST

Create `tools/sim/<name>.py` and `tools/sim/tests/test_<name>.py`. Minimum
test set (see `test_contest_model.py` for tone):

1. Output range: always within the documented bounds for extreme inputs.
2. Monotonicity of **each factor separately** (closer defender → more contest).
3. Boundary/gate values exact (e.g. contest == 0.0 at CONTEST_RADIUS).
4. Composition sanity (end-to-end: contested p < open p).
5. Degenerate geometry doesn't crash (defender on top of shooter → EPS guard).

Iterate here until the numbers feel right: `python -m pytest tools/sim -q`.
Print a small sample table (like SHOT_MODEL.md's "0.64 at the rim, 0.49 at
5 m") and sanity-check it against basketball intuition before mirroring.

## Step 3 — Mirror to GDScript

Create/edit `game/core/<name>.gd`:

- `class_name` PascalCase, all functions `static func` (mirrors must be
  callable without instancing and **must have zero scene-tree dependencies** —
  no `get_node`, no signals, no autoload reads; this keeps Sprint 6/7 cheap).
- Constants as `const NAME := <value>` — **this exact form**, one per line,
  same names, same values. The parity test regex-parses
  `const NAME := value` / `const NAME : float = value`; anything fancier
  (expressions, preload) is invisible to it and silently unlocked.
- Port function bodies line-for-line where GDScript allows; keep comments.

## Step 4 — Lock the parity

In `tools/sim/tests/test_gdscript_parity.py`, add a test naming the mirror
file and the **explicit set of expected constant names** (the set guards
against a rename making the test vacuous):

```python
def test_<name>_constants_match():
    _assert_parity(
        "game/core/<name>.gd",
        <name>_module,
        {"CONST_A", "CONST_B", ...},   # every tunable, no exceptions
    )
```

The formula *bodies* are hand-synced (documented limitation). When a module's
formulas grow beyond trivial, add **golden values**: a committed JSON of
`(inputs → expected output to 6 decimals)` asserted by BOTH pytest and
`run_tests.gd` (audit §4.4). Do this for the possession engine.

## Step 5 — Add engine-side behavior checks

Append checks to `tests/godot/run_tests.gd` in its `_check(label, cond)`
style: 4–7 assertions re-proving the key monotonicity/boundary facts and one
end-to-end composition with the other models. Exit code discipline is already
handled by the harness.

## Step 6 — Document + verify

1. Write/update `docs/<NAME>_MODEL.md`: the formula in one code block, one
   bullet per factor with its constants in prose, sample values, and the
   "one curve, two consumers … change one, change both" preamble.
2. Update `docs/DATA_ENGINE.md` test counts if it lists them, and
   `docs/DECISIONS.md` if a design choice was made (e.g. "strongest defender
   wins, no stacking").
3. Verify everything:

```bash
python -m pytest tools -q          # spec locks + parity
./.godot-bin/Godot_v4.3-stable_linux.x86_64 --headless --path . --script res://tests/godot/run_tests.gd
```

(Fetch the Godot binary per the `run-hoopclone` skill if `.godot-bin/` is
empty; run `--import` once on a fresh clone first. `ObjectDB instances leaked`
noise is benign — trust the exit code.)

## Changing an EXISTING twin

Same discipline, compressed: open both files; make the change in Python; run
pytest (parity now fails); apply the identical change to the `.gd`; rerun
pytest AND the Godot self-test; update the doc's constants/sample values.
If the change alters an output another system consumes (shot % ranges, signal
timing), check CLAUDE.md's escalation rules before shipping.
