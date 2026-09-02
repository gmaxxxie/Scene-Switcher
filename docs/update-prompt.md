# Update Scene Switcher with an AI agent

Standalone copy of the prompt from the README's *Update with an AI agent*
section. Hand it to any coding agent (pi, OpenCode, Codex, …) running on the
machine where the plugin is installed.

It runs the exact one-command update, keeps your `scenes.json`, and verifies
the result. Two hard constraints are baked into the prompt on purpose:
**never remove & reinstall the plugin**, and **stop and report instead of
guessing**.

## English prompt

> Update the omarchy plugin `max.scene` (Scene Switcher) to the latest
> version.
>
> 1. Check current state: run `md5sum` on
>    `~/.config/omarchy/plugins/max.scene/omarchy-scene` and
>    `~/.local/bin/omarchy-scene`, and `grep version` on
>    `~/.config/omarchy/plugins/max.scene/manifest.json`.
> 2. Update the plugin files: `omarchy plugin update max.scene --yes`.
> 3. Reinstall the companion CLI:
>    `"$HOME/.config/omarchy/plugins/max.scene/install.sh"` (idempotent —
>    skips `add` and `init`, never touches `scenes.json`).
> 4. Re-run the checks from step 1 and confirm the two md5s match and the
>    version is the latest; report both outputs back.
>
> Constraints: never remove/reinstall the plugin (`omarchy plugin remove` is
> forbidden), preserve `scenes.json`, and if any step errors, stop and paste
> the error instead of guessing. No shell restart is needed unless the
> update touched `Scene.qml`/`ConfigPanel.qml`.

## 中文 prompt

> 请把 omarchy 插件 `max.scene`（Scene Switcher）更新到最新版。
>
> 1. 先检查当前状态：对
>    `~/.config/omarchy/plugins/max.scene/omarchy-scene` 和
>    `~/.local/bin/omarchy-scene` 运行 `md5sum`，并对
>    `~/.config/omarchy/plugins/max.scene/manifest.json` 运行
>    `grep version`。
> 2. 更新插件文件：`omarchy plugin update max.scene --yes`。
> 3. 重装 companion CLI：
>    `"$HOME/.config/omarchy/plugins/max.scene/install.sh"`（幂等——跳过
>    `add` 和 `init`，绝不改动 `scenes.json`）。
> 4. 重跑第 1 步的检查，确认两个 md5 一致、版本为最新，并把两处输出贴回来。
>
> 约束：禁止删除重装插件（不得执行 `omarchy plugin remove`），必须保留
> `scenes.json`；任何一步报错就停下并把错误贴回来，不要自己猜测。除非本次更新
> 改动了 `Scene.qml`/`ConfigPanel.qml`，否则无需重启 shell。

## Expected result

| Check | Success |
|---|---|
| `md5sum` of the two `omarchy-scene` copies | identical |
| `grep version` in the plugin `manifest.json` | latest (see repo releases) |
| `~/.config/omarchy/scenes/scenes.json` | untouched, still present |

See [../README.md](../README.md) for the full install / update / configure
docs.
