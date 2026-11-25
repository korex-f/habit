# Changelog

All notable changes to Habit are listed here. Versions follow
[Semantic Versioning](https://semver.org/).

## 0.2.0 — 2026-11-25

### Added
- `habit today` and `habit week`: totals from the local database in the
  terminal, with today's value taken live from the running service.
- The panel header shows whether Habit is counting, e.g.
  `Tracking · 2h 13m today`, and the bar widget shows the same on hover.
  Failing storage reads `Not saving`.
- Marketplace preview image, rendered from sample data.
- CI on every push and pull request: unit, storage and CLI tests, manifest
  checks matching `omarchy plugin validate`, Qt 6 `qmllint` on all QML, and
  `shellcheck` on the `habit` command.

### Fixed
- Wall-clock steps no longer stretch, shrink, or invert sessions: the session
  is closed at the last trustworthy time and a new one starts.
- Sessions with zero duration are no longer stored; existing ones are removed
  on the next start.

## 0.1.1 — 2026-11-25

### Changed
- The package and its user command are now both named `habit`
  (`habit install`, `habit uninstall`, `habit status`), and the packaged plugin
  lives in `/usr/share/habit/plugin`. The plugin id and data directory are
  unchanged, so existing installs and history carry over.

## 0.1.0 — 2026-11-25

First release.

### Added
- Automatic tracking of active computer use with an explicit state machine
  (`SUSPENDED > LOCKED > IDLE > ACTIVE`, plus `DISABLED`), recording only
  session timestamps in a local SQLite database.
- Crash-safe persistence: WAL with `synchronous=FULL`, a checkpoint every 60
  seconds, and conservative recovery that never counts time after the last
  checkpoint.
- Panel with a 13-week heatmap (rows fixed to weekdays, hover tooltips,
  matching legend), the last seven days, and all-time total.
- Day detail view with first and last activity, session count, longest
  session, and a timeline of sessions.
- Settings for tracking on/off, idle threshold, bar display mode, opening the
  data directory, and clearing history with confirmation.
- Optional bar widget (Icon, or Icon + Today) that toggles the panel.
- Full keyboard control, including Settings and the Clear History dialog.
- `omarchy-shell habit status` for scripting and diagnostics.

### Fixed (before release)
- Idle breaks no longer count the idle threshold as activity; sessions end at
  the last input.
- The panel and bar keep "today" correct across midnight on a long-running
  shell.
- Lock polling pauses while tracking is off.
