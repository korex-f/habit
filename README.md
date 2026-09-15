# Habit

Habit is a local-first activity tracker for Omarchy. It records only local
activity-session timestamps and presents a contribution-style heatmap plus the
last seven calendar days. It has no app tracking or network use.

## Storage

Habit stores SQLite data at `~/.local/share/omarchy-habit/habit.db` and its
small local configuration at `~/.local/share/omarchy-habit/settings.json`.
Each history row contains only session timestamps and duration. WAL mode with
`synchronous=FULL` is used, and an active session is checkpointed every 60
seconds. On startup an unfinished session is closed at its last checkpoint,
never at the restart time. Clearing history deletes only activity sessions;
it preserves settings.

The service exposes `omarchy-shell habit status`, including state, current
session start, today's and all-time active milliseconds, stored-session count,
and storage health. For storage verification, inspect only the local database:

```sh
sqlite3 ~/.local/share/omarchy-habit/habit.db \
  'select id, started_at_ms, last_checkpoint_at_ms, ended_at_ms, duration_ms from activity_sessions;'
```

## Install for development

Install or symlink this directory as `~/.config/omarchy/plugins/io.github.dki.habit`,
then add `{ "id": "io.github.dki.habit" }` to the top-level `plugins` array in
`~/.config/omarchy/shell.json`. Omarchy loads the service automatically.

Use a short idle timeout while testing without changing source. Set it in the
environment that launches Omarchy Shell:

```sh
HABIT_IDLE_TIMEOUT=10 quickshell -p /path/to/habit/Service.qml
```

The value must be a whole number from 30 to 3600 seconds; otherwise Habit uses
the persisted idle setting (five minutes by default). This environment override
takes precedence over the setting and is intended only for development. For
the installed plugin, arrange for `HABIT_IDLE_TIMEOUT` to be inherited by
Hyprland before restarting the shell; a prefix on `omarchy restart shell`
alone is not inherited because Omarchy launches its shell through Hyprland.
`HABIT_DEBUG=1` enables raw signal logs.

## Milestone 1 behavior

The service derives one visible state with this precedence:

```text
SUSPENDED > LOCKED > IDLE > ACTIVE
```

Idle uses Quickshell's `IdleMonitor` with `respectInhibitors: true`. Suspend is
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
Habit. In Settings, `Esc` returns to the main view and `q` closes Habit.

Settings persist tracking on/off state, a one-to-sixty-minute idle threshold
(five minutes by default), and the bar display mode (`Off`, `Icon`, or `Icon + Today`). Turning tracking off
closes the active session immediately. Turning it back on re-derives the
effective state from the current idle, lock, and suspend signals; it never
assumes ACTIVE. The optional bar widget uses the same service as the panel and
opens or closes Habit when clicked.
