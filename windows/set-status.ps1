# Called by Claude Code hooks. Reads the hook JSON from stdin and writes a
# per-session status file for the tray widget to aggregate.
# Usage: set-status.ps1 -State working|done|needs-input|ended
param([Parameter(Mandatory=$true)][string]$State)

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sessionsDir = Join-Path $dir 'sessions'
if (-not (Test-Path $sessionsDir)) { New-Item -ItemType Directory -Path $sessionsDir -Force | Out-Null }

$cwd = ''
$sessionId = 'default'
try {
    $raw = [Console]::In.ReadToEnd()
    if ($raw) {
        $payload = $raw | ConvertFrom-Json
        if ($payload.cwd) { $cwd = [string]$payload.cwd }
        if ($payload.session_id) { $sessionId = [string]$payload.session_id }
    }
} catch {}

# session_id becomes the filename; strip anything unsafe
$safeId = ($sessionId -replace '[^A-Za-z0-9_-]', '')
if (-not $safeId) { $safeId = 'default' }
$sessionFile = Join-Path $sessionsDir "$safeId.json"

if ($State -eq 'ended') {
    try { Remove-Item $sessionFile -Force -ErrorAction Stop } catch {}
    exit 0
}

# cwd may be a Windows or a WSL/POSIX path; Split-Path -Leaf handles both
$project = ''
if ($cwd) {
    try { $project = Split-Path $cwd -Leaf } catch { $project = $cwd }
}

$json = @{
    state   = $State
    project = $project
    time    = (Get-Date).ToString('o')
} | ConvertTo-Json -Compress

# retry once in case the tray app or a concurrent hook holds the file
for ($i = 0; $i -lt 2; $i++) {
    try { Set-Content -Path $sessionFile -Value $json -Encoding utf8; break }
    catch { Start-Sleep -Milliseconds 150 }
}
