import QtQuick
import qs.Commons

// Presentation only. Panel.qml owns keyboard focus (`focusIndex`) and applies
// every change through the service.
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
  // Rows: 0 tracking, 1 idle threshold, 2 bar display, 3 open data, 4 clear.
  property int focusIndex: -1

  signal trackingToggled()
  signal idleTimeoutAdjusted(int deltaMinutes)
  signal barModeRequested(string mode)
  signal openDataRequested()
  signal clearHistoryRequested()
  signal rowClicked(int index)

  implicitHeight: content.implicitHeight

  readonly property int idleMinutes: Math.floor(idleTimeoutSeconds / 60)

  component Label: Text { color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.4 }
  // Do not call this `Row`: the bar-mode selector below intentionally uses
  // QtQuick.Row for its spacing/layout behavior. The focus frame is drawn
  // behind the row's content and does not rely on color alone.
  component SettingRow: Item {
    id: settingRow
    property int rowIndex: -1
    readonly property bool focused: root.focusIndex === rowIndex
    width: content.width; height: 28
    Rectangle {
      anchors.fill: parent
      anchors.leftMargin: -6; anchors.rightMargin: -6
      radius: 3
      color: settingRow.focused ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10) : "transparent"
      border.width: settingRow.focused ? 1 : 0
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
    }
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(12)

    Label { text: "TRACKING" }
    SettingRow {
      rowIndex: 0
      Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Track activity"; color: root.foreground; font.family: root.fontFamily }
      Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.trackingEnabled ? "On" : "Off"; color: root.trackingEnabled ? root.accent : root.muted; font.family: root.fontFamily }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.rowClicked(0); root.trackingToggled() } }
    }

    Label { text: "IDLE THRESHOLD" }
    SettingRow {
      rowIndex: 1
      Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Idle threshold"; color: root.foreground; font.family: root.fontFamily }
      Row {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 10
        Text {
          text: "−"; color: root.muted; font.family: root.fontFamily
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.rowClicked(1); root.idleTimeoutAdjusted(-1) } }
        }
        Text { text: root.idleMinutes + (root.idleMinutes === 1 ? " minute" : " minutes"); color: root.foreground; font.family: root.fontFamily }
        Text {
          text: "+"; color: root.accent; font.family: root.fontFamily
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.rowClicked(1); root.idleTimeoutAdjusted(1) } }
        }
      }
    }

    Label { text: "BAR" }
    SettingRow {
      rowIndex: 2
      Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Display"; color: root.foreground; font.family: root.fontFamily }
      Row {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
        Repeater {
          model: [{mode:"off",label:"Off"},{mode:"icon",label:"Icon"},{mode:"icon-today",label:"Icon + Today"}]
          Text {
            required property var modelData
            text: modelData.label; color: root.barDisplayMode === modelData.mode ? root.accent : root.muted; font.family: root.fontFamily
            font.underline: root.barDisplayMode === modelData.mode
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.rowClicked(2); root.barModeRequested(modelData.mode) } }
          }
        }
      }
    }

    Label { text: "DATA" }
    SettingRow {
      rowIndex: 3
      Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Open data directory"; color: root.foreground; font.family: root.fontFamily }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.rowClicked(3); root.openDataRequested() } }
    }
    SettingRow {
      rowIndex: 4
      Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Clear history"; color: root.foreground; font.family: root.fontFamily }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.rowClicked(4); root.clearHistoryRequested() } }
    }

    Label { text: "ABOUT" }
    Text { text: "Habit " + root.version; color: root.muted; font.family: root.fontFamily }
  }
}
