// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root
  property var shell: null
  property var manifest: null
  readonly property string home: Quickshell.env("HOME")
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property color ink: "#302b2b"
  readonly property color selection: "#263c3435"
  readonly property string uiFont: Qt.fontFamilies().indexOf("SF Pro Display") >= 0 ? "SF Pro Display" : "sans-serif"
  property bool opened: false
  property string query: ""
  property string filter: "all"
  property int selected: 0
  property var immediate: []
  property var files: []
  property var results: []
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
  readonly property var current: results[selected] || null
  readonly property bool commandMode: query.trim().charAt(0) === ">"
  readonly property bool expanded: query.trim().length > 0 || filter !== "all"
  readonly property var actions: current ? (current.kind === "file"
    ? [{key:"open", label:"Öffnen"}, {key:"folder", label:"Ordner öffnen"}, {key:"copy", label:"Pfad kopieren"}]
    : [{key:"open", label:current.kind === "calc" ? "Ergebnis kopieren" : current.kind === "cmd" ? "Befehl ausführen" : "Öffnen"},
       {key:"copy", label:current.kind === "app" ? "Name kopieren" : current.kind === "cmd" ? "Befehl kopieren" : "Ergebnis kopieren"}]) : []
  readonly property var filters: [{key:"all",label:"Alle"}, {key:"app",label:"Apps"}, {key:"file",label:"Dateien"}, {key:"calc",label:"Rechner"}]
  property real windowProgress: opened ? 1 : 0
  Behavior on windowProgress { NumberAnimation { duration: root.opened ? 210 : 160; easing.type: Easing.OutCubic } }

  function open(payload) {
    root.opened = false
    root.quickOpen = false
    root.quickIndex = 0
    root.query = ""
    root.filter = "all"
    root.selected = 0
    root.actionsOpen = false
    root.opened = true
    root.quickApps = root.frequentApps()
    refresh()
    Qt.callLater(function() { input.forceActiveFocus() })
  }
  function close() {
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
      return typeof v === "number" && isFinite(v) ? String(Number(v.toPrecision(12))).replace(".", ",") : null
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
      out.push({kind:"app",appId:id,title:title,subtitle:root.appLibrary ? root.appLibrary.entrySubtext(e) || "Programm" : "Programm",
        icon:root.appLibrary ? root.appLibrary.iconSource(e.icon) : iconOr(e.icon),score:match + Math.min(50, Number(root.usage[id] || 0) * 3),order:i})
    }
    out.sort(function(a,b) { return b.score - a.score || a.order - b.order })
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
    else Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(r.appId.endsWith(".desktop") ? r.appId : r.appId + ".desktop"))
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
      if (cmd) out.push({kind:"cmd",title:cmd,subtitle:"Shell-Befehl · Enter zum Ausführen",icon:iconOr("utilities-terminal")})
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
    if (root.quickOpen && !root.expanded) activateQuick(root.quickIndex)
    else performAction(root.actionsOpen ? root.actions[root.actionIndex].key : "open")
  }
  function performAction(action) {
    var r = root.results[root.selected]
    if (!root.expanded || !r) return
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
    if (root.quickOpen) root.quickOpen = false
    else if (root.actionsOpen) root.actionsOpen = false
    else if (root.filter !== "all") setFilter("all")
    else if (root.query.length) root.query = ""
    else dismiss()
  }
  function handleKey(event) {
    var key = event.key, shift = (event.modifiers & Qt.ShiftModifier) !== 0
    if (key === Qt.Key_Escape) handleEscape()
    else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
      var delta = shift || key === Qt.Key_Backtab ? -1 : 1
      if (!root.expanded) cycleQuick(delta)
      else cycleAction(delta)
    }
    else if (key === Qt.Key_Return || key === Qt.Key_Enter) activateSelected()
    else if ((event.modifiers & Qt.ControlModifier) && (key === Qt.Key_Left || key === Qt.Key_Right)) cycleFilter(key === Qt.Key_Left ? -1 : 1)
    else if (root.quickOpen && (key === Qt.Key_Left || key === Qt.Key_Right)) cycleQuick(key === Qt.Key_Left ? -1 : 1)
    else if (root.actionsOpen && (key === Qt.Key_Left || key === Qt.Key_Right)) cycleAction(key === Qt.Key_Left ? -1 : 1)
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
      quickOpen:quickOpen,quickIndex:quickIndex,rail:railProgress,quickApps:quickApps.map(function(a) {return a.appId}),selected:selected,actionsOpen:actionsOpen,actionIndex:actionIndex,results:results.map(function(r) {return {kind:r.kind,title:r.title,id:resultId(r)} })})
  }
  onQueryChanged: refresh()
  onFilterChanged: refresh()
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
      width: Math.min(680, panel.width - 32)
      height: 66 + (root.expanded ? 40 + body.height + footer.height + 12 : 0)
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.max(16, panel.height * 0.20 - 32) - 8 * (1 - root.windowProgress)
      opacity: root.windowProgress
      scale: 0.97 + root.windowProgress * 0.03
      transformOrigin: Item.Top
      Behavior on height { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
      Rectangle {
        anchors.fill: parent
        visible: root.expanded
        radius: 28
      gradient: Gradient {
        GradientStop { position: 0; color: "#daeae6e3" }
        GradientStop { position: 0.45; color: "#cce4dfdc" }
        GradientStop { position: 1; color: "#d9e7e3e7" }
      }
      border.width: 1
      border.color: "#aaffffff"
      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#40000000"
        shadowBlur: 0.8
        shadowVerticalOffset: 12
      }
      }
      MorphSurface {
        id: morph
        visible: !root.expanded
        x: -18; y: -18
        width: surface.width + 36; height: 102
        railProgress: root.railProgress
        mainLeft: 18
        collapsedMainWidth: surface.width
        expandedMainWidth: surface.width - root.quickApps.length * (buttonDiameter + buttonGap)
        shapeCenterY: 51
        shapeHeight: 66
        mainCornerRadius: 28
        buttonCount: root.quickApps.length
        buttonDiameter: Math.min(64, Math.max(28, (surface.width - 180) / 4 - 10))
        buttonGap: 10
        blurEdgeInset: 2
        surfaceColor: "#d9e8e5e3"
        shadowColor: "#40000000"
      }
      MouseArea { anchors.fill: parent }
      Canvas {
        x: 20; y: 23; width: 22; height: 22
        visible: !root.commandMode
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.strokeStyle = "#756b65"
          ctx.lineWidth = 1.8
          ctx.lineCap = "round"
          ctx.beginPath(); ctx.arc(9, 9, 6, 0, Math.PI * 2); ctx.stroke()
          ctx.beginPath(); ctx.moveTo(13.5, 13.5); ctx.lineTo(19, 19); ctx.stroke()
        }
      }
      Label {
        x: 21; y: 19; width: 24; height: 28
        visible: root.commandMode
        text: ">"; font.pixelSize: 26; color: "#756b65"
      }
      TextInput {
        id: input
        x: 52; y: 0
        width: (root.expanded ? surface.width : morph.mainWidth) - 110; height: 66
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        selectByMouse: true
        color: root.ink
        selectionColor: "#66007aff"
        selectedTextColor: root.ink
        font.family: root.uiFont
        font.pixelSize: 24
        text: root.query
        onTextChanged: root.query = text
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { root.handleKey(event) }
        Label {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          text: "Spotlight-Suche"
          color: "#88635c58"
          font.pixelSize: 24
          visible: !input.text.length
        }
      }
      Rectangle {
        anchors.right: parent.right; anchors.rightMargin: 20; y: 21
        width: 25; height: 25; radius: 13
        visible: root.query.length > 0
        color: clearMouse.containsMouse ? "#25382e28" : "#14382e28"
        Label { anchors.centerIn: parent; text: "×"; font.pixelSize: 19 }
        MouseArea { id: clearMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { root.query = ""; input.forceActiveFocus() } }
      }
      Rectangle {
        x: morph.mainWidth - 82; y: 21
        width: 64; height: 25; radius: 9
        visible: !root.expanded && !root.quickOpen && root.railProgress < 0.01 && root.quickApps.length > 0
        color: quickHintMouse.containsMouse ? "#20382e28" : "#10382e28"
        Label { anchors.centerIn: parent; text: "Apps ⇥"; font.pixelSize: 12 }
        MouseArea { id: quickHintMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.cycleQuick(1) }
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
          y: (66 - height) / 2
          width: morph.buttonDiameter; height: width
          opacity: reveal
          scale: 0.9 + reveal * 0.1
          Rectangle {
            anchors.fill: parent; anchors.margins: 3
            radius: width / 2
            color: root.quickIndex === quickButton.index || quickMouse.containsMouse ? "#20382e28" : "transparent"
            border.width: root.quickIndex === quickButton.index ? 1 : 0
            border.color: "#70ffffff"
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
        color: "#e6e8e5e3"
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
        x: 8; y: 66; width: parent.width - 16
        height: filtersRow.height + body.height + footer.height
        Rectangle { x: 14; width: parent.width - 28; height: 1; color: "#18382e28" }
        Row {
          id: filtersRow
          x: 8; y: 8; spacing: 5; height: 32
          Repeater {
            model: root.commandMode ? [{key:"all",label:"Befehl"}] : root.filters
            delegate: Rectangle {
              required property var modelData
              width: chipLabel.implicitWidth + 24; height: 26; radius: 13
              color: root.filter === modelData.key ? "#25382e28" : chipMouse.containsMouse ? "#12382e28" : "transparent"
              Label { id: chipLabel; anchors.centerIn: parent; text: modelData.label; font.pixelSize: 12; font.weight: root.filter === modelData.key ? Font.DemiBold : Font.Normal }
              MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.setFilter(modelData.key) }
            }
          }
        }
        Item {
          id: body
          y: 40; width: parent.width
          height: Math.min(420, Math.max(52, panel.height - surface.y - 210), root.results.length ? root.results.length * 56 : 76)
          ListView {
            id: list
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
              color: index === root.selected ? root.selection : rowMouse.containsMouse ? "#10382e28" : "transparent"
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
                Label { width: parent.width; text: row.modelData.title; font.pixelSize: row.modelData.kind === "calc" ? 22 : 15 }
                Label { width: parent.width; text: row.modelData.subtitle; font.pixelSize: 12; color: "#b3534943" }
              }
              Label { anchors.right: parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter; text: "↵"; font.pixelSize: 19; visible: row.index === root.selected; color: "#88635c58" }
              MouseArea {
                id: rowMouse
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { root.selected = row.index; root.performAction("open") }
              }
            }
          }
          Label {
            anchors.centerIn: parent; width: parent.width - 32
            horizontalAlignment: Text.AlignHCenter
            visible: root.results.length === 0
            text: root.searching ? "Dateien werden gesucht …" : root.searchError ? "Dateisuche nicht verfügbar" : root.commandMode ? "Befehl nach > eingeben" : root.filter === "calc" ? "Rechnung eingeben, z. B. 125 × 1,19" : root.filter === "file" && root.query.trim().length < 2 ? "Mindestens zwei Zeichen eingeben" : "Keine Treffer"
            color: "#b3534943"
          }
        }
        Item {
          id: footer
          y: body.y + body.height + 4
          width: parent.width; height: root.actionsOpen ? 46 : 32
          Rectangle { x: 14; width: parent.width - 28; height: 1; color: "#14382e28" }
          Label {
            x: 14; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - actionsButton.width - 40
            visible: !root.actionsOpen
            font.pixelSize: 11; color: "#b3534943"
            text: root.searching ? "Dateien werden gesucht …" : root.searchError ? "Dateisuche nicht verfügbar · Apps bleiben nutzbar" : "↑↓ Auswählen    ↵ Öffnen    Strg + ←/→ Filter"
          }
          Rectangle {
            id: actionsButton
            visible: !root.actionsOpen && !!root.current
            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            width: 96; height: 24; radius: 8
            color: actionsMouse.containsMouse ? "#20382e28" : "transparent"
            Label { anchors.centerIn: parent; text: "Aktionen   ⇥"; font.pixelSize: 12 }
            MouseArea { id: actionsMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.cycleAction(1) }
          }
          Row {
            visible: root.actionsOpen
            x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6
            Repeater {
              model: root.actions
              delegate: Rectangle {
                required property var modelData
                required property int index
                width: actionText.implicitWidth + 22; height: 30; radius: 10
                color: index === root.actionIndex ? "#30382e28" : actionMouse.containsMouse ? "#15382e28" : "transparent"
                Label { id: actionText; anchors.centerIn: parent; text: modelData.label; font.pixelSize: 12 }
                MouseArea { id: actionMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.performAction(modelData.key) }
              }
            }
          }
        }
      }
    }
  }
}
