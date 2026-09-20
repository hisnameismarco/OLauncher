// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import "Visual.js" as Visual

Item {
  id: root
  required property string folderName
  required property var apps
  required property int selectedIndex
  required property color ink
  required property color selectionColor
  required property string uiFont
  property bool reorderEnabled: true
  property bool editing: false
  readonly property int columns: grid.columns
  readonly property real preferredHeight: grid.preferredHeight + 42
  readonly property bool dragging: grid.dragging
  signal closed()
  signal activated(string key)
  signal reordered(string key, int targetIndex)
  signal dragSelected(string key)
  signal contextRequested(string key)
  signal renamed(string name)
  signal editCanceled()

  function cancelDrag() { grid.cancelDrag() }
  function beginRename() { editing = true; editor.text = folderName; editor.forceActiveFocus(); editor.selectAll() }
  function cancelRename() { if (editing) { editing = false; editCanceled() } }
  onVisibleChanged: { if (!visible) { cancelDrag(); cancelRename() } else reveal.restart() }
  NumberAnimation { id: reveal; target: root; property: "opacity"; from: 0; to: 1; duration: Visual.normal; easing.type: Easing.OutCubic }

  Rectangle {
    anchors.fill: parent; radius: Visual.radiusPanel
    color: Visual.alpha(root.ink,0.035)
    border.width: 1; border.color: Visual.alpha(root.ink,0.07)
  }
  Rectangle {
    x: 40; y: 4; width: parent.width - 48; height: 31
    radius: Visual.radiusControl; visible: root.editing
    color: Visual.alpha(root.ink,0.06)
    border.width: 1; border.color: Visual.alpha(root.ink,0.35)
  }

  Rectangle {
    x: 5; y: 4; width: 32; height: 30; radius: Visual.radiusControl
    color: backMouse.containsMouse ? root.selectionColor : "transparent"
    Text { anchors.centerIn: parent; text: "‹"; color: root.ink; font.pixelSize: 24 }
    MouseArea { id: backMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.closed() }
  }
  Text {
    x: 44; y: 8; width: parent.width - 52
    visible: !root.editing
    text: root.folderName
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.ink
    font.family: root.uiFont
    font.pixelSize: 15
  }
  TextInput {
    id: editor
    objectName: "folderNameEditor"
    x: 44; y: 5; width: parent.width - 52; height: 30
    visible: root.editing
    maximumLength: 64
    clip: true
    selectByMouse: true
    verticalAlignment: TextInput.AlignVCenter
    selectionColor: root.selectionColor
    selectedTextColor: root.ink
    color: root.ink
    font.family: root.uiFont
    font.pixelSize: 15
    Keys.onReturnPressed: { root.editing = false; root.renamed(text) }
    Keys.onEnterPressed: { root.editing = false; root.renamed(text) }
    Keys.onEscapePressed: root.cancelRename()
  }
  AppGrid {
    id: grid
    y: 42; width: parent.width; height: Math.max(0,parent.height - y)
    apps: root.apps
    selectedIndex: root.selectedIndex
    reorderEnabled: root.reorderEnabled
    folderTargetsEnabled: false
    ink: root.ink
    selectionColor: root.selectionColor
    uiFont: root.uiFont
    onActivated: function(key) { root.activated(key) }
    onReordered: function(key, index) { root.reordered(key,index) }
    onDragSelected: function(key) { root.dragSelected(key) }
    onContextRequested: function(key) { root.contextRequested(key) }
  }
}
