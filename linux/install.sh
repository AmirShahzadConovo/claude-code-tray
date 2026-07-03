#!/usr/bin/env bash
# Claude tray widget - Ubuntu/GNOME installer.
# Copies the widget to ~/.claude/tray-widget, merges the required hooks into
# ~/.claude/settings.json (non-destructive, idempotent), sets up autostart,
# and starts the widget. Re-running after a git pull updates in place.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude/tray-widget"
SET_STATUS="$TARGET/set-status.py"

# ---- 0. dependency check ----
# Always probe the SYSTEM python: apt installs the gi bindings there, and a
# conda/pyenv/venv python3 earlier in PATH would never see them.
PY=/usr/bin/python3
if [ ! -x "$PY" ]; then
    echo "System python not found at $PY. Install it with: sudo apt install python3"
    exit 1
fi
if ! DEP_ERR="$("$PY" -c "
import gi
gi.require_version('Gtk', '3.0')
try:
    gi.require_version('AyatanaAppIndicator3', '0.1')
except ValueError:
    gi.require_version('AppIndicator3', '0.1')
import cairo
" 2>&1)"; then
    echo "Missing dependencies for $PY:"
    echo "$DEP_ERR" | tail -1 | sed 's/^/  /'
    echo "Install them with:"
    echo "  sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1"
    exit 1
fi
echo "[1/6] Dependencies OK"

# ---- 1. copy widget files ----
mkdir -p "$TARGET"
cp "$SRC/claude-tray.py" "$SRC/set-status.py" "$TARGET/"
chmod +x "$TARGET/claude-tray.py" "$TARGET/set-status.py"
echo "[2/6] Widget files installed to $TARGET"

# ---- 2. merge hooks into settings.json (python for safe JSON handling) ----
"$PY" - "$SET_STATUS" <<'PYEOF'
import json, os, shutil, sys

set_status = sys.argv[1]
path = os.path.expanduser("~/.claude/settings.json")
settings = {}
if os.path.exists(path):
    shutil.copy(path, path + ".tray-widget.bak")
    with open(path, encoding="utf-8") as f:
        settings = json.load(f)
hooks = settings.setdefault("hooks", {})

events = [
    ("UserPromptSubmit",  None,              "working"),
    ("Stop",              None,              "done"),
    ("PermissionRequest", None,              "needs-input"),
    ("PermissionDenied",  None,              "working"),
    ("PreToolUse",        "AskUserQuestion", "needs-input"),
    ("PostToolUse",       None,              "working"),
    ("SessionEnd",        None,              "ended"),
]

added = 0
for event, matcher, state in events:
    groups = hooks.setdefault(event, [])
    # idempotency: skip if any hook for this event already calls set-status.py
    if any("set-status.py" in str(h.get("command", "")) or set_status in [str(a) for a in h.get("args", [])]
           for g in groups for h in g.get("hooks", [])):
        continue
    hook = {"type": "command",
            "command": '/usr/bin/python3 "%s" %s' % (set_status, state),
            "async": True, "timeout": 15}
    group = {"hooks": [hook]}
    if matcher:
        group["matcher"] = matcher
    groups.append(group)
    added += 1

with open(path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2)
print("[3/6] Hooks merged into settings.json (%d added, %d already present)" % (added, len(events) - added))
PYEOF

# ---- 3. app-grid launcher (Activities / dash search) ----
"$PY" "$TARGET/claude-tray.py" --make-icon "$TARGET/app.png" 128
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/claude-tray.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Claude Tray Widget
Comment=Claude Code session status in the top bar
Exec=/usr/bin/python3 $TARGET/claude-tray.py
Icon=$TARGET/app.png
Terminal=false
Categories=Utility;
EOF
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "[4/6] App-grid launcher entry created"

# ---- 4. autostart at login ----
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/claude-tray.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Claude Tray Widget
Comment=Claude Code session status in the top bar
Exec=/usr/bin/python3 $TARGET/claude-tray.py
Icon=$TARGET/app.png
X-GNOME-Autostart-enabled=true
EOF
echo "[5/6] Autostart entry created"

# ---- 5. start (or restart) the widget ----
pkill -f "claude-tray.py" 2>/dev/null || true
sleep 1
nohup "$PY" "$TARGET/claude-tray.py" >/dev/null 2>&1 &
disown
echo "[6/6] Widget started"

echo
echo "Done. Restart your Claude Code sessions so the hooks load."
echo "Note: GNOME shows AppIndicators on Ubuntu by default; on stock GNOME"
echo "install the 'AppIndicator and KStatusNotifierItem Support' extension."
