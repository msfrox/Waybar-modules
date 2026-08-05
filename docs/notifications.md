# Notifications

Quickshell owns `org.freedesktop.Notifications` on this machine. swaync is installed but
killed at login.

## Why swaync had to go

The layout wanted was one surface holding a large clock, a calendar, and the notification
list, opened by clicking the bar's clock. swaync cannot express that. Its control centre
takes a fixed list of widgets, and on 0.12.6 the complete set is:

```
notifications  title  dnd  label  mpris  buttons-grid  menubar  slider  volume
backlight  inhibitors
```

No clock, no calendar, no plugin API. `label` is static text, not a live clock.

The alternative considered first was two stacked surfaces pretending to be one — a
Quickshell card with clock and calendar, sitting directly above swaync's popup re-anchored
to the bottom right, both toggled by the same click. That was rejected once
`Quickshell.Services.Notifications` turned out to be a complete API rather than a stub:
owning the bus name is less work than co-ordinating two windows, and it makes the whole
thing one card.

## The pieces

| File | Holds |
|---|---|
| `NotificationState.qml` | the `NotificationServer`, the DND flag, arrival times, toast list, and the persisted history. A singleton because the toasts have to keep firing while the panel is closed and unmapped. |
| `NotificationCenterWindow.qml` | the bottom-right panel: clock, calendar, list. IPC target `notifications`. |
| `NotificationToasts.qml` | the top-right popups that replace the ones swaync drew. |
| `NotificationEntry.qml` | one notification, shared by the panel list and the toasts. |

The Control Center's Notifications section and its DND quick action read the same
singleton, so they no longer poll a subprocess.

## Killing swaync

`conf/autostart.lua:46` runs `hl.exec_cmd("swaync")`, and `~/.config/hypr` is a symlink
into `~/.mydotfiles/com.ml4w.dotfiles`, so editing that line gets reverted on the next ML4W
update. `~/.config/hypr/shehan/notifications.lua` (required from `custom.lua`, which loads
last and is never touched by the updater) lets ML4W start swaync and then stops it.

Two things there are load-bearing:

- **The `sleep 4`.** `hl.exec_cmd` is fire-and-forget. The `pkill` has to land after swaync
  has actually execed, or it matches nothing and swaync comes up owning the bus name —
  Quickshell then silently never receives a notification.
- **`pkill -x`, not `pkill -f`.** The pattern `swaync-client` appears in the `sh -c` command
  line running the pkill, so `-f` matches that shell and kills it before it gets there.

Check who owns the name with:

```bash
gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.GetServerInformation
```

`('quickshell', 'quickshell', '', '1.2')` is right. Anything mentioning swaync means the
kill lost the race.

## Behaviour notes

- **Everything is tracked.** A `Notification` is destroyed the moment the `notification`
  signal handler returns unless `tracked` is set, and any reference kept to an untracked one
  dangles. Transient notifications (volume OSDs and the like) are tracked too, then
  dismissed when their toast expires, so they never reach the panel.
- **DND suppresses toasts, not notifications.** The panel still fills up, which is what
  swaync did and what makes DND safe to leave on. The DND flag is persisted
  (`~/.config/waybar-control-center/notifications.json`), and separately, so is the
  notification list itself — up to 50 entries in
  `~/.cache/waybar-control-center/notification-history.json`, debounced and written as
  plain snapshots (a `Notification` cannot be re-injected, so a restored entry is `historic:
  true`, carries no actions, and cannot be replied to).
- **Timeouts** mirror the old swaync config: 2s low, 4s normal, 6s critical, and a
  notification asking for its own timeout gets it. `expireTimeout == 0` means "until
  dismissed" and the toast timer is not armed at all.
- **Hovering a toast holds it open**, otherwise anything with an action button is a race.
- **Arrival times live in the singleton**, keyed by notification id — a `Notification`
  carries no timestamp of its own, so "5m ago" has to be recorded as they land.

## Gotchas that cost time

- **Material Icons ligatures inside a Controls `Button` render as the literal word.**
  `Button` propagates its own `font` onto `contentItem`, overriding the family set there,
  so `text: "close"` came out as the word "close". Glyph buttons are a plain `Text` plus a
  `MouseArea`. Note the installed family is **Material Icons Round** — *Material Symbols
  Rounded* is not installed, and a missing family fails the same silent way.
- **`highlighted` is FINAL on `Button`.** Shadowing it with a custom property does not warn,
  it fails to load the entire Quickshell config.
