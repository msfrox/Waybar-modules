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
for base in "${XDG_CONFIG_HOME:-$HOME/.config}" "${XDG_CACHE_HOME:-$HOME/.cache}"; do
  if [ -d "$base/waybar-modules" ] && [ ! -e "$base/waybar-control-center" ]; then
    mv "$base/waybar-modules" "$base/waybar-control-center"
    ok "migrated $base/waybar-modules -> waybar-control-center"
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
  [ -e "$src" ] || continue
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
