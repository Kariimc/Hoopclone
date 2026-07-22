# HoopClone — Complete Handoff (2026-06-27)

## Where the project lives now
- Folder on this computer: C:\Users\Kariim\Dev\hoopclone
- This is OUTSIDE OneDrive (OneDrive is the online-backup folder that was making
  duplicate copies and breaking things). The path has no "OneDrive" in it.
- Online backup (GitHub): https://github.com/Kariimc/Hoopclone.git
- Branch in use: main

## Current state (all verified just now)
- Computer copy and online copy MATCH exactly — same latest version (384fd25),
  nothing waiting to upload, nothing missing.
- The project folder is CLEAN — no half-saved or leftover files.
- Full history intact — all 29 saved points (commits) came through the move.
- Health check on the project's files passed — no damage.

## What was wrong, and what got fixed
1. A finished piece of work (the animated crowd/arena) was saved on the computer
   but never uploaded to GitHub. -> Uploaded (commit cf1ca47).
2. The crowd background image was missing from the project, so it would show up
   blank for anyone who downloaded a fresh copy. Cause: the project was set to
   ignore all of Godot's small "sidecar" files (the helper file Godot pairs with
   each image), which also hid the missing image. -> Added the image and its
   sidecar (commit ff26d24).
3. Fixed the root cause so this can't happen again: the ignore rule now only
   applies inside the assets\ folder. Also added two more sidecars that were
   missing (icon and referee_ref). -> commit 384fd25.
4. Moved the whole project out of OneDrive to C:\Users\Kariim\Dev\hoopclone, history and all.

## Cleanup done / notes
- The old, empty leftover folder in OneDrive
  (C:\Users\Kariim\OneDrive\Desktop\Work\Dev\hoopclone_repo) has been DELETED.
  Nothing important was in it.
- When you moved the folder, OneDrive may have asked about deleting the old cloud
  copy. That copy is redundant now — the real project is safe at C:\Users\Kariim\Dev\hoopclone
  regardless of what you chose.

## Going forward
- Any new image or model you add under the game\ folder (or the project's main
  folder) will now keep its Godot sidecar automatically. No manual steps.
- The big files inside assets\ are still kept out of the online backup on purpose
  (you place those by hand — see docs\ASSET_INDEX.md).

## Recent saved points (newest first)
- 384fd25  build: track import sidecars for committed assets, not just assets/
- ff26d24  arena: add dense crowd panorama texture + import sidecar
- cf1ca47  arena: animated crowd bowl + dense texture, underfloor, lighting
- 3b7bde9  arena: three-sided crowd stands, side walls tuned
