"use strict"

// `habit today` and `habit week` must agree with the plugin's own daily
// aggregation, including a session that crosses local midnight.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const repo = path.join(__dirname, "..")
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "habit-cli-test-"))
const H = 3600e3, M = 60e3

function check(tz) {
  // Compute in a child so local-time functions honour the requested zone.
  const expected = JSON.parse(execFileSync(process.execPath, ["-e", `
    const D = require(${JSON.stringify(path.join(repo, "js/DateUtils.js"))});
    const S = require(${JSON.stringify(path.join(repo, "js/ActivityStore.js"))});
    const { execFileSync } = require("node:child_process");
    const db = ${JSON.stringify(path.join(dir, "habit.db"))};
    const today = D.localDayStart(Date.now()), day = n => D.addLocalDays(today, n);
    const rows = [
      [day(-6) + 9 * ${H}, day(-6) + 11 * ${H}],              // 2h
      [day(-3) - 30 * ${M}, day(-3) + 45 * ${M}],             // crosses midnight
      [day(-1) + 10 * ${H}, day(-1) + 10 * ${H} + 42 * 1000], // under a minute
      [day(0), day(0) + 7 * ${M}]                             // today
    ].filter(([, end]) => end <= Date.now());
    const values = rows.map(([s, e], i) => "(" + (i + 1) + "," + s + "," + e + "," + e + "," + (e - s) + "," + s + ")").join(",");
    execFileSync("sqlite3", [db, S.schemaSql() + " DELETE FROM activity_sessions; INSERT INTO activity_sessions VALUES " + values + ";"]);
    const bounds = []; for (let i = -6; i <= 1; i++) bounds.push(day(i));
    const totals = JSON.parse(execFileSync("sqlite3", [db, S.dailySql(bounds)], { encoding: "utf8" })).map(r => r.durationMs);
    const sum = totals.reduce((a, b) => a + b, 0);
    console.log(JSON.stringify({
      days: totals.map(ms => D.formatDuration(ms)),
      total: D.formatDuration(sum), average: D.formatDuration(Math.floor(sum / 7)),
      today: D.formatDuration(totals[6])
    }));
  `], { encoding: "utf8", env: { ...process.env, TZ: tz } }))

  // PATH without omarchy-shell: the CLI must fall back to the database alone.
  const env = { ...process.env, TZ: tz, HABIT_DATA_DIR: dir, PATH: "/usr/bin:/bin" }
  const run = cmd => execFileSync("bash", [path.join(repo, "bin/habit"), cmd], { encoding: "utf8", env })
  const week = run("week").trimEnd().split("\n")
  assert.equal(week.length, 10)
  week.slice(0, 7).forEach((line, i) => assert.ok(line.trimEnd().endsWith(expected.days[i]), tz + ": " + line + " vs " + expected.days[i]))
  assert.ok(week[8].endsWith(expected.total), tz + ": " + week[8])
  assert.ok(week[9].endsWith(expected.average), tz + ": " + week[9])
  assert.equal(run("today"), "Today\n" + expected.today + "\n")
}

try {
  for (const tz of ["UTC", "America/New_York", "Asia/Kolkata"]) check(tz)
  console.log("cli tests: ok")
} finally {
  fs.rmSync(dir, { recursive: true, force: true })
}
