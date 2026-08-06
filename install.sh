#!/usr/bin/env bash
# Link this repo's owned files into ~/.config, then print what still needs merging
# by hand into the files this repo does not own.
#
# Idempotent: re-run it after pulling.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAYBAR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
QS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m! %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }

# --- one-time rename migration ---------------------------------------------
# The project used to be called "Waybar-modules", and its settings and cache
# directories were named after it. Move them once so an existing install keeps
# its settings instead of silently falling back to defaults.
#
# Move the *contents*, not the directory: a still-running Waybar script can
# recreate the new directory before this runs, and a plain `mv` of the directory
# would then skip the migration and strand the settings. Existing files in the
# new directory win.
for base in "${XDG_CONFIG_HOME:-$HOME/.config}" "${XDG_CACHE_HOME:-$HOME/.cache}"; do
  old="$base/waybar-modules"
  [ -d "$old" ] || continue
  mkdir -p "$base/waybar-control-center"
  for f in "$old"/* "$old"/.[!.]*; do
    [ -e "$f" ] || continue
    [ -e "$base/waybar-control-center/$(basename "$f")" ] || mv "$f" "$base/waybar-control-center/"
  done
  if rmdir "$old" 2>/dev/null; then
    ok "migrated $old -> $base/waybar-control-center"
  else
    warn "$old still has files the new directory already had — stale cache, safe to delete"
  fi
done

# --- git hooks -------------------------------------------------------------
if [ -d "$REPO/.git" ]; then
  git -C "$REPO" config core.hooksPath .githooks
  ok "git hooks enabled (core.hooksPath = .githooks)"
fi

# --- scripts ---------------------------------------------------------------
mkdir -p "$WAYBAR_DIR/scripts"
for src in "$REPO"/waybar/scripts/*; do
  [ -f "$src" ] || continue   # -f, not -e: python leaves a __pycache__/ directory
                              # in here, and -e linked that into ~/.config too.
  dest="$WAYBAR_DIR/scripts/$(basename "$src")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    warn "$dest exists and is not a symlink — backing up to $dest.bak"
    mv "$dest" "$dest.bak"
  fi
  ln -sfn "$src" "$dest"
  chmod +x "$src"
  ok "linked $(basename "$src")"
done

# --- quickshell apps -------------------------------------------------------
mkdir -p "$QS_DIR"
for src in "$REPO"/quickshell/*/; do
  [ -d "$src" ] || continue
  name="$(basename "$src")"
  dest="$QS_DIR/$name"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    warn "$dest exists and is not a symlink — backing up to $dest.bak"
    mv "$dest" "$dest.bak"
  fi
  ln -sfn "${src%/}" "$dest"
  ok "linked quickshell/$name"
done

# --- keep swaync off the notification bus name -----------------------------
# NotificationCenterApp owns org.freedesktop.Notifications, and only one process
# on the session bus can. swaync is not merely autostarted, it is D-Bus
# ACTIVATABLE: /usr/share/dbus-1/services ships three service files for it
# (org.erikreider.swaync, .cc, and one that — despite its filename — claims
# org.freedesktop.Notifications), and every one of them carries
# SystemdService=swaync.service. So any process that talks to swaync brings the
# daemon back and hands it the bus name, however many times it has been killed.
#
# There is such a process inside our own shell: ML4W's
# ~/.config/quickshell/StatusbarApp/SwayncModule.qml runs `swaync-client -swb`
# to drive its bell icon. That is what silently took notifications back on
# 2026-08-06 — the hypr-side pkill had already run and won, and the statusbar
# re-activated swaync eight seconds later.
#
# Masking the unit makes every activation path fail closed ("The systemd unit
# 'swaync.service' is masked"), which is why this is here and not a pkill. The
# mask is a symlink in ~/.config/systemd/user, so it outlives both a pacman
# update of swaync and an ML4W dotfiles update — the two things that reverted
# earlier attempts. Undo with: systemctl --user unmask swaync.service
#
# ML4W's conf/autostart.lua also execs the swaync binary directly, which walks
# past the mask; ~/.config/hypr/shehan/notifications.lua kills that one. Both
# halves are needed. See docs/notifications.md.
if command -v systemctl >/dev/null 2>&1; then
  if [ "$(systemctl --user is-enabled swaync.service 2>/dev/null)" = "masked" ]; then
    ok "swaync.service already masked"
  elif systemctl --user mask swaync.service >/dev/null 2>&1; then
    ok "masked swaync.service (it can no longer be D-Bus activated)"
  else
    warn "could not mask swaync.service — swaync may steal org.freedesktop.Notifications"
  fi
  systemctl --user stop swaync.service >/dev/null 2>&1 || true
  pkill -x swaync >/dev/null 2>&1 || true

  # Quickshell re-acquires the name when the current owner releases it, so this
  # should read 'quickshell' immediately after the stop above — no restart.
  owner="$(gdbus call --session --dest org.freedesktop.Notifications \
             --object-path /org/freedesktop/Notifications \
             --method org.freedesktop.Notifications.GetServerInformation 2>/dev/null || true)"
  case "$owner" in
    *quickshell*) ok "org.freedesktop.Notifications is owned by Quickshell" ;;
    "")           warn "nothing owns org.freedesktop.Notifications — start the shell: qs -d" ;;
    *)            warn "org.freedesktop.Notifications is owned by: $owner" ;;
  esac
fi

# --- settings app ----------------------------------------------------------
# A standalone GTK4/libadwaita application, NOT a Quickshell window: it is
# opened deliberately, edits the JSON the panels already watch, and costs
# nothing when it is not running. Symlinked rather than copied so editing the
# repo edits the installed app, same as everything else here.
BIN_DIR="$HOME/.local/bin"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$BIN_DIR" "$APPS_DIR"

chmod +x "$REPO/settings/waybar-control-center-settings"
ln -sfn "$REPO/settings/waybar-control-center-settings" \
        "$BIN_DIR/waybar-control-center-settings"
ok "linked waybar-control-center-settings -> $BIN_DIR"

ln -sfn "$REPO/settings/waybar-control-center-settings.desktop" \
        "$APPS_DIR/waybar-control-center-settings.desktop"
ok "linked the .desktop entry"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on your PATH — the Control Center's Settings tile will not find it" ;;
esac

if ! python3 -c 'import gi; gi.require_version("Adw", "1")' 2>/dev/null; then
  warn "python-gobject with libadwaita is missing — the settings app will not start"
  warn "  install: python-gobject libadwaita gtk4"
fi

# --- things you have to merge yourself -------------------------------------
cat <<EOF

$(bold "Manual steps")

These files belong to your bar, not to this repo, so nothing here edits them:

  1. Module definitions  ->  $WAYBAR_DIR/modules.json
     merge the snippets in  $REPO/waybar/modules/

  2. Module placement    ->  your active theme's 'config'
     find it with:  ps aux | grep '[w]aybar -c'

  3. Styling             ->  that theme's 'style.css'
     append the snippets in  $REPO/waybar/style/

  4. Quickshell windows  ->  $QS_DIR/shell.qml
     import and instantiate each linked app, e.g.

         import "AudioApp"
         ...
         AudioWindow {}

Then reload:  $WAYBAR_DIR/launch.sh  &&  qs kill; qs -d
EOF
