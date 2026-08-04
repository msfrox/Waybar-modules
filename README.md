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
| **Audio** | `pulseaudio` with a click handler | Volume + input sliders, per-device output/input switching, media controls |
| **Claude usage** | `image` module rendering a two-window usage dial | Usage breakdown, display options, refresh controls |
| **Control Center** | one button | Sliding side panel — calendar, system usage, system tray, quick toggles |
| **Calendar** | `clock` with a click handler | Month view, repositionable |
| **App launcher** | `custom/appmenu` | Hands off to an external launcher |

Each is documented under [`docs/`](docs/).

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
- A Nerd Font and Material Symbols for the glyphs

## Licence

MIT — see [LICENSE](LICENSE).

---

Parts of this project were written with the help of a large language model. The design
decisions, the testing, and the maintenance are mine.
