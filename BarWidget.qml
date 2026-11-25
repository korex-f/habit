import QtQuick
import qs.Commons
import qs.Ui
import "js/DateUtils.js" as DateUtils
import "js/ActivityStateMachine.js" as ActivityStateMachine

// Optional bar surface. It reads only the long-lived service; no database or
// tracking logic lives in the widget.
BarWidget {
  id: root
  moduleName: "io.github.dki.habit"

  // BarWidget receives a restricted Bar facade. Its service-capable shell
  // facade is deliberately nested under `bar.shell`.
  readonly property var habitService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property string displayMode: habitService ? habitService.barDisplayMode : "off"
  readonly property bool shown: displayMode !== "off"
  readonly property string tooltipText: {
    if (!habitService) return "Habit"
    var label = ActivityStateMachine.statusLabel(habitService.effectiveState, habitService.storageHealth)
    return "Habit · " + label + " · " + DateUtils.formatDuration(habitService.todayDurationMs, "0m") + " today"
  }

  visible: shown
  implicitWidth: shown ? row.implicitWidth + Style.space(12) : 0
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(5)
    Text { text: "󰔟"; color: root.bar ? root.bar.barForeground : Color.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.body }
    Text {
      visible: root.displayMode === "icon-today"
      text: DateUtils.formatDuration(root.habitService ? root.habitService.todayDurationMs : 0)
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    // The bar facade owns tooltip placement; older shells may not expose it.
    onEntered: if (root.bar && typeof root.bar.showTooltip === "function") root.bar.showTooltip(root, root.tooltipText)
    onExited: if (root.bar && typeof root.bar.hideTooltip === "function") root.bar.hideTooltip(root)
    onClicked: {
      if (!root.bar || !root.bar.shell) return
      if (typeof root.bar.shell.toggle === "function") root.bar.shell.toggle(root.moduleName, "{}")
      else if (typeof root.bar.shell.summon === "function") root.bar.shell.summon(root.moduleName, "{}")
    }
  }
}
