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
- **Bluetooth battery on the bar**, not only in the panel.
- **A player switcher in the Media section.** It currently shows the first playing player
  and falls back to the first player at all. With Spotify, Firefox and AudioTube all
  registered at once that is a guess, not a choice.
- **Notification history across restarts.** Deliberately not persisted today — swaync did
  not either, and a list restored from before a reboot is noise. Revisit if it is missed.
- **Inline replies.** The server advertises `inlineReplySupported` and `Notification`
  carries `hasInlineReply` / `inlineReplyPlaceholder` / `sendInlineReply()`, but nothing
  draws the field yet.

## Control Center

- Migrate the quicklinks drawer.
- `custom/nowplaying` **stays on the bar** by the owner's call, alongside the Control
  Center's Media section rather than replaced by it — the bar module is the at-a-glance
  read, the section is the one with transport controls and album art.
- Per-core CPU and a short history sparkline — the one thing COSMIC's Minimon applet has
  that nothing here does.
- Remember collapsed sections across restarts.

## Usage dial

- Multiple accounts, the way YapCap does. Only one is in play here, so the settings file
  has no account concept at all.
- Other providers (Codex, Cursor, Gemini) — same shape, different endpoint. **Parked by
  the owner: Claude alone is enough for now.**

## Next session — queued, in order

1. **Phase 9, the settings app.** Scope contract is in `PLAN.md`. The one genuinely new
   idea in it is the Waybar section: read `modules.json`, list each key with its current
   value, and choose the control from the value's *type*, so new modules need no new code.
2. **Three more quick actions from ML4W's sidebar**: light/dark toggle, colour picker,
   screenshot. All three are already wired there — copy the commands, not the widgets.
3. **Per-app volume streams** (see above).

### On reusing ML4W's sidebar widgets

Asked whether the brightness sliders needed rebuilding at all. Answer: the *internal* one
did not, and effectively was not — ML4W's sidebar slider shells out to `brightnessctl`
through a `Process`, which is exactly the mechanism used here.

What could not be reused is the **code**: `SidebarWindow.qml` is a single 1021-line file
with its sliders written inline, not extracted as importable components. "Using ML4W's
slider" would mean copying the same ~40 lines out of it — which is what happened, plus a
debounce and a floor at 1%. The genuinely new part is the **external** slider: the sidebar
has no DDC/CI control at all.

Same applies to the three toggles above — lift the *bindings and commands*, not the
widgets. And note ML4W owns that file, so anything left depending on it breaks on their
next update.

The media player went the other way and did not touch the sidebar at all:
`Quickshell.Services.Mpris` is a first-class service, so binding it directly was less work
than lifting anything.

## Housekeeping

- The window chrome (layer config, slide animation, focus grab, IPC) is duplicated across
  six panels now, matching how ML4W's own windows are written. The sixth has arrived —
  factoring it into a shared component is overdue.
- `~/.gitconfig` points `credential.helper` at `gh` **twice** — once as a bare empty value
  and once as the real helper. `gh` *is* installed (`/usr/bin/gh`, authed as `msfrox`),
  so the old "not installed" note was wrong; the stray empty entry is what prints noise.
