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
        width: Math.round(root.width * 0.34); height: width
        source: modelData
        sourceSize.width: width * 2; sourceSize.height: height * 2
        fillMode: Image.PreserveAspectFit
      }
    }
  }
}
