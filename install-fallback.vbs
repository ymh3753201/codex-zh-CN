Option Explicit
Dim shell, fs, root, host, command, result
Set shell = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
root = fs.GetParentFolderName(WScript.ScriptFullName)
host = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
command = Chr(34) & host & Chr(34) & " -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & root & "\scripts\bootstrap.ps1" & Chr(34) & " -AutoClose"
On Error Resume Next
result = shell.Run(command, 1, True)
If Err.Number <> 0 Then
    MsgBox "Unable to start Windows PowerShell: " & Err.Description, 16, "Codex installer"
ElseIf result <> 0 Then
    MsgBox "Installation failed. Please send the startup log from the package diagnostics folder or %TEMP%\codex-zh-diagnostics.", 16, "Codex installer"
End If
