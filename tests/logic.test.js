"use strict"

// Pure-logic checks for the state machine and calendar/duration helpers.
const assert = require("node:assert/strict")
const path = require("node:path")
const { execFileSync } = require("node:child_process")
const Machine = require("../js/ActivityStateMachine.js")
const Dates = require("../js/DateUtils.js")

// State precedence: DISABLED > SUSPENDED > LOCKED > IDLE > ACTIVE.
assert.equal(Machine.derive({}), Machine.ACTIVE)
assert.equal(Machine.derive({ idle: true }), Machine.IDLE)
assert.equal(Machine.derive({ idle: true, locked: true }), Machine.LOCKED)
assert.equal(Machine.derive({ locked: true, suspended: true }), Machine.SUSPENDED)
assert.equal(Machine.derive({ suspended: true, disabled: true }), Machine.DISABLED)
assert.equal(Machine.transition(Machine.ACTIVE, {}).changed, false)
assert.equal(Machine.transition(Machine.ACTIVE, { idle: true }).changed, true)

// Idle ends a session at the last input, not when the idle threshold fires.
const min = 60_000
assert.equal(Machine.idleSessionEnd(0, 30 * min, 5 * min), 25 * min)
assert.equal(Machine.idleSessionEnd(28 * min, 30 * min, 5 * min), 28 * min) // never before start
assert.equal(Machine.idleSessionEnd(0, 30 * min, 0), 30 * min)

// Durations.
assert.equal(Dates.formatDuration(0), "No activity")
assert.equal(Dates.formatDuration(42_000), "<1m")
assert.equal(Dates.formatDuration(7 * min), "7m")
assert.equal(Dates.formatDuration(63 * min), "1h 03m")
assert.equal(Dates.formatDuration(830 * min), "13h 50m")
assert.equal(Dates.formatDuration(NaN), "No activity")

// Heatmap levels.
const h = Dates.HOUR_MS
assert.deepEqual([0, 1, 2 * h, 4 * h, 8 * h].map(Dates.activityLevel), [0, 1, 2, 3, 4])

// Legend and cells share one color formula: muted at level 0, accent above.
const rgba = (r, g, b, a) => [r, g, b, a]
const accent = { r: 1, g: 0, b: 0 }, muted = { r: 0, g: 0, b: 1 }
assert.deepEqual(Dates.levelColor(0, accent, muted, rgba), [0, 0, 1, Dates.LEVEL_ALPHA[0]])
assert.deepEqual(Dates.levelColor(4, accent, muted, rgba), [1, 0, 0, Dates.LEVEL_ALPHA[4]])
assert.deepEqual(Dates.levelColor(9, accent, muted, rgba), [1, 0, 0, Dates.LEVEL_ALPHA[4]])

// Week alignment uses local calendar days, including across DST.
const weeks = JSON.parse(execFileSync(process.execPath, ["-e", `
  const d = require(${JSON.stringify(path.join(__dirname, "..", "js", "DateUtils.js"))});
  const day = (y,m,n) => new Date(y,m,n).getTime();
  const iso = ms => { const x = new Date(ms); return [x.getFullYear(), x.getMonth() + 1, x.getDate(), x.getHours()] };
  console.log(JSON.stringify([
    iso(d.weekStart(day(2026,10,25) + 15 * 3600e3, 0)), // Wed -> Sun Nov 22
    iso(d.weekStart(day(2026,10,25), 1)),               // Wed -> Mon Nov 23
    iso(d.weekStart(day(2026,10,22), 0)),               // Sunday stays put
    iso(d.weekStart(day(2026,2,10), 0)),                // spans spring-forward
    iso(d.weekStart(day(2026,10,3), 0))                 // spans fall-back
  ]));
`], { encoding: "utf8", env: { ...process.env, TZ: "America/New_York" } }))
assert.deepEqual(weeks, [[2026, 11, 22, 0], [2026, 11, 23, 0], [2026, 11, 22, 0], [2026, 3, 8, 0], [2026, 11, 1, 0]])

console.log("logic tests: ok")
