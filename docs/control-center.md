# Control Center

A full-height panel that slides in from the right, holding the things a bar is a
bad home for.

![position: right edge, full height, above the bar]

## Why

The bar had accumulated three hover-out drawers — a hardware group (CPU/memory/disk), a
tools group, and a tray drawer. Drawers are a reasonable shortcut and a poor home:

- they are invisible until you already know they exist,
- they close the moment the pointer leaves, so you cannot read and act,
- each one still costs permanent width on a bar that also wants a taskbar.

Waybar cannot express a panel — its modules are GTK widgets fed text, with one click
handler and one tooltip each. So the panel is a Quickshell layer-shell window and the bar
keeps one button.

## What it holds today

| Section | Source |
|---|---|
| **Calendar** | month grid, independent of the bar's clock popup |
| **System** | `waybar/scripts/system-stats.py` — CPU, memory, swap, disk, temperature, network rates, uptime, load |
| **Tray** | `Quickshell.Services.SystemTray` — real StatusNotifierItem icons, `activate()` on left click, the item's own DBus menu on right |

The point of the first version is the **frame**, not the contents. Anything added later
drops into a `Section`:

```qml
Section {
    title: "Media"
    glyph: "music_note"

    // ...anything. It inherits the panel's spacing and collapse behaviour.
}
```

## Migrating a module off the bar

Incremental on purpose — a module stays on the bar until its replacement here is at least
as good. `group/hardware` and `group/tray` have moved; their definitions are still in
`modules.json`, just no longer listed in the theme's `config`, so putting them back is a
one-line edit.

1. Build the section here and check it live.
2. Remove the module from `modules-left/center/right` in the theme's `config`.
3. Leave its definition in `modules.json`.

## Notes from building it

**`Quickshell.Services.SystemTray` is a real tray host**, not a screenshot of one.
`SystemTray.items` gives `icon`, `title`, `tooltipTitle`, `hasMenu`, `onlyMenu`, plus
`activate()`, `secondaryActivate()` and `display(parentWindow, x, y)` — the last of which
pops the application's own DBus menu. An item with `onlyMenu` has no activate action at
all, so left-clicking it has to open the menu too, which is what a real tray does.

**Two of the system figures are rates and need two samples.** `/proc/stat` counts jiffies
since boot, so reading it once gives average utilisation since power-on — a number that
barely moves. CPU is therefore sampled inline over 0.2s. Network counters are cumulative
bytes, and a 0.2s window is far too short to characterise throughput, so those are
differenced against the previous invocation through a cache file. A cache older than 60s
is discarded rather than divided, since averaging a huge byte delta over a huge elapsed
time produces a plausible-looking number that describes nothing.

**Memory uses `MemAvailable`, not `MemFree`.** Linux spends everything spare on cache, so
`MemFree` on a healthy machine is alarmingly small and means nothing.

**A `MouseArea` cannot be anchored inside a `Layout`.** Qt warns
`Detected anchors on an item that is managed by a layout`, and the click target silently
misbehaves. Wrap the row in a plain `Item` and anchor inside that.

**Guard bindings against the first frame.** `visible: stats.memory && stats.memory.swap_total > 0`
evaluates to `undefined` before the first stats read, and `undefined` is not assignable to
`bool`. Coerce with `!!(...)`.
