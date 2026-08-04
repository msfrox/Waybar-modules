# Handoff

**State: all six planned phases shipped and running live on RUBY2.**
Repo: `msfrox/Waybar-modules` (public). Everything is symlinked into `~/.config` by
`install.sh`, so editing the repo edits the live desktop.

## Resume

```bash
cd ~/Projects/Waybar-modules && ./install.sh
```

Reload after a change: `~/.config/waybar/launch.sh` for bar changes; Quickshell hot-reloads
QML on save, so panels need nothing.

## What exists

| Waybar module | Opens | Source |
|---|---|---|
| `pulseaudio` | audio panel (sliders, devices, Easy Effects) | `quickshell/AudioApp` |
| `bluetooth` | BlueZ panel | `quickshell/BluetoothApp` |
| `network` | NetworkManager panel + connection details + Tailscale | `quickshell/NetworkApp` |
| `image#claude-usage` | usage panel | `quickshell/ClaudeUsageApp` |
| `custom/controlcenter` | Control Center | `quickshell/ControlCenterApp` |
| `clock` | ML4W's calendar, re-anchored bottom-right | ML4W's, patched |
| `custom/appmenu` | app launcher, now centre of the bar | ML4W's |

Backends in `waybar/scripts/`: `claude-usage.py`, `network-details.py`, `system-stats.py`,
`easyeffects-status.py`.

## Live gotchas

- **`~/.config/waybar/config` does not exist.** The live pair comes from
  `~/.config/ml4w/settings/waybar-theme.sh` → `~/.config/waybar/themes/ml4w-modern/`.
  Confirm with `ps aux | grep '[w]aybar -c'`.
- **ML4W-owned files are patched in place, not shipped**: `modules.json`, the theme
  `config` and `style.css`, plus `CustomTheme/Theme.qml`, `CalendarApp/`, `PowerApp/`,
  `SidebarApp/` and `shell.qml` under `~/.config/quickshell/`. An ML4W update can clobber
  any of them — `docs/quickshell-patches.md` records what to reapply.
- **Frosted glass is two halves.** Alpha in the QML fill *and* the
  `quickshell-frosted-glass` layer rule in `~/.config/hypr/shehan/theming.lua`. Blur is
  invisible over a flat backdrop; prove the rule with a temporary `dim_around = true`.
- **`nm-applet` and `blueman` are masked** via `Hidden=true` in `~/.config/autostart/`.
  That also removed NetworkManager's secret agent and BlueZ's pairing agent — see
  `BACKLOG.md`.
- **Commit authorship is enforced** by `.githooks/commit-msg`, enabled through
  `core.hooksPath`. `install.sh` sets it; a fresh clone needs it set again.

## Known-not-done

See `BACKLOG.md` — it now has a **"Next session — queued, in order"** list. Top of it:

1. **The notification list itself** in the Control Center. Today it shows the count, DND
   state and a button to swaync's own panel. Showing the notifications means Quickshell
   must become the notification daemon: only one process can own
   `org.freedesktop.Notifications`, and swaync exposes no way to enumerate its list. That
   is `NotificationServer` for the list and actions, toast popups to replace the ones
   swaync draws, and disabling swaync — a phase, not a patch.
2. Media player section (lift ML4W's sidebar Mpris bindings), then drop `custom/nowplaying`.
3. Light/dark toggle, colour picker and screenshot as quick actions (commands already exist
   in ML4W's sidebar).

Also outstanding: a replacement NetworkManager secret agent / BlueZ pairing agent, and
per-app volume streams.
