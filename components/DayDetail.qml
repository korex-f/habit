import QtQuick
import qs.Commons
import "../js/DateUtils.js" as DateUtils

Item {
  id: root

  required property double dayStartMs
  required property var detail
  required property color foreground
  required property color muted
  required property color accent
  required property string fontFamily

  implicitHeight: content.implicitHeight

  function longDate() {
    var date = new Date(dayStartMs)
    return Qt.formatDate(date, "dddd, MMMM d").toUpperCase()
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(14)

    Text { text: root.longDate(); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.heading; font.bold: true }

    Item {
      width: parent.width; height: activeLabel.implicitHeight
      Text { id: activeLabel; anchors.left: parent.left; text: "Active"; color: root.muted; font.family: root.fontFamily }
      Text { anchors.right: parent.right; text: DateUtils.formatDuration(root.detail.durationMs); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title }
    }

    Column {
      width: parent.width; spacing: 5
      Repeater {
        model: [
          { label: "First activity", value: root.detail.firstStartMs === null ? "—" : Qt.formatTime(new Date(root.detail.firstStartMs), "HH:mm") },
          { label: "Last activity", value: root.detail.lastEndMs === null ? "—" : Qt.formatTime(new Date(root.detail.lastEndMs), "HH:mm") },
          { label: "Sessions", value: String(root.detail.sessionCount) },
          { label: "Longest session", value: root.detail.longestDurationMs ? DateUtils.formatDuration(root.detail.longestDurationMs) : "—" }
        ]
        Item {
          required property var modelData
          width: parent.width; height: 19
          Text { anchors.left: parent.left; text: modelData.label; color: root.muted; font.family: root.fontFamily }
          Text { anchors.right: parent.right; text: modelData.value; color: root.foreground; font.family: root.fontFamily }
        }
      }
    }

    Text { text: "ACTIVITY"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.5 }

    Text { visible: root.detail.sessionCount === 0; text: "No activity recorded"; color: root.muted; font.family: root.fontFamily }
    ActivityTimeline { visible: root.detail.sessionCount > 0; width: parent.width; sessions: root.detail.sessions; foreground: root.foreground; muted: root.muted; accent: root.accent; fontFamily: root.fontFamily }
  }
}
