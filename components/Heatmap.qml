import QtQuick
import "../js/DateUtils.js" as DateUtils

Item {
  id: root

  required property double rangeStartMs
  required property double selectedDateMs
  required property double todayStartMs
  required property double liveTodayDurationMs
  property var totals: ({})
  property int weekCount: 13
  property int daysPerWeek: 7
  property int cellSize: 12
  property int cellSpacing: 3
  required property color foreground
  required property color accent
  required property color muted

  signal daySelected(real dayStartMs)

  readonly property int dayCount: weekCount * daysPerWeek
  implicitWidth: weekCount * cellSize + (weekCount - 1) * cellSpacing
  implicitHeight: daysPerWeek * cellSize + (daysPerWeek - 1) * cellSpacing
  width: implicitWidth
  height: implicitHeight

  function durationForDay(dayStartMs) {
    if (dayStartMs === todayStartMs) return liveTodayDurationMs
    return Number(totals[DateUtils.dateKey(dayStartMs)] || 0)
  }

  Grid {
    anchors.fill: parent
    rows: root.daysPerWeek
    columns: root.weekCount
    flow: Grid.TopToBottom
    rowSpacing: root.cellSpacing
    columnSpacing: root.cellSpacing

    Repeater {
      model: root.dayCount

      HeatmapCell {
        required property int index
        readonly property double dateMs: DateUtils.addLocalDays(root.rangeStartMs, index)
        dayStartMs: dateMs
        durationMs: root.durationForDay(dateMs)
        selected: dateMs === root.selectedDateMs
        today: dateMs === root.todayStartMs
        foreground: root.foreground
        accent: root.accent
        muted: root.muted
        cellSize: root.cellSize
        onDaySelected: function(dayStartMs) { root.daySelected(dayStartMs) }
      }
    }
  }
}
