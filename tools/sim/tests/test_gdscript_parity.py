"""Cross-language parity lock: the GDScript runtime mirrors (game/core/*.gd) must
carry the SAME numeric constants as their canonical Python modules.

We can't run Godot in CI, so the formula bodies are still kept in lockstep by
hand — but constant drift is the most common and most silent way the mirror
rots (someone tweaks a weight in one file and forgets the other). This test
parses the `const NAME := value` lines out of the .gd files and asserts each one
matches the same-named attribute in the Python module, so that class of drift
fails CI.

Run from tools/sim:  python -m pytest -q
"""

import os
import re
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import contest_model  # noqa: E402
import shot_model  # noqa: E402

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

# `const NAME := 3.5`  or  `const NAME : float = 3.5`  -> {NAME: 3.5}
_CONST_RE = re.compile(
    r"^\s*const\s+([A-Z_][A-Z0-9_]*)\s*(?::\s*\w+\s*)?:?=\s*([-+0-9.eE]+)\s*(?:#.*)?$",
    re.MULTILINE,
)


def _gd_constants(rel_path: str) -> dict:
    with open(os.path.join(REPO_ROOT, rel_path), encoding="utf-8") as fh:
        text = fh.read()
    out = {}
    for name, raw in _CONST_RE.findall(text):
        out[name] = float(raw)
    return out


def _assert_parity(gd_rel_path: str, py_module, expected_names: set):
    gd = _gd_constants(gd_rel_path)
    # The mirror must actually define the constants we expect (guards against a
    # rename silently making this test vacuous).
    missing = expected_names - gd.keys()
    assert not missing, f"{gd_rel_path} missing constants: {sorted(missing)}"
    for name in expected_names:
        py_val = getattr(py_module, name)
        assert gd[name] == float(py_val), (
            f"{name} drift: {gd_rel_path}={gd[name]} vs Python={py_val}"
        )


def test_contest_model_constants_match():
    _assert_parity(
        "game/core/contest_model.gd",
        contest_model,
        {"CONTEST_RADIUS", "LANE_FLOOR", "DEF_SKILL_FLOOR", "DEF_SKILL_RANGE", "EPS"},
    )


def test_shot_model_constants_match():
    _assert_parity(
        "game/core/shot_model.gd",
        shot_model,
        {
            "SKILL_FLOOR", "SKILL_RANGE", "DIST_FALLOFF", "DIST_FACTOR_FLOOR",
            "CONTEST_WEIGHT", "TIMING_WEIGHT", "P_MIN", "P_MAX",
            "GREEN_FLOOR", "GREEN_RANGE",
        },
    )
