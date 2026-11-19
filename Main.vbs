Option Explicit
' Silent entry point: double-click this file for a completely console-free start.
' The second-stage launcher uses ProcessStartInfo.CreateNoWindow.
Dim sh, fso, folder, psExe, script, command, logFile, errorNumber, errorDescription
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
psExe = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
script = folder & "\Launcher.ps1"
command = Chr(34) & psExe & Chr(34) & " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File " & Chr(34) & script & Chr(34)

On Error Resume Next
sh.Run command, 0, False
If Err.Number <> 0 Then
    errorNumber = Err.Number
    errorDescription = Err.Description
    Err.Clear
    Set logFile = fso.OpenTextFile(folder & "\WaterAlarm-launch-error.log", 8, True)
    If Not logFile Is Nothing Then
        logFile.WriteLine Now & "  WSH launcher error " & errorNumber & ": " & errorDescription
        logFile.Close
    End If
End If
On Error GoTo 0
