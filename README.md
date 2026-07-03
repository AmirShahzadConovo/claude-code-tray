# Claude Tray Widget

A tiny system-tray/top-bar status light for [Claude Code](https://code.claude.com). Know at a glance — without switching to VSCode or your terminal — whether Claude is working, finished, or blocked waiting on you. Works with any number of concurrent sessions across any number of editor windows.

| Icon | Meaning |
|---|---|
| 🟧 Amber squircle | Claude is working |
| 🟩 Green squircle *(+ chime)* | Claude finished — waiting for your next prompt |
| 🟦 Blue squircle, gently pulsing *(+ chime)* | Claude is **blocked**: a permission prompt or question needs you |
| ⬜ Hollow gray outline | No active sessions |
| Number badge | 2+ sessions need your attention |

It's DND-proof by design: a persistent tray icon, not a notification, so Focus Assist / Do Not Disturb can't suppress it. Click the icon to focus VSCode. Right-click for menu (log, clear stuck sessions, exit).

## Install

### Windows 10/11

```powershell
git clone https://github.com/AmirShahzadConovo/claude-code-tray.git
cd claude-code-tray
powershell -ExecutionPolicy Bypass -File windows\install.ps1
```

Then drag the icon out of the tray overflow (`^`) once so it stays visible, and restart your Claude Code sessions so the hooks load.

The widget auto-starts at login. To start it manually (e.g. after exiting it), press Win and search for **Claude Tray Widget**.

> **WSL users**: if you run Claude Code through the VSCode extension on Windows (even with projects inside WSL), use this Windows installer — the extension runs Windows-side.

### Ubuntu (native desktop)

```bash
sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1
git clone https://github.com/AmirShahzadConovo/claude-code-tray.git
cd claude-code-tray
bash linux/install.sh
```

Restart your Claude Code sessions so the hooks load.

The widget auto-starts at login and appears in the **top bar** (near the clock). To start it manually (e.g. after exiting it), open Activities and search for **Claude Tray Widget**.

### macOS

Not built yet — contributions welcome. The contract below is all you need; a [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin reading the sessions directory (~50 lines) is the suggested route.

## Update

```bash
git pull
# then re-run the installer for your OS (it's idempotent)
```

## How it works

```
Claude Code hooks ──▶ set-status helper ──▶ sessions/<session_id>.json ──▶ tray app (1s poll)
```

1. **Hooks** (merged into `~/.claude/settings.json` by the installer) fire on Claude lifecycle events: `UserPromptSubmit` → working, `Stop` → done, `PermissionRequest` / `PreToolUse:AskUserQuestion` → needs-input, `PostToolUse` / `PermissionDenied` → working, `SessionEnd` → cleanup. All hooks are `async`, so they never slow Claude down.
2. The **helper** (`set-status.ps1` / `set-status.py`) writes one small JSON file per session:
   `{"state": "working|done|needs-input", "project": "<folder name>", "time": "<iso8601>"}`
3. The **tray app** polls the sessions directory every second and aggregates: *needs-input beats done beats working*; 2+ actionable sessions show a count badge; sessions older than 24h are garbage-collected (crash protection).

Note: the `Notification` hook event does **not** fire in the VSCode extension — that's why permission prompts are detected via `PermissionRequest` instead.

## Uninstall

From the cloned repo folder:

- **Windows**: `powershell -ExecutionPolicy Bypass -File windows\uninstall.ps1`
- **Ubuntu**: `bash linux/uninstall.sh`

The uninstaller removes the widget's hook entries from `~/.claude/settings.json` (writing a backup next to it first — your other hooks and settings are preserved), stops the widget, and deletes the installed files, shortcuts, and launcher/autostart entries. Restart your Claude Code sessions afterwards so the hooks unload.
