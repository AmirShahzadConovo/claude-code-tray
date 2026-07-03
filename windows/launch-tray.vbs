' Launches the Claude tray widget with no visible console window.
' Portable: resolves ClaudeTray.ps1 relative to this script's own folder.
Dim fso, dir
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("Wscript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\ClaudeTray.ps1""", 0, False
