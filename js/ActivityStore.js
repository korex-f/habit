// SQL construction only. Service.qml owns process execution and lifecycle.

function schemaSql() {
  return "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; "
    + "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY); "
    + "INSERT OR IGNORE INTO schema_migrations(version) VALUES (1); "
    + "CREATE TABLE IF NOT EXISTS activity_sessions ("
    + "id INTEGER PRIMARY KEY, started_at_ms INTEGER NOT NULL, "
    + "last_checkpoint_at_ms INTEGER NOT NULL, ended_at_ms INTEGER, "
    + "duration_ms INTEGER NOT NULL DEFAULT 0, created_at_ms INTEGER NOT NULL); "
    + "CREATE INDEX IF NOT EXISTS activity_sessions_started ON activity_sessions(started_at_ms);"
}

function recoverSql() {
  // A missing end means the process died. Only time through the last durable
  // checkpoint is trustworthy; never credit the interval after it.
  // A session with nothing trustworthy after its start is dropped.
  return "UPDATE activity_sessions SET ended_at_ms=last_checkpoint_at_ms, "
    + "duration_ms=MAX(0,last_checkpoint_at_ms-started_at_ms) "
    + "WHERE ended_at_ms IS NULL; "
    + "DELETE FROM activity_sessions WHERE ended_at_ms IS NOT NULL AND duration_ms=0;"
}

function startSql(now) {
  return "INSERT INTO activity_sessions(started_at_ms,last_checkpoint_at_ms,ended_at_ms,duration_ms,created_at_ms) VALUES ("
    + now + "," + now + ",NULL,0," + now + "); SELECT last_insert_rowid();"
}

function checkpointSql(id, started, now) {
  return "UPDATE activity_sessions SET last_checkpoint_at_ms=" + now
    + ",duration_ms=MAX(0," + now + "-" + started + ") WHERE id=" + id + ";"
}

// A session that ends with no duration (e.g. idle ended it at its own start,
// after an unlock with no input) records nothing, so it is deleted rather than
// kept as an empty row that inflates the session count.
function endSql(id, started, now) {
  return "UPDATE activity_sessions SET last_checkpoint_at_ms=" + now
    + ",ended_at_ms=" + now + ",duration_ms=MAX(0," + now + "-" + started + ") WHERE id=" + id + "; "
    + "DELETE FROM activity_sessions WHERE id=" + id + " AND duration_ms=0;"
}

function countSql() { return "SELECT count(*) FROM activity_sessions;" }

// `duration_ms` is written at every checkpoint and on close. The active
// session's unpersisted tail is added in Service.qml, never by SQLite.
function totalDurationSql() { return "SELECT COALESCE(SUM(duration_ms),0) FROM activity_sessions;" }

function clearHistorySql() { return "DELETE FROM activity_sessions;" }

// Returns privacy-safe, local-day-clipped session intervals. Service.qml adds
// the active session's uncheckpointed tail in memory before exposing it.
function daySessionsSql(start, end) {
  return "SELECT COALESCE(json_group_array(json_object('id',id,'start',clip_start,'end',clip_end)),'[]') FROM ("
    + "SELECT id,MAX(started_at_ms," + start + ") AS clip_start,MIN(COALESCE(ended_at_ms,last_checkpoint_at_ms)," + end + ") AS clip_end "
    + "FROM activity_sessions WHERE started_at_ms < " + end + " AND COALESCE(ended_at_ms,last_checkpoint_at_ms) > " + start
    + " ORDER BY clip_start ASC);"
}

function totalBetweenSql(start, end) {
  return "SELECT COALESCE(SUM(MAX(0,MIN(COALESCE(ended_at_ms,last_checkpoint_at_ms)," + end
    + ")-MAX(started_at_ms," + start + "))),0) FROM activity_sessions "
    + "WHERE started_at_ms < " + end + " AND COALESCE(ended_at_ms,last_checkpoint_at_ms) > " + start + ";"
}

function dailySql(boundaries) {
  // Boundaries are real local midnights computed in JS. SQLite deliberately
  // receives pairs, so it never assumes a day is 86,400,000 milliseconds.
  var rows = []
  for (var i = 0; i + 1 < boundaries.length; i++) rows.push("(" + boundaries[i] + "," + boundaries[i + 1] + ")")
  if (!rows.length) return "SELECT '[]';"
  return "WITH days(day_start,day_end) AS (VALUES " + rows.join(",") + ") "
    + "SELECT json_group_array(json_object('start',day_start,'end',day_end,'durationMs',COALESCE((SELECT SUM(MAX(0,MIN(COALESCE(ended_at_ms,last_checkpoint_at_ms),day_end)-MAX(started_at_ms,day_start))) FROM activity_sessions WHERE started_at_ms < day_end AND COALESCE(ended_at_ms,last_checkpoint_at_ms) > day_start),0))) FROM days;"
}

if (typeof module !== "undefined") module.exports = { schemaSql, recoverSql, startSql, checkpointSql, endSql, countSql, totalDurationSql, clearHistorySql, daySessionsSql, totalBetweenSql, dailySql }
