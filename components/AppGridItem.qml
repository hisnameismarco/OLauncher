// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import "Visual.js" as Visual

Item {
  id: root
  required property var app
  required property bool selected
  required property color ink
  required property color selectionColor
  required property string uiFont
  property bool reorderEnabled: true
  property bool dragged: false
  property bool showLabel: true
  signal activated()
  signal contextRequested()
  signal dragStarted(point position)
  signal dragMoved(point position)
  signal dragFinished(point position)
  signal dragCanceled()
  opacity: dragged ? 0.28 : 1
  // Scale the artwork only: hit geometry and drag coordinates never move.
  readonly property real opticalScale: mouse.pressed && !mouse.dragging ? 0.97 : mouse.containsMouse ? 1.02 : 1


  Rectangle {
    anchors.fill: parent
    anchors.margins: 3
    radius: Visual.radiusItem
    border.width: root.selected ? 1 : 0
    border.color: Visual.alpha(root.ink,0.25)
    Behavior on color { ColorAnimation { duration: Visual.fast } }
    color: root.selected ? root.selectionColor : mouse.containsMouse ? Visual.alpha(root.ink,0.07) : "transparent"
  }
  AppFolderItem {
    anchors.horizontalCenter: parent.horizontalCenter
    y: 10; width: 38; height: 38
    visible: root.app.kind === "folder"
    ink: root.ink
    icons: root.app.preview || []
    scale: root.opticalScale
    Behavior on scale { NumberAnimation { duration: Visual.fast; easing.type: Easing.OutCubic } }
  }
  Image {
    id: appIcon
    scale: root.opticalScale
    Behavior on scale { NumberAnimation { duration: Visual.fast; easing.type: Easing.OutCubic } }
    visible: root.app.kind !== "folder"
    anchors.horizontalCenter: parent.horizontalCenter
    y: 10
    width: 38; height: 38
    source: root.app.icon || ""
    sourceSize.width: 76; sourceSize.height: 76
    fillMode: Image.PreserveAspectFit
  }
  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    y: 10; width: 38; height: 38; radius: Visual.radiusControl
    visible: root.app.kind !== "folder" && (appIcon.status === Image.Error || appIcon.status === Image.Null)
    color: Visual.alpha(root.ink,0.08)
    Text {
      anchors.centerIn: parent; text: "▦"; color: root.ink
      font.family: root.uiFont; font.pixelSize: 22
    }
  }
  Text {
    visible: root.showLabel
    x: 8; y: 56
    width: parent.width - 16
    text: root.app.title
    textFormat: Text.PlainText
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
    color: root.ink
    font.family: root.uiFont
    font.pixelSize: 12
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    preventStealing: root.reorderEnabled
    property point pressPosition
    property bool moved: false
    property bool dragging: false
    cursorShape: Qt.PointingHandCursor
    onPressed: function(event) {
      pressPosition = Qt.point(event.x, event.y)
      moved = false
      dragging = false
    }
    onPositionChanged: function(event) {
      if (!pressed || !(pressedButtons & Qt.LeftButton) || !root.reorderEnabled) return
      var point = Qt.point(event.x, event.y)
      if (!moved && Math.hypot(point.x - pressPosition.x, point.y - pressPosition.y) >= Qt.styleHints.startDragDistance) {
        moved = true
        dragging = true
        root.dragStarted(point)
      }
      if (dragging) root.dragMoved(point)
    }
    onReleased: function(event) {
      if (dragging) root.dragFinished(Qt.point(event.x, event.y))
      dragging = false
    }
    onCanceled: { if (dragging) root.dragCanceled(); dragging = false; moved = true }
    onClicked: function(event) { if (!moved) { if (event.button === Qt.RightButton) root.contextRequested(); else root.activated() } }
  }
}
