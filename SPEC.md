# Habit — Product & Engineering Specification

Status: Draft
Target: v0.1.0
Platform: Omarchy / Hyprland
Plugin type: Omarchy Shell Plugin
Working name: Habit

---

# 1. Overview

Habit is a local-first activity tracker for Omarchy.

It automatically measures how much time the user is actively using their
computer and presents that history through a compact, keyboard-first Omarchy
panel.

Habit answers:

> "How much time have I actually spent active on this machine?"

Habit is NOT intended to answer:

> "Was that time productive?"

The initial release tracks WHEN the computer is actively used, not WHAT the
user does while using it.

Habit MUST NOT collect window titles, URLs, terminal commands, filenames,
keystrokes, browser history, or other content-level activity in v0.1.

---

# 2. Product Principles

## 2.1 Local-first

All tracking and aggregation MUST happen locally.

Habit MUST NOT require:

- an account
- internet connectivity
- telemetry
- analytics services
- cloud storage

No activity data may leave the machine.

---

## 2.2 Active time != uptime

Habit MUST NOT count time simply because the computer is powered on.

Time counts only while the graphical user session is considered active.

Tracking MUST pause when the user:

- becomes idle
- locks the session
- suspends the machine
- logs out

Tracking MUST resume automatically when appropriate.

---

## 2.3 Passive

The normal workflow MUST NOT require manual timers.

Once enabled:

    log in
       ↓
    Habit starts
       ↓
    user works
       ↓
    activity recorded automatically

Manual pause/resume MAY be provided as an additional control.

---

## 2.4 Descriptive, not judgmental

Habit reports activity.

Habit MUST NOT assign:

- productivity scores
- distraction scores
- efficiency ratings
- "good/bad" application labels

Example:

    Today
    6h 43m

is acceptable.

Example:

    Productivity
    73%

is not.

---

## 2.5 Keyboard-first

All primary functionality MUST be usable without a mouse.

Mouse interaction SHOULD remain available.

---

# 3. Privacy Contract

The core privacy promise is:

> Habit records when you use your computer, not what you do on it.

For v0.1, Habit MAY persist:

- activity session start time
- activity session end time
- calculated duration
- internal database metadata

Habit MUST NOT persist:

- window titles
- application names
- URLs
- browser history
- terminal commands
- filenames
- keyboard input
- clipboard contents
- screenshots

---

# 4. Architecture

Habit SHOULD be implemented as one Omarchy Shell plugin containing multiple
plugin surfaces.

Conceptual architecture:

                    Hyprland
                       │
                idle/session state
                       │
                       ▼
               ┌───────────────┐
               │ Activity      │
               │ Service       │
               └───────┬───────┘
                       │
                       ▼
                  Local Store
                       │
              ┌────────┴────────┐
              │                 │
              ▼                 ▼
          Bar Widget           Panel
                                  │
                     ┌────────────┼────────────┐
                     │            │            │
                     ▼            ▼            ▼
                  Heatmap      Day List    Day Detail

The activity service MUST own tracking state.

The UI MUST NOT own tracking state.

Closing or reopening the panel MUST NOT interrupt activity tracking.

---

# 5. Repository Structure

Suggested structure:

    habit/
    ├── manifest.json
    ├── Service.qml
    ├── BarWidget.qml
    ├── Panel.qml
    │
    ├── components/
    │   ├── Heatmap.qml
    │   ├── HeatmapCell.qml
    │   ├── DayRow.qml
    │   ├── DayDetail.qml
    │   ├── ActivityTimeline.qml
    │   └── Settings.qml
    │
    ├── js/
    │   ├── ActivityStore.js
    │   ├── ActivityTracker.js
    │   ├── DateUtils.js
    │   └── Duration.js
    │
    ├── migrations/
    ├── README.md
    ├── SPEC.md
    └── LICENSE

This structure is guidance rather than a hard requirement.

Implementation SHOULD follow established Omarchy plugin conventions rather
than introducing unnecessary abstractions.

---

# 6. Activity State Machine

Habit MUST explicitly model activity state.

Required states:

    ACTIVE
    IDLE
    LOCKED
    SUSPENDED
    DISABLED

Conceptual transitions:

                    input
              ┌───────────────┐
              │               │
              ▼               │
           ACTIVE ─────────→ IDLE
              │
              ├────────────→ LOCKED
              │
              ├────────────→ SUSPENDED
              │
              └────────────→ DISABLED

    IDLE ────────────────→ ACTIVE
           user returns

    LOCKED ──────────────→ ACTIVE
           unlock + activity

    SUSPENDED ───────────→ ACTIVE
           resume + activity

No inactive state may accumulate active duration.

---

# 7. Idle Detection

Default idle threshold:

    5 minutes

The implementation SHOULD use the most reliable event-driven mechanism
available from Hyprland / Quickshell / the surrounding Omarchy environment.

Constant high-frequency polling SHOULD be avoided.

If the platform exposes the true time of last user input, Habit SHOULD use it
to avoid counting the idle grace period.

Example:

    10:00 activity begins
    10:24 last user input
    10:29 idle threshold fires

Preferred recorded interval:

    10:00 → 10:24

Fallback if true last-input timestamp cannot be determined reliably:

    10:00 → 10:29

The selected behavior MUST be documented.

---

# 8. Session Model

An activity session represents a contiguous period of active computer use.

Example:

    08:43 ───── 09:17
    09:22 ─────────── 10:41
    11:03 ──── 11:26

The service MUST begin a session when transitioning into ACTIVE.

The service MUST close/checkpoint a session when transitioning out of ACTIVE.

Sessions MUST survive UI panel closure.

---

# 9. Persistence

Preferred storage location:

    ~/.local/share/omarchy-habit/

Preferred database:

    ~/.local/share/omarchy-habit/habit.db

SQLite SHOULD be used unless integration constraints make another durable
local format substantially safer or simpler.

Minimum conceptual schema:

    activity_sessions

    id
    started_at
    ended_at
    duration_seconds
    created_at

Additional internal fields MAY be added where required.

The schema MUST be versioned/migratable.

---

# 10. Durability

Habit MUST NOT keep an entire day's activity exclusively in memory.

Active sessions SHOULD be checkpointed periodically.

A crash MUST NOT normally result in losing hours of activity.

If Habit encounters an unfinished session after a crash, it MUST recover
conservatively.

It MUST NOT assume the user remained active from the previous checkpoint
until the next application startup.

---

# 11. Time Semantics

## Midnight

Sessions crossing local midnight MUST be attributed correctly to each
calendar day.

Example:

    Monday
    23:50 → 00:00 = 10m

    Tuesday
    00:00 → 00:20 = 20m

The implementation MAY physically split sessions or split them during
aggregation.

The visible result MUST be correct.

---

## Suspend

Suspend time MUST NOT count as active time.

The current activity session SHOULD be checkpointed/closed before suspend
where possible.

---

## Lock

Locked time MUST NOT count.

---

## Clock changes

Live duration measurement SHOULD avoid relying exclusively on wall-clock
subtraction.

Where available, monotonic elapsed time SHOULD be used for active duration
measurement.

---

## Timezone changes

Stored timestamps MUST permit correct reconstruction of activity.

Calendar views MUST use local calendar dates.

Timezone changes MUST NOT create negative or impossible session durations.

---

# 12. Primary Panel

The default panel contains:

1. title/header
2. activity heatmap
3. heatmap legend
4. total tracked activity
5. "Last 7 Days" list

Approximate layout:

    HABIT                                      ×


                ░ ░ ░ ░ ░ ░ ░ ░
                ░ ░ ░ ░ ░ ░ ░ ░
                ░ ░ ▒ ░ ░ ░ ░ ░
                ░ ▒ ▓ ░ ▒ ▓ ▓ ░
                ▒ ▓ █ ▒ ▓ █ █ ▒

    Less   ░ ▒ ▓ █   More                 Total 90h 16m


    LAST 7 DAYS

    ● Tue Sep 08                           9h 17m
    ○ Wed Sep 09                       No activity
    ● Thu Sep 10                          13h 50m
    ● Fri Sep 11                          23h 35m
    ● Sat Sep 12                          16h 42m
    ● Sun Sep 13                          23h 38m
    › Mon Sep 14              TODAY        3h 13m

The reference design supplied with the project SHOULD inform layout and
hierarchy.

It MUST NOT be copied blindly.

The result SHOULD look native to Omarchy.

---

# 13. Theming

Habit MUST use Omarchy's existing theme primitives wherever available.

It MUST NOT assume a particular:

- wallpaper
- accent color
- foreground color
- background color
- font
- border color

The plugin SHOULD automatically fit the user's current Omarchy theme.

Heatmap intensity SHOULD derive from theme-compatible colors rather than
hardcoded unrelated colors.

---

# 14. Heatmap

The heatmap is a primary product feature.

Each cell represents one local calendar day.

Cell intensity represents total active duration for that day.

v0.1 SHOULD use deterministic fixed thresholds.

Suggested initial thresholds:

    0           no activity
    >0 – <2h    level 1
    2h – <4h    level 2
    4h – <8h    level 3
    >=8h        level 4

Threshold implementation SHOULD be centralized so it can be made
configurable later.

The heatmap SHOULD display approximately the recent 12–13 weeks if panel
dimensions allow.

The current day SHOULD be identifiable.

The selected day MUST be identifiable.

---

# 15. Heatmap Mouse Interaction

Hovering a cell SHOULD display:

    Sep 11
    6h 42m

Clicking a cell SHOULD select that date.

Selection MUST synchronize with other date-aware UI.

---

# 16. Last Seven Days

The panel MUST display seven calendar days including today.

Each row contains:

- activity indicator
- weekday
- date
- duration

Today SHOULD display a subtle TODAY indicator.

Zero activity SHOULD be represented explicitly:

    No activity

rather than:

    0h 0m

---

# 17. Selection Model

Habit MUST maintain one currently selected date while the panel is active.

The heatmap and day list MUST share that selection.

Example:

If Sunday is selected using the keyboard:

- Sunday's list row becomes selected.
- Sunday's heatmap cell becomes selected.

Selecting a heatmap cell MUST update the same underlying selection.

There MUST NOT be independent heatmap/list selection states.

---

# 18. Keyboard Controls

Required v0.1 bindings:

    j       next day
    k       previous day

    h       previous week
    l       next week

    g       jump to today

    Enter   open selected day

    ?       keyboard help

    Esc     back / close
    q       close panel

If additional year/week views are implemented:

    w       week view
    y       year view

Bindings MUST NOT fire while a text input requiring those keys has focus.

---

# 19. Keyboard Navigation Behavior

Keyboard navigation MUST provide visible feedback.

Selection MUST remain visible.

If the selected date moves outside the currently displayed heatmap range,
the heatmap SHOULD move its visible range appropriately.

Navigation MUST NOT unexpectedly reset to today.

---

# 20. Day Detail View

Pressing Enter on a selected date opens a detail view inside the Habit panel.

Example:

    HABIT                           SEP 14


    MONDAY, SEPTEMBER 14

    Active                            3h 13m

    First activity                     08:43
    Last activity                      14:07

    Sessions                              6
    Longest session                    1h 06m


    ACTIVITY

    08:43 ━━━━━━━ 09:17                   34m
    09:22 ━━━━━━━━━━━━━ 10:41          1h 19m
    11:03 ━━━━━ 11:26                      23m


    ESC back

Required metrics:

- total active time
- first activity
- last activity
- session count
- longest session

A chronological activity timeline SHOULD be displayed.

---

# 21. Day Detail Privacy

The timeline MUST display time intervals only.

v0.1 MUST NOT annotate sessions with:

- applications
- windows
- URLs
- files
- commands

Example:

    10:32 → 11:17

Good.

Example:

    10:32 → 11:17
    Firefox — Reddit

Not permitted in v0.1.

---

# 22. Bar Widget

The bar widget SHOULD be optional.

Supported conceptual modes:

    Off
    Icon
    Icon + Today

Example:

    󰔟 3h 13m

Activating the widget SHOULD open/toggle the Habit panel.

The widget MUST update while activity accumulates without requiring the
panel to be open.

---

# 23. Settings

v0.1 settings SHOULD remain deliberately small.

Required:

    Tracking
        Track activity              on/off

    Idle threshold
        5 minutes

    Bar
        Display mode

    Data
        Open data directory
        Clear history

    About
        version

Export history MAY ship in v0.1 if straightforward.

It MUST NOT delay the core tracker.

---

# 24. Tracking Toggle

Turning tracking off MUST:

1. close/checkpoint the current active session
2. stop accumulating time
3. preserve historical data

Turning tracking back on MUST NOT alter historical sessions.

The setting MUST persist across restarts.

---

# 25. Clear History

Clearing history is destructive.

The UI MUST require confirmation.

Example:

    Clear all Habit history?

    This permanently deletes recorded
    activity sessions.

        Cancel      Clear history

Habit MUST NOT accidentally clear settings when history is deleted.

---

# 26. Duration Formatting

Centralize duration formatting.

Examples:

    0 seconds        → No activity
    42 seconds       → <1m
    7 minutes        → 7m
    1h 03m           → 1h 03m
    13h 50m          → 13h 50m

Do not scatter custom formatting logic throughout QML components.

---

# 27. Performance

Habit is expected to remain active for the entire graphical session.

Therefore:

- CPU usage while idle SHOULD be negligible.
- high-frequency polling MUST be avoided.
- unnecessary database writes MUST be avoided.
- panel rendering MUST NOT affect tracking.
- heatmap aggregation SHOULD NOT repeatedly scan unnecessary historical
  records.

The implementation SHOULD favor event-driven behavior.

---

# 28. Startup

Habit SHOULD initialize automatically with the Omarchy Shell plugin.

Startup MUST:

1. load settings
2. initialize/migrate storage
3. inspect current session state
4. recover unfinished sessions conservatively
5. begin tracking if enabled and appropriate

Opening the panel MUST NOT be required to start tracking.

---

# 29. Error Handling

Storage failures MUST NOT crash the entire Omarchy shell.

Habit SHOULD surface a restrained error state if persistence becomes
unavailable.

The plugin MUST NOT silently pretend activity is being persisted when writes
are failing.

Debug information SHOULD be available through normal Omarchy/Quickshell
logging mechanisms.

---

# 30. Accessibility / Usability

Selection MUST NOT rely solely on subtle color differences.

Text SHOULD maintain adequate contrast using current theme primitives.

Keyboard focus MUST be visually understandable.

Clickable targets SHOULD remain usable even though the design is compact.

---

# 31. Explicit v0.1 Non-Goals

DO NOT implement the following unless required for core platform integration:

- application usage tracking
- website tracking
- browser extensions
- productivity scoring
- project detection
- Git repository tracking
- terminal command tracking
- cloud sync
- accounts
- leaderboards
- social features
- mobile applications
- cross-device synchronization
- AI summaries
- goals
- reminders
- Pomodoro timers
- blocking applications/websites

These are outside the v0.1 scope.

---

# 32. Future-Compatible Features

The architecture SHOULD avoid unnecessarily preventing future support for:

- per-application activity
- application categories
- weekly/monthly trends
- yearly views
- relative heatmap scaling
- CSV/JSON export
- CLI
- project/context tracking
- multiple machines
- configurable privacy levels

Do NOT implement speculative abstractions solely for these features.

---

# 33. CLI — Future

The data layer SHOULD make a future CLI possible.

Potential commands:

    habit today
    habit week
    habit month
    habit year

Example:

    $ habit today

    Today
    6h 43m

Potential weekly output:

    Mon    ███████       6h 21m
    Tue    █████         4h 48m
    Wed    ████████      7h 12m
    Thu    ██████        5h 37m
    Fri    ███████       6h 03m
    Sat    ███           2h 41m
    Sun    ████          3h 58m

    Total               36h 40m
    Average               5h 14m

CLI implementation is NOT required for v0.1.

---

# 34. Acceptance Criteria

v0.1 is considered functionally complete when all of the following are true.

## Tracking

- [ ] Tracking begins automatically after plugin initialization.
- [ ] Active computer use accumulates time.
- [ ] Idle time stops accumulating.
- [ ] Lock time does not accumulate.
- [ ] Suspend time does not accumulate.
- [ ] Tracking resumes correctly.
- [ ] Tracking continues when panel is closed.

## Persistence

- [ ] Sessions survive shell restart.
- [ ] A crash does not normally lose the day's activity.
- [ ] Unfinished sessions are recovered conservatively.
- [ ] Midnight attribution is correct.
- [ ] Historical data remains after reboot.

## Panel

- [ ] Panel opens reliably.
- [ ] Heatmap renders historical activity.
- [ ] Last seven days render correctly.
- [ ] Today updates while active.
- [ ] Total tracked time is correct.
- [ ] Zero-activity days are represented clearly.

## Keyboard

- [ ] j/k navigate dates.
- [ ] h/l navigate weeks.
- [ ] g returns to today.
- [ ] Enter opens selected date.
- [ ] Esc returns/closes.
- [ ] q closes.
- [ ] Selection is visible.
- [ ] Heatmap/list selection stays synchronized.

## Detail View

- [ ] Total active time is correct.
- [ ] First activity is correct.
- [ ] Last activity is correct.
- [ ] Session count is correct.
- [ ] Longest session is correct.
- [ ] Timeline intervals render chronologically.

## Privacy

- [ ] No URLs are recorded.
- [ ] No window titles are recorded.
- [ ] No terminal commands are recorded.
- [ ] No filenames are recorded.
- [ ] No keystrokes are recorded.
- [ ] No activity data is transmitted externally.

## Theme

- [ ] Works with dark Omarchy themes.
- [ ] Works with light Omarchy themes where supported.
- [ ] Uses current theme colors.
- [ ] No core UI depends on a hardcoded accent color.

---

# 35. Test Cases

At minimum test:

### Normal usage

    ACTIVE 30m
    IDLE 10m
    ACTIVE 20m

Expected:

    50m active

### Lock

    ACTIVE
    lock
    wait 30m
    unlock

Expected:

    locked 30m excluded

### Suspend

    ACTIVE
    suspend
    wait
    resume

Expected:

    suspended duration excluded

### Midnight

    active 23:50 → 00:20

Expected:

    previous day: 10m
    next day:     20m

### Crash

    begin activity
    checkpoint
    shell crashes
    shell restarts later

Expected:

    persisted activity through last trustworthy checkpoint retained

    time between last trustworthy checkpoint and restart MUST NOT
    automatically be counted

### Tracking disabled

    ACTIVE
    disable tracking
    wait
    enable tracking

Expected:

    disabled interval excluded

### No activity day

Expected UI:

    No activity

not:

    undefined
    null
    NaN
    -1m

---

# 36. Visual Direction

Use the supplied Habit reference screenshot as inspiration for:

- compact floating panel
- contribution-style heatmap
- restrained typography
- seven-day history
- minimal visual chrome
- strong information hierarchy

Do NOT reproduce the reference pixel-for-pixel.

The resulting interface should look like it belongs to Omarchy rather than
like a foreign application embedded inside Omarchy.

Prefer restraint over decorative UI.

---

# 37. Product Voice

Use short neutral labels.

Prefer:

    Today
    Last 7 Days
    Total
    No activity
    Active
    Sessions

Avoid:

    Amazing!
    You're on fire!
    Productivity increased!
    You worked too much today!

Habit reports facts.

The user interprets them.

---

# 38. Definition of Done

Habit v0.1 is done when a user can:

1. install the plugin,
2. forget that it is running,
3. use their Omarchy machine normally,
4. open Habit several days later,
5. see an accurate representation of when and how long they used the machine,
6. navigate that history entirely from the keyboard,
7. inspect individual days,
8. trust that the data never left their computer.

Anything beyond that is secondary to v0.1.