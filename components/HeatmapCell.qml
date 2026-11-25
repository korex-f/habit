import QtQuick
import qs.Ui
import "../js/DateUtils.js" as DateUtils

Rectangle {
  id: root

  required property double dayStartMs
  required property double durationMs
  required property bool selected
  required property bool today
  property bool future: false
  required property color foreground
  required property color accent
  required property color muted
  property int cellSize: 12
  property string fontFamily: "monospace"

  signal daySelected(real dayStartMs)

  readonly property int level: DateUtils.activityLevel(durationMs)

  width: cellSize
  height: cellSize
  radius: Math.max(1, Math.floor(cellSize / 4))
  // Future days keep their grid slot so rows stay aligned to weekdays.
  color: future ? "transparent" : DateUtils.levelColor(level, accent, muted, Qt.rgba)
  border.width: selected ? Math.max(1, Math.floor(cellSize / 6)) : (today ? 1 : 0)
  border.color: selected ? foreground : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)

  MouseArea {
    id: mouse
    enabled: !root.future
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.daySelected(root.dayStartMs)
  }

  // One popup per hovered cell, not one per cell.
  Loader {
    active: mouse.containsMouse
    sourceComponent: PanelToolTip {
      visible: true
      text: DateUtils.shortDate(root.dayStartMs) + "\n" + DateUtils.formatDuration(root.durationMs)
      fontFamily: root.fontFamily
    }
  }
}
