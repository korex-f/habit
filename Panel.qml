import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "js/DateUtils.js" as DateUtils
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
  property double selectedDateMs: DateUtils.localDayStart(Date.now())
  property double visibleRangeStartMs: DateUtils.addLocalDays(DateUtils.localDayStart(Date.now()), -90)

  readonly property int heatmapWeeks: 13
  readonly property int heatmapDays: heatmapWeeks * 7
  property double todayStartMs: DateUtils.localDayStart(Date.now())
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
  function totalForDay(dayStartMs) {
    if (dayStartMs === todayStartMs) return service ? service.todayDurationMs : 0
    return Number(dayTotals[DateUtils.dateKey(dayStartMs)] || 0)
  }

  function resetSelectionToToday() {
    selectedDateMs = todayStartMs
    visibleRangeStartMs = DateUtils.addLocalDays(todayStartMs, -(heatmapDays - 1))
  }

  function ensureSelectionVisible() {
    var rangeEndMs = DateUtils.addLocalDays(visibleRangeStartMs, heatmapDays - 1)
    if (selectedDateMs < visibleRangeStartMs)
      visibleRangeStartMs = selectedDateMs
    else if (selectedDateMs > rangeEndMs)
      visibleRangeStartMs = DateUtils.addLocalDays(selectedDateMs, -(heatmapDays - 1))

    // Future selection is blocked, so a range ending after today can always
    // slide forward to its normal present-day endpoint.
    var latestStart = DateUtils.addLocalDays(todayStartMs, -(heatmapDays - 1))
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
    Qt.callLater(function() {
      if (!root.opened) return
      root.reloadTotals()
      keyCatcher.forceActiveFocus()
    })
  }

  function isOpen() { return opened }
  function close() { opened = false }

  function dismiss() {
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "io.github.dki.habit")
    else close()
  }

  Connections {
    target: root.service
    function onActivityDataRevisionChanged() { if (root.opened) root.reloadTotals() }
  }

  onServiceChanged: if (opened) reloadTotals()
  onVisibleRangeStartMsChanged: if (opened) reloadTotals()

  // The service tracks local days dynamically. Keep a long-open panel on the
  // same calendar day after midnight without polling or rebuilding history.
  Timer {
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: {
      var currentDay = DateUtils.localDayStart(Date.now())
      if (currentDay !== root.todayStartMs) root.resetSelectionToToday()
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
            if (root.view !== "main") root.view = "main"
            else root.dismiss()
            event.accepted = true
            return
          }
          var key = String(event.text || "").toLowerCase()
          if (root.view === "detail") {
            if (key === "h") root.moveSelection(-1)
            else if (key === "l") root.moveSelection(1)
            else if (key === "g") root.selectDate(root.todayStartMs)
            else return
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.openDetail()
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
        }

        Heatmap {
          id: heatmap
          visible: root.view === "main"
          anchors.horizontalCenter: parent.horizontalCenter
          rangeStartMs: root.visibleRangeStartMs
          selectedDateMs: root.selectedDateMs
          todayStartMs: root.todayStartMs
          liveTodayDurationMs: root.service ? root.service.todayDurationMs : 0
          totals: root.dayTotals
          foreground: root.foreground
          accent: root.accent
          muted: root.muted
          cellSize: Style.space(12)
          cellSpacing: Math.max(2, Style.space(3))
          onDaySelected: function(dayStartMs) { root.selectDate(dayStartMs) }
        }

        Item {
          visible: root.view === "main"
          width: parent.width
          height: legend.implicitHeight

          Text {
            id: legend
            anchors.left: parent.left
            text: "Less   ░ ▒ ▓ █   More"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.right: parent.right
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

        DayDetail {
          visible: root.view === "detail"
          width: parent.width
          dayStartMs: root.selectedDateMs
          detail: root.dayDetail
          foreground: root.foreground
          muted: root.muted
          accent: root.accent
          fontFamily: root.fontFamily
        }
      }
    }
  }
}
