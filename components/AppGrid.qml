// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import "Visual.js" as Visual
import "../logic/GridNavigation.js" as GridNavigation
import "../logic/AppLayout.js" as AppLayout

Item {
  id: root
  required property var apps
  required property int selectedIndex
  required property color ink
  required property color selectionColor
  required property string uiFont
  property bool reorderEnabled: true
  property bool folderTargetsEnabled: false
  property string folderCandidateKey: ""
  property bool folderArmed: false
  readonly property string dropMode: !dragging || targetIndex < 0 ? "none" : folderArmed ? (apps[markerIndex] && apps[markerIndex].kind === "folder" ? "folder-add" : "folder-create") : markerAfter ? "insert-after" : "insert-before"
  property string draggedId: ""
  readonly property bool dragging: draggedId.length > 0
  property var draggedApp: null
  property point dragPosition
  property int targetIndex: -1
  property int markerIndex: -1
  property bool markerAfter: false
  readonly property int columns: GridNavigation.columnsForWidth(width)
  readonly property real preferredHeight: Math.max(76, Math.ceil(apps.length / columns) * grid.cellHeight)
  signal activated(string appId)
  signal reordered(string appId, int targetIndex)
  signal dragSelected(string appId)
  signal contextRequested(string key)
  signal folderDropped(string sourceKey, string targetKey)

  function keyFor(item) { return item.key || item.appId }
  function clearFolderTarget() { folderHover.stop(); folderCandidateKey = ""; folderArmed = false }
  Timer { id: folderHover; interval: 400; onTriggered: if (root.dragging && root.folderCandidateKey) root.folderArmed = true }

  function cancelDrag() {
    clearFolderTarget()
    draggedId = ""
    draggedApp = null
    targetIndex = -1
    markerIndex = -1
  }
  function beginDrag(appId, position) {
    if (!reorderEnabled || !visible) return
    var app = apps.find(function(a) { return root.keyFor(a) === appId })
    if (!app) return
    draggedApp = app
    draggedId = appId
    // Keep the source as GridView's current item while scrolling during a drag.
    dragSelected(appId)
    updateDrag(position)
  }
  function updateDrag(position) {
    if (!dragging) return
    dragPosition = position
    targetIndex = -1
    markerIndex = -1
    if (position.x < 0 || position.y < 0 || position.x >= width || position.y >= height) { clearFolderTarget(); return }
    var from = apps.findIndex(function(a) { return root.keyFor(a) === draggedId })
    if (from < 0) { cancelDrag(); return }
    var over = grid.indexAt(position.x, position.y + grid.contentY)
    var after = true
    if (over < 0) over = apps.length - 1
    else after = (position.x % grid.cellWidth) >= grid.cellWidth / 2
    targetIndex = AppLayout.insertionTarget(from, over, after, apps.length)
    markerIndex = over
    markerAfter = after
    var cell = grid.itemAtIndex(over)
    var candidate = ""
    if (folderTargetsEnabled && draggedApp.kind !== "folder" && over !== from && cell) {
      var x = position.x - cell.x, y = position.y + grid.contentY - cell.y
      if (x > grid.cellWidth * 0.28 && x < grid.cellWidth * 0.72 && y > 12 && y < grid.cellHeight - 18)
        candidate = keyFor(apps[over])
    }
    if (candidate !== folderCandidateKey) {
      clearFolderTarget()
      folderCandidateKey = candidate
      if (candidate) folderHover.restart()
    }
  }
  function finishDrag(position) {
    if (!dragging) return
    updateDrag(position)
    var id = draggedId, target = targetIndex, folderTarget = folderArmed ? folderCandidateKey : ""
    cancelDrag()
    if (id && folderTarget) folderDropped(id,folderTarget)
    else if (id && target >= 0) reordered(id, target)
  }

  function revealSelection() {
    if (visible && !dragging && selectedIndex >= 0) {
      grid.forceLayout()
      grid.positionViewAtIndex(selectedIndex, GridView.Contain)
    }
  }
  onSelectedIndexChanged: Qt.callLater(revealSelection)
  onColumnsChanged: { cancelDrag(); Qt.callLater(revealSelection) }
  onHeightChanged: Qt.callLater(revealSelection)
  onVisibleChanged: { if (!visible) cancelDrag(); else reveal.restart(); Qt.callLater(revealSelection) }
  NumberAnimation { id: reveal; target: root; property: "opacity"; from: 0; to: 1; duration: Visual.fast; easing.type: Easing.OutCubic }
  onAppsChanged: { cancelDrag(); Qt.callLater(revealSelection) }

  GridView {
    id: grid
    objectName: "applicationGrid"
    anchors.fill: parent
    clip: true
    model: root.apps
    cellWidth: width / root.columns
    cellHeight: 88
    boundsBehavior: Flickable.StopAtBounds
    currentIndex: root.selectedIndex
    keyNavigationEnabled: false
    onCountChanged: Qt.callLater(root.revealSelection)
    onCellWidthChanged: Qt.callLater(root.revealSelection)
    onCurrentIndexChanged: Qt.callLater(root.revealSelection)
    onContentYChanged: if (root.dragging) { root.clearFolderTarget(); root.updateDrag(root.dragPosition) }
    delegate: AppGridItem {
      id: cell
      required property var modelData
      required property int index
      width: grid.cellWidth
      height: grid.cellHeight
      app: modelData
      selected: index === root.selectedIndex
      ink: root.ink
      selectionColor: root.selectionColor
      uiFont: root.uiFont
      reorderEnabled: root.reorderEnabled
      dragged: root.draggedId === root.keyFor(app)
      onActivated: root.activated(root.keyFor(app))
      onDragStarted: function(position) { root.beginDrag(root.keyFor(app), cell.mapToItem(root, position)) }
      onDragMoved: function(position) { root.updateDrag(cell.mapToItem(root, position)) }
      onDragFinished: function(position) { root.finishDrag(cell.mapToItem(root, position)) }
      onDragCanceled: root.cancelDrag()
      onContextRequested: root.contextRequested(root.keyFor(app))
    }
  }
  Rectangle {
    visible: root.dragging && root.markerIndex >= 0 && !root.folderArmed
    x: (root.markerIndex % root.columns + (root.markerAfter ? 1 : 0)) * grid.cellWidth - 2
    y: Math.floor(root.markerIndex / root.columns) * grid.cellHeight + grid.originY - grid.contentY + 5
    width: 2; height: grid.cellHeight - 10; radius: 1
    color: Visual.alpha(root.ink,0.75)
  }
  Rectangle {
    visible: root.dragging && root.folderCandidateKey.length > 0
    x: root.markerIndex % root.columns * grid.cellWidth + 3
    y: Math.floor(root.markerIndex / root.columns) * grid.cellHeight + grid.originY - grid.contentY + 3
    width: grid.cellWidth - 6; height: grid.cellHeight - 6; radius: 12
    color: root.folderArmed ? Visual.alpha(root.ink,0.12) : "transparent"
    Behavior on color { ColorAnimation { duration: Visual.fast } }
    border.color: root.ink
    border.width: root.folderArmed ? 2 : 1
    opacity: root.folderArmed ? 0.85 : 0.28
  }
  Text {
    visible: root.folderArmed
    z: 3
    x: Math.max(0, Math.min(root.width - width, root.dragPosition.x - width / 2))
    y: root.dragPosition.y + 44
    text: root.dropMode === "folder-add" ? "Move into folder" : "Create folder"
    color: root.ink
    font.family: root.uiFont
    font.pixelSize: 12
  }
  Rectangle {
    visible: root.dragging
    z: 1
    x: ghost.x + 2; y: ghost.y + 5
    width: ghost.width - 4; height: ghost.height - 4
    radius: Visual.radiusItem + 2
    color: "#18000000"
  }
  AppGridItem {
    id: ghost
    visible: root.dragging
    enabled: false
    z: 2
    x: Math.max(0,Math.min(root.width - width,root.dragPosition.x + 12))
    y: Math.max(0,root.dragPosition.y - height / 2)
    width: 58; height: 58
    showLabel: false
    app: root.draggedApp || {title:"", icon:""}
    selected: true
    ink: root.ink
    selectionColor: root.selectionColor
    uiFont: root.uiFont
    opacity: 0.90
    scale: 1.02
  }
  Text {
    anchors.centerIn: parent
    visible: root.apps.length === 0
    text: "No applications"
    color: root.ink
    font.family: root.uiFont
    font.pixelSize: 14
  }
}
