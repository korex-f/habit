import QtQuick
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

  signal daySelected(real dayStartMs)

  readonly property int level: DateUtils.activityLevel(durationMs)
  readonly property color fill: level === 0
    ? Qt.rgba(muted.r, muted.g, muted.b, 0.20)
    : Qt.rgba(accent.r, accent.g, accent.b, [0, 0.28, 0.45, 0.65, 0.88][level])

  width: cellSize
  height: cellSize
  radius: Math.max(1, Math.floor(cellSize / 4))
  // Future days keep their grid slot so rows stay aligned to weekdays.
  color: future ? "transparent" : fill
  border.width: selected ? Math.max(1, Math.floor(cellSize / 6)) : (today ? 1 : 0)
  border.color: selected ? foreground : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)

  MouseArea {
    enabled: !root.future
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.daySelected(root.dayStartMs)
  }
}
