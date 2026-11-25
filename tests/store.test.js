"use strict"

// Deterministic release checks for the SQL-only storage boundary. They use a
// fresh temporary directory and never touch ~/.local/share/omarchy-habit.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")
const Store = require("../js/ActivityStore.js")
const Dates = require("../js/DateUtils.js")

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "habit-store-test-"))
const db = path.join(dir, "habit.db")
const sql = statement => execFileSync("sqlite3", ["-batch", "-noheader", db, statement], { encoding: "utf8" }).trim()
const scalar = statement => Number(sql(statement) || 0)

try {
  // Fresh install and idempotent v1 schema hook.
  sql(Store.schemaSql())
  sql(Store.schemaSql())
  assert.equal(scalar("SELECT version FROM schema_migrations"), 1)
  assert.equal(scalar("SELECT count(*) FROM activity_sessions"), 0)

  // Repeated checkpoints update one row, and normal close does not duplicate
  // duration.  T+150 is the only final duration.
  const start = 1_000_000
  const id = Number(sql(Store.startSql(start)))
  sql(Store.checkpointSql(id, start, start + 60_000))
  sql(Store.checkpointSql(id, start, start + 120_000))
  sql(Store.endSql(id, start, start + 150_000))
  assert.equal(scalar("SELECT count(*) FROM activity_sessions"), 1)
  assert.equal(scalar(Store.totalDurationSql()), 150_000)

  // Crash recovery retains only the last durable checkpoint.
  const crashId = Number(sql(Store.startSql(2_000_000)))
  sql(Store.checkpointSql(crashId, 2_000_000, 2_060_000))
  sql(Store.recoverSql())
  assert.equal(scalar("SELECT duration_ms FROM activity_sessions WHERE id=" + crashId), 60_000)

  // Zero-length sessions are not kept, whether closed normally or recovered.
  const emptyId = Number(sql(Store.startSql(3_000_000)))
  sql(Store.endSql(emptyId, 3_000_000, 3_000_000))
  assert.equal(scalar("SELECT count(*) FROM activity_sessions WHERE id=" + emptyId), 0)
  const unsavedId = Number(sql(Store.startSql(4_000_000)))
  sql(Store.recoverSql())
  assert.equal(scalar("SELECT count(*) FROM activity_sessions WHERE id=" + unsavedId), 0)
  assert.equal(scalar("SELECT count(*) FROM activity_sessions"), 2)

  // Clear-history removes activity only. Configuration is a separate file.
  const settings = path.join(dir, "settings.json")
  fs.writeFileSync(settings, '{"version":1,"trackingEnabled":false}\n')
  sql(Store.clearHistorySql())
  assert.equal(scalar("SELECT count(*) FROM activity_sessions"), 0)
  assert.match(fs.readFileSync(settings, "utf8"), /trackingEnabled/)

  // Real local calendar boundaries, including 23- and 25-hour DST days.
  const inZone = script => JSON.parse(execFileSync(process.execPath, ["-e", script], {
    encoding: "utf8", env: { ...process.env, TZ: "America/New_York" }
  }))
  const dst = inZone(`
    const d = require(${JSON.stringify(path.join(__dirname, "..", "js", "DateUtils.js"))});
    const day = (y,m,n) => new Date(y,m,n).getTime();
    const span = (a,b) => d.addLocalDays(a,b) - a;
    console.log(JSON.stringify([span(day(2026,0,15),1),span(day(2026,2,8),1),span(day(2026,10,1),1)]));
  `)
  assert.deepEqual(dst, [86_400_000, 82_800_000, 90_000_000])

  // Aggregation consumes supplied local-midnight pairs, not a fixed 24-hour
  // constant. Verify normal, spring-forward, fall-back, and zero-activity days.
  const bounds = inZone(`
    const d = (y,m,n) => new Date(y,m,n).getTime();
    console.log(JSON.stringify([[d(2026,0,15),d(2026,0,16)],[d(2026,2,8),d(2026,2,9)],[d(2026,10,1),d(2026,10,2)],[d(2026,6,1),d(2026,6,2)]]));
  `)
  for (const [startDay, endDay] of bounds.slice(0, 3))
    sql(Store.startSql(startDay).replace("NULL,0", endDay + "," + (endDay - startDay)))
  const totals = bounds.map(pair => Number(JSON.parse(sql(Store.dailySql(pair)))[0].durationMs))
  assert.deepEqual(totals, [86_400_000, 82_800_000, 90_000_000, 0])
  assert.equal(Dates.activityLevel(0), 0)
  assert.equal(Dates.formatDuration(0), "No activity")

  // A corrupt file cannot be mistaken for an initialized database.
  const corrupt = path.join(dir, "corrupt.db")
  fs.writeFileSync(corrupt, "not a sqlite database")
  assert.throws(() => execFileSync("sqlite3", [corrupt, Store.schemaSql()], { encoding: "utf8", stdio: "pipe" }))

  console.log("store tests: ok")
} finally {
  fs.rmSync(dir, { recursive: true, force: true })
}
