// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import "Visual.js" as Visual

Rectangle {
  id: root
  required property var icons
  property color ink: "#302b2b"
  radius: Visual.radiusControl
  color: Visual.alpha(ink,0.10)
  border.width: 1
  border.color: Visual.alpha(ink,0.10)
  Grid {
    anchors.centerIn: parent
    columns: 2; spacing: 2
    Repeater {
      model: root.icons.slice(0,4)
      Image {
        required property string modelData
        width: 14; height: 14
        source: modelData
        sourceSize.width: 28; sourceSize.height: 28
        fillMode: Image.PreserveAspectFit
      }
    }
  }
}
