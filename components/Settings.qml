import QtQuick
import qs.Commons
import "../js/DateUtils.js" as DateUtils

Item {
  id: root

  required property bool trackingEnabled
  required property int idleTimeoutSeconds
  required property string barDisplayMode
  required property string version
  required property color foreground
  required property color muted
  required property color accent
  required property string fontFamily

  signal trackingToggled()
  signal idleTimeoutRequested(int seconds)
  signal barModeRequested(string mode)
  signal openDataRequested()
  signal clearHistoryRequested()

  implicitHeight: content.implicitHeight

  component Label: Text { color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.4 }
  component Row: Item { width: content.width; height: 28 }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(12)

    Label { text: "TRACKING" }
    Row {
      Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Track activity"; color: root.foreground; font.family: root.fontFamily }
      Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.trackingEnabled ? "On" : "Off"; color: root.trackingEnabled ? root.accent : root.muted; font.family: root.fontFamily }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.trackingToggled() }
    }

    Label { text: "IDLE THRESHOLD" }
    Row {
      Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Idle threshold"; color: root.foreground; font.family: root.fontFamily }
      Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: Math.floor(root.idleTimeoutSeconds / 60) + " minutes"; color: root.foreground; font.family: root.fontFamily }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.idleTimeoutRequested(root.idleTimeoutSeconds === 300 ? 600 : 300) }
    }

    Label { text: "BAR" }
    Row {
      Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Display"; color: root.foreground; font.family: root.fontFamily }
      Row {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
        Repeater {
          model: [{mode:"off",label:"Off"},{mode:"icon",label:"Icon"},{mode:"icon-today",label:"Icon + Today"}]
          Text {
            required property var modelData
            text: modelData.label; color: root.barDisplayMode === modelData.mode ? root.accent : root.muted; font.family: root.fontFamily
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.barModeRequested(modelData.mode) }
          }
        }
      }
    }

    Label { text: "DATA" }
    Row {
      Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Open data directory"; color: root.foreground; font.family: root.fontFamily }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openDataRequested() }
    }
    Row {
      Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Clear history"; color: root.foreground; font.family: root.fontFamily }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.clearHistoryRequested() }
    }

    Label { text: "ABOUT" }
    Text { text: "Habit " + root.version; color: root.muted; font.family: root.fontFamily }
  }
}
