#!/usr/bin/env python3
"""Claude Code tray status widget (Linux / Ubuntu GNOME, AppIndicator).

Watches sessions/*.json (written by set-status.py via Claude Code hooks) and
shows a gradient-squircle status icon in the top bar:
  pulsing blue = a session needs input, green = finished and waiting,
  amber = working, hollow gray outline = no active sessions.
When 2+ sessions are actionable (done or needs-input) a count badge appears.

Deps (Ubuntu): python3-gi, python3-gi-cairo, gir1.2-ayatanaappindicator3-0.1
"""
import fcntl
import json
import math
import os
import subprocess
import sys
import time

import gi
gi.require_version("Gtk", "3.0")
try:
    gi.require_version("AyatanaAppIndicator3", "0.1")
    from gi.repository import AyatanaAppIndicator3 as AppIndicator
except (ValueError, ImportError):
    gi.require_version("AppIndicator3", "0.1")
    from gi.repository import AppIndicator3 as AppIndicator
from gi.repository import Gtk, GLib
import cairo

BASE = os.path.dirname(os.path.abspath(__file__))
SESSIONS_DIR = os.path.join(BASE, "sessions")
LOG_FILE = os.path.join(BASE, "tray.log")
ICON_DIR = os.path.join(os.path.expanduser("~"), ".cache", "claude-tray-icons")

COLORS = {
    "working":     (245, 158, 11),   # amber
    "done":        (34, 197, 94),    # green
    "needs-input": (37, 99, 235),    # blue (pulses)
    "idle":        (138, 148, 163),  # gray outline
}
PULSE_ALT_DARK = (147, 197, 253)     # soft light blue (dark top bar)
PULSE_ALT_LIGHT = (30, 58, 138)      # deep navy (light top bar)

SOUND_DONE = "/usr/share/sounds/freedesktop/stereo/complete.oga"
SOUND_INPUT = "/usr/share/sounds/freedesktop/stereo/bell.oga"


def log(msg):
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S") + "  " + msg + "\n")
    except OSError:
        pass


def rounded_rect(ctx, x, y, w, h, r):
    ctx.new_sub_path()
    ctx.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    ctx.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    ctx.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    ctx.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    ctx.close_path()


def draw_squircle(ctx, color, badge, style):
    """Draw the status squircle into a 32x32 coordinate space."""
    r, g, b = (c / 255.0 for c in color)

    if style == "outline":
        rounded_rect(ctx, 3, 3, 26, 26, 8)
        ctx.set_source_rgb(r, g, b)
        ctx.set_line_width(4.5)
        ctx.stroke()
    else:
        rounded_rect(ctx, 1, 1, 30, 30, 10)
        grad = cairo.LinearGradient(0, 0, 8, 32)
        lighten = lambda c, f: c + (1 - c) * f
        darken = lambda c, f: c * (1 - f)
        grad.add_color_stop_rgb(0, lighten(r, .38), lighten(g, .38), lighten(b, .38))
        grad.add_color_stop_rgb(1, darken(r, .22), darken(g, .22), darken(b, .22))
        ctx.set_source(grad)
        ctx.fill_preserve()
        # soft specular sheen across the top third
        ctx.clip()
        sheen = cairo.LinearGradient(0, 0, 0, 13)
        sheen.add_color_stop_rgba(0, 1, 1, 1, .35)
        sheen.add_color_stop_rgba(1, 1, 1, 1, 0)
        ctx.set_source(sheen)
        ctx.rectangle(0, 0, 32, 13)
        ctx.fill()
        ctx.reset_clip()

        if badge >= 2:
            text = "9" if badge > 9 else str(badge)
            lum = color[0] * .299 + color[1] * .587 + color[2] * .114
            ctx.set_source_rgb(0, 0, 0) if lum > 150 else ctx.set_source_rgb(1, 1, 1)
            ctx.select_font_face("sans-serif", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
            ctx.set_font_size(19)
            ext = ctx.text_extents(text)
            ctx.move_to(16 - ext.width / 2 - ext.x_bearing, 16 - ext.height / 2 - ext.y_bearing)
            ctx.show_text(text)


def render_icon(key, color, badge, style):
    """Render a 32x32 squircle PNG into ICON_DIR; returns the icon name."""
    path = os.path.join(ICON_DIR, key + ".png")
    if os.path.exists(path):
        return key
    os.makedirs(ICON_DIR, exist_ok=True)
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, 32, 32)
    draw_squircle(cairo.Context(surf), color, badge, style)
    surf.write_to_png(path)
    return key


def render_launcher_icon(path, size=128):
    """Render the app-grid/launcher icon (blue squircle) at the given size."""
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    ctx = cairo.Context(surf)
    ctx.scale(size / 32.0, size / 32.0)
    draw_squircle(ctx, COLORS["needs-input"], 0, "filled")
    surf.write_to_png(path)


def top_bar_is_light():
    try:
        out = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
            capture_output=True, text=True, timeout=2).stdout
        return "prefer-dark" not in out
    except Exception:
        return False


def play(sound):
    try:
        subprocess.Popen(["paplay", sound], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


class TrayApp:
    def __init__(self):
        self.session_states = {}
        self.current_key = None
        self.first_tick = True
        self.pulse_flip = False

        self.ind = AppIndicator.Indicator.new(
            "claude-tray", "", AppIndicator.IndicatorCategory.APPLICATION_STATUS)
        self.ind.set_icon_theme_path(ICON_DIR)
        self.ind.set_status(AppIndicator.IndicatorStatus.ACTIVE)

        menu = Gtk.Menu()
        self.status_item = Gtk.MenuItem(label="Claude: idle")
        self.status_item.set_sensitive(False)
        menu.append(self.status_item)
        menu.append(Gtk.SeparatorMenuItem())
        for label, cb in (
            ("Focus VSCode", self.focus_vscode),
            ("Open log", self.open_log),
            ("Clear stuck sessions", self.clear_sessions),
        ):
            item = Gtk.MenuItem(label=label)
            item.connect("activate", cb)
            menu.append(item)
        menu.append(Gtk.SeparatorMenuItem())
        quit_item = Gtk.MenuItem(label="Exit")
        quit_item.connect("activate", Gtk.main_quit)
        menu.append(quit_item)
        menu.show_all()
        self.ind.set_menu(menu)

        self.set_icon("idle", COLORS["idle"], 0, "outline", "idle/0/outline")
        GLib.timeout_add(1000, self.tick)
        log("tray app started (linux gradient-squircle icon set)")

    def set_icon(self, state, color, badge, style, key):
        name = render_icon(key.replace("/", "-"), color, badge, style)
        self.ind.set_icon_full(name, "Claude status")
        self.current_key = key

    def get_sessions(self):
        sessions = []
        if not os.path.isdir(SESSIONS_DIR):
            return sessions
        now = time.time()
        for fn in os.listdir(SESSIONS_DIR):
            if not fn.endswith(".json"):
                continue
            fp = os.path.join(SESSIONS_DIR, fn)
            try:
                if now - os.path.getmtime(fp) > 24 * 3600:
                    os.unlink(fp)     # crashed session never got SessionEnd
                    continue
                with open(fp, encoding="utf-8") as f:
                    data = json.load(f)
                if data.get("state") in COLORS:
                    sessions.append({
                        "id": fn[:-5],
                        "state": data["state"],
                        "project": str(data.get("project") or ""),
                    })
            except (OSError, ValueError):
                continue  # mid-write or malformed; next tick picks it up
        return sessions

    def tick(self):
        try:
            self.update()
        except Exception as e:
            log("tick error: %r" % (e,))
        return True

    def update(self):
        sessions = self.get_sessions()

        new_states, play_done, play_input = {}, False, False
        for s in sessions:
            new_states[s["id"]] = s["state"]
            prev = self.session_states.get(s["id"])
            if s["state"] != prev:
                if s["state"] == "done":
                    play_done = True
                elif s["state"] == "needs-input":
                    play_input = True
                log("session %s [%s]: %s -> %s" % (s["id"][:8], s["project"], prev or "", s["state"]))
        for sid in self.session_states:
            if sid not in new_states:
                log("session %s: ended" % sid[:8])
        self.session_states = new_states

        needs = [s for s in sessions if s["state"] == "needs-input"]
        done = [s for s in sessions if s["state"] == "done"]
        working = [s for s in sessions if s["state"] == "working"]

        top = "idle"
        if needs:
            top = "needs-input"
        elif done:
            top = "done"
        elif working:
            top = "working"

        actionable = len(needs) + len(done)
        badge = actionable if actionable >= 2 else 0

        color, style, variant = COLORS[top], "filled", "filled"
        if top == "idle":
            style = variant = "outline"
        elif top == "needs-input":
            self.pulse_flip = not self.pulse_flip
            if self.pulse_flip:
                if top_bar_is_light():
                    color, variant = PULSE_ALT_LIGHT, "alt-deep"
                else:
                    color, variant = PULSE_ALT_DARK, "alt-lite"

        key = "%s/%d/%s" % (top, badge, variant)
        if key != self.current_key:
            self.set_icon(top, color, badge, style, key)

        if not sessions:
            tip = "Claude: idle"
        elif len(sessions) == 1:
            s = sessions[0]
            tip = "Claude: " + s["state"] + (" - " + s["project"] if s["project"] else "")
        else:
            parts = []
            if needs:
                parts.append("%d need input" % len(needs))
            if done:
                parts.append("%d done" % len(done))
            if working:
                parts.append("%d working" % len(working))
            tip = "Claude: " + ", ".join(parts)
        self.status_item.set_label(tip)
        self.ind.set_title(tip)

        if not self.first_tick:
            if play_input:
                play(SOUND_INPUT)
            elif play_done:
                play(SOUND_DONE)
        self.first_tick = False

    def focus_vscode(self, _item):
        for cmd in (["wmctrl", "-a", "Visual Studio Code"],
                    ["xdotool", "search", "--name", "Visual Studio Code", "windowactivate"]):
            try:
                if subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                    return
            except FileNotFoundError:
                continue

    def open_log(self, _item):
        subprocess.Popen(["xdg-open", LOG_FILE])

    def clear_sessions(self, _item):
        try:
            for fn in os.listdir(SESSIONS_DIR):
                if fn.endswith(".json"):
                    os.unlink(os.path.join(SESSIONS_DIR, fn))
            log("sessions cleared manually")
        except OSError as e:
            log("clear error: %r" % (e,))


def main():
    # utility mode used by install.sh to produce the app-grid launcher icon
    if len(sys.argv) >= 3 and sys.argv[1] == "--make-icon":
        render_launcher_icon(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 128)
        return

    # single instance via an exclusive lock
    lock = open(os.path.join(BASE, ".tray.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit(0)
    TrayApp()
    Gtk.main()
    log("tray app exited")


if __name__ == "__main__":
    main()
