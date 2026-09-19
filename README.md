# OLauncher

A standalone Omarchy shell launcher with a liquid animation for your most-used apps, a unified local search and contextual actions. No Siri, cloud services or telemetry.

![OLauncher: animated quick-launch app circles](media/preview.gif)

## Features

- Press **Tab in an empty search**: up to four app circles flow out of the search field.
- Tab / Shift+Tab or Left / Right selects an app. Enter or a click launches it.
- The circles rank installed apps by **launches through OLauncher**, including launches from search results. They do not monitor other launchers or running windows.
- Before there is history, installed apps fill the slots alphabetically. Rankings update when reopening the launcher; the open rail never rearranges under your cursor.
- Search applications, filenames and arithmetic together. Filters: All, Apps, Files, Calculator.
- Decimal comma, multiplication/division symbols, powers and postfix percentages: `125*1,19` → `148,75`.
- Contextual actions: open, open containing folder, copy path/name/result.
- Commands run only with an explicit `>` prefix and activation.
- Cancelled requests cannot overwrite results for a newer query. File searches time out after 8 seconds.

The current interface language is German. This is an independent Linux launcher inspired by Spotlight, not an Apple product or a pixel-exact macOS implementation.

## Requirements

- Omarchy **Quattro shell / plugin API v1**, Quickshell with Qt 6 Quick Effects, Hyprland.
- `python3`, `fd`, `wl-copy` (wl-clipboard), `xdg-open` (xdg-utils), `gtk-launch` (gtk3) and `uwsm`.
- Node.js is only needed to run the developer tests.
- SF Pro Display is used only if already installed; otherwise the system sans-serif font is used. No Apple fonts or icons are bundled. App icons come from the user's icon theme.

## Install

Install from the public repository:

```bash
omarchy plugin add https://github.com/hisnameismarco/OLauncher.git --enable
```

For a local checkout, copy this repository to `~/.config/omarchy/plugins/OLauncher/`, then enable OLauncher in **Setup → Plugins**. Do not overwrite an existing installation without backing it up.

The plugin ID is `OLauncher`; its displayed name is **OLauncher**.

Open it with:

```bash
omarchy-shell shell toggle OLauncher '{}'
```

You can bind that command using Omarchy's keybinding configuration. Installation does not replace existing shortcuts or modify Hyprland configuration.

### Optional background blur

The launcher works without blur. For the frosted background, enable Hyprland blur and add a layer rule to your user configuration. On Omarchy's Lua configuration:

```lua
hl.layer_rule({
  match = { namespace = "^OLauncher$" },
  blur = true,
  ignore_alpha = 0.3,
})
```

Set `decoration.blur.enabled = true` in your existing `hl.config` settings block. This is a global compositor setting and also enables other configured blur rules. Validate configuration changes with `hyprctl reload` and `hyprctl configerrors`.

## Upgrade from 2.1.x

Version 2.2.0 changes the plugin ID from `marco.spotlight` to `OLauncher`. Back up your old installation, remove the old plugin with `omarchy plugin remove marco.spotlight`, then install OLauncher again using the command above. Update any launcher shortcut to the new ID and replace the old `marco-spotlight` blur namespace with `OLauncher`. Do not leave both versions enabled. The existing `spotlight-usage.json` file is deliberately retained so app rankings survive the rename.

## Controls

| Input | Behavior |
|---|---|
| Tab in an empty search | Reveal / cycle most-used app circles |
| Shift+Tab, Left / Right with circles open | Cycle apps |
| Enter or click an app circle | Launch that app |
| Start typing | Retract circles and search |
| Up / Down, Page Up / Down | Select a search result |
| Tab with search results | Open / cycle contextual actions |
| Ctrl+Left / Right | Change search filter |
| Escape | Close circles/actions → reset filter → clear query → close |
| `>` followed by a command | Explicit shell command mode |

## Data and limitations

Only app IDs and launch counters are saved in `~/.local/state/spotlight-usage.json`. They count launch requests made via this plugin, not whether the launched program ultimately starts successfully. No keystroke/search history is stored or sent anywhere. Reset by removing that file while the shell is stopped, then restart the shell.

Filename search covers non-hidden, non-ignored files under `$HOME`, up to depth 8. It excludes `node_modules` and `.git`, returns up to 40 results from at most 80 candidates and does not search document contents. Missing applications disappear from the quick-launch list. If fewer than four are installed, only available apps are shown.

## Development

```bash
omarchy plugin validate .
node tests/launcher.test.cjs
python3 tests/search_files_test.py
bash scripts/build-shaders.sh
```

Precompiled Qt shader assets are included for installation. `qt6-shadertools` is needed only when rebuilding the shader. Source edits to a kept-loaded instance may require `omarchy restart shell`.

## Remove

```bash
omarchy plugin remove OLauncher
```

Remove any shortcut or blur rule you added yourself. The usage file is retained; remove it separately if desired. The plugin installs no background daemon or global configuration.

## License and acknowledgements

GPL-3.0-only. The liquid morph is adapted from [StatIndet/quickshell](https://github.com/StatIndet/quickshell). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSE](LICENSE). This repository includes source for the modified shader as well as its compiled QSB asset.
