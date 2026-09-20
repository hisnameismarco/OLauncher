// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/AppLayout.js" as AppLayout

Item {
  id: root
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
  readonly property string directory: stateHome + "/olauncher"
  readonly property string path: directory + "/apps-layout.json"
  property var items: []
  property var hidden: []
  readonly property var order: AppLayout.allAppIds(items)
  property bool ready: false
  property bool protectedFile: false
  property bool dirty: false
  property bool writing: false
  property string pendingText: ""
  property string lastError: ""

  function load(raw) {
    if (ready) return
    var parsed = AppLayout.parse(raw)
    protectedFile = protectedFile || parsed.protected
    items = parsed.items
    hidden = parsed.hidden
    ready = true
    if (parsed.migrated && !protectedFile) { dirty = true; saveTimer.restart() }
    if (parsed.protected) console.warn("olauncher: newer apps-layout schema; using session-only layout and preserving file")
    else if (parsed.error) console.warn("olauncher: invalid apps-layout.json; using default layout until an explicit reorder")
  }

  // Migration saves the full parsed layout, never a catalog-filtered projection.
  // All later saves require an explicit user mutation.
  function commit(currentIds, id, targetIndex) {
    return mutate(currentIds.map(AppLayout.appItem), "move", ["app:" + id, targetIndex])
  }
  function mutate(currentItems, operation, args) {
    if (!ready) return false
    var next = AppLayout.operate(currentItems, operation, args)
    if (JSON.stringify(next) === JSON.stringify(currentItems)) return false
    items = next
    if (!protectedFile) { dirty = true; saveTimer.restart() }
    return true
  }
  function setVisibility(operation, id, fullItems) {
    if (!ready) return false
    var next = AppLayout.changeHidden(hidden,operation,id)
    if (JSON.stringify(next) === JSON.stringify(hidden)) return false
    // Snapshot discoveries only; never save a filtered layout during hide/restore.
    if (operation === "hide" && JSON.stringify(items) !== JSON.stringify(fullItems)) items = AppLayout.normalizeLayout(fullItems)
    hidden = next
    if (!protectedFile) { dirty = true; saveTimer.restart() }
    return true
  }
  function flush() {
    if (!AppLayout.maySave(ready, protectedFile, dirty) || writing || ensureDirectory.running) return
    ensureDirectory.running = true
  }
  Timer { id: saveTimer; interval: 200; onTriggered: root.flush() }
  Process {
    id: ensureDirectory
    command: ["mkdir", "-p", "--", root.directory]
    onExited: function(code) {
      if (code !== 0) {
        root.lastError = "Cannot create layout directory"
        console.warn("olauncher: " + root.lastError)
        return
      }
      if (!AppLayout.maySave(root.ready, root.protectedFile, root.dirty)) return
      root.pendingText = AppLayout.serialize(root.items,root.hidden)
      root.writing = true
      layoutFile.setText(root.pendingText)
    }
  }
  FileView {
    id: layoutFile
    path: root.path
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: function(error) {
      if (error !== FileViewError.FileNotFound) {
        root.protectedFile = true
        console.warn("olauncher: cannot read apps-layout.json; preserving file for this session")
      }
      root.load("")
    }
    onSaved: {
      root.writing = false
      root.lastError = ""
      root.dirty = root.pendingText !== AppLayout.serialize(root.items,root.hidden)
      if (AppLayout.maySave(root.ready, root.protectedFile, root.dirty)) saveTimer.restart()
    }
    onSaveFailed: {
      root.writing = false
      root.lastError = "Cannot save apps-layout.json; in-memory order retained"
      console.warn("olauncher: " + root.lastError)
    }
  }
}
