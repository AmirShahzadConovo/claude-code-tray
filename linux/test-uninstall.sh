#!/usr/bin/env bash
# Temporary test: run uninstall.sh against a fake HOME and verify it removes
# only our hooks/files while preserving foreign hooks and other settings.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

FAKE=/tmp/fakehome-traytest
rm -rf "$FAKE"
mkdir -p "$FAKE/.claude/tray-widget/sessions" "$FAKE/.config/autostart" \
         "$FAKE/.local/share/applications" "$FAKE/.cache/claude-tray-icons"
cat > "$FAKE/.claude/settings.json" <<'EOF'
{
  "model": "keep-me",
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "python3 \"/home/x/.claude/tray-widget/set-status.py\" done", "async": true}]},
      {"hooks": [{"type": "command", "command": "echo custom-keep"}]}
    ],
    "UserPromptSubmit": [
      {"hooks": [{"type": "command", "command": "python3 \"/home/x/.claude/tray-widget/set-status.py\" working", "async": true}]}
    ]
  }
}
EOF
touch "$FAKE/.config/autostart/claude-tray.desktop" \
      "$FAKE/.local/share/applications/claude-tray.desktop" \
      "$FAKE/.claude/tray-widget/claude-tray.py"

HOME="$FAKE" bash ./uninstall.sh

echo "=== resulting settings.json ==="
cat "$FAKE/.claude/settings.json"
echo "=== leftovers (should list only settings.json + backup) ==="
find "$FAKE" -type f | sed "s|$FAKE/||"
rm -rf "$FAKE"
echo "=== test done ==="
