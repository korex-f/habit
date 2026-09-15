import QtQuick
import qs.Commons
import "../js/DateUtils.js" as DateUtils

Column {
  id: root

  required property var sessions
  required property color foreground
  required property color muted
  required property color accent
  required property string fontFamily
  spacing: 7

  readonly property double longest: {
    var max = 1
    for (var i = 0; i < sessions.length; i++) max = Math.max(max, Number(sessions[i].end) - Number(sessions[i].start))
    return max
  }

  Repeater {
    model: root.sessions

    Item {
      required property var modelData
      width: root.width
      height: 20
      readonly property double duration: Math.max(0, Number(modelData.end) - Number(modelData.start))

      Text { id: start; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: Qt.formatTime(new Date(modelData.start), "HH:mm"); color: root.muted; font.family: root.fontFamily }
      Rectangle {
        anchors.left: start.right; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Style.space(18), Math.min(Style.space(135), Style.space(135) * duration / root.longest))
        height: 4; radius: 2; color: root.accent
      }
      Text { id: end; anchors.right: durationLabel.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: Qt.formatTime(new Date(modelData.end), "HH:mm"); color: root.muted; font.family: root.fontFamily }
      Text { id: durationLabel; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: DateUtils.formatDuration(duration); color: root.foreground; font.family: root.fontFamily }
    }
  }
}
