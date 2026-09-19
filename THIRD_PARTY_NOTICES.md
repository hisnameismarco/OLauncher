# Third-party notices

## StatIndet/quickshell

The motion and signed-distance-field surface in `MorphSurface.qml` and `assets/spotlight_mode_field.frag` derive from StatIndet's Quickshell Spotlight implementation.

- Author: StatIndet (u/Stat_Indet)
- Repository: https://github.com/StatIndet/quickshell
- Reference revision inspected: `ac388acf9a4537cf1c69232aceb326af9478b71f`
- Original QML: `Modules/Launcher/SpotlightModeMorphSurface.qml`
- Original shader: `assets/shaders/launcher/frag/spotlight_mode_field.frag`
- Upstream license: GNU General Public License version 3 (see LICENSE).

Modifications for OLauncher: Omarchy integration, configurable surface properties, rounded search field, glass shading, variable app count, app launch targets and usage ranking. Existing upstream explanatory comments are retained in the adapted source. The compiled shader is built from the source shipped here.

## Host and system assets

Quickshell, Qt and Omarchy are runtime dependencies, not vendored. Application icons and optional fonts are resolved from the user's system and are not included in this repository. No Apple artwork, fonts or macOS software is redistributed.
