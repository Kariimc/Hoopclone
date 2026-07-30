"""Pause the dev watcher while a tool rewrites something the game is using.

    from tools.dev.hold import reload_hold          # or add tools/dev to sys.path
    with reload_hold("rebuilding the player's moveset"):
        ...forty seconds of writing a .glb...

The watcher (tools/dev/watch.ps1) keeps a playable window open and reloads it
when files settle. Without this, a long rebuild takes the window away from
whoever is playing, mid-play, with nothing on screen to say why - and can hand
them a game booted onto a half-written asset.

The reason string is shown in the game's own corner panel, so the person holding
the controller sees "Working: rebuilding the player's moveset" instead of losing
the window.

Safe by construction: the file carries a timestamp and the watcher ignores a hold
older than fifteen minutes, so a tool that dies mid-run cannot freeze reloads
forever. It also never removes a hold it did not place.
"""
import os, time
from contextlib import contextmanager

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HOLD = os.path.join(ROOT, ".reload-hold")


@contextmanager
def reload_hold(reason):
    """Hold the watcher for the duration of the block."""
    mine = False
    if not os.path.exists(HOLD):
        try:
            with open(HOLD, "w", encoding="utf-8") as f:
                f.write("%s\n" % reason)
            mine = True
        except OSError:
            pass          # no watcher, no project write access - never fatal
    try:
        yield
    finally:
        if mine:
            try:
                os.remove(HOLD)
            except OSError:
                pass
        # Give the watcher a moment to notice the hold has lifted before the
        # process exits and the next tool starts writing.
        time.sleep(0.2)
