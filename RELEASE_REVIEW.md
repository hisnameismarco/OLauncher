# OLauncher v2.2.1 release review — 2026-09-20

READY FOR v2.2.1 RELEASE

This document records the pre-publication review. Afterwards, the approved
initial **Apps ▦** button correction made mouse clicks open the grid while
preserving Tab for most-used circles; README reflects that behavior. Release
packaging also incorporates the existing upstream preview commit. The full
suite is rerun against the staged release tree before committing and tagging.

This conclusion applies to the complete working checkout, including the
previously untracked feature files, not just its current Git HEAD. Nothing was
published, tagged or pushed. Production plugins and user layout/history were
not changed. ODock and ONotifications were not modified.

| Review item | Result |
|---|---|
| 1. Release blockers | One launch defect found and fixed; none remain in the reviewed candidate. |
| 2. Fix | The fallback launch path mistook `.desktop` at the end of a catalog ID for the filename extension. Quickshell strips the actual extension, so ID `org.telegram.desktop` must launch `org.telegram.desktop.desktop`. Only command construction changed; persistent identity remains the exact catalog ID. |
| 3. Files changed during this review | `Spotlight.qml`, `tests/launcher.test.cjs`, new `tests/clean_install_test.py`, `README.md`, `PUBLISHING.md`, `THIRD_PARTY_NOTICES.md`, and this report. Other dirty/untracked files existed before the review. |
| 4. Clean install | Four integration scenarios passed using the real Omarchy add/enable/validate/remove commands, a local Git snapshot, copied real host, fresh HOME/config/state/cache/data/runtime directories and private D-Bus sessions. Normal mode, grid, reorder, folder creation/rename, hide, restart, restored state, search, usage, toggle, summon and removal passed. |
| 5. Fresh state | Repeated opening produces the same deterministic grid without creating a layout file. First explicit reorder creates v2 JSON with `items` and `hidden`; observed file permissions were 0644, not group/world writable. |
| 6. Upgrade | v1 order survives migration and restart. Migration is idempotent; reopening v2 does not rewrite it. The real-store suite verifies atomic replacement through inode changes. |
| 7. Malformed state | Launcher remains usable and searchable. Original malformed bytes remain until an explicit mutation produces valid v2 state. |
| 8. Future schema | Version 999 remains byte-for-byte unchanged after reorder, create folder, rename, hide, restore, Restore All and folder deletion. Operations remain usable in memory. |
| 9. Search regression | Calculator, refresh, combine, asynchronous file generation handling, file search, limits and frequent-app ranking match original HEAD. App search adds only hidden-result filtering after scoring and before limiting. No layout/folder rank dependency. |
| 10. Folder/hidden invariants | Unique string IDs, one stored app location, no nesting, stable folder IDs, structural cleanup, hidden membership, hidden children on deletion, and unavailable catalog entries covered by logic/store/integration tests. |
| 11. Drag/drop | Root apps/folders, creation/addition targets and internal reorder reviewed. QML tests cover cancellation, outside drops, hover timer disarming, scroll/resize interruption, one reorder signal and hidden-record preservation. Edge auto-scroll is intentionally absent; wheel scrolling updates the target. |
| 12. Keyboard/focus | Navigation, Enter, Escape, Tab, filter switching, Ctrl+H, rename, folder close and hidden management reviewed and covered across logic/QML tests. Clean host additionally exercises Ctrl+H/Escape and most-used selection. |
| 13. Runtime | No unexpected QML/runtime diagnostics in the final clean-install scenarios. Expected invalid/future-state warnings occur only for their test fixtures. Private-session portal/PipeWire/RealtimeKit warnings and a test-runner accessibility-bus warning are environmental, outside OLauncher. |
| 14. Performance | No recurring plugin polling, per-frame work or save loops found. Existing 300-entry grid tests pass, including virtualization during repeated reveal/resize/scroll. A two-second sample of the entire isolated host while the grid was open measured about 1.5% CPU; this is not a replacement for the earlier 0.6% post-stress measurement. |
| 15. Node assertions | 614 passed, including three new launch-identity assertions (baseline 611). |
| 16. QML tests | 28 interaction tests passed; Qt reports 34 passes including six setup/cleanup cases. |
| 17. Real-store tests | All 15 passed. Four new clean-install integration tests also passed, with no skips. |
| 18. Other validation | Python search test, plugin validation of checkout and installed snapshot, and whitespace checks passed. |
| 19. Version | Manifest and current-release documentation consistently use 2.2.1. References to 2.1.x/2.2.0 describe upgrade history. Version unchanged; no remote tags were listed at review time. |
| 20. Licensing | GPL-3.0-only declarations and GPLv3 license remain present. StatIndet provenance and modified shader source are documented. No Swift, SF Symbols, Apple assets or copied LaunchNow implementation found. Added explicit UX-inspiration notice. |
| 21. Non-blocking limitations | See the test boundaries below. No UI redesign, architectural refactor or new feature was introduced. |
| 22. Conclusion | READY FOR v2.2.1 RELEASE |

The regression fixture installs `review-suffix.desktop.desktop`, obtains
`review-suffix.desktop` from the actual Quickshell catalog and checks the launch
command. This failed before the fix and passed afterwards. Usage still stores
the original ID, and both ordinary and folder launches use the existing shared
counting path. The clean installation verifies usage persistence after restart
and hidden-app exclusion from most-used entries without deleting history.

Static review covered the complete shipped QML, JS, Python, manifests, shader
sources, notices, README, publishing notes and tests. No temporary developer
paths, enabled test switches, debug prints or TODO/FIXME markers were found in
product code. `debugInfo()` is an existing diagnostic API used by host tests,
not a continuously running logger. Single local references such as
`preferredHeight` are consumed by parent components and were retained.

Layout saving remains a 200 ms debounce followed by `mkdir -p --` with an argv
array and atomic FileView replacement. Startup/catalog projection and
folder opening/closing do not write. Future/unreadable state protection is
checked centrally before scheduling and writing; edits that arrive during a
write trigger a follow-up only when the serialized state differs.

Visible records and stored membership remain distinct. Hidden unavailable IDs
are retained; hide/restore never destroy folder membership. Structural edits
may prune unavailable non-hidden entries under the existing documented policy.
No schema, migration, persistence path or ranking implementation was changed.

Normal launcher, grid, two-app folder and hidden management screenshots were
inspected in the actual Wayland/GPU host. No obvious clipping, label overflow,
selection ambiguity or oversized folder surface was found. The previous
light/dark, blur-off, narrow and scaling validation remains applicable because
this review changed no UI code. The QML suite reran narrow/resize interactions.

Test boundaries and release handoff:

- The clean installation uses the installed Omarchy 4.0.4 / Qt 6.11.2 runtime,
  not a second OS installation. A local Git snapshot ensures uncommitted
  candidate files are included; fetching this candidate from public GitHub
  cannot be tested before publication.
- Only the copied host is instrumented: its bar and infrastructure plugins
  are disabled, a test IPC bridge exposes the loaded plugin, and app execution
  is captured at the host command boundary. Installed OLauncher source is the
  candidate itself. App processes are not actually started by these tests.
- This host supplied a null appLibrary to the third-party plugin, exercising
  OLauncher's existing DesktopEntries fallback. The injected shared-library
  path remains covered by Node tests. No Omarchy host fix is included here.
- Save debounce must finish before forcibly stopping the shell. There is no
  edge auto-scroll, drag-out or Add-to-Folder chooser, as already documented.
- Temporary installations and test processes were cleaned up. Optional local
  screenshots/logs are review artifacts, not repository release assets.
- Commit/include every reviewed feature file before a later publication step.
  The unreferenced root `preview.gif` and prior preview edits were left intact.

Upstream license checked against the recorded reference revision:
[StatIndet GPLv3 license](https://raw.githubusercontent.com/StatIndet/quickshell/ac388acf9a4537cf1c69232aceb326af9478b71f/LICENSE).
LaunchNow is acknowledged as [UX inspiration](https://github.com/ggkevinnnn/LaunchNow).
