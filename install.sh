#!/usr/bin/env bash
#
# Scene Switcher — 一键安装（幂等，可重复执行）
#
# 安装三件事：插件本体（omarchy plugin add --enable）、companion CLI
# （~/.local/bin/omarchy-scene，widget 写死的调用路径）、初始化场景配置
# （仅当 scenes.json 尚不存在时，绝不覆盖已有配置）。
#
# 用法：
#   marketplace 一行安装（装完插件目录里就带着本脚本）:
#     omarchy plugin add https://github.com/gmaxxxie/Scene-Switcher.git --enable \
#       && "$HOME/.config/omarchy/plugins/max.scene/install.sh"
#
#   克隆仓库后直接跑:
#     git clone https://github.com/gmaxxxie/Scene-Switcher.git
#     cd Scene-Switcher && ./install.sh [repo-url]
#
set -euo pipefail

REPO_URL="${1:-https://github.com/gmaxxxie/Scene-Switcher.git}"
PLUGIN_ID="max.scene"
PLUGIN_DIR="${OMARCHY_PLUGINS_DIR:-$HOME/.config/omarchy/plugins}/$PLUGIN_ID"
SCENES_FILE="$HOME/.config/omarchy/scenes/scenes.json"
CLI="$HOME/.local/bin/omarchy-scene"

step() { printf '==> %s\n' "$*"; }

if [[ -f "$PLUGIN_DIR/manifest.json" ]]; then
  step "plugin already installed at $PLUGIN_DIR (skipping add)"
else
  step "installing plugin from $REPO_URL"
  omarchy plugin add "$REPO_URL" --enable
fi

if [[ ! -f "$PLUGIN_DIR/omarchy-scene" ]]; then
  echo "install.sh: cannot find $PLUGIN_DIR/omarchy-scene after install — aborting" >&2
  exit 1
fi
step "installing CLI to $CLI"
install -Dm755 "$PLUGIN_DIR/omarchy-scene" "$CLI"

if [[ -f "$SCENES_FILE" ]]; then
  step "scenes.json already exists — keeping your config (omarchy-scene init skipped)"
else
  step "bootstrapping scene config (omarchy-scene init)"
  "$CLI" init
fi

printf '%s\n' "done — click the scene widget or press SUPER + SHIFT + T"