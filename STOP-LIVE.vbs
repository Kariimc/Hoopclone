' STOP LIVE - double click this to stop the live game session.
'
' PLAY-LIVE.vbs runs with no window of its own, so there is nothing to close. This
' leaves a note it checks for every two seconds. It closes the game and stands down.
'
' Nothing is deleted and nothing is saved over. Double click PLAY-LIVE.vbs to start again.

Dim fso, here, f
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
Set f = fso.CreateTextFile(here & "\.stop-watching", True)
f.WriteLine "stop"
f.Close
