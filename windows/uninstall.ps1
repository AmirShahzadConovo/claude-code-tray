# Claude tray widget - Windows uninstaller.
# Removes the widget's hooks from settings.json (backup written first, other
# hooks and settings preserved), stops the widget, and deletes the installed
# files and shortcuts. Fully reverses windows\install.ps1.

$ErrorActionPreference = 'Stop'

$target = Join-Path $env:USERPROFILE '.claude\tray-widget'
$setStatusPath = Join-Path $target 'set-status.ps1'

# ---- 1. remove our hooks from settings.json ----
$settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
if ((Test-Path $settingsPath)) {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    if ($settings.PSObject.Properties['hooks']) {
        Copy-Item $settingsPath "$settingsPath.tray-widget-uninstall.bak" -Force
        $removed = 0
        foreach ($prop in @($settings.hooks.PSObject.Properties)) {
            $kept = @()
            foreach ($group in @($prop.Value)) {
                $ours = $false
                foreach ($h in @($group.hooks)) {
                    if (@($h.args) -contains $setStatusPath -or "$($h.command)" -like '*set-status.ps1*') { $ours = $true }
                }
                if ($ours) { $removed++ } else { $kept += $group }
            }
            if ($kept.Count) { $prop.Value = $kept }
            else { $settings.hooks.PSObject.Properties.Remove($prop.Name) }
        }
        if (-not @($settings.hooks.PSObject.Properties).Count) {
            $settings.PSObject.Properties.Remove('hooks')
        }
        $settings | ConvertTo-Json -Depth 16 | Set-Content $settingsPath -Encoding utf8
        Write-Host "[1/4] Removed $removed hook entries from settings.json (backup: settings.json.tray-widget-uninstall.bak)"
    } else {
        Write-Host '[1/4] No hooks in settings.json - nothing to remove'
    }
} else {
    Write-Host '[1/4] No settings.json found - nothing to remove'
}

# ---- 2. stop the widget ----
$procs = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*ClaudeTray.ps1*' -and $_.ProcessId -ne $PID })
foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -Confirm:$false }
Write-Host "[2/4] Widget stopped ($($procs.Count) process(es))"

# ---- 3. shortcuts ----
foreach ($lnk in @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Claude Tray Widget.lnk",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\Claude Tray Widget.lnk",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\claude-tray.vbs"
)) { if (Test-Path $lnk) { Remove-Item $lnk -Force } }
Write-Host '[3/4] Start Menu and Startup shortcuts removed'

# ---- 4. installed files ----
Start-Sleep -Seconds 1
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
Write-Host "[4/4] $target removed"

Write-Host ''
Write-Host 'Uninstalled. Restart your Claude Code sessions so the hooks unload.'
Write-Host '(A dead tray icon may linger until you hover over it - Windows quirk.)'
