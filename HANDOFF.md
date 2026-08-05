# Handoff

**State: phases 0–8 shipped and running live on RUBY2.** Repo:
`msfrox/waybar-control-center` (public). Everything is symlinked into `~/.config` by
`install.sh`, so editing the repo edits the live desktop.

## Resume

```bash
cd ~/Projects/waybar-control-center && ./install.sh
```

Reload after a change: `~/.config/waybar/launch.sh` for bar changes. Quickshell hot-reloads
QML on save, but **not reliably through the repo symlinks** — if a QML edit appears to do
nothing, `pkill -x qs` and relaunch `qs -d` before believing the change is wrong.

## What exists

| Waybar module | Opens | Source |
|---|---|---|
| `pulseaudio` | audio panel (sliders, devices, Easy Effects) | `quickshell/AudioApp` |
| `bluetooth` | BlueZ panel | `quickshell/BluetoothApp` |
| `network` | NetworkManager panel + connection details + Tailscale | `quickshell/NetworkApp` |
| `image#claude-usage` | usage panel | `quickshell/ClaudeUsageApp` |
| `custom/controlcenter` | Control Center | `quickshell/ControlCenterApp` |
| `clock` | notification centre — clock, calendar, notification list | `quickshell/NotificationCenterApp` |
| `custom/appmenu` | app launcher, centre of the bar | ML4W's |

Backends in `waybar/scripts/`: `claude-usage.py`, `network-details.py`, `system-stats.py`,
`easyeffects-status.py`, `brightness.py`.

IPC targets: `qs ipc show`. The ones this repo owns are `audio`, `bluetooth`, `network`,
`claude-usage`, `control-center`, `notifications`, `notification-state`.

## Live gotchas

- **`~/.config/waybar/config` does not exist.** The live pair comes from
  `~/.config/ml4w/settings/waybar-theme.sh` → `~/.config/waybar/themes/ml4w-modern/`.
  Confirm with `ps aux | grep '[w]aybar -c'`.
- **ML4W-owned files are patched in place, not shipped**: `modules.json`, the theme
  `config` and `style.css`, plus `CustomTheme/Theme.qml`, `PowerApp/`, `SidebarApp/` and
  `shell.qml` under `~/.config/quickshell/`. An ML4W update can clobber any of them —
  `docs/quickshell-patches.md` records what to reapply. (`CalendarApp/` is no longer used.)
- **Quickshell owns `org.freedesktop.Notifications`.** swaync is installed but killed at
  login by `~/.config/hypr/shehan/notifications.lua`. If notifications stop arriving, check
  the owner first — `docs/notifications.md` has the one-liner, and explains why the kill is
  a race with a load-bearing `sleep`.
- **Never put a `gradient:` on a card Rectangle.** A QML gradient is a *fill*: it paints the
  whole card, and a translucent rectangle inset inside it then composites against the
  gradient instead of the wallpaper. Every panel here was opaque for months because of it.
  Test by setting the fill alpha to `0.0` — if the card looks identical, it was never
  see-through. Cards are now one Rectangle: translucent fill + hairline `border`.
- **Frosted glass is still two halves.** Alpha in the QML fill *and* the
  `quickshell-frosted-glass` layer rule in `~/.config/hypr/shehan/theming.lua`.
- **Material Icons ligatures break inside a Controls `Button`** — it propagates its own font
  onto `contentItem`, so `text: "close"` renders the literal word. Use a plain `Text` +
  `MouseArea`. The installed family is **Material Icons Round**; *Material Symbols Rounded*
  is not installed and fails the same silent way.
- **`highlighted` is FINAL on `Button`.** Shadowing it does not warn — it fails the entire
  Quickshell config to load, with the error pointing at the property rather than the cause.
- **Never call `StatusNotifierItem.display()` from a focus-grabbed panel.** It opens a
  separate compositor surface; taking focus clears the `HyprlandFocusGrab`, which closes
  the panel and the menu with it. Symptom: right-click does nothing, log is clean. Draw the
  menu inline off `QsMenuOpener` instead. `QsMenuEntry` is activated by emitting its
  `triggered` signal — there is no callable `activate()`.
- **`pkill -f <pattern>` matches the shell running it** if the pattern appears in that
  shell's own command line. Cost a terminal twice today. Use `pkill -x`.
- **`nm-applet` and `blueman` are masked** via `Hidden=true` in `~/.config/autostart/`.
  That also removed NetworkManager's secret agent and BlueZ's pairing agent — see
  `BACKLOG.md`.
- **Commit authorship is enforced** by `.githooks/commit-msg`, enabled through
  `core.hooksPath`. `install.sh` sets it; a fresh clone needs it set again.

## Settings files this repo writes

| Path | Holds |
|---|---|
| `~/.config/waybar-control-center/claude-usage.json` | usage dial display options |
| `~/.config/waybar-control-center/notifications.json` | DND flag |
| `~/.config/waybar-control-center/control-center.json` | per-section collapse state |
| `~/.cache/waybar-control-center/notification-history.json` | notification history across restarts (capped at 50) |

These are what phase 9's settings app will edit. Each panel already watches its own file
through a `FileView`, so the settings app never has to talk to the running shell.

## The settings app

`settings/` — a standalone **GTK4/libadwaita** app, not a Quickshell panel.
`install.sh` symlinks it to `~/.local/bin/waybar-control-center-settings` and installs a
`.desktop` entry; the Control Center's **Settings** quick action opens it.

```bash
waybar-control-center-settings --page waybar
```

It edits the files above and nothing else — no IPC, no daemon. Requires
`python-gobject`, `gtk4`, `libadwaita`; `install.sh` warns if they are missing.

Read [docs/settings.md](docs/settings.md) before touching it. The two things that will bite:
`modules.json` is JSONC **owned by ML4W** and is edited by targeted text replacement so its
176 comments survive; and it is parsed with a scanner, not a regex, because the regex
version looked correct and silently parsed nothing (real comments in it contain quotes).

## Next

Finish phase 9: Control Center section/quick-action editing is still compiled into the QML,
and Waybar module add/remove/reorder is not implemented — only editing existing keys.

Everything else is in `BACKLOG.md`.
