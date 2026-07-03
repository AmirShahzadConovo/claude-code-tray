#!/usr/bin/env bash
# Repo self-test: syntax + functional check of the Linux port (no GUI needed).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

python3 -m py_compile set-status.py claude-tray.py
echo "py_compile: OK"
bash -n install.sh
echo "install.sh syntax: OK"

echo '{"session_id":"wsltest","cwd":"/home/amir/claude-work-done"}' | python3 set-status.py working
echo "helper wrote: $(cat sessions/wsltest.json)"
echo '{"session_id":"wsltest"}' | python3 set-status.py ended
remaining=$(ls sessions/ 2>/dev/null | wc -l)
echo "after ended, session files remaining: $remaining"
rm -rf sessions __pycache__
echo "selftest: ALL OK"
