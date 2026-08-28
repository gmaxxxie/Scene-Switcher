# Scene Switcher

Show the current omarchy scene in the bar with an icon, click to switch
scenes, and manage per-scene plugin sets from a centered configuration panel.

Scenes let you switch your bar/plugin set by occasion — Development at a
cafe, Focus at a desk — with one click or keypress instead of editing
`shell.json` every time.

## Features

- **Bar widget** — current scene icon + label; left click opens the switch popup
- **Scene switching** — `omarchy-scene set <scene>` applies a scene by
  atomically rewriting `~/.config/omarchy/shell.json` (positions/settings of
  enabled plugins are cached and restored on re-enable)
- **Config panel** — lazy-loaded centered overlay (destroyed on close):
  scene tabs, create/rename/delete (max 5 custom scenes, names ≤10 chars),
  per-scene plugin toggles, lock/unlock buttons, and a preset icon picker
- **Locked plugins** — locked plugins are inherited by every scene (always on);
  omarchy built-ins are listed after user plugins, locked by default and
  following the system state — unlock them to manage manually
- **Keybinding** — `SUPER + SHIFT + S` cycles scenes
- **Menu integration** — optional "Scenes" submenu in the omarchy menu

## Install

```sh
# 1. Install the plugin (from the marketplace URL or this repository)
omarchy plugin add https://github.com/<your-name>/omarchy-scene.git --enable

# 2. Install the companion CLI (the widget delegates to it)
install -Dm755 omarchy-scene "$HOME/.local/bin/omarchy-scene"

# 3. Bootstrap the scene configuration (snapshots your currently enabled set)
omarchy-scene init
```

After `init`, `~/.config/omarchy/scenes/scenes.json` holds the scene
definitions, `entries.json` caches plugin entry snapshots, and
`ui-state.json` is the rendered state the panel's FileView watches.

## Usage

- Click the bar widget (or press `SUPER + SHIFT + S`) to switch scenes
- Click the ⚙ button in the popup to open the configuration panel
- Pick the scene tab, toggle plugins, lock/unlock, set an icon, then Apply

## Configure

```sh
omarchy-scene list                                    # scenes + members
omarchy-scene set <scene>                             # switch (drop --dry-run to apply)
omarchy-scene add <name> --label <label> --icon <glyph>
omarchy-scene toggle-plugin <scene> <plugin-id> on|off
omarchy-scene lock/unlock <plugin-id>                 # inherit everywhere / release
omarchy-scene icon <scene> <glyph>                    # empty glyph clears the icon
omarchy-scene menu-add / menu-remove                  # bar menu submenu
```

## Keybinding

The widget installs `SUPER + SHIFT + S` -> `omarchy-scene cycle` in
`~/.config/hypr/bindings.lua`; remove that line to uninstall the binding.

## Remove

```sh
omarchy plugin remove max.scene
rm -rf ~/.config/omarchy/scenes           # scene config (optional)
rm -f ~/.local/bin/omarchy-scene          # companion CLI (optional)
```

## Security

The plugin and its CLI run unsandboxed with your user permissions. The CLI
only calls `omarchy plugin enable/disable`, rewrites `~/.config/omarchy/`
files atomically (backing up `shell.json` before each switch), and issues a
reload query to the running shell. It never uses `sudo`, starts no extra
Quickshell process, and sends no network traffic.

## License

MIT — see [`LICENSE`](LICENSE).