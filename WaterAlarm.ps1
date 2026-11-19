# WaterAlarm v1.0.0 - Windows PowerShell 5.1, source-only portable application.
# MIT License. All WinForms controls are created on a DPI-aware STA thread.
param([switch]$CheckOnly)
# This script is intended to be launched by Main.vbs / Launcher.ps1.
$ErrorActionPreference = 'Stop'
$script:HomeDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:LogPath = Join-Path $script:HomeDir 'WaterAlarm.log'
$script:ConfigPath = Join-Path $script:HomeDir 'Config.json'
$script:Mutex = $null
$script:OwnsMutex = $false
$script:StopSignal = $null
$script:Context = $null
$script:Tray = $null
$script:ClockTimer = $null
$script:StopTimer = $null
$script:CloseTimer = $null
$script:Popup = $null
$script:BigFont = $null
$script:SmallFont = $null
$script:Paused = $false
$script:Fired = New-Object 'System.Collections.Generic.HashSet[string]'

function Write-Log([string]$Level, [string]$Message) {
    try {
        $line = ('{0} [{1}] {2}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message, [Environment]::NewLine)
        [System.IO.File]::AppendAllText($script:LogPath, $line, [System.Text.Encoding]::UTF8)
    } catch { }
}

function Read-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)) {
        throw 'Config.json does not exist. Restore it from the distribution.'
    }
    $json = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8
    $c = $json | ConvertFrom-Json -ErrorAction Stop
    if ([int]$c.schemaVersion -ne 1) { throw 'Unsupported Config.json schemaVersion (expected 1).' }

    $times = @($c.times)
    if ($times.Count -lt 1 -or $times.Count -gt 48) { throw 'times must contain 1 to 48 entries.' }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($t in $times) {
        if ($t -isnot [string] -or $t -cnotmatch '^([01][0-9]|2[0-3]):[0-5][0-9]$') {
            throw "Invalid time '$t'. Use 24-hour HH:mm."
        }
        if (-not $seen.Add($t)) { throw "Duplicate reminder time: $t" }
    }
    if ([string]::IsNullOrWhiteSpace([string]$c.message) -or ([string]$c.message).Length -gt 80) {
        throw 'message must contain 1 to 80 characters.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$c.hint) -or ([string]$c.hint).Length -gt 80) {
        throw 'hint must contain 1 to 80 characters.'
    }
    if ([int]$c.durationSeconds -lt 1 -or [int]$c.durationSeconds -gt 120) {
        throw 'durationSeconds must be 1 to 120.'
    }
    if ([int]$c.pollSeconds -lt 1 -or [int]$c.pollSeconds -gt 30) {
        throw 'pollSeconds must be 1 to 30.'
    }
    if ($null -eq $c.appearance) { throw 'Missing appearance.' }
    if ([int]$c.appearance.width -lt 160 -or [int]$c.appearance.width -gt 1000 -or
        [int]$c.appearance.height -lt 60 -or [int]$c.appearance.height -gt 400) {
        throw 'appearance width/height are outside the allowed range.'
    }
    foreach ($property in @('background', 'foreground', 'hintColor')) {
        $color = [string]$c.appearance.$property
        if ($color -cnotmatch '^[0-9A-Fa-f]{6}$') {
            throw "appearance.$property must be exactly six hexadecimal digits."
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$c.appearance.font)) { throw 'Font name cannot be empty.' }
    if ([double]$c.appearance.mainFontPt -lt 8 -or [double]$c.appearance.mainFontPt -gt 50 -or
        [double]$c.appearance.hintFontPt -lt 6 -or [double]$c.appearance.hintFontPt -gt 20) {
        throw 'Font sizes are outside the allowed range.'
    }
    return $c
}

function Get-InstanceLock {
    # Local\ scopes the primitives to the interactive Windows session.
    $mutexName = 'Local\WaterAlarm.PS51.v1.Mutex'
    $eventName = 'Local\WaterAlarm.PS51.v1.Stop'
    $script:Mutex = [System.Threading.Mutex]::new($false, $mutexName)
    try {
        $script:OwnsMutex = $script:Mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $script:OwnsMutex = $true
    }
    if (-not $script:OwnsMutex) {
        # Equivalent intent to AHK #SingleInstance Force: ask the old worker to exit.
        for ($i = 0; $i -lt 12; $i++) {
            try {
                $existingSignal = [System.Threading.EventWaitHandle]::OpenExisting($eventName)
                try { [void]$existingSignal.Set() } finally { $existingSignal.Dispose() }
                break
            } catch [System.Threading.WaitHandleCannotBeOpenedException] {
                Start-Sleep -Milliseconds 100
            }
        }
        try {
            $script:OwnsMutex = $script:Mutex.WaitOne(8000)
        } catch [System.Threading.AbandonedMutexException] {
            $script:OwnsMutex = $true
        }
        if (-not $script:OwnsMutex) {
            Write-Log 'ERROR' 'Another instance refused to stop within 8 seconds; new instance exited.'
            return $false
        }
    }
    $script:StopSignal = [System.Threading.EventWaitHandle]::new(
        $false, [System.Threading.EventResetMode]::AutoReset, $eventName
    )
    return $true
}

function Set-DpiAwareness {
    # Deliberately compile Win32 interop before loading System.Windows.Forms.
    $native = @'
using System;
using System.Runtime.InteropServices;
public static class WaterAlarmNative {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetDpiForWindow(IntPtr hwnd);
}
'@
    Add-Type -TypeDefinition $native -ErrorAction Stop
    # -4 = DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 (Windows 10 1703+).
    $wanted = [IntPtr]::new(-4)
    $processOK = [WaterAlarmNative]::SetProcessDpiAwarenessContext($wanted)
    if (-not $processOK) {
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        # The powershell.exe manifest may already have set the process default.
        Write-Log 'INFO' "Process DPI setting returned Win32 $errorCode; applying thread override."
    }
    $previous = [WaterAlarmNative]::SetThreadDpiAwarenessContext($wanted)
    if ($previous -eq [IntPtr]::Zero) {
        throw ('Could not enable Per-Monitor V2 DPI. Win32 error: ' +
               [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    Write-Log 'INFO' 'Per-Monitor V2 DPI context established before WinForms initialization.'
}

function Add-NonActivatingFormType {
    $source = @'
using System;
using System.Windows.Forms;
namespace WaterAlarm {
    public sealed class NoActivateForm : Form {
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams {
            get {
                CreateParams p = base.CreateParams;
                p.ExStyle |= 0x08000080; // WS_EX_NOACTIVATE + WS_EX_TOOLWINDOW
                return p;
            }
        }
        protected override void WndProc(ref Message m) {
            if (m.Msg == 0x0021) { // WM_MOUSEACTIVATE
                m.Result = new IntPtr(3); // MA_NOACTIVATE, deliver the click
                return;
            }
            base.WndProc(ref m);
        }
    }
}
'@
    Add-Type -TypeDefinition $source -ReferencedAssemblies @('System.Windows.Forms.dll', 'System.Drawing.dll') -ErrorAction Stop
}

function Close-Reminder {
    if ($null -ne $script:CloseTimer) { $script:CloseTimer.Stop() }
    if ($null -ne $script:Popup) {
        $old = $script:Popup
        $script:Popup = $null
        try { $old.Close() } finally { $old.Dispose() }
    }
    if ($null -ne $script:BigFont) { $script:BigFont.Dispose(); $script:BigFont = $null }
    if ($null -ne $script:SmallFont) { $script:SmallFont.Dispose(); $script:SmallFont = $null }
}

function Show-Reminder {
    Close-Reminder
    $a = $script:Config.appearance
    $form = [WaterAlarm.NoActivateForm]::new()
    $script:Popup = $form
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#' + [string]$a.background)

    # Query the primary display in physical pixels after applying PMv2.
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $form.Location = [System.Drawing.Point]::new([int]$screen.Left, [int]$screen.Top)
    $dpi = [WaterAlarmNative]::GetDpiForWindow($form.Handle)
    if ($dpi -lt 96 -or $dpi -gt 768) { throw "Unexpected window DPI: $dpi" }
    $scale = [double]$dpi / 96.0
    $w = [int][Math]::Round([double]$a.width * $scale)
    $h = [int][Math]::Round([double]$a.height * $scale)
    $form.ClientSize = [System.Drawing.Size]::new($w, $h)

    $script:BigFont = [System.Drawing.Font]::new([string]$a.font, [single]$a.mainFontPt,
        [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
    $script:SmallFont = [System.Drawing.Font]::new([string]$a.font, [single]$a.hintFontPt,
        [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)

    $main = [System.Windows.Forms.Label]::new()
    $main.Bounds = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
    $main.Text = [string]$script:Config.message
    $main.Font = $script:BigFont
    $main.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $main.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#' + [string]$a.foreground)
    $main.BackColor = [System.Drawing.Color]::Transparent
    $main.Add_Click({ Close-Reminder })
    [void]$form.Controls.Add($main)

    $hint = [System.Windows.Forms.Label]::new()
    $hintY = [int][Math]::Round($h * 0.76)
    $hintH = [int][Math]::Round($h * 0.20)
    $hint.Bounds = [System.Drawing.Rectangle]::new(0, $hintY, $w, $hintH)
    $hint.Text = [string]$script:Config.hint
    $hint.Font = $script:SmallFont
    $hint.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $hint.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#' + [string]$a.hintColor)
    $hint.BackColor = [System.Drawing.Color]::Transparent
    $hint.Add_Click({ Close-Reminder })
    [void]$form.Controls.Add($hint)
    $hint.BringToFront()

    # Form has no border; the frame and main label share the same geometric center.
    $left = [int]($screen.Left + [Math]::Floor(($screen.Width - $form.Width) / 2.0))
    $top = [int]($screen.Top + [Math]::Floor(($screen.Height - $form.Height) / 2.0))
    $form.Location = [System.Drawing.Point]::new($left, $top)
    $form.Show() # ShowWithoutActivation + WS_EX_NOACTIVATE keep keyboard focus.
    $script:CloseTimer.Interval = [int]$script:Config.durationSeconds * 1000
    $script:CloseTimer.Start()
}

function Check-Clock {
    if ($script:Paused) { return }
    $now = [DateTime]::Now
    $hhmm = $now.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    if (-not $script:ReminderTimes.Contains($hhmm)) { return }
    $key = $now.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    if ($script:Fired.Add($key)) {
        Write-Log 'INFO' "Scheduled reminder: $key"
        Show-Reminder
    }
}

function Set-PauseState {
    $script:Paused = -not $script:Paused
    if ($script:Paused) {
        $script:PauseItem.Text = '恢复提醒'
        $script:Tray.Text = '喝水提醒 - 已暂停'
        $script:Tray.Icon = [System.Drawing.SystemIcons]::Warning
        Write-Log 'INFO' 'Reminders paused via tray menu.'
    } else {
        $script:PauseItem.Text = '暂停提醒'
        $script:Tray.Text = '喝水提醒 - 正在运行'
        $script:Tray.Icon = [System.Drawing.SystemIcons]::Information
        Write-Log 'INFO' 'Reminders resumed via tray menu.'
    }
}

# Config-only diagnostics do not create GUI, timers or a persistent worker.
if ($CheckOnly) {
    try {
        $checked = Read-Config
        Write-Host 'Config.json: PASS' -ForegroundColor Green
        Write-Host ('Schedule: ' + ($checked.times -join ', '))
        Write-Host ('Duration: ' + $checked.durationSeconds + ' s; polling: ' + $checked.pollSeconds + ' s')
    } catch {
        Write-Host ('Config.json: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
    return
}

try {
    # Validate and initialize this replacement before asking a running copy to exit.
    $script:Config = Read-Config
    $script:ReminderTimes = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($t in $script:Config.times) { [void]$script:ReminderTimes.Add([string]$t) }
    Set-DpiAwareness

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    Add-NonActivatingFormType
    [System.Windows.Forms.Application]::EnableVisualStyles()
    if (-not (Get-InstanceLock)) { return }

    $script:Context = [System.Windows.Forms.ApplicationContext]::new()
    $menu = [System.Windows.Forms.ContextMenuStrip]::new()
    $preview = [System.Windows.Forms.ToolStripMenuItem]::new('立即预览提醒')
    $script:PauseItem = [System.Windows.Forms.ToolStripMenuItem]::new('暂停提醒')
    $edit = [System.Windows.Forms.ToolStripMenuItem]::new('编辑配置（重启生效）')
    $openLog = [System.Windows.Forms.ToolStripMenuItem]::new('打开运行日志')
    $quit = [System.Windows.Forms.ToolStripMenuItem]::new('退出')
    [void]$menu.Items.Add($preview)
    [void]$menu.Items.Add($script:PauseItem)
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    [void]$menu.Items.Add($edit)
    [void]$menu.Items.Add($openLog)
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    [void]$menu.Items.Add($quit)

    $preview.Add_Click({ try { Show-Reminder } catch { Write-Log 'ERROR' ('Preview failed: ' + $_.Exception.ToString()) } })
    $script:PauseItem.Add_Click({ try { Set-PauseState } catch { Write-Log 'ERROR' ('Pause failed: ' + $_.Exception.ToString()) } })
    $edit.Add_Click({ try { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $script:ConfigPath + '"') } catch { Write-Log 'ERROR' ('Open config failed: ' + $_.Exception.ToString()) } })
    $openLog.Add_Click({ try { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $script:LogPath + '"') } catch { Write-Log 'ERROR' ('Open log failed: ' + $_.Exception.ToString()) } })
    $quit.Add_Click({ $script:Context.ExitThread() })

    $script:Tray = [System.Windows.Forms.NotifyIcon]::new()
    $script:Tray.Icon = [System.Drawing.SystemIcons]::Information
    $script:Tray.Text = '喝水提醒 - 正在运行'
    $script:Tray.ContextMenuStrip = $menu
    $script:Tray.Add_DoubleClick({ try { Show-Reminder } catch { Write-Log 'ERROR' ('Preview failed: ' + $_.Exception.ToString()) } })
    $script:Tray.Visible = $true

    $script:CloseTimer = [System.Windows.Forms.Timer]::new()
    $script:CloseTimer.Add_Tick({ try { Close-Reminder } catch { Write-Log 'ERROR' ('Close timer: ' + $_.Exception.ToString()) } })

    $script:ClockTimer = [System.Windows.Forms.Timer]::new()
    $script:ClockTimer.Interval = [int]$script:Config.pollSeconds * 1000
    $script:ClockTimer.Add_Tick({ try { Check-Clock } catch { Write-Log 'ERROR' ('Clock timer: ' + $_.Exception.ToString()) } })

    $script:StopTimer = [System.Windows.Forms.Timer]::new()
    $script:StopTimer.Interval = 250
    $script:StopTimer.Add_Tick({
        try {
            if ($script:StopSignal.WaitOne(0)) {
                Write-Log 'INFO' 'Restart requested by another instance.'
                $script:Context.ExitThread()
            }
        } catch { Write-Log 'ERROR' ('Stop event failed: ' + $_.Exception.ToString()) }
    })

    Write-Log 'INFO' ('WaterAlarm v1.0.0 started; schedule: ' + ($script:Config.times -join ', '))
    $script:ClockTimer.Start()
    $script:StopTimer.Start()
    # No immediate reminder on startup (same as the uploaded AHK file).
    [System.Windows.Forms.Application]::Run($script:Context)
}
catch {
    Write-Log 'ERROR' ('Fatal: ' + $_.Exception.ToString())
}
finally {
    try { Close-Reminder } catch { }
    foreach ($obj in @($script:ClockTimer, $script:StopTimer, $script:CloseTimer)) {
        if ($null -ne $obj) { try { $obj.Stop(); $obj.Dispose() } catch { } }
    }
    if ($null -ne $script:Tray) {
        try { $script:Tray.Visible = $false; $script:Tray.Dispose() } catch { }
    }
    if ($null -ne $script:Context) { try { $script:Context.Dispose() } catch { } }
    if ($null -ne $script:StopSignal) { try { $script:StopSignal.Dispose() } catch { } }
    if ($null -ne $script:Mutex) {
        if ($script:OwnsMutex) { try { $script:Mutex.ReleaseMutex() } catch { } }
        try { $script:Mutex.Dispose() } catch { }
    }
    Write-Log 'INFO' 'WaterAlarm worker exited.'
}
