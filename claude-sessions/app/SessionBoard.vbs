' Starts the Claude Sessions card with no console window.
' Windows 11 sends console programs to Windows Terminal, which ignores
' "-WindowStyle Hidden" and leaves a PowerShell tab open (closing it would
' close the card). conhost.exe --headless runs PowerShell with no window at
' all, and this script itself is started by wscript.exe, which has none either.
Dim fso, here, ps1, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(here, "SessionBoard.ps1")
cmd = "conhost.exe --headless powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """"
CreateObject("WScript.Shell").Run cmd, 0, False
