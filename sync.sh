#!/usr/bin/env bash
# Deploy the project files into the live omarchy plugin folder.
# The shell hot-reloads on save (no restart needed).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$HOME/.config/omarchy/plugins/max.scene"
mkdir -p "$DST"
for f in manifest.json Scene.qml ConfigPanel.qml omarchy-scene; do
  install -m644 "$SRC/$f" "$DST/$f"
done
chmod +x "$DST/omarchy-scene"
echo "deployed $SRC -> $DST (shell hot-reloads)"
