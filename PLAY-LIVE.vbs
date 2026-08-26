' PLAY LIVE - double click this.
'
' The game opens and stays open while your agents work on it. When a change lands it
' reloads once, quietly, and hands your keyboard straight back to whatever you were
' using. If the game crashes it comes back on its own.
'
' HIS RULE, 2026-08-25, in his own words:
'   "I just want to be able to be controlling the game in one window that updates live
'    while my agents are building the game without the screen always stuttering or
'    blinking and not a bunch of cmd line screens opening up while I'm testing the game."
'
' That is why this is a .vbs and not a .bat. A .bat opens a black command window and
' keeps it on screen for the whole session. This opens NOTHING except the game.
'
' To stop it: double click STOP-LIVE.vbs in this same folder.
' To see what it has been doing: open .watch.log in this folder.

Dim shell, fso, here, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)

' -WindowStyle Hidden covers PowerShell's own window; the 0 in Run covers the console
' host that would otherwise flash up for a moment before it applies. Both are needed:
' with only one of them a black rectangle blinks on screen at every start.
cmd = "powershell -NoProfile -WindowStyle Hidden -File """ & here & "\tools\dev\watch.ps1"""
shell.Run cmd, 0, False
