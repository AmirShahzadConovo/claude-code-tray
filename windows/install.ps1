# Claude tray widget - Windows installer.
# Copies the widget to %USERPROFILE%\.claude\tray-widget, merges the required
# hooks into %USERPROFILE%\.claude\settings.json (non-destructive, idempotent),
# creates Start Menu + Startup shortcuts, and starts the widget.
# Re-running after a git pull updates the installed copy in place.

$ErrorActionPreference = 'Stop'

$src    = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $env:USERPROFILE '.claude\tray-widget'
$setStatusPath = Join-Path $target 'set-status.ps1'

# ---- 1. copy widget files ----
New-Item -ItemType Directory -Force $target | Out-Null
foreach ($f in @('ClaudeTray.ps1', 'icon-lib.ps1', 'set-status.ps1', 'launch-tray.vbs')) {
    Copy-Item (Join-Path $src $f) (Join-Path $target $f) -Force
}
Write-Host "[1/5] Widget files installed to $target"

# ---- 2. merge hooks into settings.json ----
$settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
if (Test-Path $settingsPath) {
    Copy-Item $settingsPath "$settingsPath.tray-widget.bak" -Force
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    New-Item -ItemType Directory -Force (Split-Path $settingsPath) | Out-Null
    $settings = [pscustomobject]@{}
}
if (-not $settings.PSObject.Properties['hooks']) {
    $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
}

$events = @(
    @{ e = 'UserPromptSubmit';  m = $null;              s = 'working' },
    @{ e = 'Stop';              m = $null;              s = 'done' },
    @{ e = 'PermissionRequest'; m = $null;              s = 'needs-input' },
    @{ e = 'PermissionDenied';  m = $null;              s = 'working' },
    @{ e = 'PreToolUse';        m = 'AskUserQuestion';  s = 'needs-input' },
    @{ e = 'PostToolUse';       m = $null;              s = 'working' },
    @{ e = 'SessionEnd';        m = $null;              s = 'ended' }
)

$added = 0
foreach ($ev in $events) {
    $existing = $settings.hooks.PSObject.Properties[$ev.e]
    # idempotency: skip if any hook for this event already calls our set-status.ps1
    $already = $false
    if ($existing) {
        foreach ($group in @($existing.Value)) {
            foreach ($h in @($group.hooks)) {
                if (@($h.args) -contains $setStatusPath -or "$($h.command)" -like "*set-status.ps1*") { $already = $true }
            }
        }
    }
    if ($already) { continue }

    $hook = [pscustomobject]@{
        type    = 'command'
        command = 'powershell.exe'
        args    = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $setStatusPath, '-State', $ev.s)
        async   = $true
        timeout = 15
    }
    $group = if ($ev.m) { [pscustomobject]@{ matcher = $ev.m; hooks = @($hook) } }
             else       { [pscustomobject]@{ hooks = @($hook) } }

    if ($existing) {
        $existing.Value = @($existing.Value) + $group
    } else {
        $settings.hooks | Add-Member -NotePropertyName $ev.e -NotePropertyValue @($group)
    }
    $added++
}
$settings | ConvertTo-Json -Depth 16 | Set-Content $settingsPath -Encoding utf8
Write-Host "[2/5] Hooks merged into settings.json ($added added, $($events.Count - $added) already present)"

# ---- 3. app icon for shortcuts ----
. (Join-Path $target 'icon-lib.ps1')
$bmp = New-StatusBitmap ([System.Drawing.Color]::FromArgb(37, 99, 235)) 0 'filled'
$ico = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
$fs = [System.IO.File]::Create((Join-Path $target 'app.ico'))
$ico.Save($fs); $fs.Close(); $bmp.Dispose()
Write-Host '[3/5] App icon generated'

# ---- 4. shortcuts: Start Menu + Startup (auto-start at login) ----
$ws = New-Object -ComObject WScript.Shell
foreach ($loc in @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Claude Tray Widget.lnk",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\Claude Tray Widget.lnk"
)) {
    $lnk = $ws.CreateShortcut($loc)
    $lnk.TargetPath = 'wscript.exe'
    $lnk.Arguments = '"' + (Join-Path $target 'launch-tray.vbs') + '"'
    $lnk.IconLocation = Join-Path $target 'app.ico'
    $lnk.Description = 'Claude Code tray status widget'
    $lnk.Save()
}
# remove the legacy plain-vbs autostart if present (pre-installer installs)
$legacy = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\claude-tray.vbs"
if (Test-Path $legacy) { Remove-Item $legacy -Force }
Write-Host '[4/5] Start Menu + Startup shortcuts created'

# ---- 5. start (or restart) the widget ----
$old = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*ClaudeTray.ps1*' -and $_.ProcessId -ne $PID })
foreach ($p in $old) { Stop-Process -Id $p.ProcessId -Force -Confirm:$false }
Start-Sleep -Seconds 1
Start-Process wscript.exe -ArgumentList ('"' + (Join-Path $target 'launch-tray.vbs') + '"')
Write-Host '[5/5] Widget started'

Write-Host ''
Write-Host 'Done. Two one-time steps:'
Write-Host '  1. Drag the icon out of the tray overflow (^) so it is always visible.'
Write-Host '  2. Restart your Claude Code sessions so the hooks load.'
