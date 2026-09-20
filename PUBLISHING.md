# Marketplace submission draft

Name: OLauncher
Author: marco / hisnameismarco
Repository: https://github.com/hisnameismarco/OLauncher
Category: Productivity
Tags: Launcher, Quickshell, Hyprland
License: GPL-3.0-only

Description:

> A liquid app launcher for Omarchy. Press Tab to reveal your four most-used apps as animated circles, or search apps, filenames and arithmetic in one place. Includes a compact Apps grid with manual ordering, folders and reversible hidden apps, contextual actions, keyboard navigation, local usage ranking and explicit shell commands. No AI or cloud services.

The website requires a public GitHub repository with a root manifest, README and license. Listing approval is separate from publishing the code. Release v1.1.0 adds coordinated glass styling and an English interface to the reviewed App Grid implementation.

Publishing guide / submission form: https://plugins.omarchy.org/publish.html

The v1.0 checkout passed an isolated clean installation using the real Omarchy add/enable/validate/remove commands and a local Git snapshot. Fresh HOME/XDG directories, a private session bus and a copied host isolate production state. Reorder, folder rename, hidden state and usage survive host restart; migration, malformed state and future-schema protection are covered by `tests/clean_install_test.py`. App launch commands are captured at the host execution boundary, without opening real applications. This is a fresh plugin installation on the installed Omarchy runtime, not a second OS installation. See `RELEASE_REVIEW.md` for the pre-publication review and test boundaries.

Earlier isolated runtimes cover dark/light materials, blur-off readability, narrow widths, 1.5× rendering and 2× interaction tests. Both direct Apps payload commands pass in the clean-install host. The demo in `media/preview.gif` shows most-used apps, the App Grid, folder creation and rename, hidden-app restoration and search. It was recorded using isolated demo data and a neutral background, without personal windows. The refreshed v1.1.0 demo uses the same neutral presentation style and is attached to the v1.1.0 GitHub release.

The v1.1.0 candidate also passed plugin validation, the Node launcher regression suite, the Python search and layout-store suites, and all four isolated clean-install tests. The changed QML components passed all 34 existing runtime tests.
