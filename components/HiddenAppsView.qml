// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import "Visual.js" as Visual

Item {
  id: root
  required property var apps
  required property int totalHidden
  required property color ink
  required property color selectionColor
  required property string uiFont
  readonly property var rows: apps.map(function(app) {
    return {key:"app:" + app.appId,appId:app.appId,title:app.title,icon:app.icon,all:false}
  }).concat(totalHidden ? [{key:"action:restore-all",title:"Unhide all",icon:"",all:true}] : [])
  readonly property real preferredHeight: 42 + Math.max(76,rows.length * 48)
  property int selectedIndex: -1
  property string selectedKey: ""
  signal closed()
  signal restoreRequested(string appId)
  signal restoreAllRequested()

  function select(index) {
    selectedIndex = rows.length ? Math.max(0,Math.min(rows.length - 1,index)) : -1
    selectedKey = selectedIndex >= 0 ? rows[selectedIndex].key : ""
  }
  function reconcileSelection() {
    var found = rows.findIndex(function(row) { return row.key === root.selectedKey })
    select(found >= 0 ? found : selectedIndex)
  }
  function moveSelection(delta) { select(selectedIndex + delta) }
  function activateSelected() {
    var row = rows[selectedIndex]
    if (!row) return
    if (row.all) restoreAllRequested()
    else restoreRequested(row.appId)
  }
  onRowsChanged: reconcileSelection()
  onVisibleChanged: if (visible) { select(0); reveal.restart() }
  NumberAnimation { id: reveal; target: root; property: "opacity"; from: 0; to: 1; duration: Visual.fast; easing.type: Easing.OutCubic }
  Component.onCompleted: reconcileSelection()

  Rectangle {
    x: 5; y: 4; width: 32; height: 30; radius: Visual.radiusControl
    color: backMouse.containsMouse ? root.selectionColor : "transparent"
    Text { anchors.centerIn: parent; text: "‹"; color: root.ink; font.pixelSize: 24 }
    MouseArea { id: backMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.closed() }
  }
  Text {
    x: 44; y: 8; width: parent.width - 52
    text: "Hidden apps"
    color: root.ink; font.family: root.uiFont; font.pixelSize: 15
    elide: Text.ElideRight
  }
  ListView {
    id: list
    objectName: "hiddenAppsList"
    y: 42; width: parent.width; height: Math.max(0,parent.height - y)
    clip: true
    model: root.rows
    currentIndex: root.selectedIndex
    keyNavigationEnabled: false
    boundsBehavior: Flickable.StopAtBounds
    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex,ListView.Contain)
    delegate: Rectangle {
      required property var modelData
      required property int index
      width: list.width; height: 48; radius: Visual.radiusItem
      color: index === root.selectedIndex ? root.selectionColor : mouse.containsMouse ? Visual.alpha(root.ink,0.07) : "transparent"
      border.width: index === root.selectedIndex ? 1 : 0
      border.color: Visual.alpha(root.ink,0.25)
      Behavior on color { ColorAnimation { duration: Visual.fast } }
      Image {
        x: 12; anchors.verticalCenter: parent.verticalCenter
        width: 30; height: 30
        visible: !modelData.all
        source: modelData.icon || ""
        sourceSize.width: 60; sourceSize.height: 60
        fillMode: Image.PreserveAspectFit
      }
      Text {
        x: modelData.all ? 12 : 52
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - 98
        text: modelData.title; textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.ink; font.family: root.uiFont; font.pixelSize: 14
      }
      Text {
        anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
        text: modelData.all ? "↵" : "Unhide"
        color: root.ink; font.family: root.uiFont; font.pixelSize: 12
      }
      MouseArea {
        id: mouse
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: { root.select(index); root.activateSelected() }
      }
    }
  }
  Text {
    anchors.centerIn: list
    visible: root.rows.length === 0
    text: "No hidden apps"
    opacity: 0.68
    color: root.ink; font.family: root.uiFont; font.pixelSize: 14
  }
}
