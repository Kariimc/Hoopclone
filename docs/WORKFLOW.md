# Working across machines (cloud + laptop) — the one rule

You work on this project from more than one place: the cloud and your laptop.
To never again open the wrong copy or hit a missing file, there is **one rule**:

> **The GitHub repo is the only source of truth. Every machine has exactly ONE
> copy, and that copy syncs to GitHub.**

Everything the project needs — code *and* art (the player mesh, court, jerseys,
crowd) — now lives **inside** the repo. There are no more hand-placed files.
So a fresh, up-to-date copy is always a complete, working project.

## The actions you ever take

In the top folder of the project there are scripts. You double-click them — no typing.

| When | Double-click | What it does |
|------|--------------|--------------|
| **Before** you start working | `GET-LATEST.bat` | Pulls the newest version from GitHub so you're not on a stale copy. |
| **To test the game** | `PLAY.bat` | Pulls the latest, then launches the game in Godot so you can play the current build. |
| **After** you finish working | `SAVE-WORK.bat` | Uploads everything you changed to GitHub so the other machine can get it. |

That's the whole workflow: **Get-Latest → work → Save-Work**, and **Play** any
time you want to see the latest build. Do that on every machine and the cloud
and the laptop stay identical.

### PLAY needs no setup

Just double-click `PLAY.bat`. It finds Godot if it's installed, and if it isn't,
it **downloads Godot itself** the first time (into a per-machine `.godot-bin`
folder that isn't synced) — nothing for you to install. **Controls:** move with
WASD / arrows, hold **Space** to shoot.

## One-time cleanup (the cause of the trouble)

The earlier problems came from having **several copies** of the project on the
same computer, each missing different files. Keep **one** copy per machine:

- **Laptop:** the canonical copy is `C:\Dev\hoopclone`. Delete the others
  (`C:\Dev\hoopclone_repo\...`, `C:\Users\karii\Desktop\Work\Dev\hoopclone`, any
  `Temp\claude\...` copy). Always open Godot on `C:\Dev\hoopclone\project.godot`.
- **Cloud:** it gets its own fresh copy automatically each session.

If you're ever unsure which copy you're in: in Godot, **Project → Open Project
Data Folder** shows the path on disk.

## Why this fixes it for good

- Art assets are **committed** (not gitignored), so every copy is complete.
- `GET-LATEST` guarantees you start from the newest version.
- `SAVE-WORK` guarantees your changes leave the machine you made them on.
- One copy per machine means there's no "wrong copy" to accidentally open.
