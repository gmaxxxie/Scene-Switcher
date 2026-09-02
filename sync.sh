#!/usr/bin/env bash
# Deploy the project files into the live omarchy plugin folder, and
# (re)install the companion CLI into ~/.local/bin — the widget hardcodes
# $HOME/.local/bin/omarchy-scene, so one command must update both.
# NOTE: the running bar widget does NOT hot-reload the new Scene.qml in place —
# run `omarchy-restart-shell` once after deploying so the widget reloads from disk
# (rescanPlugins only re-walks the plugin dirs; it does not rebuild an already-
# running bar widget).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$HOME/.config/omarchy/plugins/max.scene"
mkdir -p "$DST"
for f in manifest.json Scene.qml ConfigPanel.qml omarchy-scene install.sh; do
  install -m644 "$SRC/$f" "$DST/$f"
done
chmod +x "$DST/omarchy-scene" "$DST/install.sh"
install -Dm755 "$SRC/omarchy-scene" "$HOME/.local/bin/omarchy-scene"
echo "deployed $SRC -> $DST"
echo "installed $HOME/.local/bin/omarchy-scene"
echo "NOTE: run 'omarchy-restart-shell' once so the running bar widget reloads the new Scene.qml"
