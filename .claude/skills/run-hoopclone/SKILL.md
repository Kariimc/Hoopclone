---
name: run-hoopclone
description: Build, launch, drive, screenshot, and smoke-test the HoopClone Godot 4.3 basketball game headlessly on Linux. Use when asked to run, start, launch, play, screenshot, or verify the HoopClone game/scene renders.
---

# Run HoopClone

HoopClone is a **Godot 4.3** (Forward+) 3D basketball scene: broadcast camera,
a roster-driven player in a team kit, an on-ball defender, a ball + hoop, and an
animated crowd bowl. The main scene is `res://game/main.tscn`.

There is no window to click on a headless box, so the agent path is a GDScript
driver — **`tools/godot/screenshot.gd`** — that boots the real game scene, can
**hold input actions** (move / shoot) to actually play it, renders some frames,
and writes a PNG. It runs under `xvfb` with Godot's OpenGL-compatibility
rasterizer (the container has no Vulkan driver, so the project's native Forward+
path can't render here).

> The driver is at `tools/godot/screenshot.gd`, **not** in this skill dir:
> Godot's resource system ignores dotfile directories, so a script under
> `.claude/` cannot be loaded as `res://`.

All paths below are relative to the repo root (the unit). All commands were run
from there in a headless Linux container.

## Prerequisites

```bash
# Display + software OpenGL rasterizer (already present in this container).
sudo apt-get update && sudo apt-get install -y xvfb libgl1-mesa-dri

# Godot 4.3-stable headless Linux binary (same version CI pins), into the
# already-gitignored .godot-bin/ (matches PLAY.bat's convention).
mkdir -p .godot-bin
curl -fsSL -o .godot-bin/godot.zip \
  https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip -o -q .godot-bin/godot.zip -d .godot-bin
chmod +x .godot-bin/Godot_v4.3-stable_linux.x86_64
```

## Build (import — REQUIRED before loading any scene)

The project ships without Godot's `.godot/` cache, so on a fresh checkout the
global `class_name` registry is empty and textures aren't imported. Loading
`main.tscn` then fails with `Could not find type "AnimStateMachine"` and
`... make sure resources have been imported`. Run the import pass once:

```bash
./.godot-bin/Godot_v4.3-stable_linux.x86_64 --headless --path . --import
```

(Prints `ObjectDB instances leaked at exit` / `resources still in use` — benign,
exit code is still 0. Creates `.godot/`, which is gitignored.)

## Run (agent path) — boot, drive, screenshot

Needs a display (`xvfb`) **and** the OpenGL-compat rasterizer. Do **not** pass
`--headless` here — the dummy rasterizer renders nothing and the PNG comes back
empty.

```bash
HOOP_SHOT_OUT="$PWD/hoopclone_shot.png" \
xvfb-run -a -s "-screen 0 1280x720x24" \
  ./.godot-bin/Godot_v4.3-stable_linux.x86_64 --path . \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --script res://tools/godot/screenshot.gd
```

On success it prints `DRIVER: SHOT SAVED -> .../hoopclone_shot.png (1152x648)`.
**Open the PNG and look at it** — you should see the hardwood court with painted
lines, the player in the crimson kit, the blue defender capsule, the orange
ball, and the crowd bowl.

Driver tunables (env vars):

| Env | Default | Meaning |
|-----|---------|---------|
| `HOOP_SHOT_OUT` | `<project>/hoopclone_shot.png` | absolute output PNG path |
| `HOOP_WARMUP` | `120` | frames rendered before capture |
| `HOOP_HOLD` | _(none)_ | comma-separated actions held during warmup to play the game: `move_left`, `move_right`, `move_up`, `move_down`, `shoot` |

Drive the player toward the hoop and shoot, then capture:

```bash
HOOP_SHOT_OUT="$PWD/play.png" HOOP_WARMUP=150 HOOP_HOLD="move_right,shoot" \
xvfb-run -a -s "-screen 0 1280x720x24" \
  ./.godot-bin/Godot_v4.3-stable_linux.x86_64 --path . \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --script res://tools/godot/screenshot.gd
```

The broadcast camera follows the player, so the framed scene visibly changes.

## Smoke / logic tests (no display needed)

```bash
# Engine-side sim self-test (the real GDScript ContestModel + ShotModel).
./.godot-bin/Godot_v4.3-stable_linux.x86_64 --headless --path . \
  --script res://tests/godot/run_tests.gd        # exit 0 = all passed

# Python data + sim spec-lock suite.
python -m pytest tools -v
```

## Run (human path)

On a desktop with a GPU + display: open the folder in the Godot 4.3 editor, or
`godot --path .` to run `main.tscn` (controls: WASD/arrows to move, hold SPACE to
charge a shot and release near the top of the meter). On Windows, double-click
`PLAY.bat` (auto-downloads Godot). Useless headless — use the driver above.

## Gotchas

- **Import is not optional.** The headless self-test passes *without* importing
  (it only `preload`s pure-logic scripts), so green CI does **not** mean a scene
  will load. Always run the import step before the screenshot driver.
- **Forward+ can't render in this container.** There's no software Vulkan ICD
  (lavapipe) installed, so the project's default Forward+ method fails. Forcing
  `--rendering-method gl_compatibility --rendering-driver opengl3` falls back to
  software OpenGL (Mesa llvmpipe) and works. (Alternatively
  `apt-get install mesa-vulkan-drivers` to get the native path — not needed for
  a screenshot.)
- **`--headless` + screenshot = blank PNG.** Headless uses the dummy rasterizer.
  For pixels you need `xvfb` + the gl_compatibility flags above, no `--headless`.
- **Audio errors are noise.** `libpulse.so.0: cannot open`, ALSA `cannot find
  card '0'` → Godot falls back to the dummy audio driver. Ignore.
- The driver `await`s `RenderingServer.frame_post_draw` after warmup so the
  readback isn't a half-drawn frame — keep that if you edit it.
- The game runs fine with missing optional art (it falls back to placeholders);
  it will **not** run if the project hasn't been imported.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Could not find type "AnimStateMachine"` / `Identifier "Attributes" not declared` | Run the import step — global class cache is empty. |
| `... referenced non-existent resource` / `make sure resources have been imported` | Same — run `--headless --import`. |
| `DRIVER: framebuffer readback was empty` or a blank PNG | You passed `--headless`; rerun under `xvfb-run` with the gl_compatibility flags. |
| `Your video card drivers seem not to support the required Vulkan version` | Use the gl_compatibility flags (no Vulkan in this container). |
| `DRIVER: failed to load res://game/main.tscn` | Import hasn't run, or you're not in the repo root (`--path .`). |
| `curl: (22) ... error: 502` on the Godot download | Transient proxy/GitHub hiccup — retry the `curl` (e.g. `curl --retry 5`). The release URL is stable. |
