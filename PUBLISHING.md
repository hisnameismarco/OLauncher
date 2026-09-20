# Marketplace submission draft

Name: OLauncher
Author: marco / hisnameismarco
Repository: https://github.com/hisnameismarco/OLauncher
Category: Productivity
Tags: Launcher, Quickshell, Hyprland
License: GPL-3.0-only

Description:

> A liquid app launcher for Omarchy. Press Tab to reveal your four most-used apps as animated circles, or search apps, filenames and arithmetic in one place. Includes a compact Apps grid with manual ordering, folders and reversible hidden apps, contextual actions, keyboard navigation, local usage ranking and explicit shell commands. No AI or cloud services.

The website requires a public GitHub repository with a root manifest, README and license. Listing approval is separate from publishing the code. Release v2.2.1 includes the complete reviewed App Grid implementation and its tests.

Publishing guide / submission form: https://plugins.omarchy.org/publish.html

The v2.2.1 checkout passed an isolated clean installation using the real Omarchy add/enable/validate/remove commands and a local Git snapshot. Fresh HOME/XDG directories, a private session bus and a copied host isolate production state. Reorder, folder rename, hidden state and usage survive host restart; migration, malformed state and future-schema protection are covered by `tests/clean_install_test.py`. App launch commands are captured at the host execution boundary, without opening real applications. This is a fresh plugin installation on the installed Omarchy runtime, not a second OS installation. See `RELEASE_REVIEW.md` for the pre-publication review and test boundaries.

Earlier isolated runtimes cover dark/light materials, blur-off readability, narrow widths, 1.5× rendering and 2× interaction tests. Both direct Apps payload commands pass in the clean-install host. The animation preview in `media/preview.gif` was recorded on an empty workspace without personal windows.
