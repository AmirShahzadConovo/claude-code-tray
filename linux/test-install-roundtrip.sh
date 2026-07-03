#!/usr/bin/env bash
# Temporary: full install -> uninstall round-trip against a fake HOME.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

FAKE=/tmp/fakehome-installtest
rm -rf "$FAKE"
mkdir -p "$FAKE"

echo "=========== INSTALL ==========="
HOME="$FAKE" bash ./install.sh

echo "=========== VERIFY INSTALLED ==========="
echo "--- hook events:"
HOME="$FAKE" /usr/bin/python3 -c "import json,os; s=json.load(open(os.path.expanduser('~/.claude/settings.json'))); print(sorted(s['hooks'].keys()))"
echo "--- installed files:"
ls "$FAKE/.claude/tray-widget"
echo "--- desktop entries:"
ls "$FAKE/.local/share/applications" "$FAKE/.config/autostart"
echo "--- launcher icon exists:"
test -f "$FAKE/.claude/tray-widget/app.png" && echo "app.png OK"

sleep 1
pkill -f "$FAKE/.claude/tray-widget/claude-tray.py" 2>/dev/null || true

echo "=========== UNINSTALL ==========="
HOME="$FAKE" bash ./uninstall.sh

echo "=========== VERIFY REMOVED ==========="
echo "--- leftovers (should be settings.json + backups only):"
find "$FAKE" -type f | sed "s|$FAKE/||"
echo "--- hooks key present after uninstall:"
HOME="$FAKE" /usr/bin/python3 -c "import json,os; s=json.load(open(os.path.expanduser('~/.claude/settings.json'))); print('hooks' in s)"
rm -rf "$FAKE"
echo "=========== ROUND-TRIP OK ==========="
