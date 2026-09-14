import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Milestone 3 only: a small service-backed readout. Omarchy injects `service`
// from the matching service entry; this panel owns neither tracking nor store
// state. This is deliberately a standalone PanelWindow, not KeyboardPanel:
// KeyboardPanel is for bar-anchored popouts.
Item {
  id: root

  property var service: null
  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property color background: Color.popups.background
  readonly property color foreground: Color.foreground
  readonly property color muted: Color.muted
  readonly property color border: Color.popups.border
  readonly property string fontFamily: Style.font.family
  readonly property int cardWidth: Style.space(300)
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property var borderSpec: Border.surfaceSpec("popups", "border", border, Math.max(1, Style.space(2)))

  function formatDuration(ms) {
    var seconds = Math.floor(Math.max(0, Number(ms) || 0) / 1000)
    var hours = Math.floor(seconds / 3600)
    var minutes = Math.floor((seconds % 3600) / 60)
    if (hours) return hours + "h " + (minutes < 10 ? "0" : "") + minutes + "m"
    return minutes + "m"
  }

  function open(payloadJson) {
    opened = true
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  // Read-only lifecycle probe for the standard shell `call` helper. It is
  // useful for smoke tests and does not add a plugin-specific IPC surface.
  function isOpen() { return opened }

  // Called by the shell host for `shell hide`; keep this idempotent so a
  // user dismissal routed through shell.hide does not cause a second action.
  function close() { opened = false }

  // User-initiated close must inform the host so its open-panel registry
  // stays correct and the next `shell toggle` summons instead of hides.
  function dismiss() {
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "io.github.dki.habit")
    else close()
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

    // A transparent full-screen surface lets the card float independently of
    // any bar while the dimmer makes keyboard focus and dismissal predictable.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.30)
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(root.cardWidth, Math.max(Style.space(220), parent.width - Style.space(32)))
      height: content.implicitHeight + root.contentMargin * 2
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
          if (event.key === Qt.Key_Escape || event.text === "q" || event.text === "Q") {
            root.dismiss()
            event.accepted = true
          }
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
        spacing: Style.space(18)

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

        Column {
          spacing: Style.space(4)
          Text { text: "Today"; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.body }
          Text { text: root.formatDuration(root.service ? root.service.todayDurationMs : 0); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.display }
        }

        Item {
          width: parent.width
          height: stateLabel.implicitHeight
          Text { id: stateLabel; anchors.left: parent.left; text: "State"; color: root.muted; font.family: root.fontFamily }
          Text { anchors.right: parent.right; text: root.service ? root.service.effectiveState : "Starting…"; color: root.foreground; font.family: root.fontFamily }
        }
      }
    }
  }
}
