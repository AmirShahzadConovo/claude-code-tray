#!/usr/bin/env bash
# Claude tray widget - Ubuntu uninstaller.
# Removes the widget's hooks from settings.json (backup written first, other
# hooks and settings preserved), stops the widget, and deletes the installed
# files and desktop entries. Fully reverses linux/install.sh.
set -euo pipefail

TARGET="$HOME/.claude/tray-widget"

# ---- 1. remove our hooks from settings.json ----
python3 <<'PYEOF'
import json, os, shutil

path = os.path.expanduser("~/.claude/settings.json")
if not os.path.exists(path):
    print("[1/4] No settings.json found - nothing to remove")
else:
    with open(path, encoding="utf-8") as f:
        settings = json.load(f)
    if "hooks" not in settings:
        print("[1/4] No hooks in settings.json - nothing to remove")
    else:
        shutil.copy(path, path + ".tray-widget-uninstall.bak")
        hooks = settings["hooks"]
        removed = 0
        for event in list(hooks):
            kept = []
            for group in hooks[event]:
                ours = any("set-status.py" in str(h.get("command", ""))
                           for h in group.get("hooks", []))
                if ours:
                    removed += 1
                else:
                    kept.append(group)
            if kept:
                hooks[event] = kept
            else:
                del hooks[event]
        if not hooks:
            del settings["hooks"]
        with open(path, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2)
        print("[1/4] Removed %d hook entries from settings.json "
              "(backup: settings.json.tray-widget-uninstall.bak)" % removed)
PYEOF

# ---- 2. stop the widget ----
pkill -f "claude-tray.py" 2>/dev/null || true
echo "[2/4] Widget stopped"

# ---- 3. desktop entries ----
rm -f "$HOME/.config/autostart/claude-tray.desktop" \
      "$HOME/.local/share/applications/claude-tray.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "[3/4] Launcher and autostart entries removed"

# ---- 4. installed files ----
rm -rf "$TARGET" "$HOME/.cache/claude-tray-icons"
echo "[4/4] Installed files removed"

echo
echo "Uninstalled. Restart your Claude Code sessions so the hooks unload."
