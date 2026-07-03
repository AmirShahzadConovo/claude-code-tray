# Claude Code tray status widget.
# Watches sessions\*.json (written by set-status.ps1 via Claude Code hooks) and
# shows a gradient-squircle status icon in the Windows system tray:
#   pulsing blue = a session needs input, green = finished and waiting,
#   amber = working, hollow gray outline = no active sessions.
# When 2+ sessions are actionable (done or needs-input) a count badge appears.
# Left-click focuses VSCode. Right-click for menu. Chimes on done / needs-input.

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$dir         = Split-Path -Parent $MyInvocation.MyCommand.Path
$sessionsDir = Join-Path $dir 'sessions'
$logFile     = Join-Path $dir 'tray.log'

. (Join-Path $dir 'icon-lib.ps1')

# single instance
$mutex = New-Object System.Threading.Mutex($false, 'ClaudeTrayWidget')
if (-not $mutex.WaitOne(0, $false)) { exit }

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Win32Focus {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@

function Log([string]$msg) {
    try {
        Add-Content -Path $logFile -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
    } catch {}
}

$colors = @{
    'working'     = [System.Drawing.Color]::FromArgb(245, 158, 11)   # amber
    'done'        = [System.Drawing.Color]::FromArgb(34, 197, 94)    # green
    'needs-input' = [System.Drawing.Color]::FromArgb(37, 99, 235)    # blue (pulses)
    'idle'        = [System.Drawing.Color]::FromArgb(138, 148, 163)  # faint gray
}

# icons cached by explicit key, created on demand
$script:iconCache = @{}
function Get-DotIcon([string]$key, [System.Drawing.Color]$color, [int]$badge, [string]$style) {
    if (-not $script:iconCache.ContainsKey($key)) {
        $script:iconCache[$key] = New-StatusIcon $color $badge $style
    }
    return $script:iconCache[$key]
}

# Windows taskbar theme: 1 = light taskbar (pulse alternates to navy),
# 0 or unreadable = dark taskbar (pulse alternates to soft light blue)
function Get-SystemUsesLightTheme {
    try {
        $v = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'SystemUsesLightTheme' -ErrorAction Stop
        return [bool]$v.SystemUsesLightTheme
    } catch { return $false }
}

function Get-Sessions {
    $result = @()
    if (-not (Test-Path $sessionsDir)) { return $result }
    foreach ($f in @(Get-ChildItem $sessionsDir -Filter '*.json' -ErrorAction SilentlyContinue)) {
        # garbage-collect sessions that never got a SessionEnd (crash, kill)
        if ($f.LastWriteTime -lt (Get-Date).AddHours(-24)) {
            try { Remove-Item $f.FullName -Force } catch {}
            continue
        }
        try {
            $s = Get-Content $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($s.state -and $colors.ContainsKey([string]$s.state)) {
                $result += [pscustomobject]@{
                    Id      = $f.BaseName
                    State   = [string]$s.state
                    Project = [string]$s.project
                }
            }
        } catch {}  # mid-write or malformed; next tick will pick it up
    }
    return $result
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = Get-DotIcon 'idle/0/outline' $colors['idle'] 0 'outline'
$notify.Text = 'Claude: idle'
$notify.Visible = $true

$script:sessionStates = @{}
$script:currentKey    = 'idle/0/outline'
$script:firstTick     = $true
$script:pulseFlip     = $false

function Update-Status {
    $sessions = @(Get-Sessions)

    # per-session transition detection (drives sounds and the log)
    $newStates = @{}
    $playDone = $false
    $playInput = $false
    foreach ($s in $sessions) {
        $newStates[$s.Id] = $s.State
        $prev = $script:sessionStates[$s.Id]
        if ($s.State -ne $prev) {
            if ($s.State -eq 'done') { $playDone = $true }
            elseif ($s.State -eq 'needs-input') { $playInput = $true }
            $shortId = $s.Id.Substring(0, [Math]::Min(8, $s.Id.Length))
            Log ("session {0} [{1}]: {2} -> {3}" -f $shortId, $s.Project, $prev, $s.State)
        }
    }
    foreach ($id in @($script:sessionStates.Keys)) {
        if (-not $newStates.ContainsKey($id)) {
            Log ("session {0}: ended" -f $id.Substring(0, [Math]::Min(8, $id.Length)))
        }
    }
    $script:sessionStates = $newStates

    $needsInput = @($sessions | Where-Object { $_.State -eq 'needs-input' })
    $done       = @($sessions | Where-Object { $_.State -eq 'done' })
    $working    = @($sessions | Where-Object { $_.State -eq 'working' })

    $top = 'idle'
    if ($needsInput.Count) { $top = 'needs-input' }
    elseif ($done.Count)   { $top = 'done' }
    elseif ($working.Count){ $top = 'working' }

    $actionable = $needsInput.Count + $done.Count
    $badge = 0
    if ($actionable -ge 2) { $badge = $actionable }

    # idle is a hollow outline; needs-input pulses by alternating blue with a
    # softened theme-contrast frame (light blue on dark taskbar, navy on light)
    $dotColor = $colors[$top]
    $style = 'filled'
    $variant = 'filled'
    if ($top -eq 'idle') {
        $style = 'outline'
        $variant = 'outline'
    } elseif ($top -eq 'needs-input') {
        $script:pulseFlip = -not $script:pulseFlip
        if ($script:pulseFlip) {
            if (Get-SystemUsesLightTheme) {
                $dotColor = [System.Drawing.Color]::FromArgb(30, 58, 138)     # deep navy
                $variant = 'alt-deep'
            } else {
                $dotColor = [System.Drawing.Color]::FromArgb(147, 197, 253)   # soft light blue
                $variant = 'alt-lite'
            }
        }
    }

    $key = "$top/$badge/$variant"
    if ($key -ne $script:currentKey) {
        $notify.Icon = Get-DotIcon $key $dotColor $badge $style
        $script:currentKey = $key
    }

    # tooltip (NotifyIcon.Text is capped at 63 chars)
    if ($sessions.Count -eq 0) {
        $tip = 'Claude: idle'
    } elseif ($sessions.Count -eq 1) {
        $s = $sessions[0]
        $tip = "Claude: $($s.State)"
        if ($s.Project) { $tip += " - $($s.Project)" }
    } else {
        $parts = @()
        if ($needsInput.Count) { $parts += "$($needsInput.Count) need input" }
        if ($done.Count)       { $parts += "$($done.Count) done" }
        if ($working.Count)    { $parts += "$($working.Count) working" }
        $tip = 'Claude: ' + ($parts -join ', ')
    }
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
    if ($notify.Text -ne $tip) { $notify.Text = $tip }

    # chime on transitions, but not for state discovered at startup
    if (-not $script:firstTick) {
        if ($playInput)   { [System.Media.SystemSounds]::Exclamation.Play() }
        elseif ($playDone){ [System.Media.SystemSounds]::Asterisk.Play() }
    }
    $script:firstTick = $false
}

function Focus-VSCode {
    $p = Get-Process -Name 'Code' -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
        Select-Object -First 1
    if ($p) {
        [Win32Focus]::ShowWindow($p.MainWindowHandle, 9) | Out-Null   # SW_RESTORE
        [Win32Focus]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
    }
}

$notify.add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Focus-VSCode }
})

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$openItem = $menu.Items.Add('Focus VSCode')
$openItem.add_Click({ Focus-VSCode })
$logItem = $menu.Items.Add('Open log')
$logItem.add_Click({ Start-Process notepad.exe $logFile })
$clearItem = $menu.Items.Add('Clear stuck sessions')
$clearItem.add_Click({
    try {
        Get-ChildItem $sessionsDir -Filter '*.json' -ErrorAction SilentlyContinue | Remove-Item -Force
        Log 'sessions cleared manually'
    } catch { Log "clear error: $_" }
})
$menu.Items.Add('-') | Out-Null
$exitItem = $menu.Items.Add('Exit')
$exitItem.add_Click({
    $notify.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})
$notify.ContextMenuStrip = $menu

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.add_Tick({ try { Update-Status } catch { Log "tick error: $_" } })
$timer.Start()

Log 'tray app started (gradient-squircle icon set)'
try { Update-Status } catch { Log "startup error: $_" }
[System.Windows.Forms.Application]::Run()

$timer.Stop()
$notify.Dispose()
$mutex.ReleaseMutex()
Log 'tray app exited'
