#!/usr/bin/env python3
"""Called by Claude Code hooks. Reads the hook JSON from stdin and writes a
per-session status file for the tray widget to aggregate.
Usage: set-status.py working|done|needs-input|ended
"""
import json
import os
import re
import sys

STATES = {"working", "done", "needs-input", "ended"}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in STATES:
        sys.exit(0)
    state = sys.argv[1]

    base = os.path.dirname(os.path.abspath(__file__))
    sessions_dir = os.path.join(base, "sessions")
    os.makedirs(sessions_dir, exist_ok=True)

    session_id, cwd = "default", ""
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        session_id = str(payload.get("session_id") or "default")
        cwd = str(payload.get("cwd") or "")
    except Exception:
        pass

    safe_id = re.sub(r"[^A-Za-z0-9_-]", "", session_id) or "default"
    session_file = os.path.join(sessions_dir, safe_id + ".json")

    if state == "ended":
        try:
            os.unlink(session_file)
        except OSError:
            pass
        return

    project = os.path.basename(cwd.rstrip("/\\")) if cwd else ""
    from datetime import datetime, timezone
    data = json.dumps({
        "state": state,
        "project": project,
        "time": datetime.now(timezone.utc).isoformat(),
    })
    tmp = session_file + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(data)
    os.replace(tmp, session_file)


if __name__ == "__main__":
    main()
