// Local-calendar helpers shared by the Milestone 4 panel surfaces. Dates are
// always local midnights; no navigation or range calculation adds a fixed day
// length, so DST transitions remain calendar-correct.

var HOUR_MS = 60 * 60 * 1000

function localDayStart(ms) {
  var date = new Date(ms)
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
}

function addLocalDays(dayStartMs, days) {
  var date = new Date(dayStartMs)
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days).getTime()
}

function dateKey(dayStartMs) { return String(localDayStart(dayStartMs)) }

// Local start of the calendar week containing `ms`. `firstDayOfWeek` uses
// Date#getDay numbering (0 = Sunday), matching QML's Locale.firstDayOfWeek.
function weekStart(ms, firstDayOfWeek) {
  var first = Number(firstDayOfWeek) || 0
  var day = localDayStart(ms)
  return addLocalDays(day, -((new Date(day).getDay() - first + 7) % 7))
}

function activityLevel(durationMs) {
  var value = Math.max(0, Number(durationMs) || 0)
  if (value === 0) return 0
  if (value < 2 * HOUR_MS) return 1
  if (value < 4 * HOUR_MS) return 2
  if (value < 8 * HOUR_MS) return 3
  return 4
}

function formatDuration(durationMs, zeroLabel) {
  var seconds = Math.floor(Math.max(0, Number(durationMs) || 0) / 1000)
  if (seconds === 0) return zeroLabel || "No activity"
  var minutes = Math.floor(seconds / 60)
  if (minutes === 0) return "<1m"
  var hours = Math.floor(minutes / 60)
  minutes %= 60
  return hours ? hours + "h " + (minutes < 10 ? "0" : "") + minutes + "m" : minutes + "m"
}

function weekdayDate(dayStartMs) {
  var date = new Date(dayStartMs)
  var weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return weekdays[date.getDay()] + " " + months[date.getMonth()] + " " + date.getDate()
}

function shortDate(dayStartMs) {
  var date = new Date(dayStartMs)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return months[date.getMonth()] + " " + date.getDate()
}

if (typeof module !== "undefined") module.exports = {
  HOUR_MS, localDayStart, addLocalDays, dateKey, weekStart, activityLevel,
  formatDuration, weekdayDate, shortDate
}
