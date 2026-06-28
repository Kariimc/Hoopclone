#!/bin/bash
# HoopClone session-start hook (Claude Code on the web).
# Makes the spec-lock test suite runnable with zero manual setup: the tests in
# tools/sim and tools/data are the source of truth for the sim math, and they're
# stdlib + pytest only, so all a fresh remote session needs is pytest installed.
set -euo pipefail

# Local machines have their own Python env — only bootstrap remote/web sessions.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Idempotent: a no-op if pytest is already present (cached container state).
python -m pip install --quiet "pytest>=8.0"

echo "session-start: pytest ready -> run 'python -m pytest tools'"
