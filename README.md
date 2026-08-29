# Scene Switcher

Show the current omarchy scene in the bar with an icon, click to switch
scenes, and manage per-scene plugin sets from a centered configuration panel.

Scenes let you switch your bar/plugin set by occasion — Development at a
cafe, Focus at a desk — with one click or keypress instead of editing
`shell.json` every time.

## Screenshots

![Scene switch popup](screenshots/scene-popup.png)

![Configuration panel](screenshots/scene-config-panel.png)

## Features

- **Bar widget** — current scene icon + label; left click opens the switch popup
- **Scene switching** — `omarchy-scene set <scene>` applies a scene by
  atomically rewriting `~/.config/omarchy/shell.json` (positions/settings of
  enabled plugins are cached and restored on re-enable)
- **Config panel** — lazy-loaded centered overlay (destroyed on close):
  scene tabs, create/rename/delete (max 5 custom scenes, names ≤10 chars),
  per-scene plugin toggles, lock/unlock buttons, and a preset icon picker
  (30 icons) for each scene
- **Refresh plugins** — a ⟳ button at the top-right of the plugin list
  (next to the "User plugins" header) rescans the plugin registry, so plugins
  newly installed through `omarchy plugin add`/`clone` appear immediately
- **Status echo** — each row shows the plugin's effective state: locked
  plugins and omarchy built-ins follow the system default; plugins in a scene
  show the scene switch state; unmanaged (new) plugins echo their system
  default on/off
- **Locked plugins** — locked plugins are inherited by every scene (always on);
  omarchy built-ins are listed after user plugins, locked by default and
  following the system state — unlock them to manage manually
- **Keybinding** — `SUPER + SHIFT + S` cycles scenes
- **Menu integration** — optional "Scenes" submenu in the omarchy menu

## Install

Requires `python3` (stdlib only — used for the descriptor-bound secure I/O core).

```sh
# 1. Install the plugin (from the marketplace URL or this repository)
omarchy plugin add https://github.com/gmaxxxie/Scene-Switcher.git --enable

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

All file I/O is **descriptor-bound** — there is no check-then-open anywhere:

- Every read opens the path **once** via `openat(2)`, walking each path
  component with `O_NOFOLLOW` (`O_DIRECTORY` on intermediate directories),
  then validates with `fstat(2)`: regular file, owned by the current user,
  size ≤ 8 MiB. Reads use `O_NONBLOCK` + `S_ISREG` so a hostile FIFO at a
  config path can never block the CLI. A symlink pointed at a config path
  (or any component of it) is refused with `ELOOP`, and the validated bytes
  are captured from that descriptor — later tools (`jq`/`awk`/`sed`/`grep`)
  only ever consume the in-memory content via stdin, never the mutable
  pathname.
- Writes create a random temp file in the **same directory** as the target
  with `O_CREAT|O_EXCL` and keep its descriptor open for the whole
  create → write → validate → `fchmod` → `fsync` → atomic `rename(2)`
  sequence (rename bound to the validated parent-directory descriptor, so a
  directory switch mid-operation cannot redirect the publish). The temp
  pathname is never reopened by `cat`/`stat`/`chmod`/`sync`.
- Backups copy descriptor-to-descriptor into a random `O_EXCL` name in the
  same directory (timestamp + random suffix) — no predictable paths, no
  collisions.
- Mutating commands hold an `flock(2)`-based mutex whose lock file is opened
  atomically (`O_CREAT` + `O_NOFOLLOW`) and whose holder dies with its parent
  (`PR_SET_PDEATHSIG`), so a crashed CLI never leaves a stale lock.
- Structural limits are enforced on the validated read before anything is
  emitted to QML: 8 MiB byte cap, JSON depth ≤ 32, strings ≤ 4096 chars,
  array/object member counts ≤ 65536; `scenes.json` — at most 12 scenes,
  scene keys ≤ 10 chars (`[a-zA-Z0-9_-]`), labels ≤ 64 chars, icons ≤ 4
  chars, plugin lists ≤ 256 entries, plugin ids
  `^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$`; `entries.json` ≤ 4096 records;
  catalog-derived fields (`name` ≤ 128, `id` ≤ 64, `kinds` ≤ 16×32); menu
  actions are bounded by the scene-key limit.
- Each scene remembers its exact bar layout (`_layouts` snapshots), so
  switching default ↔ dev restores the arrangement precisely every time and
  unmanaged built-in widgets (wifi/ai/audio/monitor/power, …) are never
  pushed out of place by index drift.

## Development

This repository is the source of truth. The live plugin folder
(`~/.config/omarchy/plugins/max.scene`) is a deployed copy — edit here, then
deploy (the shell hot-reloads on save):

```sh
./sync.sh          # copy the runtime files to the live folder
bash tests/run-tests.sh   # security/regression suite (97 checks)
omarchy plugin validate .   # spec validation before pushing
```

The test suite covers symlink rejection, TOCTOU swap races, FIFO
non-blocking, oversized files, concurrent writers, backup collisions, menu
shell-injection attempts, structural limit enforcement, lock safety, and
byte-level round-trips — all in a sandboxed fake `$HOME` with stubbed
`omarchy`/`omarchy-shell` binaries.

## License

MIT — see [`LICENSE`](LICENSE).