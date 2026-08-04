# Audio, Bluetooth and Network panels

Three panels, one story: Waybar's `pulseaudio`, `bluetooth` and `network` modules can each
show a level and run a single command, and that is the whole of their interaction budget.
Anything richer has to live in a window the module opens.

## What they replaced

| Module | Was | Now |
|---|---|---|
| `pulseaudio` | click → `pavucontrol` | click → sliders + device switching; right-click still `pavucontrol` for per-app streams |
| `bluetooth` | click → blueman's tray menu scraped into rofi | click → native BlueZ panel |
| `network` | click → nm-applet's tray menu scraped into rofi | click → native NetworkManager panel |

The rofi approach worked but had two problems. It depended on `blueman-applet` and
`nm-applet` running in the tray — close the tray icon and the module's click did nothing,
with no error — and the menus looked like rofi rather than like the bar.

`Quickshell.Bluetooth` and `Quickshell.Networking` talk to BlueZ and NetworkManager over
DBus directly, so both panels are first-party. `nm-applet` and `blueman` are now masked
with `Hidden=true` overrides in `~/.config/autostart/`.

> [!warning] What the applets also provided
> Both applets registered **agents**: nm-applet was NetworkManager's secret agent and
> blueman was BlueZ's pairing agent. The panels cover the common paths — the wifi PSK
> field passes the secret straight through `connectWithPsk()`, and `pair()` works for
> devices that need no confirmation — but a VPN or 802.1x prompt, or a device that needs a
> PIN confirmed, has nothing to display it. Delete the override in `~/.config/autostart/`
> and log back in to restore either applet.

## Audio

Output and input sliders with the icon as the mute toggle, a radio list of sinks and
sources, and a gear to `pavucontrol`. Per-app stream routing is deliberately not
duplicated — that is what right-click is for.

It also carries an **Easy Effects** block: active/bypassed state, a one-click bypass
toggle, and the output preset list with the current one marked.

EasyEffects is a PipeWire filter chain, so the device list above shows it as a plain
virtual sink named `Easy Effects Sink` with no indication of what it is or which preset it
is running — all of that is only reachable through its own CLI
(`-p` list, `-a output` current, `-l <name>` load, `-b 3` bypass state,
`--bypass-toggle`), which `waybar/scripts/easyeffects-status.py` wraps.

The toggle bypasses rather than quits: quitting drops the filter chain out of the graph
and moves every stream, which is a far bigger hammer than "let me hear it without the
effects for a second".

Two things about `Quickshell.Services.Pipewire` cost real time:

**Filter on the constant members only.** `audio`, `isSink` and `isStream` are declared
constant and are set when the node is constructed, so they read correctly on an untracked
node. `properties` — and therefore `media.class` — is empty until a `PwObjectTracker`
binds the node, which makes filtering on it circular: the tracker's object list is exactly
what the filter feeds. Filtering on `media.class` showed one device (the already-bound
default sink) and no inputs at all.

```qml
readonly property var audioNodes: Pipewire.nodes.values.filter(n => n.audio && !n.isStream)
PwObjectTracker { objects: root.audioNodes }
```

**Short device names come out of `properties["node.nick"]`, for the mirror-image reason.**
`nickname` is also declared constant, so it is captured empty at construction and never
updates. Without it every port on one card renders as
`Core Ultra 200H/200V Series Processors HD Audio HD…`; with it they are `Speaker`,
`HDMI 2`, `LG SDQHD`.

## Bluetooth

Adapter toggle, connected / paired / discovered device lists, battery percentage where the
device reports it, connect / disconnect / pair / forget. Discovery runs only while the
panel is open — it is expensive and it drains peripherals that answer it.

BlueZ publishes a freedesktop icon name per device (`audio-headset`, `input-mouse`); those
are mapped to Material ligatures rather than shipping an icon theme.

## Network

Wi-Fi toggle, network list sorted connected-first then by signal, connect / disconnect /
forget, and an inline password field for a secured network NetworkManager has no saved
secret for. Wired devices appear above with their address.

Below that, two blocks that are **not** in Quickshell's object model:

- **Connection** — IP, gateway, DNS, signal, link rate, frequency, security. Link rate and
  frequency are not in `Quickshell.Networking` at all. These are the facts the bar module's
  hover tooltip used to carry, which vanished when the click started opening a panel.
- **Tailscale** — status, machine name, tailnet, MagicDNS suffix, exit node, peer count,
  and a connect/disconnect action. Tailscale is not a NetworkManager device, so nothing in
  the panel above can see it.

Both come from `waybar/scripts/network-details.py`, which returns one JSON object rather
than scattering `Process` blocks through the QML.

> [!note] `nmcli dev wifi` triggers a radio sweep
> A bare `nmcli dev wifi` blocks for several seconds while the adapter scans, which was
> blowing the script's subprocess timeout and rendering the whole block empty. Pass
> `list --rescan no` — the cached scan is what the panel's own network list already shows.

## Frosted glass

All the popups share the layer-shell namespace `quickshell`, so one Hyprland rule covers
them (see [`quickshell-patches.md`](quickshell-patches.md) and
`~/.config/hypr/shehan/theming.lua`):

```lua
hl.layer_rule({
    name = "quickshell-frosted-glass",
    match = { namespace = "quickshell" },
    blur = true,
    ignore_alpha = 0.2,
    blur_popups = true,
})
```

The translucency has to live in the card's **fill colour**, not in the window's `opacity`
— fading the layer fades the text and the border with it, and a layer rule cannot make an
opaque surface see-through:

```qml
color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.45)
```

`ignore_alpha` matters because the card leaves a 20px fully transparent margin for its drop
shadow; without it Hyprland frosts a 420px-wide rectangle of wallpaper around every popup.

> [!tip] Proving the rule is applied
> Blur is invisible over a flat backdrop, so "it isn't working" is easy to conclude wrongly.
> Temporarily add `dim_around = true` to the rule and reload — if the screen dims when the
> panel opens, the rule is live and the fill is simply too opaque. That is exactly what
> happened here at `0.62`; `0.45` reads as glass.
