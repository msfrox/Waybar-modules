# Waybar Modules

A set of Waybar modules and Quickshell popups for a Hyprland desktop, built to close the
gap between Waybar's text-only modules and the polished popup UIs that full desktop
environments ship with.

Waybar is excellent at putting information *on* a bar. It is deliberately bad at anything
that needs a panel: its modules are GTK widgets fed by text or JSON, it cannot host a
foreign Wayland surface, and its only interaction surfaces are a click handler and a
tooltip. So every module here that needs more than a label pairs a thin Waybar module with
a [Quickshell](https://quickshell.org/) layer-shell window that Waybar toggles over IPC.

Built against Hyprland + Waybar 0.15 on top of the
[ML4W dotfiles](https://github.com/mylinuxforwork/dotfiles), but nothing here is
ML4W-specific beyond the install paths.

## What's in here

| Module | Waybar side | Panel side |
|---|---|---|
| **Audio** | `pulseaudio` | Output/input sliders and mute, per-device switching, Easy Effects preset control |
| **Bluetooth** | `bluetooth` | Adapter toggle, connect/pair/forget, device battery — native BlueZ, no tray applet |
| **Network** | `network` | Wi-Fi list with inline PSK entry, connection details (IP, link rate, frequency), Tailscale status |
| **Claude usage** | `image` module rendering a two-window dial | Usage breakdown and display options |
| **Control Center** | one button | Calendar, live system usage, quick actions, pending updates, the system tray |

Docs: [audio / bluetooth / network](docs/audio-bluetooth-network.md) ·
[Claude usage](docs/claude-usage.md) · [Control Center](docs/control-center.md) ·
[patches to ML4W's files](docs/quickshell-patches.md)

### The usage dial

Waybar modules are text-only, so a two-window reading had nowhere to go. This one is drawn
and served through Waybar's `image` module: the **outer ring** is the 7-day window, the
**inner pie** is the current 5-hour session in 10% steps. Colours come from Matugen, so it
follows the wallpaper.

## Install

```bash
git clone https://github.com/msfrox/Waybar-modules.git
cd Waybar-modules
./install.sh
```

`install.sh` symlinks `waybar/scripts/` and `quickshell/` into `~/.config/`, enables the
repo's git hooks, and prints the JSON and CSS snippets that need merging into your own
`modules.json`, bar `config`, and `style.css` — it does not edit those files for you,
because they are yours.

## Requirements

- Hyprland (for `HyprlandFocusGrab` and the `hyprctl` layer queries)
- Waybar 0.15+
- Quickshell 0.3+
- Python 3 with `pycairo` (usage dial rendering)
- Optional: `nmcli` for connection details, `tailscale`, `easyeffects`
- A Nerd Font and Material Symbols for the glyphs

## Licence

MIT — see [LICENSE](LICENSE).

---

Parts of this project were written with the help of a large language model. The design
decisions, the testing, and the maintenance are mine.
