# Backlog

Ideas parked rather than built, so they stay out of the working context.

## Panels

- **Per-app volume streams** in the audio panel. `Quickshell.Services.Pipewire` exposes
  them (`isStream` nodes) and the sliders would be the same component. Deliberately left
  out of v1 so the panel matched what it replaced; right-click still opens `pavucontrol`.
- **A secret agent.** Masking `nm-applet` and `blueman` removed NetworkManager's secret
  agent and BlueZ's pairing agent. The panels cover the common paths (wifi PSK, pairing
  without confirmation) but a VPN prompt, an 802.1x prompt, or a device that needs a PIN
  confirmed has nothing to display it.
- **The notification *list* in the Control Center.** Currently only the count, DND state
  and a button that opens swaync's own panel. Showing the notifications themselves means
  **Quickshell has to become the notification daemon** — only one process can own
  `org.freedesktop.Notifications`, and swaync exposes no way to read its list
  (`swaync-client` has count and DND, no enumeration). That is a real swap:
  `NotificationServer` for the list and actions, plus toast popups to replace the ones
  swaync draws, plus disabling swaync. Its own phase, not a patch.
- **Media controls.** `Quickshell.Services.Mpris` — would replace `custom/nowplaying`.
- **Bluetooth battery on the bar**, not only in the panel.

## Control Center

- Migrate `custom/nowplaying`, `custom/notification` and the quicklinks drawer.
- Per-core CPU and a short history sparkline — the one thing COSMIC's Minimon applet has
  that nothing here does.
- Remember collapsed sections across restarts.

## Usage dial

- Multiple accounts, the way YapCap does. Only one is in play here, so the settings file
  has no account concept at all.
- Other providers (Codex, Cursor, Gemini) — same shape, different endpoint.

## Housekeeping

- The window chrome (layer config, slide animation, focus grab, IPC) is duplicated across
  five panels, matching how ML4W's own windows are written. Factor it into a shared
  component if a sixth appears.
- `~/.gitconfig` still points `credential.helper` at `gh`, which is not installed — every
  push prints two harmless "No such file or directory" lines.
