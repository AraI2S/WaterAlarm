# WaterAlarm v1.0.0 - Stage 2: spawn Windows PowerShell 5.1 without a console.
# MIT licensed. Source only: no EXE packaging.
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$logPath = Join-Path $base 'WaterAlarm-launch-error.log'

try {
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $worker = Join-Path $base 'WaterAlarm.ps1'
    if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) {
        throw "Worker script missing: $worker"
    }

    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $exe
    $start.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File "' + $worker + '"'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $start.WorkingDirectory = $base
    $process = [System.Diagnostics.Process]::Start($start)
    if ($null -eq $process) { throw 'Process.Start returned null.' }
    $process.Dispose()
}
catch {
    try {
        $line = ('{0}  Launcher: {1}{2}' -f (Get-Date -Format o), $_.Exception.ToString(), [Environment]::NewLine)
        [System.IO.File]::AppendAllText($logPath, $line, [System.Text.Encoding]::UTF8)
    } catch { }
}
