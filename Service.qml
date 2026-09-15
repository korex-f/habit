import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "js/ActivityStateMachine.js" as ActivityStateMachine
import "js/ActivityStore.js" as ActivityStore

Item {
  id: root

  readonly property int productionIdleTimeoutSeconds: 300
  readonly property int minimumIdleTimeoutSeconds: 30
  readonly property int maximumIdleTimeoutSeconds: 3600
  readonly property int idleTimeoutSeconds: configuredIdleTimeout()
  readonly property int lockPollIntervalMs: 3000
  readonly property bool debugEnabled: Quickshell.env("HABIT_DEBUG") === "1"
  readonly property string sessionId: Quickshell.env("XDG_SESSION_ID")
  readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchy-habit"
  readonly property string databasePath: dataDir + "/habit.db"
  readonly property string settingsPath: dataDir + "/settings.json"

  // Raw platform signals. Never derive state by overwriting these values.
  property bool idle: false
  property bool locked: false
  property bool suspended: false
  property bool disabled: false
  property bool trackingEnabled: true
  property int idleTimeoutSettingSeconds: productionIdleTimeoutSeconds
  property string barDisplayMode: "off"
  property bool settingsLoaded: false
  property bool settingsHydrating: false
  property bool clearingHistory: false
  property bool historyClearPending: false
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
  property bool storageReady: false
  property string storageHealth: "starting"
  property int totalStoredSessions: 0
  property double todayStoredDurationMs: 0
  property double totalStoredDurationMs: 0
  // Changes only after a durable storage refresh. Panels use this to refresh
  // historical range data after a checkpoint or completed session.
  property int activityDataRevision: 0
  property int activeSessionId: 0
  property double activeSessionStartMs: 0
  property double activeSessionCheckpointMs: 0
  property bool sessionStartPending: false
  property bool sessionEndPending: false
  property var dbQueue: []
  property var dbCurrent: null
  property double displayNowMs: Date.now()
  readonly property double todayDurationMs: todayStoredDurationMs + liveTodayDelta()
  readonly property double totalDurationMs: totalStoredDurationMs + liveTodayDelta()

  function configuredIdleTimeout() {
    var raw = String(Quickshell.env("HABIT_IDLE_TIMEOUT") || "").trim()
    if (raw === "") return validIdleTimeout(idleTimeoutSettingSeconds) ? idleTimeoutSettingSeconds : productionIdleTimeoutSeconds
    var value = Number(raw)
    if (!isFinite(value) || value < 1 || Math.floor(value) !== value || value > 86400) {
      console.warn("[habit] invalid HABIT_IDLE_TIMEOUT; using persisted setting")
      return validIdleTimeout(idleTimeoutSettingSeconds) ? idleTimeoutSettingSeconds : productionIdleTimeoutSeconds
    }
    return value
  }

  function validIdleTimeout(value) {
    var seconds = Number(value)
    return isFinite(seconds) && Math.floor(seconds) === seconds
      && seconds >= minimumIdleTimeoutSeconds && seconds <= maximumIdleTimeoutSeconds
  }

  function normalizeBarDisplay(value) {
    var mode = String(value || "off")
    return mode === "icon" || mode === "icon-today" ? mode : "off"
  }

  function log(message) { console.log("[habit] " + message) }
  function debug(message) { if (debugEnabled) log("debug " + message) }
  function sourceSummary() { return "idle=" + idle + " locked=" + locked + " suspended=" + suspended + " disabled=" + disabled }

  function reconcile(reason) {
    if (!settingsLoaded || !idleKnown || !lockKnown || resumeReevaluationPending) return
    var result = ActivityStateMachine.transition(effectiveState, { idle: idle, locked: locked, suspended: suspended, disabled: disabled })
    if (!startupLogged) {
      effectiveState = result.state
      startupLogged = true
      log("initial state=" + effectiveState + " " + sourceSummary())
      syncTracking()
      return
    }
    if (!result.changed) return
    var previous = effectiveState
    effectiveState = result.state
    log(previous + " -> " + effectiveState + " reason=" + reason)
    syncTracking()
  }

  function todayStartMs() {
    var now = new Date(); return new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  }

  function liveTodayDelta() {
    if (!activeSessionId || effectiveState !== ActivityStateMachine.ACTIVE) return 0
    return Math.max(0, displayNowMs - Math.max(activeSessionCheckpointMs, todayStartMs()))
  }

  function nextLocalMidnight(ms) {
    var day = new Date(ms); return new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1).getTime()
  }

  function localDayBoundaries(startMs, endMs) {
    var first = new Date(startMs); var cursor = new Date(first.getFullYear(), first.getMonth(), first.getDate())
    var bounds = [cursor.getTime()]
    while (bounds[bounds.length - 1] < endMs) {
      cursor.setDate(cursor.getDate() + 1)
      bounds.push(cursor.getTime())
    }
    return bounds
  }

  function queueDb(label, command, callback) {
    var next = dbQueue.slice(); next.push({ label: label, command: command, callback: callback }); dbQueue = next; runNextDb()
  }

  function queueSql(label, sql, callback) { queueDb(label, ["sqlite3", "-batch", "-noheader", databasePath, sql], callback) }

  function runNextDb() {
    if (dbProcess.running || dbCurrent || dbQueue.length === 0) return
    dbCurrent = dbQueue[0]; dbProcess.command = dbCurrent.command; dbProcess.running = true
  }

  function failStorage(label, detail) {
    storageHealth = "error: " + label
    console.warn("[habit] storage error=" + label + " " + detail)
  }

  function initializeStorage() {
    queueDb("mkdir", ["mkdir", "-p", dataDir], function() {
      queueSql("schema", ActivityStore.schemaSql(), function() {
        queueSql("recovery", ActivityStore.recoverSql(), function() {
          storageReady = true; storageHealth = "ok"; refreshStorageStats(); syncTracking(); log("storage ready")
        })
      })
    })
  }

  function loadSettings(raw) {
    if (settingsLoaded) return
    var parsed = ({})
    try { parsed = JSON.parse(raw || "{}") || ({}) } catch (error) { console.warn("[habit] settings parse failed") }
    settingsHydrating = true
    trackingEnabled = parsed.trackingEnabled !== false
    idleTimeoutSettingSeconds = validIdleTimeout(parsed.idleTimeoutSeconds)
      ? Number(parsed.idleTimeoutSeconds) : productionIdleTimeoutSeconds
    barDisplayMode = normalizeBarDisplay(parsed.barDisplayMode)
    disabled = !trackingEnabled
    settingsHydrating = false
    settingsLoaded = true
    reconcile("settings-loaded")
  }

  function saveSettings() {
    if (!settingsLoaded || settingsHydrating) return
    settingsSaveTimer.restart()
  }

  function flushSettings() {
    settingsFile.setText(JSON.stringify({ version: 1, trackingEnabled: trackingEnabled,
      idleTimeoutSeconds: idleTimeoutSettingSeconds, barDisplayMode: barDisplayMode }, null, 2) + "\n")
  }

  function setTrackingEnabled(value) {
    var next = value === true
    if (trackingEnabled === next) return
    trackingEnabled = next
    setDisabled(!next)
    saveSettings()
  }

  function setIdleTimeoutSetting(value) {
    var next = Number(value)
    if (!validIdleTimeout(next) || idleTimeoutSettingSeconds === next) return false
    idleTimeoutSettingSeconds = next
    saveSettings()
    return true
  }

  function setBarDisplayMode(value) {
    var next = normalizeBarDisplay(value)
    if (barDisplayMode === next) return
    barDisplayMode = next
    saveSettings()
  }

  function refreshStorageStats(onRefreshed) {
    if (!storageReady) return
    queueSql("count", ActivityStore.countSql(), function(output) { totalStoredSessions = Number(output.trim() || 0) })
    var start = todayStartMs(); var end = nextLocalMidnight(start)
    queueSql("today-total", ActivityStore.totalBetweenSql(start, end), function(output) {
      todayStoredDurationMs = Number(output.trim() || 0)
    })
    queueSql("total-duration", ActivityStore.totalDurationSql(), function(output) {
      totalStoredDurationMs = Number(output.trim() || 0)
      activityDataRevision += 1
      if (onRefreshed) onRefreshed()
    })
  }

  // Public future-UI API. Results are local-day overlap totals, including
  // sessions that cross midnight; no content metadata exists in the schema.
  function requestDailyTotals(startMs, endMs, callback) {
    if (!storageReady) { callback([]); return }
    queueSql("daily-totals", ActivityStore.dailySql(localDayBoundaries(startMs, endMs)), function(output) {
      try { callback(JSON.parse(output.trim() || "[]")) } catch (error) { callback([]) }
    })
  }

  function requestDayDetail(dayStartMs, callback) {
    if (!storageReady) { callback(emptyDayDetail(dayStartMs)); return }
    var start = todayStartMsFor(dayStartMs); var end = nextLocalMidnight(start)
    queueSql("day-sessions", ActivityStore.daySessionsSql(start, end), function(output) {
      var sessions = []
      try { sessions = JSON.parse(output.trim() || "[]") } catch (error) {}
      callback(buildDayDetail(start, end, sessions))
    })
  }

  function todayStartMsFor(ms) {
    var date = new Date(ms); return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
  }

  function emptyDayDetail(start) { return { dayStartMs: start, durationMs: 0, firstStartMs: null, lastEndMs: null, sessionCount: 0, longestDurationMs: 0, sessions: [] } }

  function buildDayDetail(start, end, storedSessions) {
    var sessions = storedSessions.slice()
    var now = Date.now()
    if (activeSessionId && effectiveState === ActivityStateMachine.ACTIVE) {
      var liveStart = Math.max(activeSessionStartMs, start)
      var liveEnd = Math.min(now, end)
      if (liveEnd > liveStart) {
        var found = false
        for (var i = 0; i < sessions.length; i++) if (Number(sessions[i].id) === activeSessionId) {
          sessions[i].end = Math.max(Number(sessions[i].end), liveEnd); found = true; break
        }
        if (!found) sessions.push({ id: activeSessionId, start: liveStart, end: liveEnd })
      }
    }
    sessions.sort(function(a, b) { return Number(a.start) - Number(b.start) })
    var detail = emptyDayDetail(start)
    detail.sessions = sessions
    for (var j = 0; j < sessions.length; j++) {
      var duration = Math.max(0, Number(sessions[j].end) - Number(sessions[j].start))
      if (!duration) continue
      detail.durationMs += duration
      detail.firstStartMs = detail.firstStartMs === null ? Number(sessions[j].start) : Math.min(detail.firstStartMs, Number(sessions[j].start))
      detail.lastEndMs = detail.lastEndMs === null ? Number(sessions[j].end) : Math.max(detail.lastEndMs, Number(sessions[j].end))
      detail.sessionCount += 1
      detail.longestDurationMs = Math.max(detail.longestDurationMs, duration)
    }
    return detail
  }

  function syncTracking() {
    if (!storageReady || !startupLogged || clearingHistory) return
    if (effectiveState === ActivityStateMachine.ACTIVE && activeSessionId === 0 && !sessionStartPending) beginSession()
    else if (effectiveState !== ActivityStateMachine.ACTIVE && activeSessionId !== 0 && !sessionEndPending) endSession()
  }

  function beginSession() {
    sessionStartPending = true
    var now = Date.now()
    queueSql("session-start", ActivityStore.startSql(now), function(output) {
      sessionStartPending = false
      activeSessionId = Number(output.trim() || 0); activeSessionStartMs = now; activeSessionCheckpointMs = now
      if (!activeSessionId) { failStorage("session-start", "missing id"); return }
      if (clearingHistory) { endSession(); return }
      refreshStorageStats(); log("session started")
      syncTracking()
    })
  }

  function checkpointSession() {
    if (!storageReady || !activeSessionId) return
    var now = Date.now()
    queueSql("session-checkpoint", ActivityStore.checkpointSql(activeSessionId, activeSessionStartMs, now), function() {
      // Retain the old in-memory checkpoint until its durable total has been
      // read back. That keeps persisted duration + live delta continuous at
      // the checkpoint boundary without changing the 60-second write policy.
      refreshStorageStats(function() { activeSessionCheckpointMs = now })
    })
  }

  function endSession() {
    sessionEndPending = true
    var id = activeSessionId; var started = activeSessionStartMs; var now = Date.now()
    queueSql("session-end", ActivityStore.endSql(id, started, now), function() {
      activeSessionId = 0; activeSessionStartMs = 0; activeSessionCheckpointMs = 0; sessionEndPending = false
      if (clearingHistory) { performClearHistory(); return }
      refreshStorageStats(); log("session ended"); syncTracking()
    })
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

  function setDisabled(value) {
    if (disabled === (value === true)) return
    disabled = value === true
    reconcile(disabled ? "tracking-disabled" : "tracking-enabled")
  }

  function clearHistory() {
    if (!storageReady || clearingHistory) return false
    clearingHistory = true
    if (sessionStartPending) { historyClearPending = true; return true }
    if (activeSessionId && !sessionEndPending) { endSession(); return true }
    performClearHistory()
    return true
  }

  function performClearHistory() {
    queueSql("clear-history", ActivityStore.clearHistorySql(), function() {
      todayStoredDurationMs = 0; totalStoredDurationMs = 0; totalStoredSessions = 0
      clearingHistory = false; historyClearPending = false; activityDataRevision += 1
      log("history cleared")
      syncTracking()
    })
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
  Timer { id: checkpointTimer; interval: 60000; repeat: true; onTriggered: root.checkpointSession() }
  Timer { id: displayTimer; interval: 1000; repeat: true; running: root.effectiveState === ActivityStateMachine.ACTIVE; onTriggered: root.displayNowMs = Date.now() }
  Timer { id: settingsSaveTimer; interval: 200; repeat: false; onTriggered: root.flushSettings() }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.loadSettings("")
  }

  Process {
    id: dbProcess
    running: false
    stdout: StdioCollector { id: dbStdout; waitForEnd: true }
    stderr: StdioCollector { id: dbStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var work = root.dbCurrent; root.dbCurrent = null
      var next = root.dbQueue.slice(1); root.dbQueue = next
      if (!work) { root.runNextDb(); return }
      if (exitCode !== 0) root.failStorage(work.label, String(dbStderr.text || dbStdout.text || "exit=" + exitCode).trim())
      else if (work.callback) work.callback(String(dbStdout.text || ""))
      root.runNextDb()
    }
  }

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
      root.displayNowMs = Date.now()
      return JSON.stringify({ state: root.effectiveState, idle: root.idle, locked: root.locked, suspended: root.suspended, disabled: root.disabled, trackingEnabled: root.trackingEnabled, idleTimeoutSeconds: root.idleTimeoutSeconds, barDisplayMode: root.barDisplayMode, currentActiveSessionStart: root.activeSessionId ? root.activeSessionStartMs : null, todayActiveDurationMs: root.todayDurationMs, totalActiveDurationMs: root.totalDurationMs, totalStoredSessions: root.totalStoredSessions, storageHealth: root.storageHealth, databasePath: root.databasePath, lockDetection: "omarchy-shell-poll" })
    }
    function disable(): void { root.setTrackingEnabled(false) }
    function enable(): void { root.setTrackingEnabled(true) }
  }

  Component.onCompleted: {
    log("service started")
    if (idleTimeoutSeconds !== productionIdleTimeoutSeconds) log("idle timeout=" + idleTimeoutSeconds + "s source=HABIT_IDLE_TIMEOUT")
    initialIdleTimer.start()
    log("lock detection=omarchy-shell polling interval=" + (lockPollIntervalMs / 1000) + "s")
    lockPollTimer.start()
    requestLockProbe("startup-lock")
    startSuspendListener()
    checkpointTimer.start()
    settingsFile.reload()
    initializeStorage()
  }

  Component.onDestruction: {
    stopping = true
    initialIdleTimer.stop(); lockPollTimer.stop(); suspendListenerRestart.stop(); checkpointTimer.stop(); displayTimer.stop(); settingsSaveTimer.stop()
    lockProbe.running = false; suspendListener.running = false; dbProcess.running = false
    log("service stopping")
  }
}
