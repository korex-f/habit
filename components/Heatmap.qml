import QtQuick
import "../js/DateUtils.js" as DateUtils

// Contribution-style grid: one column per week, one row per weekday. The
// panel keeps `rangeStartMs` on the first day of a week, so every row is a
// fixed weekday; days after today in the final column stay blank.
Item {
  id: root

  required property double rangeStartMs
  required property double selectedDateMs
  required property double todayStartMs
  required property double liveTodayDurationMs
  property var totals: ({})
  property int weekCount: 13
  property int daysPerWeek: 7
  property int firstDayOfWeek: 0
  property int cellSize: 12
  property int cellSpacing: 3
  property string fontFamily: "monospace"
  property int labelPixelSize: 9
  required property color foreground
  required property color accent
  required property color muted

  signal daySelected(real dayStartMs)

  readonly property int dayCount: weekCount * daysPerWeek
  readonly property int gridWidth: weekCount * cellSize + (weekCount - 1) * cellSpacing
  implicitWidth: labels.width + cellSpacing * 2 + gridWidth
  implicitHeight: daysPerWeek * cellSize + (daysPerWeek - 1) * cellSpacing
  width: implicitWidth
  height: implicitHeight

  function durationForDay(dayStartMs) {
    if (dayStartMs === todayStartMs) return liveTodayDurationMs
    return Number(totals[DateUtils.dateKey(dayStartMs)] || 0)
  }

  function weekdayLabel(row) {
    var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    return names[(firstDayOfWeek + row) % 7]
  }

  // Label alternate rows, as contribution graphs do, to stay compact.
  Column {
    id: labels
    anchors.left: parent.left
    spacing: root.cellSpacing
    Repeater {
      model: root.daysPerWeek
      Text {
        required property int index
        height: root.cellSize
        verticalAlignment: Text.AlignVCenter
        // Hide via opacity, not empty text: positioners skip zero-width items,
        // which would collapse the column and misalign the labels.
        text: root.weekdayLabel(index)
        opacity: index % 2 === 1 ? 1 : 0
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: root.labelPixelSize
      }
    }
  }

  Grid {
    anchors.right: parent.right
    width: root.gridWidth
    height: parent.height
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
        future: dateMs > root.todayStartMs
        foreground: root.foreground
        accent: root.accent
        muted: root.muted
        cellSize: root.cellSize
        onDaySelected: function(dayStartMs) { root.daySelected(dayStartMs) }
      }
    }
  }
}
