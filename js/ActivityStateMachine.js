// Pure activity-state derivation for the platform spike. Platform I/O belongs
// in Service.qml so this remains independently testable and reusable later.

var ACTIVE = "ACTIVE"
var IDLE = "IDLE"
var LOCKED = "LOCKED"
var SUSPENDED = "SUSPENDED"
var DISABLED = "DISABLED"

function sources(input) {
  var value = input || {}
  return {
    idle: value.idle === true,
    locked: value.locked === true,
    suspended: value.suspended === true,
    disabled: value.disabled === true
  }
}

// Precedence is intentional: lock-screen input can make the idle protocol
// active, but that must never make Habit appear active while still locked.
function derive(input) {
  var value = sources(input)
  if (value.disabled) return DISABLED
  if (value.suspended) return SUSPENDED
  if (value.locked) return LOCKED
  if (value.idle) return IDLE
  return ACTIVE
}

function transition(previous, input) {
  var value = sources(input)
  var state = derive(value)
  return { state: state, changed: previous !== state, sources: value }
}

// The idle signal fires `idleTimeoutMs` after the last user input, so that is
// the true end of activity. Never end before the session began or after now.
function idleSessionEnd(sessionStartMs, nowMs, idleTimeoutMs) {
  var lastInput = nowMs - Math.max(0, Number(idleTimeoutMs) || 0)
  return Math.min(nowMs, Math.max(sessionStartMs, lastInput))
}

if (typeof module !== "undefined") {
  module.exports = { ACTIVE: ACTIVE, IDLE: IDLE, LOCKED: LOCKED, SUSPENDED: SUSPENDED, DISABLED: DISABLED, sources: sources, derive: derive, transition: transition, idleSessionEnd: idleSessionEnd }
}
