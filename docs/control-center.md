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
| **System** | `waybar/scripts/system-stats.py` — CPU, memory, swap, disk, temperature, fan RPMs, network rates, uptime, load |
| **Display** | two brightness sliders — internal panel via `brightnessctl`, external monitor via DDC/CI |
| **Quick actions** | Wi-Fi, Bluetooth, mute, do-not-disturb, lock, clipboard, keep-awake, night light, power profile — the bar's old `group/tools` plus the four toggles from swaync's own buttons-grid |
| **Notifications** | count, DND state and the panel toggle, over `swaync-client` |
| **Updates** | `ml4w-check-system-updates`, on its own 30-minute timer |
| **Tray** | `Quickshell.Services.SystemTray` — real StatusNotifierItem icons, `activate()` on left click, the item's own DBus menu on right |

The panel is **bottom-anchored and content-sized**, not full height: a surface pinned to
both vertical edges is mostly empty space on a tall screen and reads as a second desktop
rather than as something the bar opened. It caps at 1300px so a long tray list scrolls.

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
as good. `group/hardware`, `group/tools`, `group/tray` and `custom/updates` have moved; their
definitions are still in `modules.json`, just no longer listed in the theme's `config`, so
putting any of them back is a one-line edit.

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

**The update count is deliberately off the stats tick.** `checkupdates` hits the package
databases and takes seconds; it runs on open and then every 30 minutes, the same cadence
the bar module used. CPU, memory and the tool states are cheap enough for the 2-second
tick.

**Do not reference a nested `id` from the root's `implicitHeight`.** The root binding is
evaluated before the nested object exists, which throws
`ReferenceError: body is not defined` and leaves the window unsized. Push the value up
from the child (`onImplicitHeightChanged: root.bodyHeight = implicitHeight`) instead.

**Bind a `ScrollView`'s content width to the ScrollView by id.** `parent.parent` inside it
resolves to the internal `Flickable`, whose `availableWidth` is not the one that matters —
the column sizes to its own content and hugs the left edge.

**swaync stays the notification daemon.** Only one process can own
`org.freedesktop.Notifications`, so moving the bar's notification button here means a front
end over `swaync-client` (`-c` count, `-D` DND state, `-d` toggle, `-t` open panel) — which
is exactly what `custom/notification` was. Reimplementing a daemon to relocate a button is
the wrong trade.

**Popup transparency matches swaync's**, which defines
`@blur_background: rgba(bg, 0.3)` in its Matugen-generated `colors.css`. Every Quickshell
card here uses the same 0.30 alpha so the two panels look like the same system.

**Tooltips use the `ToolTip` attached property**, gated on the MouseArea's `containsMouse`.
The tiles show their *current state* rather than their name, so without a tooltip there is
nowhere a tile says what it actually is.

**No scroll view.** The panel grows to fit its sections. A control centre you have to
scroll defeats the point — everything in it is meant to be one glance away — and the window
is already sized from the content column's `implicitHeight`, so a scroll view would only
fight it. The remaining cap is a guard against running off the top of the screen.

**Fans come from `sensors -j`, not sysfs.** On this machine the fans sit under a platform
driver that exposes no `fan*_input` files under `/sys/class/hwmon`, so a sysfs sweep finds
nothing while lm-sensors reports both fine. The `acpi_fan` chip is skipped — it duplicates
the first real fan.

**The two brightness sliders are not the same mechanism.** Internal is a sysfs backlight
through `brightnessctl` — instant. External is DDC/CI over the monitor's I2C bus through
`ddcutil`, where a `detect` sweep costs a second or more, so the bus number is cached after
the first detect and writes are debounced: a drag emits a value per pixel and each one
would otherwise be its own I2C round-trip. Internal is floored at 1% — a slider that can
reach 0 leaves you with a black panel and no way to see the slider you need to drag back.

**`mode_fan` is Material *Symbols*, not Material Icons.** The Round font here has no fan
glyph; `toys` (a pinwheel) is the closest that actually renders. A missing ligature renders
as the literal fallback, not as nothing, so it is easy to miss.
