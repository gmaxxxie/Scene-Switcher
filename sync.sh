#!/usr/bin/env bash
# Deploy the project files into the live omarchy plugin folder, and
# (re)install the companion CLI into ~/.local/bin — the widget hardcodes
# $HOME/.local/bin/omarchy-scene, so one command must update both.
# The shell hot-reloads the plugin on save (no restart needed).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$HOME/.config/omarchy/plugins/max.scene"
mkdir -p "$DST"
for f in manifest.json Scene.qml ConfigPanel.qml omarchy-scene install.sh; do
  install -m644 "$SRC/$f" "$DST/$f"
done
chmod +x "$DST/omarchy-scene" "$DST/install.sh"
install -Dm755 "$SRC/omarchy-scene" "$HOME/.local/bin/omarchy-scene"
echo "deployed $SRC -> $DST (shell hot-reloads)"
echo "installed $HOME/.local/bin/omarchy-scene"
