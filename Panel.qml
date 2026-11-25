import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "js/DateUtils.js" as DateUtils
import "js/ActivityStateMachine.js" as ActivityStateMachine
import "components"

// Main Habit panel. The service is the only source of persisted data; this
// surface holds only presentation state (selection, viewport, and a cached
// daily-total map) while it is open.
Item {
  id: root

  property var service: null
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string view: "main"
  property var dayDetail: ({ dayStartMs: 0, durationMs: 0, firstStartMs: null, lastEndMs: null, sessionCount: 0, longestDurationMs: 0, sessions: [] })
  property int requestSerial: 0
  property var dayTotals: ({})
  // Settings and confirm-dialog keyboard focus. Settings rows are, in order:
  // tracking, idle threshold, bar display, open data directory, clear history.
  readonly property int settingsRowCount: 5
  readonly property var barModes: ["off", "icon", "icon-today"]
  property int settingsIndex: 0
  property int confirmIndex: 0

  readonly property int heatmapWeeks: 13
  readonly property int heatmapDays: heatmapWeeks * 7
  // Heatmap rows are fixed weekdays, starting from the locale's first day.
  readonly property int firstDayOfWeek: Qt.locale().firstDayOfWeek
  // The panel is keepLoaded and outlives calendar days; refreshToday() keeps
  // this current on every open and at local midnight.
  property double todayStartMs: DateUtils.localDayStart(Date.now())
  property double selectedDateMs: todayStartMs
  // Always the first day of a week; the last column contains today.
  property double visibleRangeStartMs: latestRangeStart()
  readonly property color background: Color.popups.background
  readonly property color foreground: Color.foreground
  readonly property color muted: Color.muted
  readonly property color accent: Color.accent
  readonly property color border: Color.popups.border
  readonly property string fontFamily: Style.font.family
  readonly property int cardWidth: Style.space(460)
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property var borderSpec: Border.surfaceSpec("popups", "border", border, Math.max(1, Style.space(2)))

  function formatDuration(ms) { return DateUtils.formatDuration(ms) }
  // "Tracking · 2h 13m today": whether Habit is counting right now, in words.
  readonly property string statusText: {
    if (!service) return ""
    var label = ActivityStateMachine.statusLabel(service.effectiveState, service.storageHealth)
    var today = service.todayDurationMs
    return today > 0 ? label + " · " + DateUtils.formatDuration(today) + " today" : label
  }
  function totalForDay(dayStartMs) {
    if (dayStartMs === todayStartMs) return service ? service.todayDurationMs : 0
    return Number(dayTotals[DateUtils.dateKey(dayStartMs)] || 0)
  }

  function refreshToday() { todayStartMs = DateUtils.localDayStart(Date.now()) }

  function latestRangeStart() {
    return DateUtils.addLocalDays(DateUtils.weekStart(todayStartMs, firstDayOfWeek), -7 * (heatmapWeeks - 1))
  }

  function resetSelectionToToday() {
    refreshToday()
    selectedDateMs = todayStartMs
    visibleRangeStartMs = latestRangeStart()
  }

  // The range moves in whole weeks so each row keeps its weekday.
  function ensureSelectionVisible() {
    var selectedWeek = DateUtils.weekStart(selectedDateMs, firstDayOfWeek)
    var rangeEndMs = DateUtils.addLocalDays(visibleRangeStartMs, heatmapDays - 1)
    if (selectedDateMs < visibleRangeStartMs)
      visibleRangeStartMs = selectedWeek
    else if (selectedDateMs > rangeEndMs)
      visibleRangeStartMs = DateUtils.addLocalDays(selectedWeek, -7 * (heatmapWeeks - 1))

    // Future selection is blocked, so the range never needs to end after
    // the week containing today.
    var latestStart = latestRangeStart()
    if (visibleRangeStartMs > latestStart) visibleRangeStartMs = latestStart
  }

  function selectDate(dayStartMs) {
    var normalized = DateUtils.localDayStart(dayStartMs)
    selectedDateMs = Math.min(normalized, todayStartMs)
    ensureSelectionVisible()
    reloadTotals()
    if (view === "detail") loadDayDetail()
  }

  function moveSelection(days) { selectDate(DateUtils.addLocalDays(selectedDateMs, days)) }

  function loadDayDetail() {
    if (!service || typeof service.requestDayDetail !== "function") return
    var requestedDay = selectedDateMs
    service.requestDayDetail(requestedDay, function(detail) {
      if (root.view === "detail" && root.selectedDateMs === requestedDay) root.dayDetail = detail
    })
  }

  function openDetail() { view = "detail"; loadDayDetail() }
  function openSettings() { settingsIndex = 0; view = "settings" }
  function openConfirm() { confirmIndex = 0; view = "confirm" } // Cancel is the default.

  function adjustIdleTimeout(deltaMinutes) {
    if (!service) return
    var seconds = service.idleTimeoutSettingSeconds + deltaMinutes * 60
    service.setIdleTimeoutSetting(Math.max(60, Math.min(3600, seconds)))
  }

  function cycleBarMode(step) {
    if (!service) return
    var i = barModes.indexOf(service.barDisplayMode)
    service.setBarDisplayMode(barModes[(Math.max(0, i) + step + barModes.length) % barModes.length])
  }

  function adjustSetting(step) {
    if (!service) return
    if (settingsIndex === 0) service.setTrackingEnabled(step > 0)
    else if (settingsIndex === 1) adjustIdleTimeout(step)
    else if (settingsIndex === 2) cycleBarMode(step)
  }

  function activateSetting() {
    if (!service) return
    if (settingsIndex === 0) service.setTrackingEnabled(!service.trackingEnabled)
    else if (settingsIndex === 1) adjustIdleTimeout(1)
    else if (settingsIndex === 2) cycleBarMode(1)
    else if (settingsIndex === 3) service.openDataDirectory()
    else if (settingsIndex === 4) openConfirm()
  }

  function confirmClearHistory() {
    if (service) service.clearHistory()
    view = "main"
  }

  function reloadTotals() {
    if (!service || !opened || typeof service.requestDailyTotals !== "function") return
    // The one query covers the viewport and the fixed last-seven-days list.
    // It remains small even when navigating the heatmap into older history.
    var rangeEnd = DateUtils.addLocalDays(visibleRangeStartMs, heatmapDays)
    var lastSevenStart = DateUtils.addLocalDays(todayStartMs, -6)
    var queryStart = Math.min(visibleRangeStartMs, lastSevenStart)
    var queryEnd = Math.max(rangeEnd, DateUtils.addLocalDays(todayStartMs, 1))
    var serial = ++requestSerial
    service.requestDailyTotals(queryStart, queryEnd, function(rows) {
      if (serial !== root.requestSerial) return
      var next = ({})
      for (var i = 0; i < rows.length; i++) next[DateUtils.dateKey(rows[i].start)] = Number(rows[i].durationMs || 0)
      root.dayTotals = next
    })
  }

  function open(payloadJson) {
    resetSelectionToToday() // v0.1 intentionally starts each opening at today.
    view = "main"
    opened = true
    if (service && typeof service.setPanelOpen === "function") service.setPanelOpen(true)
    Qt.callLater(function() {
      if (!root.opened) return
      root.reloadTotals()
      keyCatcher.forceActiveFocus()
    })
  }

  function isOpen() { return opened }
  function close() {
    opened = false
    if (service && typeof service.setPanelOpen === "function") service.setPanelOpen(false)
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "io.github.dki.habit")
    else close()
  }

  Connections {
    target: root.service
    function onActivityDataRevisionChanged() { if (root.opened) root.reloadTotals() }
  }

  onServiceChanged: {
    if (opened && service && typeof service.setPanelOpen === "function") service.setPanelOpen(true)
    if (opened) reloadTotals()
  }
  onVisibleRangeStartMsChanged: if (opened) reloadTotals()

  // The service tracks local days dynamically. Keep a long-open panel on the
  // same calendar day after midnight without polling or rebuilding history.
  Timer {
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: {
      var currentDay = DateUtils.localDayStart(Date.now())
      if (currentDay === root.todayStartMs) return
      root.resetSelectionToToday()
      root.reloadTotals()
      if (root.view === "detail") root.loadDayDetail()
    }
  }

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "io.github.dki.habit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(root.cardWidth, Math.max(Style.space(300), parent.width - Style.space(32)))
      // BorderSurface content in a layer-shell window does not reliably
      // propagate an anchored Column's implicit height. Keep this compact,
      // theme-scaled panel explicit rather than allowing a zero-height card.
      height: Math.min(Style.space(470), parent.height - Style.space(32))
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.text === "q" || event.text === "Q") {
            root.dismiss()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            if (root.view === "confirm") root.view = "settings"
            else if (root.view !== "main") root.view = "main"
            else root.dismiss()
            event.accepted = true
            return
          }
          var key = String(event.text || "").toLowerCase()
          var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space
          if (root.view === "help") return
          if (root.view === "settings") {
            if (key === "j" || event.key === Qt.Key_Down) root.settingsIndex = Math.min(root.settingsRowCount - 1, root.settingsIndex + 1)
            else if (key === "k" || event.key === Qt.Key_Up) root.settingsIndex = Math.max(0, root.settingsIndex - 1)
            else if (key === "h" || event.key === Qt.Key_Left) root.adjustSetting(-1)
            else if (key === "l" || event.key === Qt.Key_Right) root.adjustSetting(1)
            else if (enter) root.activateSetting()
            else return
            event.accepted = true
            return
          }
          if (root.view === "confirm") {
            if (key === "h" || key === "l" || event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab)
              root.confirmIndex = root.confirmIndex === 0 ? 1 : 0
            else if (enter) {
              if (root.confirmIndex === 1) root.confirmClearHistory()
              else root.view = "settings"
            }
            else return
            event.accepted = true
            return
          }
          if (root.view === "detail") {
            if (key === "h") root.moveSelection(-1)
            else if (key === "l") root.moveSelection(1)
            else if (key === "g") root.selectDate(root.todayStartMs)
            else return
            event.accepted = true
            return
          }
          if (key === "s") root.openSettings()
          else if (key === "?") root.view = "help"
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.openDetail()
          else if (key === "j") root.moveSelection(1)
          else if (key === "k") root.moveSelection(-1)
          else if (key === "h") root.moveSelection(-7)
          else if (key === "l") root.moveSelection(7)
          else if (key === "g") root.selectDate(root.todayStartMs)
          else return
          event.accepted = true
        }
      }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.space(16)

        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, closeButton.implicitHeight)

          Text {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "HABIT"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 2
          }

          Text {
            anchors.left: title.right
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusText
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelActionButton {
            id: closeButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "×"
            tooltipText: "Close  ( Esc / q )"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.dismiss()
          }
          PanelActionButton {
            anchors.right: closeButton.left; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
            visible: root.view === "main"
            iconText: "⚙"; tooltipText: "Settings  ( s )"; foreground: root.foreground; fontFamily: root.fontFamily
            onClicked: root.openSettings()
          }
        }

        Heatmap {
          id: heatmap
          visible: root.view === "main"
          anchors.horizontalCenter: parent.horizontalCenter
          rangeStartMs: root.visibleRangeStartMs
          selectedDateMs: root.selectedDateMs
          todayStartMs: root.todayStartMs
          firstDayOfWeek: root.firstDayOfWeek
          liveTodayDurationMs: root.service ? root.service.todayDurationMs : 0
          totals: root.dayTotals
          foreground: root.foreground
          accent: root.accent
          muted: root.muted
          cellSize: Style.space(12)
          cellSpacing: Math.max(2, Style.space(3))
          fontFamily: root.fontFamily
          onDaySelected: function(dayStartMs) { root.selectDate(dayStartMs) }
        }

        Item {
          visible: root.view === "main"
          width: parent.width
          height: Math.max(legend.implicitHeight, totalLabel.implicitHeight)

          // Swatches use the same colors as the heatmap cells.
          Row {
            id: legend
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.max(2, Style.space(3))
            Text { text: "Less"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
            Item { width: Style.space(4); height: 1 }
            Repeater {
              model: 5
              Rectangle {
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                width: heatmap.cellSize; height: heatmap.cellSize
                radius: Math.max(1, Math.floor(heatmap.cellSize / 4))
                color: DateUtils.levelColor(index, root.accent, root.muted, Qt.rgba)
              }
            }
            Item { width: Style.space(4); height: 1 }
            Text { text: "More"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
          }

          Text {
            id: totalLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Total  " + root.formatDuration(root.service ? root.service.totalDurationMs : 0)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Text {
          visible: root.view === "main"
          text: "LAST 7 DAYS"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.5
        }

        Column {
          visible: root.view === "main"
          width: parent.width
          spacing: 2

          Repeater {
            model: 7

            DayRow {
              required property int index
              readonly property double dateMs: DateUtils.addLocalDays(root.todayStartMs, index - 6)
              width: parent.width
              dayStartMs: dateMs
              durationMs: root.totalForDay(dateMs)
              selected: dateMs === root.selectedDateMs
              today: dateMs === root.todayStartMs
              foreground: root.foreground
              muted: root.muted
              accent: root.accent
              fontFamily: root.fontFamily
              onDaySelected: function(dayStartMs) { root.selectDate(dayStartMs) }
            }
          }
        }

        Flickable {
          id: detailFlickable
          visible: root.view === "detail"
          width: parent.width
          height: Math.min(detailContent.implicitHeight, Style.space(390))
          contentWidth: width
          contentHeight: detailContent.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          DayDetail {
            id: detailContent
            width: detailFlickable.width
            dayStartMs: root.selectedDateMs
            detail: root.dayDetail
            foreground: root.foreground
            muted: root.muted
            accent: root.accent
            fontFamily: root.fontFamily
          }
        }

        Settings {
          visible: root.view === "settings"
          width: parent.width
          trackingEnabled: root.service ? root.service.trackingEnabled : true
          idleTimeoutSeconds: root.service ? root.service.idleTimeoutSettingSeconds : 300
          barDisplayMode: root.service ? root.service.barDisplayMode : "off"
          focusIndex: root.settingsIndex
          version: root.manifest && root.manifest.version ? root.manifest.version : "0.2.0"
          foreground: root.foreground; muted: root.muted; accent: root.accent; fontFamily: root.fontFamily
          onTrackingToggled: if (root.service) root.service.setTrackingEnabled(!root.service.trackingEnabled)
          onIdleTimeoutAdjusted: function(deltaMinutes) { root.adjustIdleTimeout(deltaMinutes) }
          onBarModeRequested: function(mode) { if (root.service) root.service.setBarDisplayMode(mode) }
          onOpenDataRequested: if (root.service) root.service.openDataDirectory()
          onClearHistoryRequested: root.openConfirm()
          onRowClicked: function(index) { root.settingsIndex = index }
        }

        Column {
          visible: root.view === "help"
          width: parent.width; spacing: 8
          Text { text: "SHORTCUTS"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.5 }
          Text { text: "j/k    day\nh/l    week\ng      today\nEnter  inspect\ns      settings\n?      shortcuts\nq      close"; color: root.foreground; font.family: root.fontFamily; lineHeight: 1.35 }
          Text { text: "IN SETTINGS"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.5 }
          Text { text: "j/k    move\nh/l    change\nEnter  toggle / open"; color: root.foreground; font.family: root.fontFamily; lineHeight: 1.35 }
          Text { text: "Esc back"; color: root.muted; font.family: root.fontFamily }
        }

        Column {
          visible: root.view === "confirm"
          width: parent.width; spacing: Style.space(12)
          Text { text: "CLEAR ALL HABIT HISTORY?"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.heading; font.bold: true }
          Text { text: "This permanently deletes recorded\nactivity sessions."; color: root.muted; font.family: root.fontFamily }
          Row {
            spacing: Style.space(10)
            Repeater {
              model: [{ label: "Cancel", destructive: false }, { label: "Clear history", destructive: true }]
              Rectangle {
                required property var modelData
                required property int index
                readonly property bool focused: root.confirmIndex === index
                width: buttonLabel.implicitWidth + Style.space(20)
                height: buttonLabel.implicitHeight + Style.space(10)
                radius: 3
                color: focused ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10) : "transparent"
                border.width: focused ? 1 : 0
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
                Text {
                  id: buttonLabel
                  anchors.centerIn: parent
                  text: modelData.label
                  color: modelData.destructive ? root.accent : (parent.focused ? root.foreground : root.muted)
                  font.family: root.fontFamily
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (modelData.destructive) root.confirmClearHistory()
                    else root.view = "settings"
                  }
                }
              }
            }
          }
          Text { text: "h/l choose · Enter confirm · Esc cancel"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
        }
      }
    }
  }
}
