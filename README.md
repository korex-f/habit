# Habit

Habit is a local-first activity tracker for Omarchy. It records only local
activity-session timestamps and presents a contribution-style heatmap, recent
days, and per-day intervals. It has no app tracking, telemetry, or network
use. It requires the normal Omarchy environment, including Quickshell,
`sqlite3`, `dbus-monitor`, and `xdg-open`.

## Storage

Habit stores SQLite data at `~/.local/share/omarchy-habit/habit.db` and its
small local configuration at `~/.local/share/omarchy-habit/settings.json`.
Each history row contains only session timestamps and duration. WAL mode with
`synchronous=FULL` is used, and an active session is checkpointed every 60
seconds. On startup an unfinished session is closed at its last checkpoint,
never at the restart time. Clearing history deletes only activity sessions;
it preserves settings.

The `habit` command prints totals from the local database, with today's value
taken live from the running service when available:

```sh
habit today   # today's active time
habit week    # last seven days with a bar per day, total and average
```

The service exposes `omarchy-shell habit status`, including state, current
session start, today's and all-time active milliseconds, stored-session count,
and storage health. For storage verification, inspect only the local database:

```sh
sqlite3 ~/.local/share/omarchy-habit/habit.db \
  'select id, started_at_ms, last_checkpoint_at_ms, ended_at_ms, duration_ms from activity_sessions;'
```

## Install and enable

Install the package from the Omarchy package repository (submission pending;
until it lands, use the git install below), then enable it for your user (not
as root):

```sh
omarchy pkg add habit
habit install
```

The package puts the plugin in `/usr/share/habit/plugin`, and
`habit install` links it into `~/.config/omarchy/plugins` and enables
it, since Omarchy only discovers third-party plugins there. Package upgrades
apply after `omarchy restart shell`. `habit uninstall` removes the link
and keeps your activity data.

Alternatively, install straight from git with the Omarchy plugin manager:

```sh
omarchy plugin add https://github.com/korex-f/habit.git --enable
```

Use one method or the other, not both. Habit creates its data directory and
schema automatically; tracking starts on and the bar defaults to Off.

Use a short idle timeout while testing without changing source. Set it in the
environment that launches Omarchy Shell:

```sh
HABIT_IDLE_TIMEOUT=10 quickshell -p /path/to/habit/Service.qml
```

The value must be a whole number from 1 to 86400 seconds; otherwise Habit uses
the persisted idle setting (five minutes by default). This environment override
takes precedence over the setting and is intended only for development. For
the installed plugin, arrange for `HABIT_IDLE_TIMEOUT` to be inherited by
Hyprland before restarting the shell; a prefix on `omarchy restart shell`
alone is not inherited because Omarchy launches its shell through Hyprland.
`HABIT_DEBUG=1` enables raw signal logs.

For an isolated development or release-test fixture, `HABIT_DATA_DIR` redirects
only Habit’s `habit.db` and `settings.json`. It is unset in normal use and is
not a user setting:

```sh
HABIT_DATA_DIR=/tmp/habit-fixture quickshell -p /usr/share/omarchy/shell
```

## Milestone 1 behavior

The service derives one visible state with this precedence:

```text
SUSPENDED > LOCKED > IDLE > ACTIVE
```

Idle uses Quickshell's `IdleMonitor` with `respectInhibitors: true`. The idle
signal fires once the idle threshold has passed without input, so Habit ends
the session at the last input (signal time minus the threshold) rather than
counting the threshold wait as activity. With a five-minute threshold, input
at 10:24 and the idle signal at 10:29 records a session ending at 10:24. Suspend is
observed through logind's `PrepareForSleep(bool)` signal. Omarchy's native
`WlSessionLock` does not update logind's `LockedHint` on the verified target,
so lock state is read from `omarchy-shell lock isLocked` every three seconds.
That conservative fallback is the smallest reliable public mechanism available
to an ordinary third-party service. No information about apps, windows, input
contents, or activity history is collected.

## Panel

Open the panel through Omarchy's standard plugin surface API:

```sh
omarchy-shell shell toggle io.github.dki.habit '{}'
```

The panel starts each opening with today selected. `j`/`k` move one local
calendar day, `h`/`l` move one local calendar week, and `g` returns to today.
Selection never moves into the future. `Enter` opens the selected date;
`s` opens Settings; `?` opens contextual shortcut help. In day detail, `h`,
`l`, and `g` navigate dates, `Esc` returns to the main view, and `q` closes
Habit. In Settings, `j`/`k` move between rows, `h`/`l` change the focused
value, `Enter` toggles or opens it, `Esc` returns to the main view, and `q`
closes Habit. The Clear History confirmation starts on Cancel; `h`/`l` switch
buttons, `Enter` confirms the focused one, and `Esc` cancels.

The heatmap shows 13 weeks, one column per week and one row per weekday,
starting from your locale's first day of the week. Days after today in the
current week stay blank.

Settings persist tracking on/off state, a one-to-sixty-minute idle threshold
(five minutes by default), and the bar display mode (`Off`, `Icon`, or `Icon + Today`). Turning tracking off
closes the active session immediately. Turning it back on re-derives the
effective state from the current idle, lock, and suspend signals; it never
assumes ACTIVE. The optional bar widget uses the same service as the panel and
opens or closes Habit when clicked.

To place the optional widget in a bar section once, use the normal registry:

```sh
omarchy-shell shell putBarWidget io.github.dki.habit '{"section":"right"}'
```

Choose Icon or Icon + Today in Settings. Off is invisible and uses no bar
width; changing modes never enables or disables the plugin.

## Clear History and uninstall

Clear History requires confirmation. Confirming ends any current session,
deletes all recorded sessions, resets aggregates, and starts a new session if
tracking remains active. It never resets settings.

Removing or disabling Habit does not delete `~/.local/share/omarchy-habit/`.
To remove the plugin, run `habit uninstall` and then
`omarchy pkg drop habit` for the package install, or
`omarchy plugin remove io.github.dki.habit` for a git install. To
permanently erase all Habit data as well, run:

```sh
rm -rf ~/.local/share/omarchy-habit/
```

This deletes the database, SQLite sidecars, and settings and cannot be undone.

## Known limitations

- Lock state uses the public `omarchy-shell lock isLocked` probe every three
  seconds because the native lock surface does not update logind `LockedHint`
  on the verified target. Polling pauses while tracking is off; turning
  tracking back on probes the lock state before any time is counted.
- A crash can lose up to 60 seconds since the last checkpoint; Habit never
  invents that unverified time.
- Durations use the wall clock, checked against Qt's monotonic timers once a
  minute. When the clock steps (a manual change or a large NTP correction),
  Habit closes the session at the last trustworthy time and starts a new one,
  so no session is stretched, shrunk, or negative.
- Activity means computer interaction, not productivity or application use.
