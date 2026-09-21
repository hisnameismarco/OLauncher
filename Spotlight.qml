// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "components"
import "components/Visual.js" as Visual
import "model"
import "logic/AppLayout.js" as AppLayout
import "logic/GridNavigation.js" as GridNavigation

Item {
  id: root
  property var shell: null
  property var manifest: null
  readonly property string home: Quickshell.env("HOME")
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property color ink: Color.popups.text
  readonly property color material: Color.popups.background
  readonly property color quiet: Visual.alpha(Color.accent,0.10)
  readonly property color secondary: Visual.alpha(ink,0.68)
  readonly property color selection: Visual.alpha(Color.accent,0.18)
  readonly property string uiFont: Style.font.family
  readonly property string monoFont: Style.font.resolvedFamily
  property bool opened: false
  property string query: ""
  property string filter: "all"
  property int selected: 0
  property var immediate: []
  property var files: []
  property var results: []
  property var gridCatalog: []
  property var persistentLayout: []
  property var gridStructure: []
  property var gridLayout: []
  property bool hiddenOpen: false
  readonly property var hiddenApps: gridCatalog.filter(function(app) { return layoutStore.hidden.indexOf(app.appId) >= 0 })
  property var gridApps: []
  property string openFolderId: ""
  property string folderSelectedId: ""
  property int folderSerial: 0
  readonly property var openFolder: gridApps.find(function(item) { return item.kind === "folder" && item.folderId === root.openFolderId }) || null
  readonly property var folderApps: openFolder ? openFolder.children : []
  readonly property int folderSelectedIndex: folderApps.findIndex(function(app) { return app.key === root.folderSelectedId })
  readonly property var activeGridApps: openFolder ? folderApps : gridApps
  readonly property int activeGridIndex: openFolder ? folderSelectedIndex : gridSelectedIndex
  property string gridSelectedId: ""
  readonly property int gridSelectedIndex: gridApps.findIndex(function(app) { return app.key === root.gridSelectedId })
  readonly property bool gridActive: GridNavigation.isGrid(filter, query)
  property var usage: ({})
  property bool usageLoaded: false
  property int generation: 0
  property bool searching: false
  property string searchError: ""
  property bool actionsOpen: false
  property int actionIndex: 0
  property var quickApps: []
  property bool quickOpen: false
  property int quickIndex: 0
  property real railProgress: quickOpen ? 1 : 0
  Behavior on railProgress { NumberAnimation { duration: 620; easing.type: Easing.Linear } }
  readonly property string pluginId: root.manifest && root.manifest.id ? root.manifest.id : "olauncher"
  readonly property var current: hiddenOpen ? null : gridActive ? activeGridApps[activeGridIndex] || null : results[selected] || null
  readonly property bool commandMode: query.trim().charAt(0) === ">"
  readonly property bool expanded: query.trim().length > 0 || filter !== "all"
  readonly property var actions: current ? (current.kind === "folder"
    ? [{key:"open",label:"Open"},{key:"rename",label:"Rename"},{key:"deleteFolder",label:"Dissolve folder"}]
    : openFolder && gridActive
    ? [{key:"open",label:"Open"},{key:"removeFromFolder",label:"Remove from folder"},{key:"hide",label:"Hide from OLauncher"}]
    : current.kind === "app"
    ? [{key:"open",label:"Open"},{key:"copy",label:"Copy name"},{key:"hide",label:"Hide from OLauncher"}]
    : current.kind === "file"
    ? [{key:"open", label:"Open"}, {key:"folder", label:"Open folder"}, {key:"copy", label:"Copy path"}]
    : [{key:"open", label:current.kind === "calc" ? "Copy result" : current.kind === "cmd" ? "Run command" : "Open"},
       {key:"copy", label:current.kind === "app" ? "Copy name" : current.kind === "cmd" ? "Copy command" : "Copy result"}]) : []
  readonly property var filters: [{key:"all",label:"All"}, {key:"app",label:"Apps"}, {key:"file",label:"Files"}, {key:"calc",label:"Calculator"}]
  property real windowProgress: opened ? 1 : 0
  readonly property int barHeight: 52
  readonly property real motionOffset: 100
  Behavior on windowProgress { NumberAnimation { duration: root.opened ? 240 : 180; easing.type: root.opened ? Easing.OutCubic : Easing.InCubic } }

  function open(payload) {
    root.hiddenOpen = false
    root.openFolderId = ""
    root.opened = false
    root.quickOpen = false
    root.quickIndex = 0
    root.query = ""
    root.filter = GridNavigation.payloadFilter(payload)
    root.selected = 0
    root.actionsOpen = false
    root.opened = true
    root.quickApps = root.frequentApps()
    refresh()
    Qt.callLater(function() { input.forceActiveFocus() })
  }
  // A projection of the shared catalog, independent of search and usage scores.
  function refreshGridCatalog() {
    var rows = root.appLibrary ? root.appLibrary.sortedEntries("") : (DesktopEntries.applications.values || []).filter(function(e) {
      return e && !e.noDisplay
    }).map(function(e) { return {entry:e} })
    var apps = [], seen = Object.create(null)
    for (var i = 0; i < rows.length; i++) {
      var e = rows[i].entry
      var id = String(e.id || "")
      if (!id || seen[id]) continue
      seen[id] = true
      apps.push({kind:"app", key:"app:" + id, appId:id,
        title:root.appLibrary ? root.appLibrary.entryName(e) : String(e.name || id),
        icon:root.appLibrary ? root.appLibrary.iconSource(e.icon) : iconOr(e.icon)})
    }
    apps.sort(GridNavigation.compareApps)
    root.gridCatalog = apps
    root.applyGridLayout()
  }
  function applyGridLayout() {
    var previousIndex = root.gridSelectedIndex
    var byId = Object.create(null)
    root.gridCatalog.forEach(function(app) { byId[app.appId] = app })
    var childIndex = root.folderSelectedIndex
    var ids = root.gridCatalog.map(function(app) { return app.appId })
    root.persistentLayout = AppLayout.extendLayout(layoutStore.items,ids)
    root.gridStructure = AppLayout.reconcileWithHidden(root.persistentLayout,ids,layoutStore.hidden)
    root.gridLayout = AppLayout.filterVisibleLayout(root.gridStructure,layoutStore.hidden)
    var apps = root.gridLayout.map(function(item) {
      if (item.type === "app") return byId[item.appId]
      var children = item.apps.map(function(id) { return byId[id] })
      return {kind:"folder",key:"folder:" + item.id,folderId:item.id,title:item.name,
        children:children,preview:children.slice(0,4).map(function(app) { return app.icon })}
    })
    var nextId = GridNavigation.selectionId(apps, root.gridSelectedId, previousIndex)
    root.gridApps = apps
    root.gridSelectedId = nextId
    if (root.openFolderId && !root.openFolder) root.openFolderId = ""
    root.folderSelectedId = GridNavigation.selectionId(root.folderApps, root.folderSelectedId, childIndex)
    if (root.gridActive || !root.current) root.actionsOpen = false
  }
  function selectGrid(key) {
    if (root.openFolder) root.folderSelectedId = key
    else root.gridSelectedId = key
  }
  function reorderGrid(key, targetIndex) {
    if (!root.gridActive || !root.opened) return
    var item = root.activeGridApps.find(function(app) { return app.key === key || app.appId === key })
    if (!item) return
    selectGrid(item.key)
    if (root.openFolder) layoutStore.mutate(root.gridStructure, "insideVisible", [root.openFolderId,item.appId,targetIndex,root.folderApps.map(function(app) { return app.appId })])
    else layoutStore.mutate(root.gridStructure, "moveVisible", [item.key,targetIndex,root.gridApps.map(function(app) { return app.key })])
  }
  function moveGridSelection(direction) {
    root.actionsOpen = false
    var index = GridNavigation.move(root.activeGridIndex, root.activeGridApps.length, root.openFolder ? folderView.columns : appGrid.columns, direction)
    selectGrid(index >= 0 ? root.activeGridApps[index].key : "")
  }
  function activateGrid(key) {
    var item = root.activeGridApps.find(function(app) { return app.key === key || app.appId === key })
    if (!root.opened || !root.gridActive || !item) return
    selectGrid(item.key)
    if (item.kind === "folder") openGridFolder(item.folderId)
    else root.launchApp(item)
  }
  function openGridFolder(id) {
    var folder = root.gridApps.find(function(item) { return item.kind === "folder" && item.folderId === id })
    if (!folder) return
    root.gridSelectedId = folder.key
    root.openFolderId = id
    root.folderSelectedId = folder.children.length ? folder.children[0].key : ""
    root.actionsOpen = false
    input.forceActiveFocus()
  }
  function closeGridFolder() {
    folderView.cancelDrag()
    folderView.cancelRename()
    root.openFolderId = ""
    root.actionsOpen = false
    input.forceActiveFocus()
  }
  function folderDrop(sourceKey, targetKey) {
    if (!root.opened || !root.gridActive || root.openFolder) return
    var source = root.gridApps.find(function(item) { return item.key === sourceKey })
    var target = root.gridApps.find(function(item) { return item.key === targetKey })
    if (!source || source.kind !== "app" || !target || source === target) return
    var id = target.folderId
    if (target.kind === "folder") layoutStore.mutate(root.gridStructure,"add",[source.appId,id])
    else {
      do { id = "folder-" + Date.now().toString(36) + "-" + (++root.folderSerial).toString(36) }
      while (layoutStore.items.some(function(item) { return item.type === "folder" && item.id === id }))
      layoutStore.mutate(root.gridStructure,"create",[source.appId,target.appId,id])
    }
    root.gridSelectedId = "folder:" + id
  }
  function showGridActions(key) {
    selectGrid(key)
    root.actionsOpen = true
    root.actionIndex = 0
    input.forceActiveFocus()
  }
  function renameGridFolder(name) {
    if (root.openFolder) layoutStore.mutate(root.gridStructure,"rename",[root.openFolderId,name])
    input.forceActiveFocus()
  }
  function changeVisibility(operation, appId) {
    if (operation === "hide" && !root.gridCatalog.some(function(app) { return app.appId === appId })) return
    layoutStore.setVisibility(operation,appId,root.persistentLayout)
  }
  function visibilityChanged() {
    root.applyGridLayout()
    root.actionsOpen = false
    root.quickOpen = false
    root.quickIndex = 0
    root.quickApps = root.frequentApps()
    // Keep file/calculator results and in-flight file requests intact.
    if (root.opened && !root.commandMode && (root.filter === "all" || root.filter === "app")) {
      var oldIndex = root.selected, oldId = resultId(root.results[oldIndex])
      root.immediate = root.immediate.filter(function(row) { return row.kind !== "app" }).concat(root.appResults(root.query.trim()))
      combine(true)
      if (!root.results.some(function(row) { return resultId(row) === oldId }))
        root.selected = Math.max(0,Math.min(root.results.length - 1,oldIndex))
    }
  }
  function showHiddenApps() {
    if (!root.gridActive) return
    closeGridFolder()
    appGrid.cancelDrag()
    root.hiddenOpen = true
    root.actionsOpen = false
    input.forceActiveFocus()
  }
  function closeHiddenApps() {
    root.hiddenOpen = false
    input.forceActiveFocus()
  }
  function close() {
    root.hiddenOpen = false
    appGrid.cancelDrag()
    closeGridFolder()
    root.quickOpen = false
    root.opened = false
    root.generation++
    debounce.stop()
    fileProc.running = false
    root.searching = false
    root.actionsOpen = false
  }
  function dismiss() {
    close()
    if (root.shell) root.shell.hide(root.pluginId)
  }
  function toggle() { if (opened) dismiss(); else open("{}") }
  function iconOr(name) { return Quickshell.iconPath(name, true) || Quickshell.iconPath("application-x-executable", true) }
  function resultId(r) { return r ? r.kind + ":" + (r.appId || r.path || r.title) : "" }
  function combine(preserve) {
    var id = preserve ? resultId(root.results[root.selected]) : ""
    var rows = root.immediate.concat(root.files)
    if (root.query.trim().charAt(0) !== ">" && root.filter !== "all") rows = rows.filter(function(r) { return r.kind === root.filter })
    root.results = rows
    var index = rows.findIndex(function(r) { return resultId(r) === id })
    root.selected = Math.max(0, index)
    if (index < 0) root.actionsOpen = false
  }
  function calculate(expr) {
    var t = expr.trim().replace(/,/g, ".").replace(/×/g, "*").replace(/÷/g, "/")
    if (!t || !/^[0-9+\-*/().%\s^]+$/.test(t) || !/[0-9]/.test(t)) return null
    // Percent is a postfix percentage; input is restricted to arithmetic.
    t = t.replace(/(\d+(?:\.\d+)?)\s*%/g, "($1/100)").replace(/\^/g, "**")
    if (t.indexOf("%") >= 0) return null
    try {
      var v = Function('"use strict";return (' + t + ')')()
      return typeof v === "number" && isFinite(v) ? String(Number(v.toPrecision(12))) : null
    } catch (e) { return null }
  }
  function appResults(q, unlimited) {
    var rows = root.appLibrary ? root.appLibrary.sortedEntries(q) : (DesktopEntries.applications.values || []).filter(function(e) {
      return e && !e.noDisplay && (!q || (String(e.name) + " " + String(e.id) + " " + String(e.genericName || "")).toLowerCase().indexOf(q.toLowerCase()) >= 0)
    }).map(function(e) { return {entry:e} })
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var e = rows[i].entry
      var id = String(e.id || "")
      if (!id) continue
      var title = root.appLibrary ? root.appLibrary.entryName(e) : String(e.name || id)
      var name = title.toLowerCase(), needle = q.toLowerCase()
      var match = !needle ? 0 : name === needle ? 300 : name.indexOf(needle) === 0 ? 200 : name.indexOf(needle) >= 0 ? 100 : 0
      out.push({kind:"app",appId:id,title:title,subtitle:root.appLibrary ? root.appLibrary.entrySubtext(e) || "Application" : "Application",
        icon:root.appLibrary ? root.appLibrary.iconSource(e.icon) : iconOr(e.icon),score:match + Math.min(50, Number(root.usage[id] || 0) * 3),order:i})
    }
    out.sort(function(a,b) { return b.score - a.score || a.order - b.order })
    out = AppLayout.filterAppResults(out,layoutStore.hidden)
    return unlimited ? out : out.slice(0, q ? 12 : 8)
  }
  function frequentApps() {
    var apps = appResults("", true)
    apps.sort(function(a, b) {
      return Number(root.usage[b.appId] || 0) - Number(root.usage[a.appId] || 0)
        || a.title.localeCompare(b.title) || a.appId.localeCompare(b.appId)
    })
    return apps.slice(0, 4)
  }
  function cycleQuick(delta) {
    if (root.expanded || !root.quickApps.length) return
    if (!root.quickOpen) { root.quickIndex = 0; root.quickOpen = true }
    else root.quickIndex = (root.quickIndex + Number(delta) + root.quickApps.length) % root.quickApps.length
    input.forceActiveFocus()
  }
  function launchApp(r) {
    if (!r || !r.appId) return
    var counts = Object.assign({}, root.usage)
    counts[r.appId] = Number(counts[r.appId] || 0) + 1
    root.usage = counts
    if (root.usageLoaded) usageFile.setText(JSON.stringify(counts))
    if (root.appLibrary) root.appLibrary.launch(r.appId, r.title)
    // Quickshell entry.id excludes the filename extension, even when the ID
    // itself ends in .desktop (e.g. org.telegram.desktop). Only the launch
    // filename gains an extension; stored identities stay exactly entry.id.
    else Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(r.appId + ".desktop"))
    dismiss()
  }
  function activateQuick(index) {
    index = Number(index)
    if (!root.opened || root.expanded || !root.quickOpen || index < 0 || index >= root.quickApps.length) return
    launchApp(root.quickApps[index])
  }
  function refresh() {
    if (root.query.trim().length || root.filter !== "all") root.quickOpen = false
    root.generation++
    debounce.stop()
    fileProc.running = false
    root.files = []
    root.searchError = ""
    root.searching = false
    root.actionsOpen = false
    if (!root.opened) return
    var q = root.query.trim(), out = []
    if (q.charAt(0) === ">") {
      var cmd = q.slice(1).trim()
      if (cmd) out.push({kind:"cmd",title:cmd,subtitle:"Shell command · Enter to run",icon:iconOr("utilities-terminal")})
    } else {
      var value = calculate(q)
      if (value !== null) out.push({kind:"calc",title:value,subtitle:q + " =",icon:iconOr("accessories-calculator")})
      if (root.filter === "all" || root.filter === "app") out = out.concat(appResults(q))
      if (q.length >= 2 && (root.filter === "all" || root.filter === "file")) {
        root.searching = true
        debounce.restart()
      }
    }
    root.immediate = out
    combine(false)
  }
  function startFileSearch() {
    if (!root.opened || !root.searching) return
    if (fileProc.running) { debounce.restart(); return }
    fileProc.command = ["python3", decodeURIComponent(Qt.resolvedUrl("search-files.py").toString().replace("file://", "")), String(root.generation), root.query.trim(), root.home]
    fileProc.running = true
  }
  function acceptFiles(text) {
    var data
    try { data = JSON.parse(text) } catch (e) { return }
    if (!root.opened || data.token !== root.generation) return
    root.searching = false
    root.searchError = data.error || ""
    root.files = data.paths.map(function(p) {
      var slash = p.lastIndexOf("/")
      return {kind:"file",path:p,title:p.slice(slash+1),subtitle:p.slice(0,slash).replace(root.home,"~"),icon:iconOr("text-x-generic")}
    })
    combine(true)
  }
  function setFilter(key) {
    if (!["all","app","file","calc"].includes(key)) return
    root.filter = key
    input.forceActiveFocus()
  }
  function cycleFilter(delta) {
    var index = root.filters.findIndex(function(f) { return f.key === root.filter })
    setFilter(root.filters[(index + delta + root.filters.length) % root.filters.length].key)
  }
  function moveSelection(delta) {
    delta = Number(delta)
    root.actionsOpen = false
    root.selected = Math.max(0, Math.min(root.results.length - 1, root.selected + delta))
  }
  function cycleAction(delta) {
    delta = Number(delta)
    if (!root.expanded || !root.current) return
    if (!root.actionsOpen) { root.actionsOpen = true; root.actionIndex = 0 }
    else root.actionIndex = (root.actionIndex + delta + root.actions.length) % root.actions.length
  }
  function activateSelected() {
    if (root.hiddenOpen) { hiddenView.activateSelected(); return }
    if (root.quickOpen && !root.expanded) activateQuick(root.quickIndex)
    else performAction(root.actionsOpen ? root.actions[root.actionIndex].key : "open")
  }
  function performAction(action) {
    var r = root.current
    if (!root.expanded || !r) return
    if (action === "hide" && r.kind === "app") { changeVisibility("hide",r.appId); return }
    if (r.kind === "folder") {
      if (action === "deleteFolder") layoutStore.mutate(root.gridStructure,"delete",[r.folderId])
      else {
        openGridFolder(r.folderId)
        if (action === "rename") Qt.callLater(function() { folderView.beginRename() })
      }
      root.actionsOpen = false
      return
    }
    if (action === "removeFromFolder" && root.openFolder) {
      layoutStore.mutate(root.gridStructure,"remove",[root.openFolderId,r.appId])
      root.actionsOpen = false
      return
    }
    if (action === "copy" || r.kind === "calc") {
      Util.execDetached("wl-copy -- " + Util.shellQuote(r.path || r.title))
    } else if (r.kind === "app") {
      launchApp(r)
      return
    } else if (r.kind === "file") {
      var path = action === "folder" ? r.path.slice(0,r.path.lastIndexOf("/")) : r.path
      Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote(path))
    } else if (r.kind === "cmd" && root.query.trim().charAt(0) === ">") {
      Util.execDetached(r.title)
    }
    dismiss()
  }
  function handleEscape() {
    if (root.hiddenOpen) { closeHiddenApps(); return }
    if (appGrid.dragging) { appGrid.cancelDrag(); return }
    if (folderView.dragging) { folderView.cancelDrag(); return }
    if (root.openFolder) { closeGridFolder(); return }
    if (root.quickOpen) root.quickOpen = false
    else if (root.actionsOpen) root.actionsOpen = false
    else if (root.filter !== "all") setFilter("all")
    else if (root.query.length) root.query = ""
    else dismiss()
  }
  function handleKey(event) {
    var key = event.key, shift = (event.modifiers & Qt.ShiftModifier) !== 0
    if ((event.modifiers & Qt.ControlModifier) && key === Qt.Key_H && root.gridActive) {
      if (root.hiddenOpen) closeHiddenApps(); else showHiddenApps()
    }
    else if (root.hiddenOpen && (key === Qt.Key_Up || key === Qt.Key_Down)) hiddenView.moveSelection(key === Qt.Key_Up ? -1 : 1)
    else if (key === Qt.Key_Escape) handleEscape()
    else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
      var delta = shift || key === Qt.Key_Backtab ? -1 : 1
      if (!root.expanded) cycleQuick(delta)
      else cycleAction(delta)
    }
    else if (key === Qt.Key_Return || key === Qt.Key_Enter) activateSelected()
    else if ((event.modifiers & Qt.ControlModifier) && (key === Qt.Key_Left || key === Qt.Key_Right)) cycleFilter(key === Qt.Key_Left ? -1 : 1)
    else if (root.quickOpen && (key === Qt.Key_Left || key === Qt.Key_Right)) cycleQuick(key === Qt.Key_Left ? -1 : 1)
    else if (root.actionsOpen && (key === Qt.Key_Left || key === Qt.Key_Right)) cycleAction(key === Qt.Key_Left ? -1 : 1)
    else if (root.gridActive && !root.hiddenOpen && [Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down, Qt.Key_PageUp, Qt.Key_PageDown].includes(key)) {
      moveGridSelection(key === Qt.Key_Left ? "left" : key === Qt.Key_Right ? "right" : key === Qt.Key_Up ? "up" : key === Qt.Key_Down ? "down" : key === Qt.Key_PageUp ? "pageUp" : "pageDown")
    }
    else if (key === Qt.Key_Down) moveSelection(1)
    else if (key === Qt.Key_Up) moveSelection(-1)
    else if (key === Qt.Key_PageDown) moveSelection(6)
    else if (key === Qt.Key_PageUp) moveSelection(-6)
    else return
    event.accepted = true
  }
  function setQuery(q) { root.query = String(q); return root.results.length }
  function debugInfo() {
    return JSON.stringify({opened:opened,query:query,filter:filter,searching:searching,error:searchError,
      hiddenOpen:hiddenOpen,hiddenCount:layoutStore.hidden.length,gridActive:gridActive,gridCount:gridApps.length,gridSelectedId:gridSelectedId,gridSelectedIndex:gridSelectedIndex,gridColumns:appGrid.columns,openFolderId:openFolderId,folderSelectedId:folderSelectedId,
      quickOpen:quickOpen,quickIndex:quickIndex,rail:railProgress,quickApps:quickApps.map(function(a) {return a.appId}),selected:selected,actionsOpen:actionsOpen,actionIndex:actionIndex,results:results.map(function(r) {return {kind:r.kind,title:r.title,id:resultId(r)} })})
  }
  AppLayoutStore {
    id: layoutStore
    onItemsChanged: root.applyGridLayout()
    onHiddenChanged: root.visibilityChanged()
  }
  Component.onCompleted: refreshGridCatalog()
  onAppLibraryChanged: refreshGridCatalog()
  Connections {
    target: root.appLibrary
    function onAppsChanged() { root.refreshGridCatalog() }
  }
  Connections {
    target: root.appLibrary ? null : DesktopEntries.applications
    function onValuesChanged() { root.refreshGridCatalog() }
  }
  onQueryChanged: { if (root.query.trim().length) root.hiddenOpen = false; if (root.query.trim().length && root.openFolderId) closeGridFolder(); refresh() }
  onFilterChanged: { if (root.filter !== "app") root.hiddenOpen = false; if (root.filter !== "app" && root.openFolderId) closeGridFolder(); refresh() }
  Timer { id: debounce; interval: 180; onTriggered: root.startFileSearch() }
  Process {
    id: fileProc
    stdout: StdioCollector { onStreamFinished: root.acceptFiles(text) }
  }
  FileView {
    id: usageFile
    path: root.home + "/.local/state/spotlight-usage.json"
    printErrors: false
    onLoaded: {
      try { root.usage = JSON.parse(text()) || ({}) } catch (e) { root.usage = ({}) }
      root.usageLoaded = true
      if (root.opened) { if (!root.quickOpen) root.quickApps = root.frequentApps(); root.refresh() }
    }
    onLoadFailed: root.usageLoaded = true
  }
  component Label: Text {
    color: root.ink
    font.family: root.uiFont
    font.pixelSize: 14
    textFormat: Text.PlainText
    elide: Text.ElideRight
  }
  PanelWindow {
    id: panel
    visible: root.opened || root.windowProgress > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "olauncher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    Item {
      id: surface
      width: Math.min(578, panel.width - 32)
      height: root.barHeight + (root.expanded ? 40 + body.height + footer.height + 12 : 0)
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.max(16, panel.height * 0.20 - 32) - 8 * (1 - root.windowProgress)
      opacity: root.windowProgress
      scale: 0.97 + root.windowProgress * 0.03
      transformOrigin: Item.Top
      transform: Translate {
        id: openCloseTranslate
        x: -root.motionOffset * (1 - root.windowProgress)
      }
      Behavior on height { NumberAnimation { duration: Visual.normal; easing.type: Easing.OutCubic } }
      Rectangle {
        anchors.fill: parent
        visible: root.expanded
        radius: Visual.radiusOuter
        // Frosted material shared with the dock, denser for text readability.
        color: Visual.alpha(root.material,Visual.surfaceOpacity)
        border.width: 1
        border.color: Visual.alpha(root.ink,Visual.edgeOpacity)
        Rectangle {
          anchors.fill: parent; radius: parent.radius
          gradient: Gradient {
            GradientStop { position: 0; color: Visual.alpha("#ffffff",Visual.sheenOpacity) }
            GradientStop { position: 0.5; color: "#00ffffff" }
            GradientStop { position: 1; color: "#09000000" }
          }
        }
        Rectangle {
          x: parent.radius; y: 1; width: parent.width - 2 * x; height: 1
          color: Visual.alpha("#ffffff",0.16)
        }
      }
      MorphSurface {
        id: morph
        visible: !root.expanded
        x: -18; y: -18
        width: surface.width + 36; height: root.barHeight + 36
        railProgress: root.railProgress
        mainLeft: 18
        collapsedMainWidth: surface.width
        expandedMainWidth: surface.width - root.quickApps.length * (buttonDiameter + buttonGap)
        shapeCenterY: 18 + root.barHeight / 2
        shapeHeight: root.barHeight
        mainCornerRadius: Visual.radiusOuter
        buttonCount: root.quickApps.length
        buttonDiameter: Math.min(root.barHeight - 2, Math.max(28, (surface.width - 180) / 4 - 10))
        buttonGap: 10
        blurEdgeInset: 2
        surfaceColor: Visual.alpha(root.material,Visual.surfaceOpacity)
      }
      MouseArea { anchors.fill: parent }
      Canvas {
        x: 20; y: Math.round((root.barHeight - 22) / 2); width: 22; height: 22
        visible: !root.commandMode
        property color stroke: root.secondary
        onStrokeChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.strokeStyle = root.secondary.toString()
          ctx.lineWidth = 1.8
          ctx.lineCap = "round"
          ctx.beginPath(); ctx.arc(9, 9, 6, 0, Math.PI * 2); ctx.stroke()
          ctx.beginPath(); ctx.moveTo(13.5, 13.5); ctx.lineTo(19, 19); ctx.stroke()
        }
      }
      Label {
        x: 21; y: Math.round((root.barHeight - 28) / 2); width: 24; height: 28
        visible: root.commandMode
        text: ">"; font.pixelSize: 26; color: root.secondary
      }
      TextInput {
        id: input
        x: 52; y: 0
        width: (root.expanded ? surface.width : morph.mainWidth) - 110; height: root.barHeight
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        selectByMouse: true
        color: root.ink
        selectionColor: Visual.alpha(Color.accent,0.35)
        selectedTextColor: root.ink
        font.family: root.commandMode ? root.monoFont : root.uiFont
        font.pixelSize: 24
        text: root.query
        onTextChanged: root.query = text
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { root.handleKey(event) }
        Label {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          text: "Spotlight Search"
          color: root.secondary
          font.pixelSize: 24
          visible: !input.text.length
        }
      }
      Rectangle {
        anchors.right: parent.right; anchors.rightMargin: 20; y: Math.round((root.barHeight - 25) / 2)
        width: 25; height: 25; radius: 13
        visible: root.query.length > 0
        color: clearMouse.containsMouse ? root.selection : root.quiet
        Label { anchors.centerIn: parent; text: "×"; font.pixelSize: 19 }
        MouseArea { id: clearMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { root.query = ""; input.forceActiveFocus() } }
      }
      Rectangle {
        x: morph.mainWidth - 82; y: Math.round((root.barHeight - 25) / 2)
        width: 64; height: 25; radius: 9
        visible: !root.expanded && !root.quickOpen && root.railProgress < 0.01 && root.quickApps.length > 0
        color: quickHintMouse.containsMouse ? root.selection : root.quiet
        Label { anchors.centerIn: parent; text: "Apps ▦"; font.pixelSize: 12 }
        MouseArea { id: quickHintMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.setFilter("app") }
      }
      Repeater {
        model: root.quickApps
        delegate: Item {
          id: quickButton
          required property var modelData
          required property int index
          readonly property real reveal: morph.iconProgress(index)
          visible: !root.expanded
          x: morph.x + morph.buttonCenterX(index) - width / 2
          y: (root.barHeight - height) / 2
          width: morph.buttonDiameter; height: width
          opacity: reveal
          scale: 0.9 + reveal * 0.1
          Rectangle {
            anchors.fill: parent; anchors.margins: 3
            radius: width / 2
            color: root.quickIndex === quickButton.index || quickMouse.containsMouse ? root.selection : "transparent"
            border.width: root.quickIndex === quickButton.index ? 1 : 0
            border.color: Visual.alpha(root.ink,0.24)
          }
          Image {
            anchors.centerIn: parent
            width: Math.min(36, parent.width - 16); height: width
            source: quickButton.modelData.icon
            sourceSize.width: 72; sourceSize.height: 72
            fillMode: Image.PreserveAspectFit
          }
          MouseArea {
            id: quickMouse
            anchors.fill: parent; hoverEnabled: true
            enabled: root.quickOpen && quickButton.reveal > 0.55
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activateQuick(quickButton.index)
          }
        }
      }
      Rectangle {
        visible: !root.expanded && root.quickOpen && root.quickApps.length > 0
        opacity: morph.iconProgress(root.quickIndex)
        x: morph.mainWidth + 10; y: 78
        width: surface.width - x; height: 28; radius: 14
        color: Visual.alpha(root.material,0.96)
        Label {
          anchors.fill: parent; anchors.margins: 6
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: root.quickApps[root.quickIndex] ? root.quickApps[root.quickIndex].title + "   ↵" : ""
          font.pixelSize: 12
        }
      }
      Item {
        id: content
        visible: root.expanded
        x: 8; y: root.barHeight; width: parent.width - 16
        height: filtersRow.height + body.height + footer.height
        Rectangle { x: 14; width: parent.width - 28; height: 1; color: Visual.alpha(root.ink,0.10) }
        Row {
          id: filtersRow
          x: 8; y: 8; spacing: 5; height: 32
          Repeater {
            model: root.commandMode ? [{key:"all",label:"Command"}] : root.filters
            delegate: Rectangle {
              required property var modelData
              width: chipLabel.implicitWidth + (surface.width < 360 ? 16 : 24); height: 26; radius: Visual.radiusControl
              color: root.filter === modelData.key ? root.selection : chipMouse.containsMouse ? root.quiet : "transparent"
              Behavior on color { ColorAnimation { duration: Visual.fast } }
              Label { id: chipLabel; anchors.centerIn: parent; text: modelData.label; font.pixelSize: 12; font.weight: root.filter === modelData.key ? Font.DemiBold : Font.Normal }
              MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.setFilter(modelData.key) }
            }
          }
        }
        Item {
          id: body
          y: 40; width: parent.width
          height: Math.min(420, Math.max(52, panel.height - surface.y - 210), root.gridActive ? (root.hiddenOpen ? hiddenView.preferredHeight : root.openFolder ? folderView.preferredHeight : appGrid.preferredHeight) : root.results.length ? root.results.length * 56 : 76)
          AppGrid {
            id: appGrid
            anchors.fill: parent
            visible: root.gridActive && !root.openFolder && !root.hiddenOpen
            folderTargetsEnabled: true
            apps: root.gridApps
            reorderEnabled: layoutStore.ready
            selectedIndex: root.gridSelectedIndex
            ink: root.ink
            selectionColor: root.selection
            uiFont: root.uiFont
            onActivated: function(appId) { root.activateGrid(appId) }
            onReordered: function(appId, targetIndex) { root.reorderGrid(appId, targetIndex) }
            onDragSelected: function(key) { root.selectGrid(key); root.actionsOpen = false }
            onFolderDropped: function(sourceKey, targetKey) { root.folderDrop(sourceKey,targetKey) }
            onContextRequested: function(key) { root.showGridActions(key) }
          }
          AppFolderView {
            id: folderView
            anchors.fill: parent
            visible: root.gridActive && !!root.openFolder && !root.hiddenOpen
            folderName: root.openFolder ? root.openFolder.title : ""
            apps: root.folderApps
            selectedIndex: root.folderSelectedIndex
            reorderEnabled: layoutStore.ready
            ink: root.ink
            selectionColor: root.selection
            uiFont: root.uiFont
            onClosed: root.closeGridFolder()
            onActivated: function(key) { root.activateGrid(key) }
            onReordered: function(key, index) { root.reorderGrid(key,index) }
            onDragSelected: function(key) { root.selectGrid(key); root.actionsOpen = false }
            onContextRequested: function(key) { root.showGridActions(key) }
            onRenamed: function(name) { root.renameGridFolder(name) }
            onEditCanceled: input.forceActiveFocus()
          }
          HiddenAppsView {
            id: hiddenView
            anchors.fill: parent
            visible: root.gridActive && root.hiddenOpen
            apps: root.hiddenApps
            totalHidden: layoutStore.hidden.length
            ink: root.ink
            selectionColor: root.selection
            uiFont: root.uiFont
            onClosed: root.closeHiddenApps()
            onRestoreRequested: function(appId) { root.changeVisibility("restore",appId) }
            onRestoreAllRequested: root.changeVisibility("restoreAll","")
          }
          ListView {
            id: list
            visible: !root.gridActive
            onVisibleChanged: if (visible) resultReveal.restart()
            NumberAnimation { id: resultReveal; target: list; property: "opacity"; from: 0; to: 1; duration: Visual.fast; easing.type: Easing.OutCubic }
            anchors.fill: parent
            clip: true
            model: root.results
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: root.selected
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
            delegate: Rectangle {
              id: row
              required property var modelData
              required property int index
              width: list.width; height: 56; radius: 12
              border.width: index === root.selected ? 1 : 0
              border.color: Visual.alpha(root.ink,0.22)
              color: index === root.selected ? root.selection : rowMouse.containsMouse ? root.quiet : "transparent"
              Image {
                id: icon
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 32
                source: row.modelData.icon
                sourceSize.width: 64; sourceSize.height: 64
                fillMode: Image.PreserveAspectFit
              }
              Column {
                x: 56; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 104; spacing: 3
                Label { width: parent.width; text: row.modelData.title; font.family: row.modelData.kind === "cmd" ? root.monoFont : root.uiFont; font.pixelSize: row.modelData.kind === "calc" ? 22 : 15 }
                Label { width: parent.width; text: row.modelData.subtitle; font.pixelSize: 12; color: root.secondary }
              }
              Label { anchors.right: parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter; text: "↵"; font.pixelSize: 19; visible: row.index === root.selected; color: root.secondary }
              MouseArea {
                id: rowMouse
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(event) {
                  root.selected = row.index
                  if (event.button === Qt.RightButton) { root.actionsOpen = true; root.actionIndex = 0; input.forceActiveFocus() }
                  else root.performAction("open")
                }
              }
            }
          }
          Label {
            anchors.centerIn: parent; width: parent.width - 32
            horizontalAlignment: Text.AlignHCenter
            visible: !root.gridActive && root.results.length === 0
            text: root.searching ? "Searching files …" : root.searchError ? "File search unavailable" : root.commandMode ? "Type a command after >" : root.filter === "calc" ? "Enter a calculation, e.g. 125 × 1.19" : root.filter === "file" && root.query.trim().length < 2 ? "Type at least two characters" : "No results"
            color: root.secondary
          }
        }
        Item {
          id: footer
          y: body.y + body.height + 4
          width: parent.width; height: root.actionsOpen ? 46 : 32
          Rectangle { x: 14; width: parent.width - 28; height: 1; color: root.quiet }
          Label {
            x: 14; anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0,parent.width - (actionsButton.visible ? actionsButton.width : 0) - (hiddenButton.visible ? hiddenButton.width + 8 : 0) - 40)
            visible: !root.actionsOpen && width > 100
            font.pixelSize: 11; font.family: root.monoFont; color: root.secondary
            text: root.hiddenOpen ? "↑↓ Select    ↵ Unhide    Esc Back" : root.searching ? "Searching files …" : root.searchError ? "File search unavailable · Apps still available" : root.gridActive ? "Arrows Select    ↵ Open    Ctrl + ←/→ Filter" : "↑↓ Select    ↵ Open    Ctrl + ←/→ Filter"
          }
          Rectangle {
            id: hiddenButton
            visible: root.gridActive && !root.hiddenOpen && !root.actionsOpen
            anchors.right: actionsButton.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(144,Math.max(112,parent.width - 122)); height: 24; radius: Visual.radiusControl
            color: hiddenMouse.containsMouse ? root.selection : "transparent"
            Label { anchors.centerIn: parent; text: "Hidden  Ctrl+H"; font.pixelSize: 12 }
            MouseArea { id: hiddenMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.showHiddenApps() }
          }
          Rectangle {
            id: actionsButton
            visible: !root.actionsOpen && !!root.current
            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            width: 96; height: 24; radius: Visual.radiusControl
            color: actionsMouse.containsMouse ? root.selection : "transparent"
            Label { anchors.centerIn: parent; text: "Actions   ⇥"; font.pixelSize: 12 }
            MouseArea { id: actionsMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.cycleAction(1) }
          }
          ListView {
            visible: root.actionsOpen
            x: 8; width: parent.width - 16; height: 30
            anchors.verticalCenter: parent.verticalCenter
            orientation: ListView.Horizontal; spacing: 6; clip: true
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: false
            model: root.actions
            currentIndex: root.actionIndex
            onCurrentIndexChanged: if (visible) positionViewAtIndex(currentIndex,ListView.Contain)
            onVisibleChanged: if (visible) positionViewAtIndex(currentIndex,ListView.Contain)
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: actionText.implicitWidth + 22; height: 30; radius: Visual.radiusControl
              border.width: index === root.actionIndex ? 1 : 0
              border.color: Visual.alpha(root.ink,0.22)
              color: index === root.actionIndex ? root.selection : actionMouse.containsMouse ? root.quiet : "transparent"
              Label { id: actionText; anchors.centerIn: parent; text: modelData.label; font.pixelSize: 12 }
              MouseArea { id: actionMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.performAction(modelData.key) }
            }
          }
        }
      }
    }
  }
}
