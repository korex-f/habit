import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "js/ActivityStateMachine.js" as ActivityStateMachine

Item {
  id: root

  readonly property int productionIdleTimeoutSeconds: 300
  readonly property int idleTimeoutSeconds: configuredIdleTimeout()
  readonly property int lockPollIntervalMs: 3000
  readonly property bool debugEnabled: Quickshell.env("HABIT_DEBUG") === "1"
  readonly property string sessionId: Quickshell.env("XDG_SESSION_ID")

  // Raw platform signals. Never derive state by overwriting these values.
  property bool idle: false
  property bool locked: false
  property bool suspended: false
  property bool idleKnown: false
  property bool lockKnown: false
  property bool resumeReevaluationPending: false
  property bool startupLogged: false
  property bool stopping: false
  // Omarchy's native WlSessionLock does not update logind LockedHint on this
  // installation (verified during the platform spike), so the documented
  // Omarchy IPC is the reliable source of lock state.
  property bool usingLockPollFallback: true
  property bool lockProbePending: false
  property string effectiveState: ""
  property string lockProbeReason: "startup"
  property string lockProbeOutput: ""

  function configuredIdleTimeout() {
    var raw = String(Quickshell.env("HABIT_IDLE_TIMEOUT") || "").trim()
    if (raw === "") return productionIdleTimeoutSeconds
    var value = Number(raw)
    if (!isFinite(value) || value < 1 || Math.floor(value) !== value || value > 86400) {
      console.warn("[habit] invalid HABIT_IDLE_TIMEOUT; using " + productionIdleTimeoutSeconds + "s")
      return productionIdleTimeoutSeconds
    }
    return value
  }

  function log(message) { console.log("[habit] " + message) }
  function debug(message) { if (debugEnabled) log("debug " + message) }
  function sourceSummary() { return "idle=" + idle + " locked=" + locked + " suspended=" + suspended }

  function reconcile(reason) {
    if (!idleKnown || !lockKnown || resumeReevaluationPending) return
    var result = ActivityStateMachine.transition(effectiveState, { idle: idle, locked: locked, suspended: suspended })
    if (!startupLogged) {
      effectiveState = result.state
      startupLogged = true
      log("initial state=" + effectiveState + " " + sourceSummary())
      return
    }
    if (!result.changed) return
    var previous = effectiveState
    effectiveState = result.state
    log(previous + " -> " + effectiveState + " reason=" + reason)
  }

  function setIdle(value, reason) {
    var next = value === true
    if (idle === next && idleKnown) return
    idle = next
    idleKnown = true
    debug("idle=" + idle + " reason=" + reason)
    reconcile(reason)
  }

  function setLocked(value, reason) {
    var next = value === true
    if (locked === next && lockKnown) return
    locked = next
    lockKnown = true
    debug("locked=" + locked + " reason=" + reason)
    reconcile(reason)
  }

  function setSuspended(value, reason) {
    var next = value === true
    if (suspended === next) return
    suspended = next
    debug("suspended=" + suspended + " reason=" + reason)
    reconcile(reason)
  }

  function requestLockProbe(reason) {
    lockProbeReason = reason || "lock-probe"
    if (lockProbe.running) { lockProbePending = true; return }
    lockProbe.command = usingLockPollFallback
      ? ["omarchy-shell", "lock", "isLocked"]
      : ["loginctl", "show-session", sessionId, "-p", "LockedHint", "--value"]
    lockProbe.running = true
  }

  function consumeLockProbe() {
    var normalized = String(lockProbeOutput || "").trim().toLowerCase()
    if (normalized === "true" || normalized === "yes") {
      setLocked(true, lockProbeReason)
      finishResumeReevaluation()
    } else if (normalized === "false" || normalized === "no") {
      setLocked(false, lockProbeReason)
      finishResumeReevaluation()
    }
    else {
      console.warn("[habit] lock-state probe failed; output=" + JSON.stringify(normalized))
      if (!lockKnown) console.warn("[habit] lock state is not yet known; retrying")
    }
  }

  function finishResumeReevaluation() {
    if (!resumeReevaluationPending) return
    resumeReevaluationPending = false
    reconcile("resume")
  }

  function startSuspendListener() {
    if (stopping || suspendListener.running) return
    suspendListener.command = ["dbus-monitor", "--system", "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"]
    suspendListener.running = true
  }

  IdleMonitor {
    id: idleMonitor
    enabled: true
    timeout: root.idleTimeoutSeconds
    respectInhibitors: true
    onIsIdleChanged: root.setIdle(isIdle, isIdle ? "idle-timeout" : "input-resumed")
  }

  Timer { id: initialIdleTimer; interval: 250; repeat: false; onTriggered: root.setIdle(idleMonitor.isIdle, "startup-idle") }
  Timer { id: lockPollTimer; interval: root.lockPollIntervalMs; repeat: true; onTriggered: root.requestLockProbe("lock-poll") }
  Timer { id: suspendListenerRestart; interval: 5000; repeat: false; onTriggered: root.startSuspendListener() }

  Process {
    id: lockProbe
    running: false
    stdout: SplitParser { onRead: function(line) { root.lockProbeOutput = String(line).trim() } }
    onStarted: root.lockProbeOutput = ""
    onExited: function(exitCode) {
      if (exitCode === 0) root.consumeLockProbe()
      else {
        console.warn("[habit] lock-state probe exited=" + exitCode)
        if (!root.lockKnown) root.requestLockProbe("startup-lock-retry")
      }
      if (root.lockProbePending && !root.stopping) {
        root.lockProbePending = false
        root.requestLockProbe(root.lockProbeReason)
      }
    }
  }

  Process {
    id: suspendListener
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        var match = String(line).match(/^\s*boolean\s+(true|false)\s*$/)
        if (!match) return
        if (match[1] === "true") root.setSuspended(true, "prepare-for-sleep")
        else {
          // Do not expose ACTIVE from a stale pre-suspend lock value. The
          // fresh IPC probe below decides the post-resume derived state.
          root.resumeReevaluationPending = true
          root.setSuspended(false, "resume")
          root.requestLockProbe("resume")
          root.setIdle(idleMonitor.isIdle, "resume")
        }
      }
    }
    onExited: function(exitCode) {
      if (root.stopping) return
      console.warn("[habit] suspend listener exited=" + exitCode + "; retrying")
      suspendListenerRestart.restart()
    }
  }

  IpcHandler {
    target: "habit"
    function status(): string {
      return JSON.stringify({ state: root.effectiveState, idle: root.idle, locked: root.locked, suspended: root.suspended, idleTimeoutSeconds: root.idleTimeoutSeconds, lockDetection: "omarchy-shell-poll" })
    }
  }

  Component.onCompleted: {
    log("service started")
    if (idleTimeoutSeconds !== productionIdleTimeoutSeconds) log("idle timeout=" + idleTimeoutSeconds + "s source=HABIT_IDLE_TIMEOUT")
    initialIdleTimer.start()
    log("lock detection=omarchy-shell polling interval=" + (lockPollIntervalMs / 1000) + "s")
    lockPollTimer.start()
    requestLockProbe("startup-lock")
    startSuspendListener()
  }

  Component.onDestruction: {
    stopping = true
    initialIdleTimer.stop(); lockPollTimer.stop(); suspendListenerRestart.stop()
    lockProbe.running = false; suspendListener.running = false
    log("service stopping")
  }
}
