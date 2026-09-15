import QtQuick
import "../js/DateUtils.js" as DateUtils

Item {
  id: root

  required property double dayStartMs
  required property double durationMs
  required property bool selected
  required property bool today
  required property color foreground
  required property color muted
  required property color accent
  property string fontFamily: "monospace"

  signal daySelected(real dayStartMs)

  implicitHeight: 28
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: 3
    color: root.selected ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10) : "transparent"
    border.width: root.selected ? 1 : 0
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    text: root.selected ? "›" : (root.durationMs > 0 ? "●" : "○")
    color: root.selected ? root.foreground : (root.durationMs > 0 ? root.accent : root.muted)
    font.family: root.fontFamily
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: 22
    anchors.verticalCenter: parent.verticalCenter
    text: DateUtils.weekdayDate(root.dayStartMs)
    color: root.foreground
    font.family: root.fontFamily
  }

  Text {
    anchors.right: duration.left
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    visible: root.today
    text: "TODAY"
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: 10
    font.bold: true
    font.letterSpacing: 1
  }

  Text {
    id: duration
    anchors.right: parent.right
    anchors.rightMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    text: DateUtils.formatDuration(root.durationMs)
    color: root.durationMs > 0 ? root.foreground : root.muted
    font.family: root.fontFamily
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.daySelected(root.dayStartMs)
  }
}
