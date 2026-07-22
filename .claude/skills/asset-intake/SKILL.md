---
name: asset-intake
description: Commit art/binary assets into HoopClone correctly — LFS tracking, .import sidecars, candidates-list wiring, manifest entries, and the boot-with-and-without verification. Use when adding, replacing, moving, or wiring any texture, mesh, or other binary asset, or when the game boots without expected art.
---

# Asset intake — getting art into the game without breaking anything

Assets have caused more repair commits in this repo's history than any other
change type: missing-file boot failures, a texture committed twice, a 9 MB
`*.png.jpeg`, LFS migration. This skill is the path that avoids all of them.

## The three invariants (why each rule below exists)

1. **The repo is the only source of truth.** A cloud session cannot see chat
   uploads, Higgsfield's CDN, or the laptop's Downloads folder. Art exists for
   the game only once it is committed. (The owner's no-typing path for this is
   `ADD-ASSETS.bat`; you are the typing path.)
2. **Asset-optional boot.** `main.tscn` must open and CI must pass with zero
   optional binaries present. Every asset is hydrated at runtime behind an
   existence check with a coded fallback — never `preload()` on an optional
   binary, never a scene-file reference to one.
3. **Binaries ride LFS.** `.gitattributes` routes `png/jpg/jpeg/webp/glb/wav/
   ogg/ttf…` through Git LFS. A binary that bypasses LFS bloats every clone
   forever.

## Step 1 — Name and place it

- Target paths and naming live in `docs/ASSET_INDEX.md` — check it first; the
  asset may already have a reserved path (e.g. `res://assets/textures/
  court_floor.png`, `res://assets/models/player_base.glb`).
- Textures → `assets/textures/`, meshes → `assets/models/`, environment →
  `assets/env/`. Lowercase snake_case, **one real extension** (no
  `foo.png.jpeg` — rename to the actual format).
- Never commit the same file at two paths. If game code wants it elsewhere,
  point the code at the one copy.

## Step 2 — Verify LFS will take it

```bash
git check-attr filter assets/textures/<file>   # must print: filter: lfs
```

If it prints `unspecified`, add the pattern to `.gitattributes` (same style as
existing lines) BEFORE `git add`-ing the binary. After committing, confirm the
blob is a pointer: `git show HEAD:assets/textures/<file> | head -1` should
start with `version https://git-lfs...`.

## Step 3 — Generate and commit the `.import` sidecar

Godot needs the `.import` sidecar so every machine imports identically:

```bash
./.godot-bin/Godot_v4.3-stable_linux.x86_64 --headless --path . --import
```

(Fetch the binary per the `ship` skill if missing.) Commit the new
`<file>.import` **next to the asset**. Do NOT commit anything under `.godot/`.

## Step 4 — Wire it asset-optionally

Follow `game/main.gd`'s existing pattern:

- Add the path to a `*_CANDIDATES` array (list every plausible extension —
  `.png`, `.jpg`, `.jpeg`, `.webp` — the owner's exports vary) and resolve via
  `_first_existing(candidates)`.
- On miss: keep the current fallback (plain color, capsule mesh) and continue
  silently or with a `push_warning` — never crash, never blank-screen.
- Team-kit style swaps (jerseys, logos) go through `assets/team_manifest.json`
  / `manifest.json` as **texture swaps on a fixed mesh** — regenerating meshes
  per team is a locked-out approach (DECISIONS.md).

## Step 5 — Verify BOTH boot states

This is the step that prevents the historical breakage. Using the
`run-hoopclone` skill (xvfb + compatibility renderer):

1. **With the asset:** boot `main.tscn`, screenshot, and LOOK at the PNG —
   confirm the art actually shows (right surface, not stretched, not magenta).
2. **Without it:** temporarily move the asset out (`mv assets/textures/<file>
   /tmp/`), re-run `--import`, boot again — the scene must still come up on
   fallbacks with exit code 0. Move the file back and re-run `--import`.
3. Run the full self-test: `--script res://tests/godot/run_tests.gd`.

## Step 6 — Document + ship

- Add/update the asset's row in `docs/ASSET_INDEX.md` (what it is, target
  path, notes).
- If the asset is a reference (not imported into the engine), it goes in the
  index's reference table, not into `assets/`.
- Commit as `assets: <what> + <what it's wired to>` and run the `ship` skill's
  gauntlet (CI's Godot job will re-import from scratch — that's your fresh-
  clone proof).

## Replacing or removing an asset

- Replace: same path, same name — the candidates wiring means zero code
  change. Re-run Step 3 and Step 5.
- Remove: also delete its `.import` sidecar, remove it from candidates lists
  and `docs/ASSET_INDEX.md`, then run Step 5's "without it" boot to prove
  nothing hard-depended on it. Ask before deleting anything you didn't add —
  assets are expensive to regenerate.
